pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io

// Cross-tree visibility state for the vendored (upstream) Ephemera slideout.
// The bar button toggles this; EphemeraPortHost shows/hides the panel from it.
Singleton {
    id: root

    property bool visible: false

    function toggle(): void {
        visible = !visible;
    }
    function show(): void {
        visible = true;
    }
    function hide(): void {
        visible = false;
    }

    IpcHandler {
        target: "ephemera-port"

        function toggle(): void {
            root.toggle();
        }
        function show(): void {
            root.show();
        }
        function hide(): void {
            root.hide();
        }
    }
}
