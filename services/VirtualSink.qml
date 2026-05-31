pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Caelestia.Config
import qs.services
import qs.utils

// Virtual-sink routing. Volume/mute/pin are native PwNode.audio writes; only device routing
// (which Quickshell's read-only PwLink can't do) shells out to pw-link.
//
// Graph (NixOS PipeWire config): app -> music_sink -> music_sink.output -> <selected physical>.
//   music_sink            the default output you select in "Output Devices" (apps land here)
//   music_sink.output     loopback, pinned to unity (the "quiet at 100%" fix)
//   <selected physical>   the device music actually comes out of; its volume IS the "Music" slider
//   notification_sink      -> notification_sink.output -> ALL physical sinks (alert bus)
//
// Output selection is a small state machine: persisted across reboots, auto-switches to a newly
// connected device, falls back through an MRU stack when one disconnects, and always keeps
// exactly one valid device selected.
Singleton {
    id: root

    readonly property string musicSinkName: "music_sink"
    readonly property string notificationSinkName: "notification_sink"
    readonly property string musicLoopbackName: "music_sink.output"
    readonly property string notificationLoopbackName: "notification_sink.output"

    readonly property PwNode musicSink: Audio.sinks.find(n => n?.name === root.musicSinkName) ?? null
    readonly property PwNode notificationSink: Audio.sinks.find(n => n?.name === root.notificationSinkName) ?? null
    readonly property PwNode musicLoopback: Audio.streams.find(n => n?.name === root.musicLoopbackName) ?? null
    readonly property PwNode notificationLoopback: Audio.streams.find(n => n?.name === root.notificationLoopbackName) ?? null

    // Real output devices = sinks minus our virtual ones.
    readonly property list<PwNode> physicalSinks: Audio.sinks.filter(n => n && n.name !== root.musicSinkName && n.name !== root.notificationSinkName)

    readonly property bool available: musicSink !== null || notificationSink !== null

    // node.name of the physical device music currently routes to (persisted).
    property string musicOutput: ""
    // Most-recently-used preference order for fallback when devices disconnect (persisted).
    property var outputStack: []

    readonly property PwNode musicOutputNode: physicalSinks.find(n => n?.name === root.musicOutput) ?? null
    // "Music: <name>" label (B)
    readonly property string musicOutputLabel: musicOutputNode?.description ?? musicOutputNode?.name ?? qsTr("None")

    // The "Music" slider (C) is the SELECTED OUTPUT DEVICE's volume — not music_sink's.
    readonly property real outputVolume: musicOutputNode?.audio?.volume ?? 0
    readonly property bool outputMuted: !!musicOutputNode?.audio?.muted

    readonly property real notificationVolume: notificationSink?.audio?.volume ?? 0
    readonly property bool notificationMuted: !!notificationSink?.audio?.muted

    // music_sink's own volume — persisted only (it's a null-sink recreated at unity each boot,
    // and it's what the Main Sound slider drives whenever Music Virtual Sink is the default).
    readonly property real musicSinkVolume: musicSink?.audio?.volume ?? 0

    property bool _stateLoaded: false
    property bool _inited: false
    property var _prevSinkNames: []
    property real _savedMusicSinkVol: -1
    property real _savedNotifVol: -1
    // Saved volumes are restored to the null-sinks exactly ONCE (when they first become ready),
    // never re-applied afterwards — otherwise every notification/device change would clobber a
    // volume the user just set on the slider.
    property bool _musicVolRestored: false
    property bool _notifVolRestored: false

    // ── Selected-output volume/mute (C) ──────────────────────────────────────────
    function setOutputVolume(v: real): void {
        if (musicOutputNode?.ready && musicOutputNode?.audio) {
            musicOutputNode.audio.muted = false;
            musicOutputNode.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, v));
        }
    }

    function setOutputMuted(m: bool): void {
        if (musicOutputNode?.ready && musicOutputNode?.audio)
            musicOutputNode.audio.muted = m;
    }

    // ── Notification (alert bus) ─────────────────────────────────────────────────
    function setNotificationVolume(v: real): void {
        if (notificationSink?.ready && notificationSink?.audio) {
            notificationSink.audio.muted = false;
            notificationSink.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, v));
        }
    }

    function setNotificationMuted(m: bool): void {
        if (notificationSink?.ready && notificationSink?.audio)
            notificationSink.audio.muted = m;
    }

    // Pin the loopback "*.output" routing streams to unity gain + unmuted (the "quiet at 100%" fix).
    function pinLoopbacks(): void {
        if (musicLoopback?.ready && musicLoopback?.audio) {
            musicLoopback.audio.muted = false;
            if (Math.abs((musicLoopback.audio.volume ?? 1) - 1) > 0.001)
                musicLoopback.audio.volume = 1;
        }
        if (notificationLoopback?.ready && notificationLoopback?.audio) {
            notificationLoopback.audio.muted = false;
            if (Math.abs((notificationLoopback.audio.volume ?? 1) - 1) > 0.001)
                notificationLoopback.audio.volume = 1;
        }
    }

    // User manually picks a music output device.
    function setMusicOutput(node: PwNode): void {
        if (node?.name)
            _selectOutput(node.name);
    }

    // Apply a selection: record it (MRU front), route music_sink.output -> it, persist.
    function _selectOutput(name: string): void {
        console.log(`[VirtualSink] route music -> ${name}`);
        root.musicOutput = name;
        root.outputStack = [name, ...root.outputStack.filter(n => n !== name)];
        relinkProc.command = ["sh", "-c", root._relinkScript(root.musicLoopbackName, [name])];
        relinkProc.running = true;
        root.save();
    }

    // Selection state machine. Decides which physical device music routes to whenever the device
    // set changes (and at startup), then applies it. Guarantees one valid selection at all times.
    function _reconcileOutput(): void {
        if (!_stateLoaded)
            return;

        const curr = physicalSinks.map(n => n.name).filter(Boolean);
        if (curr.length === 0) {
            // Everything dropped out (e.g. mid Bluetooth renegotiation). Keep the saved
            // selection so we can restore it when devices return; don't clear it.
            root._prevSinkNames = [];
            return;
        }

        const prev = root._prevSinkNames;
        const added = curr.filter(n => !prev.includes(n));

        let target;
        if (_inited && prev.length > 0 && added.length > 0)
            // A genuinely new device connected at runtime -> switch to it (newest wins).
            target = added[added.length - 1];
        else if (root.musicOutput && curr.includes(root.musicOutput))
            // Current selection still present -> keep it.
            target = root.musicOutput;
        else
            // Startup restore, or current device gone -> first available in MRU order, else first device.
            target = root.outputStack.find(n => curr.includes(n)) ?? curr[0];

        root._prevSinkNames = curr;
        console.log(`[VirtualSink] reconcile curr=[${curr}] added=[${added}] inited=${_inited} cur=${root.musicOutput} -> ${target}`);

        // Re-route on change, and once on first init even if unchanged (boot may not be linked yet).
        if (target && (target !== root.musicOutput || !_inited))
            _selectOutput(target);
    }

    function linkNotificationToAll(): void {
        const names = physicalSinks.map(n => n.name).filter(Boolean);
        if (names.length === 0)
            return;
        notifLinkProc.command = ["sh", "-c", root._relinkScript(root.notificationLoopbackName, names)];
        notifLinkProc.running = true;
    }

    // Disconnect every existing link from <out>:output_* then link it to each target's
    // :playback_FL/FR. awk pairs each source output port with its `|->` target.
    function _relinkScript(out: string, targets: var): string {
        let s = `pw-link -l 2>/dev/null | awk -v o="${out}" '/^[^[:space:]]/ { src = ($1 ~ "^"o":output_") ? $1 : ""; next } /\\|->/ && src != "" { print src, $2 }' | while read -r src tgt; do pw-link -d "$src" "$tgt" 2>/dev/null; done; `;
        for (const tgt of targets)
            s += `pw-link "${out}:output_FL" "${tgt}:playback_FL" 2>/dev/null; pw-link "${out}:output_FR" "${tgt}:playback_FR" 2>/dev/null; `;
        return s;
    }

    function save(): void {
        if (!root._stateLoaded)
            return;
        stateFile.setText(JSON.stringify({
            musicOutput: root.musicOutput,
            outputStack: root.outputStack,
            musicSinkVolume: root.musicSinkVolume,
            notificationVolume: root.notificationVolume
        }));
    }

    // Restore each null-sink's saved volume EXACTLY ONCE, when it first becomes ready. After that
    // the user owns the slider — we never write the volume again, so notifications/device changes
    // can't snap it back to the boot value.
    function _restoreVolumes(): void {
        if (!_notifVolRestored && _savedNotifVol >= 0 && notificationSink?.ready && notificationSink?.audio) {
            notificationSink.audio.volume = _savedNotifVol;
            _notifVolRestored = true;
        }
        if (!_musicVolRestored && _savedMusicSinkVol >= 0 && musicSink?.ready && musicSink?.audio) {
            musicSink.audio.volume = _savedMusicSinkVol;
            _musicVolRestored = true;
        }
    }

    // Sinks changed (device connect/disconnect): re-decide the output, re-fan notifications, pin
    // loopbacks. _reconcileOutput reads _inited to tell the first (restore) pass from runtime ones.
    function _update(): void {
        if (!_stateLoaded)
            return;
        pinLoopbacks();
        _reconcileOutput();
        linkNotificationToAll();
        _restoreVolumes();
        _inited = true;
    }

    // Streams changed (loopbacks appearing, an app/sound starting): only keep the loopbacks pinned
    // and do the one-time volume restore. Crucially does NOT touch the notification volume or
    // re-link — so playing a notification sound can't reset the slider the user set.
    function _onStreams(): void {
        if (!_stateLoaded)
            return;
        pinLoopbacks();
        _restoreVolumes();
    }

    onMusicSinkVolumeChanged: saveDebounce.restart()
    onNotificationVolumeChanged: saveDebounce.restart()

    // Any sink change (device connect/disconnect, BT profile switch) re-evaluates the selection.
    // Driven off Audio.sinks directly because a bound list<> property's own change signal isn't
    // always emitted reliably. Debounced so Bluetooth renegotiation bursts don't spam pw-link.
    Connections {
        target: Audio

        function onSinksChanged(): void {
            sinksDebounce.restart();
        }

        // Loopback "*.output" nodes live in Audio.streams; re-run the lightweight path so they get
        // pinned once present, without touching volume or routing on every app/sound stream.
        function onStreamsChanged(): void {
            streamsDebounce.restart();
        }
    }

    Timer {
        id: sinksDebounce

        interval: 250
        onTriggered: root._update()
    }

    Timer {
        id: streamsDebounce

        interval: 250
        onTriggered: root._onStreams()
    }

    Process {
        id: relinkProc
    }

    Process {
        id: notifLinkProc
    }

    Timer {
        id: saveDebounce

        interval: 500
        onTriggered: root.save()
    }

    FileView {
        id: stateFile

        path: `${Paths.state}/audio-virtualsink.json`
        onLoaded: {
            try {
                const c = JSON.parse(text());
                if (c.musicOutput)
                    root.musicOutput = c.musicOutput;
                if (Array.isArray(c.outputStack))
                    root.outputStack = c.outputStack;
                root._savedMusicSinkVol = c.musicSinkVolume ?? -1;
                root._savedNotifVol = c.notificationVolume ?? -1;
            } catch (e) {}
            root._stateLoaded = true;
            sinksDebounce.restart();
        }
        onLoadFailed: {
            root._stateLoaded = true;
            sinksDebounce.restart();
        }
    }
}
