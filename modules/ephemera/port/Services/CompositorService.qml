pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// DMS-compat CompositorService shim — Ephemera only needs per-screen scale.
Singleton {
    id: root

    function getScreenScale(screen) {
        if (screen && screen.devicePixelRatio)
            return screen.devicePixelRatio;
        return 1;
    }
}
