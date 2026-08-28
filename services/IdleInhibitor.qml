pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    // Full mode: inhibits every idle timeout (no lock, no screen off, no sleep).
    property alias enabled: props.enabled
    // Sleep-only mode: lock and screen off still fire on idle, but sleep-type
    // timeouts (suspend/hibernate) are blocked — for background jobs.
    property alias sleepOnly: props.sleepOnly
    readonly property bool active: props.enabled || props.sleepOnly
    readonly property alias enabledSince: props.enabledSince

    // Handled by IdleMonitors (which owns the lock): locks the session, then blanks
    signal lockAndBlankRequested

    function lockAndBlank(): void {
        lockAndBlankRequested();
    }

    PersistentProperties {
        id: props

        property bool enabled
        property bool sleepOnly
        property date enabledSince

        onEnabledChanged: {
            if (enabled) {
                sleepOnly = false;
                enabledSince = new Date();
            }
        }

        onSleepOnlyChanged: {
            if (sleepOnly) {
                enabled = false;
                enabledSince = new Date();
            }
        }

        reloadableId: "idleInhibitor"
    }

    IdleInhibitor {
        enabled: props.enabled
        window: PanelWindow {
            // Idle inhibitors only count while their surface is mapped & visible.
            // A 0x0 layer surface never maps, so the inhibitor was silently ignored.
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            mask: Region {}
        }
    }

    IpcHandler {
        function isEnabled(): bool {
            return props.enabled;
        }

        function toggle(): void {
            props.enabled = !props.enabled;
        }

        function enable(): void {
            props.enabled = true;
        }

        function disable(): void {
            props.enabled = false;
        }

        function toggleSleepOnly(): void {
            props.sleepOnly = !props.sleepOnly;
        }

        function getMode(): string {
            return props.enabled ? "full" : props.sleepOnly ? "sleepOnly" : "off";
        }

        function setMode(mode: string): void {
            props.enabled = mode === "full";
            props.sleepOnly = mode === "sleepOnly";
        }

        function lockAndBlank(): void {
            root.lockAndBlank();
        }

        target: "idleInhibitor"
    }
}
