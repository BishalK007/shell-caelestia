pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.components.containers
import qs.components.misc
import qs.services

Scope {
    id: root

    // Special workspaces never shown in the rail (tunable; see DESIGN.md).
    property var hiddenSpecials: ["special:whispr", "special:wisprflow"]

    function open(): void {
        if (loader.active) {
            loader.item?.cancelClose(); // reopen during the close fade
            return;
        }
        // Latch the target screen at open time — a live binding on focusedMonitor
        // would re-anchor the overlay mid-session (focus-follows-mouse, or commit
        // focusing another monitor during the close fade).
        loader.targetScreen = Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? null;
        loader.closing = false;
        loader.activeAsync = true;
    }

    function requestClose(): void {
        if (loader.active)
            loader.item?.startClose("");
    }

    function toggle(): void {
        // "active but closing" counts as closed, else toggling during the fade is a dead zone.
        if (loader.active && !loader.closing)
            requestClose();
        else
            open();
    }

    LazyLoader {
        id: loader

        property bool closing: false
        property var targetScreen: null
        property string pendingFocus: ""

        StyledWindow {
            id: win

            function startClose(focusAddr: string): void {
                if (closeAnim.running)
                    return;
                loader.pendingFocus = focusAddr ?? "";
                // Reset the submap first so compositor binds come back immediately.
                Hypr.dispatch("submap reset");
                closeAnim.start();
            }

            function cancelClose(): void {
                if (!closeAnim.running && !loader.closing)
                    return;
                closeAnim.stop();
                loader.closing = false;
                loader.pendingFocus = "";
                content.opacity = 1;
                Hypr.dispatch("submap windowswitcher"); // startClose already reset it
            }

            screen: loader.targetScreen
            name: "windowswitcher"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            // Overlay so the switcher appears above fullscreen windows. The layer
            // choice provably does NOT affect toplevel-export capture (tested with
            // a minimal protocol client under Overlay+Exclusive scrims) — earlier
            // blank thumbnails were hyprland 0.55.2 capture bugs, see DESIGN.md.
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: loader.closing ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
            mask: loader.closing ? emptyRegion : null

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Component.onCompleted: Hypr.dispatch("submap windowswitcher")
            Component.onDestruction: Hypr.dispatch("submap reset") // idempotent safety (shell reload while open)

            Region {
                id: emptyRegion
            }

            SwitcherState {
                id: state

                hiddenSpecials: root.hiddenSpecials
                onCloseRequested: focusAddr => win.startClose(focusAddr)
            }

            Content {
                id: content

                anchors.fill: parent
                switcher: state
                screen: win.screen
            }

            SequentialAnimation {
                id: closeAnim

                PropertyAction {
                    target: loader
                    property: "closing"
                    value: true
                }
                Anim {
                    target: content
                    property: "opacity"
                    to: 0
                    type: Anim.StandardLarge
                }
                PropertyAction {
                    target: loader
                    property: "activeAsync"
                    value: false
                }
            }
        }
    }

    Connections {
        target: loader

        function onActiveChanged(): void {
            if (!loader.active && loader.pendingFocus)
                focusReassert.restart();
        }
    }

    Timer {
        id: focusReassert

        // With the exclusive-keyboard surface gone, hyprland re-evaluates seat
        // focus — and with follow_mouse=2 (detached pointer/keyboard focus) the
        // pointer still parked on the old monitor wins, splitting state: window
        // raised on monitor B, keyboard typing into monitor A. Re-assert the
        // committed window once the surface is truly destroyed, and on
        // cross-monitor commits bring the cursor along so pointer, keyboard and
        // monitor focus all agree — per hyprland's own rules, no shell state.
        interval: 200
        onTriggered: {
            const addr = loader.pendingFocus;
            loader.pendingFocus = "";
            if (!addr)
                return;
            Hypr.dispatch(`focuswindow address:0x${addr}`);
            try {
                const t = Hypr.toplevels.values.find(tl => tl?.address === addr) ?? null;
                const mon = t?.monitor?.name ?? "";
                const overlayMon = loader.targetScreen?.name ?? "";
                const ipc = t?.lastIpcObject;
                // Coordinates are read NOW (post-focus) — a scrolled-out window
                // has already been scrolled into view, so its center is valid.
                if (mon && overlayMon && mon !== overlayMon && ipc?.at && ipc?.size)
                    Hypr.dispatch(`movecursor ${Math.round(ipc.at[0] + ipc.size[0] / 2)} ${Math.round(ipc.at[1] + ipc.size[1] / 2)}`);
            } catch (e) {}
        }
    }

    IpcHandler {
        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.requestClose();
        }

        target: "windowswitcher"
    }

    // Fallback toggle path: with the empty submap engaged, Super+Tab is swallowed by the
    // compositor and handled as a key event by Content, so this close branch only fires
    // for IPC/edge cases where the submap is not active.
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "windowSwitcher"
        description: "Toggle window switcher"
        onPressed: root.toggle()
    }
}
