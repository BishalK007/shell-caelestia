pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// DMS-compat Appearance shim — used by the vendored StyledText.
Singleton {
    id: root

    readonly property var anim: ({
            durations: ({
                    normal: 400
                }),
            curves: ({
                    standard: [0.2, 0, 0, 1, 1, 1]
                })
        })
    readonly property var fontSize: ({
            normal: 14
        })
    readonly property var rounding: ({
            normal: 12
        })
}
