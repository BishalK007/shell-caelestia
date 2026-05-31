pragma Singleton

import Quickshell
import qs.components
import qs.services

Singleton {
    property var screens: new Map()
    property var bars: new Map()
    // Per-monitor bar-popout wrappers, so a global keybind can toggle the popout on the active screen.
    property var popouts: new Map()

    // Pre-fill text applied to the launcher search on next open (e.g. open straight into a mode)
    property string launcherQuery: ""

    function load(screen: ShellScreen, visibilities: DrawerVisibilities): void {
        screens.set(Hypr.monitorFor(screen), visibilities);
    }

    function getForActive(): DrawerVisibilities {
        return screens.get(Hypr.focusedMonitor);
    }

    function loadPopouts(screen: ShellScreen, p: var): void {
        popouts.set(Hypr.monitorFor(screen), p);
    }

    function getPopoutsForActive(): var {
        return popouts.get(Hypr.focusedMonitor);
    }
}
