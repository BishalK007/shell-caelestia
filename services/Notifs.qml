pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Caelestia
import Caelestia.Config
import qs.components.misc
import qs.services
import qs.utils

Singleton {
    id: root

    property list<NotifData> list: []
    readonly property list<NotifData> notClosed: list.filter(n => !n.closed)
    readonly property list<NotifData> popups: list.filter(n => n.popup)

    // Display mode (button A): "default" full cards, "peek" small circle only, "dnd" hidden
    // (no popups, history still accrues). Persisted in props.
    readonly property string mode: props.mode
    readonly property bool dnd: props.mode === "dnd"
    readonly property bool peek: props.mode === "peek"
    // Notification sound on/off (button B) — fully independent of the display mode.
    readonly property alias soundEnabled: props.soundEnabled
    readonly property string soundFile: GlobalConfig.notifs.soundPath || `${Quickshell.shellDir}/assets/sounds/notification.wav`

    property bool loaded

    function cycleMode(): void {
        props.mode = props.mode === "default" ? "peek" : props.mode === "peek" ? "dnd" : "default";
    }

    function setMode(m: string): void {
        props.mode = m;
    }

    function toggleDnd(): void {
        props.mode = props.mode === "dnd" ? "default" : "dnd";
    }

    function toggleSound(): void {
        props.soundEnabled = !props.soundEnabled;
    }

    // Play the notification sound into notification_sink (linked to every output, scaled by the
    // Notification volume slider). Cooldown-debounced so bursts don't stack; falls back to the
    // default sink if the virtual sink isn't present.
    function playSound(): void {
        if (!props.soundEnabled || soundCooldown.running)
            return;
        // Stay silent while dictating — a notification chime would be picked up by the mic and
        // corrupt the transcription.
        if (Dictation.active)
            return;
        const args = ["pw-play"];
        if (VirtualSink.notificationSink)
            args.push("--target", "notification_sink");
        args.push(root.soundFile);
        Quickshell.execDetached(args);
        soundCooldown.restart();
    }

    function hasFullscreen(): bool {
        for (const monitor of Hypr.monitors.values) {
            if (monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1))
                return true;
        }
        return false;
    }

    function shouldShowPopup(): bool {
        // Only DND fully suppresses popups; peek still shows them (rendered small elsewhere).
        if (props.mode === "dnd" || [...Visibilities.screens.values()].some(v => v.sidebar))
            return false;
        if (GlobalConfig.notifs.fullscreen === "off" && hasFullscreen())
            return false;
        return true;
    }

    onModeChanged: {
        if (!GlobalConfig.utilities.toasts.dndChanged)
            return;

        if (mode === "dnd")
            Toaster.toast(qsTr("Do not disturb"), qsTr("Popup notifications are hidden"), "do_not_disturb_on");
        else if (mode === "peek")
            Toaster.toast(qsTr("Peek mode"), qsTr("Notifications show as a small badge"), "notifications_paused");
        else
            Toaster.toast(qsTr("Notifications shown"), qsTr("Popup notifications are enabled"), "do_not_disturb_off");
    }

    Timer {
        id: soundCooldown

        interval: 300
    }

    onListChanged: {
        if (loaded)
            saveTimer.restart();
    }

    Timer {
        id: saveTimer

        interval: 1000
        onTriggered: storage.setText(JSON.stringify(root.notClosed.map(n => ({
                    time: n.time,
                    id: n.id,
                    summary: n.summary,
                    body: n.body,
                    appIcon: n.appIcon,
                    appName: n.appName,
                    image: n.image,
                    expireTimeout: n.expireTimeout,
                    urgency: n.urgency,
                    resident: n.resident,
                    hasActionIcons: n.hasActionIcons,
                    actions: n.actions
                }))))
    }

    PersistentProperties {
        id: props

        property string mode: "default"
        property bool soundEnabled: true

        reloadableId: "notifs"
    }

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true;

            const comp = notifComp.createObject(root, {
                popup: root.shouldShowPopup(),
                notification: notif
            });
            root.list = [comp, ...root.list];
            root.playSound();
        }
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.state}/notifs.json`
        onLoaded: {
            const data = JSON.parse(text());
            for (const notif of data)
                root.list.push(notifComp.createObject(root, notif));
            root.list.sort((a, b) => b.time - a.time);
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.loaded = true;
                Qt.callLater(() => setText("[]"));
            }
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "clearNotifs"
        description: "Clear all notifications"
        onPressed: {
            for (const notif of root.list.slice())
                notif.close();
        }
    }

    IpcHandler {
        function clear(): void {
            for (const notif of root.list.slice())
                notif.close();
        }

        function isDndEnabled(): bool {
            return props.mode === "dnd";
        }

        function toggleDnd(): void {
            root.toggleDnd();
        }

        function enableDnd(): void {
            props.mode = "dnd";
        }

        function disableDnd(): void {
            props.mode = "default";
        }

        function getMode(): string {
            return props.mode;
        }

        function setMode(m: string): void {
            root.setMode(m);
        }

        function cycleMode(): void {
            root.cycleMode();
        }

        function toggleSound(): void {
            root.toggleSound();
        }

        target: "notifs"
    }

    Component {
        id: notifComp

        NotifData {}
    }
}
