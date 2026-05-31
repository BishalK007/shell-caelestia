pragma ComponentBehavior: Bound

import QtQuick
import qs.services

// Eagerly construct the VirtualSink singleton at startup (singletons are otherwise lazy and
// would only initialize when the audio popout first opens). This restores the saved music
// routing and pins the loopback "*.output" nodes to unity at boot — so playback isn't left
// quiet-at-100% from a stale loopback gain before the user ever opens the popout.
Item {
    // Referencing a property forces the singleton to be constructed; VirtualSink's own
    // _tryInit (gated on the loopback nodes becoming ready) does the actual pin/route.
    readonly property bool active: VirtualSink.available

    Component.onCompleted: VirtualSink.pinLoopbacks()
}
