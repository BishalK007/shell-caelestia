pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ALSA hardware mixer (Master / Speaker / Headphone) for the internal sound card.
// Quickshell only exposes PipeWire, so the raw ALSA controls need `amixer`. Volumes
// are 0-100. Reads are ref-gated (only while the audio popout is open); writes are
// optimistic + debounced so dragging a slider doesn't spawn an amixer storm.
Singleton {
    id: root

    // Internal card. NixOS names it "Generic_1"; hw:<name> is stable across reboots
    // (unlike the numeric index, which shifts when USB audio devices come and go).
    readonly property string card: "hw:Generic_1"

    property bool available: false

    property int masterVolume: 100
    property bool masterMuted: false
    property int speakerVolume: 100
    property bool speakerMuted: false
    property int headphoneVolume: 100
    property bool headphoneMuted: false

    property int refCount

    function setVolume(control: string, percent: int): void {
        const clamped = Math.max(0, Math.min(100, Math.round(percent)));
        // Optimistic local update for a responsive slider; the periodic refresh reconciles.
        if (control === "Master")
            root.masterVolume = clamped;
        else if (control === "Speaker")
            root.speakerVolume = clamped;
        else if (control === "Headphone")
            root.headphoneVolume = clamped;
        _pendingVol = ["amixer", "-D", root.card, "set", control, `${clamped}%`];
        volDebounce.restart();
    }

    function setMuted(control: string, muted: bool): void {
        if (control === "Master")
            root.masterMuted = muted;
        else if (control === "Speaker")
            root.speakerMuted = muted;
        else if (control === "Headphone")
            root.headphoneMuted = muted;
        muteProc.command = ["amixer", "-D", root.card, "set", control, muted ? "mute" : "unmute"];
        muteProc.running = true;
    }

    function refresh(): void {
        getProc.running = true;
    }

    property var _pendingVol: []

    Timer {
        id: volDebounce

        interval: 40
        onTriggered: {
            if (volProc.running) {
                restart(); // amixer still busy, retry shortly with the latest pending value
                return;
            }
            volProc.command = root._pendingVol;
            volProc.running = true;
        }
    }

    Process {
        id: volProc
    }

    Process {
        id: muteProc
    }

    // Periodic re-read while the popout is open, so external changes (volume keys,
    // pavucontrol) are reflected. triggeredOnStart gives an immediate read on open.
    Timer {
        running: root.refCount > 0
        interval: 1500
        repeat: true
        triggeredOnStart: true
        onTriggered: getProc.running = true
    }

    Process {
        id: getProc

        command: ["sh", "-c", `for c in Master Speaker Headphone; do out=$(amixer -D ${root.card} get "$c" 2>/dev/null); pct=$(printf '%s' "$out" | grep -om1 '[0-9]*%' | tr -d '%'); st=$(printf '%s' "$out" | grep -om1 '\\[on\\]\\|\\[off\\]'); printf '%s|%s|%s\\n' "$c" "$pct" "$st"; done`]

        stdout: StdioCollector {
            onStreamFinished: {
                let any = false;
                for (const line of text.trim().split("\n")) {
                    const [control, pct, st] = line.split("|");
                    if (pct === "" && st === "")
                        continue;
                    any = true;
                    const vol = parseInt(pct, 10) || 0;
                    const muted = st === "[off]";
                    if (control === "Master") {
                        root.masterVolume = vol;
                        root.masterMuted = muted;
                    } else if (control === "Speaker") {
                        root.speakerVolume = vol;
                        root.speakerMuted = muted;
                    } else if (control === "Headphone") {
                        root.headphoneVolume = vol;
                        root.headphoneMuted = muted;
                    }
                }
                root.available = any;
            }
        }
    }
}
