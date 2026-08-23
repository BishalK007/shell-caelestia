pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Caelestia.Config
import qs.services
import qs.utils

// Persistent volumes, keyed by identifiers that survive reboots (PipeWire node.name,
// application.name, ALSA control name — never the numeric node id, which reshuffles).
//
// Keys (all volumes stored 0..1):
//   sink:<node.name>    physical output while it is DIRECTLY the default sink
//   music:<node.name>   the same physical output while driven THROUGH music_sink — a
//                       separate pair key (music_sink + its selected output), so the
//                       direct and via-music volumes of one device are remembered apart
//   source:<node.name>  input device (applied when it becomes the default source)
//   app:<app name>      per-application playback stream (applied when the app appears)
//   alsa:<control>      ALSA hardware control (Master/Speaker/Headphone)
//
// Saves happen only on shell-initiated changes (the setters in Audio/VirtualSink/Alsa
// call remember*), never by observing node volumes — so our own restores and transient
// device states can't clobber what the user set. music_sink's and notification_sink's
// own volumes are already persisted by VirtualSink; this service skips them.
Singleton {
    id: root

    // MASTER SWITCH — memorization is OFF. The restore machinery was force-applying
    // stale values into the music chain (e.g. a mis-captured `sink:` volume for the
    // routed output landing on it during default-sink races), choking playback below
    // what every slider showed. Keep this false until the redesigned scheme lands.
    readonly property bool enabled: false

    // key -> volume (0..1). Reassigned on change so bindings (e.g. the Headphone
    // display fallback in Alsa) stay reactive.
    property var volumes: ({})
    property bool loaded: false

    function recall(key: string): real {
        const v = root.volumes[key];
        return v === undefined || v === null ? -1 : v;
    }

    function remember(key: string, vol: real): void {
        if (!root.enabled || !key || !(vol >= 0))
            return;
        root.volumes = Object.assign({}, root.volumes, {
            [key]: vol
        });
        saveDebounce.restart();
    }

    // ── Save hooks (called from the volume setters) ──────────────────────────────
    function rememberSinkVolume(node: PwNode, vol: real): void {
        // Virtual sinks persist their own volumes in VirtualSink's state file.
        if (node?.name && node.name !== VirtualSink.musicSinkName && node.name !== VirtualSink.notificationSinkName)
            remember(`sink:${node.name}`, vol);
    }

    function rememberMusicVolume(node: PwNode, vol: real): void {
        if (node?.name)
            remember(`music:${node.name}`, vol);
    }

    function rememberSourceVolume(node: PwNode, vol: real): void {
        if (node?.name)
            remember(`source:${node.name}`, vol);
    }

    function rememberStreamVolume(node: PwNode, vol: real): void {
        if (!node?.isSink || node.name === VirtualSink.musicLoopbackName || node.name === VirtualSink.notificationLoopbackName)
            return;
        remember(`app:${Audio.getStreamName(node)}`, vol);
    }

    // ── Restore: pending applies wait for the node to become ready ──────────────
    property var _pending: ({})
    property int _pumpTicks: 0

    function _schedule(key: string, node: PwNode): void {
        if (!root.enabled || !key || !node)
            return;
        const p = Object.assign({}, root._pending);
        p[key] = node;
        root._pending = p;
        root._pumpTicks = 0;
        pump.start();
    }

    function _apply(key: string, node: PwNode): void {
        if (!root.enabled)
            return;
        const v = recall(key);
        if (v >= 0) {
            node.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, v));
            console.log(`[AudioPersist] restore ${key} -> ${Math.round(v * 100)}%`);
        }
    }

    function _pump(): void {
        if (!root.loaded) {
            if (++root._pumpTicks > 40)
                pump.stop();
            return;
        }
        const rest = {};
        for (const key of Object.keys(root._pending)) {
            const node = root._pending[key];
            try {
                if (!node)
                    continue; // device vanished while pending
                if (node.ready && node.audio)
                    _apply(key, node);
                else
                    rest[key] = node;
            } catch (e) {} // node destroyed mid-check: drop it
        }
        root._pending = rest;
        if (Object.keys(rest).length === 0 || ++root._pumpTicks > 40)
            pump.stop();
    }

    // ── Selection events ─────────────────────────────────────────────────────────
    function _onSinkSelected(): void {
        const s = Audio.sink;
        if (!s?.name)
            return;
        if (s.name === VirtualSink.musicSinkName)
            // Default is the music virtual sink: the audible volume is the routed
            // physical device's — restore its PAIR volume, not its direct one.
            _onMusicPair();
        else if (s.name !== VirtualSink.notificationSinkName)
            _schedule(`sink:${s.name}`, s);
    }

    function _onMusicPair(): void {
        // The pair volume only owns the device while music_sink is the default output.
        if (Audio.sink?.name !== VirtualSink.musicSinkName)
            return;
        const node = VirtualSink.musicOutputNode;
        if (node?.name)
            _schedule(`music:${node.name}`, node);
    }

    function _onSourceSelected(): void {
        const s = Audio.source;
        if (s?.name)
            _schedule(`source:${s.name}`, s);
    }

    // ── Application streams: restore once per stream, when it first appears ─────
    property var _appliedStreams: ({})
    property int _streamTicks: 0

    function _applyStreams(): void {
        if (!root.enabled || !root.loaded)
            return;
        let waiting = false;
        for (const s of Audio.streams) {
            if (!s?.isSink || s.name === VirtualSink.musicLoopbackName || s.name === VirtualSink.notificationLoopbackName)
                continue;
            if (root._appliedStreams[s.id])
                continue;
            if (!s.ready || !s.audio) {
                waiting = true;
                continue;
            }
            root._appliedStreams[s.id] = true;
            _apply(`app:${Audio.getStreamName(s)}`, s);
        }
        if (waiting && ++root._streamTicks < 40)
            streamsDebounce.restart();
    }

    Connections {
        target: Audio

        function onSinkChanged(): void {
            root._onSinkSelected();
        }

        function onSourceChanged(): void {
            root._onSourceSelected();
        }

        function onStreamsChanged(): void {
            root._streamTicks = 0;
            streamsDebounce.restart();
        }
    }

    Connections {
        target: VirtualSink

        // Fires on manual pick, MRU fallback and boot restore alike.
        function onMusicOutputChanged(): void {
            root._onMusicPair();
        }
    }

    Timer {
        id: pump

        interval: 250
        repeat: true
        onTriggered: root._pump()
    }

    Timer {
        id: streamsDebounce

        interval: 300
        onTriggered: root._applyStreams()
    }

    Timer {
        id: saveDebounce

        interval: 500
        onTriggered: stateFile.setText(JSON.stringify(root.volumes))
    }

    function _init(): void {
        root.loaded = true;
        if (!root.enabled)
            return;
        // Catch selections that were announced before our state file loaded.
        _onSinkSelected();
        _onSourceSelected();
        _applyStreams();
        // Pull the Alsa singleton in at startup so hardware volumes restore at boot,
        // not on first popout open (its reads are otherwise ref-gated).
        Alsa.restoreSaved();
    }

    FileView {
        id: stateFile

        path: `${Paths.state}/audio-volumes.json`
        onLoaded: {
            try {
                const c = JSON.parse(text());
                if (c && typeof c === "object")
                    root.volumes = c;
            } catch (e) {}
            root._init();
        }
        onLoadFailed: root._init()
    }
}
