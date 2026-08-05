pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Front-end for voice dictation with two engines:
//  - Wispr Flow:  driven via `wispr-flow wispr-flow://{start,stop}-hands-free`
//  - OpenWhispr:  driven via its D-Bus `Toggle` (start when idle, stop->transcribe->paste)
// Neither engine reports state back to us, so we drive our own listening/converting state and
// visualise it in the bottom popup. The hotkey first opens a picker (DictationPicker) to choose
// the engine; pressing the hotkey again cycles the selection, Enter/click starts it.
Singleton {
    id: root

    readonly property string service: "com.openwhispr.App"
    readonly property string path: "/com/openwhispr/App"
    readonly property string iface: "com.openwhispr.App"

    readonly property var providers: [
        {
            id: "wisprflow",
            name: qsTr("Wispr Flow")
        },
        {
            id: "openwhispr",
            name: qsTr("Open Whispr")
        }
    ]

    // Engine of the current/last session. Remembered so the picker preselects it next time.
    property string provider: "wisprflow"
    readonly property string providerName: providers.find(p => p.id === provider)?.name ?? ""

    property bool pickerOpen: false
    property int pickerIndex: 0

    // Window focused before the picker grabbed keyboard focus. Restored after the picker closes
    // (confirm or Escape) so the engine's auto-paste lands in the text field the user was in.
    property string _prevAddress

    // "idle" | "listening" | "converting"
    property string state: "idle"
    readonly property bool active: state !== "idle"
    readonly property string statusText: state === "converting" ? qsTr("Converting…") : qsTr("Listening…")

    // Neither engine signals "done", so we close after a heuristic conversion window.
    // The transcription + paste still complete inside the engine regardless of our popup.
    property int convertTimeout: 3500

    function _toggleWhispr(): void {
        Quickshell.execDetached(["dbus-send", "--session", "--type=method_call", `--dest=${root.service}`, root.path, `${root.iface}.Toggle`]);
    }

    function toggle(): void {
        if (state === "converting")
            return;

        if (state === "listening") {
            stop();
            return;
        }

        // Idle: first press opens the picker, further presses cycle the selection.
        if (pickerOpen)
            pickerIndex = (pickerIndex + 1) % providers.length;
        else
            openPicker();
    }

    function openPicker(): void {
        _prevAddress = Hyprland.activeToplevel?.address ?? "";
        pickerIndex = Math.max(0, providers.findIndex(p => p.id === provider));
        pickerOpen = true;
    }

    function closePicker(): void {
        pickerOpen = false;
        refocusTimer.restart();
    }

    // Dismissal via focus grab clear: the user focused another window on purpose,
    // so don't steal focus back to the remembered one.
    function dismissPicker(): void {
        if (!pickerOpen)
            return;
        pickerOpen = false;
        _prevAddress = "";
    }

    function confirmPicker(): void {
        start(providers[pickerIndex].id);
    }

    function start(providerId: string): void {
        pickerOpen = false;
        provider = providerId;

        if (providerId === "wisprflow")
            Quickshell.execDetached(["wispr-flow", "wispr-flow://start-hands-free"]);
        else
            _toggleWhispr();

        state = "listening";
        refocusTimer.restart();
    }

    function stop(): void {
        if (provider === "wisprflow")
            Quickshell.execDetached(["wispr-flow", "wispr-flow://stop-hands-free"]);
        else
            _toggleWhispr();

        state = "converting";
        convertTimer.restart();
    }

    Timer {
        id: convertTimer

        interval: root.convertTimeout
        onTriggered: root.state = "idle"
    }

    Timer {
        id: refocusTimer

        // Give the compositor a beat to release the picker's exclusive keyboard focus first.
        interval: 80
        onTriggered: {
            if (root._prevAddress)
                Hyprland.dispatch(`focuswindow address:0x${root._prevAddress}`);
            root._prevAddress = "";
        }
    }

    IpcHandler {
        function toggle(): void {
            root.toggle();
        }

        function start(provider: string): void {
            root.start(provider);
        }

        function stop(): void {
            if (root.state === "listening")
                root.stop();
        }

        target: "dictation"
    }
}
