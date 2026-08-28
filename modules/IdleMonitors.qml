pragma ComponentBehavior: Bound

import "lock"
import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Internal
import qs.services
// Qualified alias: unqualified `IdleInhibitor` resolves to the Quickshell.Wayland
// type here, silently shadowing our qs.services singleton.
import qs.services as Services

Scope {
    id: root

    required property Lock lock
    readonly property bool enabled: !GlobalConfig.general.idle.inhibitWhenAudio || !Players.list.some(p => p.isPlaying)

    // Sleep-type actions are the ones additionally blocked in sleep-only inhibit
    // mode; lock/dpms timeouts keep firing there.
    function isSleepAction(action: var): bool {
        const s = Array.isArray(action) ? action.join(" ") : String(action ?? "");
        return /suspend|hibernate/i.test(s);
    }

    function handleIdleAction(action: var): void {
        if (!action)
            return;

        if (action === "lock")
            lock.lock.locked = true;
        else if (action === "unlock")
            lock.lock.locked = false;
        else if (typeof action === "string")
            Hypr.dispatch(action);
        else
            Quickshell.execDetached(action);
    }

    Connections {
        target: Services.IdleInhibitor

        function onLockAndBlankRequested(): void {
            root.lock.lock.locked = true;
            dpmsTimer.restart();
        }
    }

    Timer {
        id: dpmsTimer

        // Let the lock surfaces map (and their screencopy capture run) before blanking
        interval: 500
        onTriggered: Hypr.dispatch("dpms off")
    }

    LogindManager {
        onAboutToSleep: {
            if (GlobalConfig.general.idle.lockBeforeSleep)
                root.lock.lock.locked = true;
        }
        onLockRequested: root.lock.lock.locked = true
        onUnlockRequested: root.lock.lock.unlock()
    }

    Variants {
        model: GlobalConfig.general.idle.timeouts

        IdleMonitor {
            required property var modelData

            enabled: root.enabled && (modelData.enabled ?? true) && !(Services.IdleInhibitor.sleepOnly && root.isSleepAction(modelData.idleAction))
            timeout: modelData.timeout
            respectInhibitors: modelData.respectInhibitors ?? true
            onIsIdleChanged: root.handleIdleAction(isIdle ? modelData.idleAction : modelData.returnAction)
        }
    }
}
