pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Front-end for OpenWhispr's D-Bus dictation. OpenWhispr only exposes a fire-and-forget `Toggle`
// (start when idle, stop->transcribe->paste when recording) — no state/transcription over D-Bus —
// so we drive our own listening/converting state and visualise it in the bottom popup.
Singleton {
    id: root

    readonly property string service: "com.openwhispr.App"
    readonly property string path: "/com/openwhispr/App"
    readonly property string iface: "com.openwhispr.App"

    // "idle" | "listening" | "converting"
    property string state: "idle"
    readonly property bool active: state !== "idle"
    readonly property string statusText: state === "converting" ? qsTr("Converting…") : qsTr("Listening…")

    // OpenWhispr doesn't signal "done" over D-Bus, so we close after a heuristic conversion window.
    // The transcription + paste still complete inside OpenWhispr regardless of our popup.
    property int convertTimeout: 3500

    function _toggleWhispr(): void {
        Quickshell.execDetached(["dbus-send", "--session", "--type=method_call", `--dest=${root.service}`, root.path, `${root.iface}.Toggle`]);
    }

    function toggle(): void {
        if (state === "converting")
            return;

        _toggleWhispr();

        if (state === "idle") {
            state = "listening";
        } else {
            state = "converting";
            convertTimer.restart();
        }
    }

    Timer {
        id: convertTimer

        interval: root.convertTimeout
        onTriggered: root.state = "idle"
    }

    IpcHandler {
        function toggle(): void {
            root.toggle();
        }

        target: "dictation"
    }
}
