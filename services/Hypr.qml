pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.Internal
import qs.components.misc

Singleton {
    id: root

    readonly property var toplevels: Hyprland.toplevels
    readonly property var workspaces: Hyprland.workspaces
    readonly property var monitors: Hyprland.monitors

    readonly property HyprlandToplevel activeToplevel: {
        const t = Hyprland.activeToplevel;
        return t?.workspace?.name.startsWith("special:") || Hyprland.focusedWorkspace?.toplevels.values.length > 0 ? t : null;
    }
    readonly property HyprlandWorkspace focusedWorkspace: Hyprland.focusedWorkspace
    readonly property HyprlandMonitor focusedMonitor: Hyprland.focusedMonitor
    readonly property int activeWsId: focusedWorkspace?.id ?? 1

    readonly property HyprKeyboard keyboard: extras.devices.keyboards.find(kb => kb.main) ?? null
    readonly property bool capsLock: keyboard?.capsLock ?? false
    readonly property bool numLock: keyboard?.numLock ?? false
    readonly property string defaultKbLayout: keyboard?.layout.split(",")[0] ?? "??"
    readonly property string kbLayoutFull: keyboard?.activeKeymap ?? "Unknown"
    readonly property string kbLayout: kbMap.get(kbLayoutFull) ?? "??"
    readonly property var kbMap: new Map()

    readonly property alias extras: extras
    readonly property alias options: extras.options
    readonly property alias devices: extras.devices

    property bool hadKeyboard
    property string lastSpecialWorkspace: ""

    // True when Hyprland runs the Lua config manager (hyprland.lua): the
    // request socket then evaluates dispatch args as Lua ("dispatch X" becomes
    // "return hl.dispatch(X)" server-side), so classic dispatcher strings must
    // be translated to hl.dsp.* factory expressions. Probed once at startup:
    // "eval" only exists under the Lua manager.
    property bool luaConfig: false

    // Until the probe resolves, the config-manager mode is UNKNOWN — any
    // mode-dependent request sent before that races into the wrong branch
    // (e.g. Colours' startup border push became a rejected `keyword` under
    // Lua). Queue them and flush once the probe lands.
    property bool cmProbed: false
    property var _pendingModeRequests: []

    signal configReloaded
    signal monitorsHotplugged

    function _deferUntilProbed(thunk: var): bool {
        if (root.cmProbed)
            return false;
        root._pendingModeRequests.push(thunk);
        return true;
    }

    function dispatch(request: string): void {
        if (_deferUntilProbed(() => root.dispatch(request)))
            return;
        Hyprland.dispatch(root.luaConfig ? root.luaDispatch(request) : request);
    }

    // A full socket request line for the given classic dispatch (for
    // batchMessage callers, which send raw requests).
    function dispatchRequest(request: string): string {
        return "dispatch " + (root.luaConfig ? root.luaDispatch(request) : request);
    }

    // Classic dispatcher string -> hl.dsp.* Lua expression (hyprland 0.56.2
    // Lua config manager; see the window-switcher DESIGN.md for the mapping
    // source). Unknown verbs pass through with a warning.
    function luaDispatch(request: string): string {
        if (request.startsWith("hl."))
            return request; // already typed-Lua

        const sp = request.indexOf(" ");
        const verb = sp < 0 ? request : request.slice(0, sp);
        const rest = sp < 0 ? "" : request.slice(sp + 1).trim();
        const q = s => `"${String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;

        switch (verb) {
        case "submap":
            return `hl.dsp.submap(${q(rest)})`;
        case "global":
            return `hl.dsp.global(${q(rest)})`;
        case "focuswindow":
            return `hl.dsp.focus({window=${q(rest)}})`;
        case "workspace":
            return `hl.dsp.focus({workspace=${q(rest)}})`;
        case "togglespecialworkspace":
            return rest ? `hl.dsp.workspace.toggle_special(${q(rest)})` : "hl.dsp.workspace.toggle_special()";
        case "movecursor": {
            const parts = rest.split(/\s+/);
            return `hl.dsp.cursor.move({x=${Number(parts[0]) || 0}, y=${Number(parts[1]) || 0}})`;
        }
        case "movetoworkspace":
        case "movetoworkspacesilent": {
            const ci = rest.indexOf(",");
            const ws = ci < 0 ? rest : rest.slice(0, ci);
            const win = ci < 0 ? "" : rest.slice(ci + 1);
            const follow = verb === "movetoworkspace" ? "true" : "false";
            return win ? `hl.dsp.window.move({workspace=${q(ws)}, window=${q(win)}, follow=${follow}})` : `hl.dsp.window.move({workspace=${q(ws)}, follow=${follow}})`;
        }
        case "togglefloating":
            return rest ? `hl.dsp.window.float({window=${q(rest)}})` : "hl.dsp.window.float({})";
        case "layoutmsg":
            return `hl.dsp.layout(${q(rest)})`;
        case "dpms": {
            const parts = rest.split(/\s+/);
            return parts[1] ? `hl.dsp.dpms({action=${q(parts[0])}, monitor=${q(parts[1])}})` : `hl.dsp.dpms({action=${q(parts[0])}})`;
        }
        case "moveworkspacetomonitor": {
            const parts = rest.split(/\s+/);
            return `hl.dsp.workspace.move({workspace=${q(parts[0])}, monitor=${q(parts[1] ?? "")}})`;
        }
        case "exec":
            return `hl.dsp.exec_cmd(${q(rest)})`;
        case "execr":
            return `hl.dsp.exec_raw(${q(rest)})`;
        case "pin":
            return rest ? `hl.dsp.window.pin({window=${q(rest)}})` : "hl.dsp.window.pin({})";
        case "killwindow":
            // window.kill is the forceful legacy killwindow; window.close is graceful.
            return rest ? `hl.dsp.window.kill({window=${q(rest)}})` : "hl.dsp.window.kill({})";
        default:
            console.warn(`[Hypr] no Lua translation for dispatcher "${verb}" — sending classic form`);
            return request;
        }
    }

    function cycleSpecialWorkspace(direction: string): void {
        const openSpecials = workspaces.values.filter(w => w.name.startsWith("special:") && w.lastIpcObject.windows > 0);

        if (openSpecials.length === 0)
            return;

        const activeSpecial = focusedMonitor.lastIpcObject.specialWorkspace.name ?? "";

        if (!activeSpecial) {
            if (lastSpecialWorkspace) {
                const workspace = workspaces.values.find(w => w.name === lastSpecialWorkspace);
                if (workspace && workspace.lastIpcObject.windows > 0) {
                    dispatch(`workspace ${lastSpecialWorkspace}`);
                    return;
                }
            }
            dispatch(`workspace ${openSpecials[0].name}`);
            return;
        }

        const currentIndex = openSpecials.findIndex(w => w.name === activeSpecial);
        let nextIndex = 0;

        if (currentIndex !== -1) {
            if (direction === "next")
                nextIndex = (currentIndex + 1) % openSpecials.length;
            else
                nextIndex = (currentIndex - 1 + openSpecials.length) % openSpecials.length;
        }

        dispatch(`workspace ${openSpecials[nextIndex].name}`);
    }

    function monitorNames(): list<string> {
        return monitors.values.map(e => e.name);
    }

    function monitorFor(screen: ShellScreen): HyprlandMonitor {
        // Resolve by name over the live list instead of Hyprland.monitorFor: hotplug
        // destroys and recreates HyprlandMonitor objects, and reading monitors.values
        // here makes caller BINDINGS re-evaluate when the list changes, so they pick up
        // the new object instead of keeping a stale/null one forever.
        return monitors.values.find(m => m.name === screen?.name) ?? null;
    }

    // Set live config values. `values` maps CLASSIC keys ("general:col.active_border")
    // to string values ("rgba(aabbccff)"). Legacy: one keyword per entry. Lua:
    // one eval hl.config — keys transform ":"->"." and "-"->"_", values stay
    // strings (the gradient/color parser accepts rgba(...) verbatim), and
    // hl.config MERGES (only listed keys change), applying live.
    function setConfigValues(values: var): void {
        if (_deferUntilProbed(() => root.setConfigValues(values)))
            return;
        if (root.luaConfig) {
            const entries = [];
            for (const k in values)
                entries.push(`["${k.replace(/:/g, ".").replace(/-/g, "_")}"] = "${values[k]}"`);
            extras.batchMessage([`eval hl.config({ ${entries.join(", ")} })`]);
        } else {
            const reqs = [];
            for (const k in values)
                reqs.push(`keyword ${k} ${values[k]}`);
            extras.batchMessage(reqs);
        }
    }

    // Update a monitor rule live. `fields` maps monitorv2 option names
    // (sdr_max_luminance, ...) to values; numbers stay unquoted. Lua: hl.monitor
    // MERGES into the rule matching `selector` (verified: mode/scale/bitdepth
    // survive a partial update). The selector must be the EXACT output string of
    // the winning config rule (e.g. "desc:...") — a name selector like "DP-2"
    // can resurrect a stale name-keyed rule as the winning one. Legacy hyprlang
    // falls back to per-field monitorv2 keywords addressed by connector name.
    function setMonitorRule(name: string, selector: string, fields: var): void {
        if (_deferUntilProbed(() => root.setMonitorRule(name, selector, fields)))
            return;
        if (root.luaConfig) {
            const entries = [`output = "${selector.replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`];
            for (const k in fields) {
                const v = fields[k];
                entries.push(typeof v === "number" ? `${k} = ${v}` : `${k} = "${v}"`);
            }
            extras.batchMessage([`eval hl.monitor({ ${entries.join(", ")} })`]);
        } else {
            const reqs = [];
            for (const k in fields)
                reqs.push(`keyword monitorv2[${name}]:${k} ${fields[k]}`);
            extras.batchMessage(reqs);
        }
    }

    // Set layer rules for a layershell namespace. `effects` maps effect names
    // (blur, ignore_alpha, ...) to bool/number values. Lua: one NAMED rule per
    // effect — a stable name makes re-issues reuse the rule (matches replace;
    // effects append but application is last-wins, so re-theming stays correct).
    function setLayerRules(namespace: string, effects: var): void {
        if (_deferUntilProbed(() => root.setLayerRules(namespace, effects)))
            return;
        const reqs = [];
        if (root.luaConfig) {
            for (const k in effects) {
                const v = effects[k];
                const lv = typeof v === "boolean" ? (v ? "true" : "false") : String(v);
                reqs.push(`eval hl.layer_rule({ name="caelestia-${namespace}-${k}", match={ namespace="${namespace}" }, ${k}=${lv} })`);
            }
        } else {
            for (const k in effects) {
                const v = effects[k];
                const cv = typeof v === "boolean" ? (v ? 1 : 0) : v;
                reqs.push(`keyword layerrule ${k} ${cv}, match:namespace ${namespace}`);
            }
        }
        extras.batchMessage(reqs);
    }

    function reloadDynamicConfs(): void {
        if (root.luaConfig) {
            // "keyword" is rejected by the Lua config manager ("Use eval");
            // hl.bind adds the keybind immediately at runtime. A config reload
            // wipes runtime binds, and configReloaded re-runs this — no dupes.
            const opts = "{ locked = true, non_consuming = true, ignore_mods = true }";
            extras.batchMessage([`eval hl.bind("Caps_Lock", hl.dsp.global("caelestia:refreshDevices"), ${opts})`, `eval hl.bind("Num_Lock", hl.dsp.global("caelestia:refreshDevices"), ${opts})`]);
        } else {
            extras.batchMessage(["keyword bindlni ,Caps_Lock,global,caelestia:refreshDevices", "keyword bindlni ,Num_Lock,global,caelestia:refreshDevices"]);
        }
    }

    // Probe the config-manager type BEFORE the first dynamic-conf push:
    // "eval" only exists under the Lua manager (legacy replies with a fixed
    // error string, never "ok").
    Process {
        id: luaProbe

        command: ["hyprctl", "eval", "return true"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.luaConfig = text.trim() === "ok";
                root.cmProbed = true;
                if (root.luaConfig)
                    console.info("[Hypr] Lua config manager detected — dispatches translate to hl.dsp.*");
                root.reloadDynamicConfs();
                // Flush requests that arrived before the mode was known.
                const pending = root._pendingModeRequests;
                root._pendingModeRequests = [];
                for (const thunk of pending)
                    thunk();
            }
        }
    }

    Component.onCompleted: luaProbe.running = true

    onCapsLockChanged: {
        if (!GlobalConfig.utilities.toasts.capsLockChanged)
            return;

        if (capsLock)
            Toaster.toast(qsTr("Caps lock enabled"), qsTr("Caps lock is currently enabled"), "keyboard_capslock_badge");
        else
            Toaster.toast(qsTr("Caps lock disabled"), qsTr("Caps lock is currently disabled"), "keyboard_capslock");
    }

    onNumLockChanged: {
        if (!GlobalConfig.utilities.toasts.numLockChanged)
            return;

        if (numLock)
            Toaster.toast(qsTr("Num lock enabled"), qsTr("Num lock is currently enabled"), "looks_one");
        else
            Toaster.toast(qsTr("Num lock disabled"), qsTr("Num lock is currently disabled"), "timer_1");
    }

    onKbLayoutFullChanged: {
        if (hadKeyboard && GlobalConfig.utilities.toasts.kbLayoutChanged)
            Toaster.toast(qsTr("Keyboard layout changed"), qsTr("Layout changed to: %1").arg(kbLayoutFull), "keyboard");

        hadKeyboard = !!keyboard;
    }

    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;
            if (n.endsWith("v2"))
                return;

            if (n === "configreloaded") {
                // Monitor rules (cm/HDR presets, sdr luminance) may have changed
                // and there is no separate event for that — refresh so consumers
                // (e.g. Brightness method resolution) see the new state.
                Hyprland.refreshMonitors();
                root.configReloaded();
                root.reloadDynamicConfs();
            } else if (n === "monitoradded" || n === "monitorremoved") {
                root.monitorsHotplugged();
                Hyprland.refreshMonitors();
            } else if (["workspace", "moveworkspace", "activespecial", "focusedmon"].includes(n)) {
                Hyprland.refreshWorkspaces();
                Hyprland.refreshMonitors();
            } else if (["openwindow", "closewindow", "movewindow"].includes(n)) {
                Hyprland.refreshToplevels();
                Hyprland.refreshWorkspaces();
            } else if (n.includes("mon")) {
                Hyprland.refreshMonitors();
            } else if (n.includes("workspace")) {
                Hyprland.refreshWorkspaces();
            } else if (n.includes("window") || n.includes("group") || ["pin", "fullscreen", "changefloatingmode", "minimize"].includes(n)) {
                Hyprland.refreshToplevels();
            }
        }

        target: Hyprland
    }

    Connections {
        function onLastIpcObjectChanged(): void {
            const specialName = root.focusedMonitor.lastIpcObject.specialWorkspace.name;

            if (specialName && specialName.startsWith("special:")) {
                root.lastSpecialWorkspace = specialName;
            }
        }

        target: root.focusedMonitor
    }

    FileView {
        id: kbLayoutFile

        path: Quickshell.env("CAELESTIA_XKB_RULES_PATH") || "/usr/share/X11/xkb/rules/base.lst"
        onLoaded: {
            const layoutMatch = text().match(/! layout\n([\s\S]*?)\n\n/);
            if (layoutMatch) {
                const lines = layoutMatch[1].split("\n");
                for (const line of lines) {
                    if (!line.trim() || line.trim().startsWith("!"))
                        continue;

                    const match = line.match(/^\s*([a-z]{2,})\s+([a-zA-Z() ]+)$/);
                    if (match)
                        root.kbMap.set(match[2], match[1]);
                }
            }

            const variantMatch = text().match(/! variant\n([\s\S]*?)\n\n/);
            if (variantMatch) {
                const lines = variantMatch[1].split("\n");
                for (const line of lines) {
                    if (!line.trim() || line.trim().startsWith("!"))
                        continue;

                    const match = line.match(/^\s*([a-zA-Z0-9_-]+)\s+([a-z]{2,}): (.+)$/);
                    if (match)
                        root.kbMap.set(match[3], match[2]);
                }
            }
        }
    }

    IpcHandler {
        function refreshDevices(): void {
            extras.refreshDevices();
        }

        function cycleSpecialWorkspace(direction: string): void {
            root.cycleSpecialWorkspace(direction);
        }

        function listSpecialWorkspaces(): string {
            return root.workspaces.values.filter(w => w.name.startsWith("special:") && w.lastIpcObject.windows > 0).map(w => w.name).join("\n");
        }

        target: "hypr"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "refreshDevices"
        description: "Reload devices"
        onPressed: extras.refreshDevices()
        onReleased: extras.refreshDevices()
    }

    HyprExtras {
        id: extras
    }
}
