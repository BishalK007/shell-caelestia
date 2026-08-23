pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components.misc

Singleton {
    id: root

    // connector name -> { busNum, cur, max } for externals that answered a
    // getvcp 10 probe. Swapped atomically at the end of a detect pass — never
    // cleared up front, so resolved monitors keep working during re-detection.
    property var ddcMonitorMap: ({})
    property bool appleDisplayPresent: false

    // connector name -> panel-declared peak luminance in nits, parsed from the
    // EDID HDR static metadata block during the sysfs pass. Used as the
    // per-panel default for the HDR slider's 100% point (rules still win).
    property var edidPeakMap: ({})

    // CTA-861 extension walk: find extended data block 0x06 (HDR static
    // metadata); desired-content-max-luminance code -> 50 * 2^(code/32) nits.
    // Validated against the Odyssey G50SF (code 96 -> 400 nits).
    function parseEdidPeakNits(hex: string): int {
        if (!hex || hex.length < 256)
            return 0;
        const b = i => parseInt(hex.slice(i * 2, i * 2 + 2), 16);
        const numExt = b(126);
        for (let e = 0; e < numExt; e++) {
            const base = 128 * (e + 1);
            if ((base + 128) * 2 > hex.length || b(base) !== 0x02)
                continue;
            const dtd = b(base + 2);
            const end = base + (dtd >= 4 ? dtd : 127);
            let i = base + 4;
            while (i < end) {
                const len = b(i) & 0x1f;
                if (b(i) >> 5 === 7 && b(i + 1) === 0x06) {
                    if (len >= 4) {
                        const nits = Math.round(50 * Math.pow(2, b(i + 4) / 32));
                        if (nits >= 100 && nits <= 10000)
                            return nits;
                    }
                    return 0;
                }
                i += len + 1;
            }
        }
        return 0;
    }

    // True from shell start / hotplug until the current detect pass commits.
    // Externals resolve to "pending" (not "unsupported", and NEVER the laptop
    // backlight) while this is set, so slider input is buffered instead of
    // being sent to the wrong device.
    property bool detecting: true

    // Internal panel backlight, resolved once per detect pass from sysfs.
    property string backlightName
    property int backlightMax
    property int backlightCur

    // Detect pass state, generation-tagged so a stale pass discards itself.
    property int _gen: 0
    property var _queue: []
    property var _results: ({})
    property var _connected: []
    property bool _fallbackRan: false

    readonly property list<Monitor> monitors: variants.instances // qmllint disable incompatible-type

    function getMonitorForScreen(screen: ShellScreen): var {
        return monitors.find(m => m.modelData === screen); // qmllint disable missing-property
    }

    function getMonitor(query: string): var {
        if (query === "active") {
            // NOTE: HyprlandMonitor has no `focused` property in quickshell 0.3.0
            // (the old find over monitorFor(...)?.focused silently never matched) —
            // resolve via the focusedMonitor singleton property instead.
            const focused = Hypr.focusedMonitor;
            return focused ? monitors.find(m => m.modelData.name === focused.name) : undefined; // qmllint disable missing-property
        }

        if (query.startsWith("model:")) {
            const model = query.slice(6);
            return monitors.find(m => m.modelData.model === model); // qmllint disable missing-property
        }

        if (query.startsWith("serial:")) {
            const serial = query.slice(7);
            return monitors.find(m => m.modelData.serialNumber === serial); // qmllint disable missing-property
        }

        if (query.startsWith("id:")) {
            const id = parseInt(query.slice(3), 10);
            return monitors.find(m => Hypr.monitorFor(m.modelData)?.id === id); // qmllint disable missing-property
        }

        return monitors.find(m => m.modelData.name === query); // qmllint disable missing-property
    }

    function increaseBrightness(): void {
        const monitor = getMonitor("active");
        if (monitor)
            monitor.setBrightness(monitor.brightness + GlobalConfig.services.brightnessIncrement);
    }

    function decreaseBrightness(): void {
        const monitor = getMonitor("active");
        if (monitor)
            monitor.setBrightness(monitor.brightness - GlobalConfig.services.brightnessIncrement);
    }

    function scheduleDetect(): void {
        detecting = true;
        hotplugTimer.restart();
    }

    function startDetect(): void {
        _gen++;
        detecting = true;

        if (appleProc.running)
            appleProc.running = false;
        appleProc.running = true;

        if (backlightProc.running)
            backlightProc.running = false;
        backlightProc.running = true;

        if (!GlobalConfig.services.ddcEnabled) {
            ddcMonitorMap = {};
            detecting = false;
            return;
        }

        sysfsProc.gen = _gen;
        if (sysfsProc.running)
            sysfsProc.running = false;
        sysfsProc.running = true;
    }

    function advanceProbe(): void {
        while (_queue.length > 0 && _results[_queue[0].connector])
            _queue.shift();

        if (_queue.length === 0) {
            finishPass();
            return;
        }

        const head = _queue[0];
        probeProc.gen = _gen;
        probeProc.connector = head.connector;
        probeProc.bus = head.bus;
        probeProc.command = ["ddcutil", "--bus", head.bus, "getvcp", "10", "--brief"];
        probeProc.running = true;
    }

    function finishPass(): void {
        // Connected externals with no working bus: one ddcutil detect fallback
        // (covers connectors without sysfs i2c hints, e.g. proprietary nvidia).
        if (!_fallbackRan && _connected.some(c => !_results[c])) {
            _fallbackRan = true;
            detectProc.gen = _gen;
            detectProc.running = true;
            return;
        }

        ddcMonitorMap = _results;
        detecting = false;
    }

    Component.onCompleted: startDetect()
    onMonitorsChanged: scheduleDetect()

    Connections {
        target: Hypr

        function onMonitorsHotplugged(): void {
            root.scheduleDetect();
        }

        // hyprctl reload resets sdr_max_luminance to the config file value;
        // re-assert the slider value so HDR behaves like hardware brightness
        // (which a config reload doesn't touch either).
        function onConfigReloaded(): void {
            for (const m of root.monitors) {
                if (m.method === "hdr")
                    m.pushCurrent();
            }
        }
    }

    Timer {
        id: hotplugTimer

        interval: GlobalConfig.services.hotplugDebounceMs
        onTriggered: root.startDetect()
    }

    Variants {
        id: variants

        model: Quickshell.screens // Don't respect excluded screens cause ipc

        Monitor {}
    }

    Process {
        id: appleProc

        command: ["sh", "-c", "asdbctl get"] // To avoid warnings if asdbctl is not installed
        stdout: StdioCollector {
            onStreamFinished: root.appleDisplayPresent = text.trim().length > 0
        }
    }

    Process {
        id: backlightProc

        command: ["sh", "-c", `for d in /sys/class/backlight/*/; do [ -d "$d" ] || continue; echo "$(basename "$d")|$(cat "$d"type 2>/dev/null)|$(cat "$d"actual_brightness 2>/dev/null)|$(cat "$d"max_brightness 2>/dev/null)"; done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const typeRank = t => t === "firmware" ? 0 : t === "platform" ? 1 : t === "raw" ? 2 : 3;
                const pinned = GlobalConfig.services.backlightDevice;
                let best = null;
                for (const line of text.trim().split("\n")) {
                    if (!line)
                        continue;
                    const [name, type, cur, max] = line.split("|");
                    if (!name || !(parseInt(max) > 0))
                        continue;
                    const dev = {
                        name,
                        rank: typeRank(type),
                        cur: parseInt(cur) || 0,
                        max: parseInt(max)
                    };
                    if (pinned) {
                        if (name === pinned) {
                            best = dev;
                            break;
                        }
                    } else if (!best || dev.rank < best.rank) {
                        best = dev;
                    }
                }
                if (best) {
                    root.backlightName = best.name;
                    root.backlightMax = best.max;
                    root.backlightCur = best.cur;
                    for (const m of root.monitors)
                        m.syncBacklight();
                }
            }
        }
    }

    // Sysfs pass: connected connectors + their candidate i2c buses. The i2c-*
    // subdevices (DP AUX) come FIRST — the ddc symlink is verified to point at
    // a dead hw-i2c bus for amdgpu DP outputs; it is kept as a last candidate
    // since it IS correct for HDMI.
    Process {
        id: sysfsProc

        property int gen

        command: ["sh", "-c", `for c in /sys/class/drm/card*-*/; do [ -f "$c"status ] || continue; read -r st < "$c"status || continue; [ "$st" = connected ] || continue; n=$(basename "$c" | sed 's/^card[0-9]*-//'); ddc=""; [ -L "$c"ddc ] && ddc=$(basename "$(readlink -f "$c"ddc)"); subs=""; for s in "$c"i2c-*; do [ -e "$s" ] && subs="$subs $(basename "$s")"; done; eh=""; [ -f "$c"edid ] && eh=$(od -An -v -tx1 "$c"edid 2>/dev/null | tr -dc "0-9a-f"); echo "$n|$ddc|$subs|$eh"; done`]
        stdout: StdioCollector {
            onStreamFinished: {
                if (sysfsProc.gen !== root._gen)
                    return;

                const queue = [];
                const connected = [];
                const peaks = {};
                for (const line of text.trim().split("\n")) {
                    if (!line)
                        continue;
                    const [name, ddc, subs, edid] = line.split("|");
                    if (!name)
                        continue;
                    const peak = root.parseEdidPeakNits(edid ?? "");
                    if (peak > 0)
                        peaks[name] = peak;
                    if (name.startsWith("eDP-") || name.startsWith("LVDS-") || name.startsWith("DSI-"))
                        continue;
                    connected.push(name);
                    const cands = (subs ?? "").trim().split(/\s+/).filter(s => s).map(s => s.replace("i2c-", ""));
                    if (ddc) {
                        const b = ddc.replace("i2c-", "");
                        if (!cands.includes(b))
                            cands.push(b);
                    }
                    for (const b of cands)
                        queue.push({
                            connector: name,
                            bus: b
                        });
                }

                root.edidPeakMap = peaks;
                if (Object.keys(peaks).length > 0)
                    console.info(`[Brightness] EDID peak luminance: ${Object.entries(peaks).map(([k, v]) => `${k}=${v} nits`).join(", ")}`);

                root._connected = connected;
                root._queue = queue;
                root._results = {};
                root._fallbackRan = false;
                root.advanceProbe();
            }
        }
    }

    // Sequential candidate probe: a wrong bus fails in ~60ms; a hit returns
    // both current and max in one shot (max is NOT always 100 — e.g. 50 on
    // Samsung Odyssey), so probing doubles as the initial value read. getvcp
    // success is the only reliable DDC signal ("capabilities" lies).
    Process {
        id: probeProc

        property int gen
        property string connector
        property string bus

        stdout: StdioCollector {
            id: probeOut
        }
        onExited: {
            if (probeProc.gen !== root._gen)
                return;

            const m = probeOut.text.match(/VCP 10 C (\d+) (\d+)/);
            if (m && parseInt(m[2]) > 0)
                root._results[probeProc.connector] = {
                    busNum: probeProc.bus,
                    cur: parseInt(m[1]),
                    max: parseInt(m[2])
                };

            root._queue.shift();
            root.advanceProbe();
        }
    }

    Process {
        id: detectProc

        property int gen

        command: ["ddcutil", "detect", "--brief"]
        stdout: StdioCollector {
            id: detectOut
        }
        onExited: {
            if (detectProc.gen !== root._gen)
                return;

            for (const block of detectOut.text.split("\n\n")) {
                if (!block.startsWith("Display"))
                    continue;
                const busM = block.match(/I2C bus:\s*\/dev\/i2c-(\d+)/);
                const connM = block.match(/DRM connector:\s*(\S+)/);
                if (!busM || !connM)
                    continue;
                const conn = connM[1].replace(/^card\d+-/, "");
                if (!root._results[conn])
                    root._queue.push({
                        connector: conn,
                        bus: busM[1]
                    });
            }

            root.advanceProbe();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "brightnessUp"
        description: "Increase brightness"
        onPressed: root.increaseBrightness()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "brightnessDown"
        description: "Decrease brightness"
        onPressed: root.decreaseBrightness()
    }

    IpcHandler {
        function get(): real {
            return getFor("active");
        }

        // Allows searching by active/model/serial/id/name
        function getFor(query: string): real {
            return root.getMonitor(query)?.brightness ?? -1;
        }

        function list(): string {
            return root.monitors.map(m => {
                const detail = m.method === "ddc" ? `, bus ${m.busNum}` : m.method === "hdr" ? `, ${m.hdrMinNits}-${m.hdrMaxNits} nits` : "";
                return `${m.modelData.name}: ${+m.brightness.toFixed(2)} (${m.method}${detail})`;
            }).join("\n");
        }

        function set(value: string): string {
            return setFor("active", value);
        }

        // Handles brightness value like brightnessctl: 0.1, +0.1, 0.1-, 10%, +10%, 10%-
        function setFor(query: string, value: string): string {
            const monitor = root.getMonitor(query);
            if (!monitor)
                return "Invalid monitor: " + query;

            if (monitor.method === "unsupported")
                return `Monitor ${monitor.modelData.name} has no controllable brightness (no DDC/CI, not internal, not in HDR mode)`;

            let targetBrightness;
            if (value.endsWith("%-")) {
                const percent = parseFloat(value.slice(0, -2));
                targetBrightness = monitor.brightness - (percent / 100);
            } else if (value.startsWith("+") && value.endsWith("%")) {
                const percent = parseFloat(value.slice(1, -1));
                targetBrightness = monitor.brightness + (percent / 100);
            } else if (value.endsWith("%")) {
                const percent = parseFloat(value.slice(0, -1));
                targetBrightness = percent / 100;
            } else if (value.startsWith("+")) {
                const increment = parseFloat(value.slice(1));
                targetBrightness = monitor.brightness + increment;
            } else if (value.endsWith("-")) {
                const decrement = parseFloat(value.slice(0, -1));
                targetBrightness = monitor.brightness - decrement;
            } else if (value.includes("%") || value.includes("-") || value.includes("+")) {
                return `Invalid brightness format: ${value}\nExpected: 0.1, +0.1, 0.1-, 10%, +10%, 10%-`;
            } else {
                targetBrightness = parseFloat(value);
            }

            if (isNaN(targetBrightness))
                return `Failed to parse value: ${value}\nExpected: 0.1, +0.1, 0.1-, 10%, +10%, 10%-`;

            monitor.setBrightness(targetBrightness);

            return `Set monitor ${monitor.modelData.name} brightness to ${+monitor.brightness.toFixed(2)} (${monitor.method}${monitor.method === "ddc" ? ", bus " + monitor.busNum : ""})`;
        }

        target: "brightness"
    }

    component Monitor: QtObject {
        id: monitor

        required property ShellScreen modelData

        readonly property bool isInternal: modelData.name.startsWith("eDP-") || modelData.name.startsWith("LVDS-") || modelData.name.startsWith("DSI-")
        readonly property var ddcInfo: root.ddcMonitorMap[modelData.name] ?? null
        readonly property string busNum: ddcInfo?.busNum ?? ""
        readonly property bool isAppleDisplay: root.appleDisplayPresent && modelData.model.startsWith("StudioDisplay")
        property bool ddcFailed: false
        property bool useBrightnessctl: false

        readonly property var hyprMonitor: Hypr.monitorFor(modelData)
        readonly property string cmPreset: hyprMonitor?.lastIpcObject?.colorManagementPreset ?? ""
        readonly property bool isHdr: cmPreset === "hdr" || cmPreset === "hdredid"
        // The EXACT selector of the user's config rule form (desc:), so a
        // partial runtime update merges into the winning rule instead of
        // resurrecting a stale name-keyed one.
        readonly property string hyprSelector: {
            const d = hyprMonitor?.lastIpcObject?.description;
            return d ? "desc:" + d : modelData.name;
        }

        readonly property var rule: {
            const rules = GlobalConfig.services.brightnessRules;
            if (!rules)
                return null;
            for (const r of rules) {
                const m = String(r.match ?? "");
                const hit = m.startsWith("model:") ? modelData.model === m.slice(6) : m.startsWith("serial:") ? modelData.serialNumber === m.slice(7) : m.startsWith("name:") ? modelData.name === m.slice(5) : modelData.name === m;
                if (hit)
                    return r;
            }
            return null;
        }

        // Resolution order: config rule > apple > internal backlight > HDR
        // (compositor SDR white — hardware VCP writes in HDR rescale the PQ
        // tone mapping) > DDC > unsupported. "backlight" is unreachable for
        // externals by construction: they stay "pending" during detection and
        // become "unsupported" if nothing matches — never the laptop panel.
        readonly property string method: {
            const r = rule;
            if (r?.method)
                return r.method === "none" ? "unsupported" : r.method;
            if (isAppleDisplay)
                return "apple";
            if (isInternal)
                return "backlight";
            if (isHdr)
                return "hdr";
            if (ddcInfo && !ddcFailed)
                return "ddc";
            return root.detecting ? "pending" : "unsupported";
        }

        readonly property int hdrMinNits: rule?.hdrMinNits ?? GlobalConfig.services.hdrMinNits
        // 100% point: per-monitor rule > panel-declared EDID peak > global default
        readonly property int hdrMaxNits: rule?.hdrMaxNits ?? (root.edidPeakMap[modelData.name] || GlobalConfig.services.hdrMaxNits)

        // The EDID peak lands after the sysfs pass; re-derive the displayed
        // slider position from the live nits value under the new scale.
        onHdrMaxNitsChanged: {
            if (method === "hdr" && !writer.inFlight && writer.pendingRaw < 0)
                initBrightness();
        }

        property real brightness
        // Bumped only by user/IPC intent — the OSD pops on this, not on
        // init/detect churn.
        property int userChangeSerial: 0
        // Buffered request while method is still "pending".
        property real pendingValue: NaN

        function rawFor(value: real): int {
            switch (method) {
            case "ddc":
                return Math.round(value * (ddcInfo?.max ?? 100));
            case "apple":
                return Math.round(value * 100);
            case "backlight":
                return Math.max(1, Math.round(value * root.backlightMax));
            case "hdr":
                return Math.round(hdrMinNits + value * (hdrMaxNits - hdrMinNits));
            }
            return 0;
        }

        function setBrightness(value: real): void {
            // Keep a floor on the panel backlight: raw 0 can mean fully off.
            const floor = method === "backlight" ? 0.01 : 0;
            value = Math.max(floor, Math.min(1, value));

            if (method === "unsupported") {
                userChangeSerial++; // still pop the OSD so the disabled state is discoverable
                return;
            }

            brightness = value;
            userChangeSerial++;

            if (method === "pending") {
                pendingValue = value;
                return;
            }

            writer.push(rawFor(value));
        }

        function initBrightness(): void {
            if (method === "ddc" && ddcInfo) {
                brightness = ddcInfo.cur / ddcInfo.max;
                writer.lastRaw = ddcInfo.cur;
            } else if (method === "hdr") {
                const lum = hyprMonitor?.lastIpcObject?.sdrMaxLuminance;
                if (lum !== undefined && hdrMaxNits > hdrMinNits) {
                    brightness = Math.max(0, Math.min(1, (lum - hdrMinNits) / (hdrMaxNits - hdrMinNits)));
                    writer.lastRaw = Math.round(lum);
                }
            } else if (method === "backlight") {
                syncBacklight();
            } else if (method === "apple") {
                initProc.command = ["asdbctl", "get"];
                initProc.running = true;
            }
        }

        function syncBacklight(): void {
            if (method === "backlight" && root.backlightMax > 0 && !writer.inFlight && writer.pendingRaw < 0) {
                brightness = root.backlightCur / root.backlightMax;
                writer.lastRaw = root.backlightCur;
            }
        }

        // Re-assert the slider value (used after hyprctl reload resets HDR SDR
        // luminance to the config file value).
        function pushCurrent(): void {
            writer.lastRaw = -1;
            writer.push(rawFor(brightness));
        }

        onMethodChanged: {
            writer.pendingRaw = -1;
            writer.lastRaw = -1;
            writer.failCount = 0;
            if (method === "pending" || method === "unsupported")
                return;
            if (!isNaN(pendingValue)) {
                const v = pendingValue;
                pendingValue = NaN;
                setBrightness(v);
            } else {
                initBrightness();
            }
        }

        onDdcInfoChanged: {
            ddcFailed = false;
            // A fresh detect pass re-read the hardware value (catches changes
            // made via the monitor's own OSD while we weren't looking).
            if (ddcInfo && method === "ddc" && !writer.inFlight && writer.pendingRaw < 0)
                initBrightness();
        }

        Component.onCompleted: {
            if (method !== "pending" && method !== "unsupported")
                initBrightness();
        }

        readonly property Process initProc: Process {
            stdout: StdioCollector {
                onStreamFinished: {
                    const val = parseInt(text.trim());
                    if (!isNaN(val)) {
                        monitor.brightness = val / 100;
                        monitor.writer.lastRaw = val;
                    }
                }
            }
        }

        // Keep-latest write queue: first write fires immediately (leading
        // edge), newer values replace the pending slot while one is in flight,
        // and a trailing write of the exact final value is guaranteed after a
        // per-method gap. Replaces the old trailing-only 500ms debounce.
        readonly property QtObject writer: QtObject {
            id: writer

            property int pendingRaw: -1
            property int lastRaw: -1
            property bool inFlight: false
            property int failCount: 0

            function push(raw: int): void {
                if (raw === lastRaw && pendingRaw < 0 && !inFlight)
                    return;
                if (inFlight || gapTimer.running || backoffTimer.running) {
                    pendingRaw = raw;
                    return;
                }
                send(raw);
            }

            function send(raw: int): void {
                lastRaw = raw;

                if (monitor.method === "hdr") {
                    // Socket write, fire-and-forget; throttle via gapTimer only.
                    Hypr.setMonitorRule(monitor.modelData.name, monitor.hyprSelector, {
                        sdr_max_luminance: raw
                    });
                    gapTimer.interval = 30;
                    gapTimer.restart();
                    return;
                }

                inFlight = true;
                if (monitor.method === "ddc")
                    writeProc.command = ["ddcutil", "--bus", monitor.busNum, "--noverify", "--skip-ddc-checks", "setvcp", "10", String(raw)];
                else if (monitor.method === "apple")
                    writeProc.command = ["asdbctl", "set", String(raw)];
                else if (monitor.useBrightnessctl)
                    writeProc.command = ["brightnessctl", "-d", root.backlightName, "s", String(raw)];
                else
                    writeProc.command = ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", root.backlightName, String(raw)];
                writeProc.running = true;
            }

            function pop(): void {
                if (pendingRaw < 0)
                    return;
                const r = pendingRaw;
                pendingRaw = -1;
                if (r !== lastRaw)
                    send(r);
            }

            readonly property Timer gapTimer: Timer {
                onTriggered: writer.pop()
            }

            readonly property Timer backoffTimer: Timer {
                onTriggered: {
                    const r = writer.pendingRaw >= 0 ? writer.pendingRaw : writer.lastRaw;
                    writer.pendingRaw = -1;
                    writer.send(r);
                }
            }

            readonly property Process writeProc: Process {
                stderr: StdioCollector {
                    id: writeErr
                }
                onExited: code => { // qmllint disable signal-handler-parameters
                    writer.inFlight = false;

                    if (code !== 0) {
                        if (monitor.method === "backlight" && !monitor.useBrightnessctl) {
                            // logind refused (no active session takeover?) — brightnessctl fallback
                            monitor.useBrightnessctl = true;
                            writer.send(writer.lastRaw);
                            return;
                        }
                        if (monitor.method === "ddc") {
                            writer.failCount++;
                            if (writer.failCount >= 3) {
                                console.warn(`[Brightness] DDC write to ${monitor.modelData.name} (bus ${monitor.busNum}) failed 3x: ${writeErr.text.trim()}`);
                                monitor.ddcFailed = true;
                                writer.pendingRaw = -1;
                                return;
                            }
                            writer.backoffTimer.interval = 1000 * writer.failCount;
                            writer.backoffTimer.restart();
                            return;
                        }
                    } else {
                        writer.failCount = 0;
                    }

                    const gap = monitor.method === "ddc" ? GlobalConfig.services.ddcMinWriteIntervalMs : monitor.method === "apple" ? 100 : 0;
                    if (gap > 0) {
                        writer.gapTimer.interval = gap;
                        writer.gapTimer.restart();
                    } else {
                        writer.pop();
                    }
                }
            }
        }
    }
}
