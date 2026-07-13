pragma Singleton

import Quickshell
import qs.components
import qs.services

Singleton {
    // All maps are keyed by screen NAME (string), never by HyprlandMonitor/ShellScreen
    // objects: quickshell destroys and recreates monitor objects on hotplug (and
    // Hyprland.monitorFor can even return null if the Wayland output appears before the
    // IPC monitoradded event), so object keys go stale and getForActive() misses for
    // that monitor until the shell is restarted.
    property var screens: new Map()
    property var bars: new Map()
    // Per-monitor bar-popout wrappers, so a global keybind can toggle the popout on the active screen.
    property var popouts: new Map()

    // Pre-fill text applied to the launcher search on next open (e.g. open straight into a mode)
    property string launcherQuery: ""

    function load(screen: ShellScreen, visibilities: DrawerVisibilities): void {
        screens.set(screen.name, visibilities);
    }

    function unload(visibilities: DrawerVisibilities): void {
        dropValue(screens, visibilities);
    }

    function getForActive(): DrawerVisibilities {
        return screens.get(Hypr.focusedMonitor?.name) ?? null;
    }

    function loadPopouts(screen: ShellScreen, p: var): void {
        popouts.set(screen.name, p);
    }

    function unloadPopouts(p: var): void {
        dropValue(popouts, p);
    }

    function getPopoutsForActive(): var {
        return popouts.get(Hypr.focusedMonitor?.name);
    }

    // Remove by value, not key: at Component.onDestruction the screen may already be
    // gone, and a same-named replacement may have registered first — deleting by key
    // could drop the new entry.
    function dropValue(map: var, value: var): void {
        for (const [key, v] of map) {
            if (v === value)
                map.delete(key);
        }
    }
}
