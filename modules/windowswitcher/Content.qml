pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property SwitcherState switcher
    required property ShellScreen screen

    // Base cell height (derived from the full window size, not the grid size,
    // so the rail cannot feed back into it — binding loop). Each cell's WIDTH
    // follows its own window's aspect ratio.
    readonly property real cellH: Math.max(150, Math.min(240, height * 0.18))

    property bool keyboardNavActive: false
    property bool superDown: false
    property bool superChorded: false

    // Right-drag session (Content-owned, driven by per-cell right-button
    // events). All toplevel data is captured as plain scalars at beginDrag —
    // wrappers may die mid-drag while rebuild is deferred. Gates rail
    // hover-select in WindowCell while a drag is held.
    property bool dragging: false
    property string dragAddr: ""
    property int dragSrcRow: -1
    property int dragSrcCol: -1
    property int dragSrcWs: -1
    property point dragGrabOffset: Qt.point(0, 0)
    property var dropTarget: null // { row, insert, x, y, h } | null
    property var ghostResult: null // keeps the ItemGrabResult (and its URL) alive
    property real ghostW: 0
    property real ghostH: 0
    property string ghostIcon: ""

    // Wheel accumulation: one mouse notch (120) = one step; touchpads sum
    // fractional deltas up to the same threshold. The threshold is the single
    // tunable if touchpad scrolling feels sluggish (drop toward 60).
    // 90: a mouse notch (120) fires immediately with remainder, touchpads step
    // 25% sooner than notch-exact 120 — tuned for responsiveness.
    readonly property int wheelStepThreshold: 90
    property real wheelAccV: 0
    property real wheelAccH: 0
    property string wheelAxisLast: "" // "v-band" | "v-grid" | "v-rail" | "h"

    function noteKeyboardNav(): void {
        keyboardNavActive = true;
        hoverGuard.restart();
    }

    function wheelRegion(x: real, y: real): string {
        if (rail.visible && x >= rail.x)
            return "rail";
        // Center row band: the selected row settles vertically centered in the
        // GridCamera viewport; band = viewport-center ± rowPitch/2. Anchored to
        // the viewport center (where rows settle), stable while rows are mid-flight.
        const p = mapToItem(grid, x, y);
        if (Math.abs(p.y - grid.height / 2) <= grid.rowPitch / 2)
            return "band";
        return "grid";
    }

    function handleWheel(event: var): void {
        if (root.switcher.dragActive) {
            event.accepted = true;
            return;
        }

        const region = root.wheelRegion(event.x, event.y);
        // Shift-convention: Shift turns vertical deltas into horizontal intent.
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        const hDelta = shift ? event.angleDelta.y : event.angleDelta.x;
        const vDelta = shift ? 0 : event.angleDelta.y;
        // Horizontal deltas are explicit horizontal intent: row scroll over the
        // ENTIRE grid (band restriction applies only to vertical deltas). Over
        // the rail, horizontal is ignored.
        const horizontal = hDelta !== 0;
        if (horizontal && region === "rail") {
            event.accepted = true;
            return;
        }
        const delta = horizontal ? hDelta : vDelta;
        if (delta === 0) {
            event.accepted = true;
            return;
        }

        // Axis-key change or sign flip zeroes the accumulator — stale
        // remainders must not fire a surprise step.
        const axisKey = horizontal ? "h" : "v-" + region;
        const prevAcc = horizontal ? root.wheelAccH : root.wheelAccV;
        if (axisKey !== root.wheelAxisLast || (prevAcc !== 0 && (prevAcc > 0) !== (delta > 0))) {
            if (horizontal)
                root.wheelAccH = 0;
            else
                root.wheelAccV = 0;
        }
        root.wheelAxisLast = axisKey;
        wheelIdle.restart();

        let acc = (horizontal ? root.wheelAccH : root.wheelAccV) + delta;
        let stepped = false;
        while (Math.abs(acc) >= root.wheelStepThreshold) {
            const step = acc > 0 ? -1 : 1; // angleDelta.y > 0 = wheel up = row up / col left
            if (axisKey === "h" || axisKey === "v-band")
                root.switcher.scrollColBy(step);
            else if (axisKey === "v-grid")
                root.switcher.scrollRowBy(step);
            else
                root.switcher.scrollRailBy(step);
            acc += step * root.wheelStepThreshold; // keep the remainder
            stepped = true;
        }
        if (horizontal)
            root.wheelAccH = acc;
        else
            root.wheelAccV = acc;

        // Wheel IS keyboard-like nav: it moves the real selection and slides
        // cells under the stationary cursor — guard rail hover-select.
        if (stepped)
            root.noteKeyboardNav();
        event.accepted = true;
    }

    function beginDrag(cellItem: var, rowIdx: int, colIdx: int, pressPos: point): void {
        // Capture addr + source ws id as plain scalars — never touch the
        // toplevel wrapper again after this point (it may die mid-drag with
        // rebuild deferred).
        let addr = "";
        let wsId = -1;
        try {
            addr = String(cellItem.toplevel?.address ?? "");
            wsId = cellItem.toplevel?.workspace?.id ?? -1;
        } catch (e) {}

        root.dragAddr = addr;
        root.dragSrcRow = rowIdx;
        root.dragSrcCol = colIdx;
        root.dragSrcWs = wsId;
        root.dragGrabOffset = pressPos;
        root.dropTarget = null;
        root.ghostW = cellItem.width;
        root.ghostH = cellItem.height;
        root.ghostIcon = cellItem.iconSource ?? "";
        root.ghostResult = null;
        ghostImage.source = "";

        console.debug(`[windowswitcher] beginDrag addr=${addr} src=${rowIdx},${colIdx}`);
        root.dragging = true;
        root.switcher.dragActive = true;
        // A drag mid-super-hold must not commit on modifier release.
        root.superDown = false;
        root.wheelAccV = 0;
        root.wheelAccH = 0;
        dragWatchdog.restart();

        const p = cellItem.mapToItem(root, pressPos.x, pressPos.y);
        ghost.x = p.x - pressPos.x;
        ghost.y = p.y - pressPos.y;

        // Frozen snapshot, fully decoupled from delegate lifetime
        // (belt-and-braces on top of rebuild deferral). If the grab fails or
        // never delivers (dmabuf-backed thumbnails on some drivers grab
        // blank), the plan-B icon ghost in dragLayer stays instead.
        try {
            // Tag the session: grabToImage delivers async (next render pass) —
            // a stale callback from a previous drag must not install the wrong
            // cell's snapshot into a newer session's ghost.
            const session = addr;
            cellItem.grabToImage(res => {
                if (!root.dragging || root.dragAddr !== session)
                    return;
                root.ghostResult = res;
                ghostImage.source = res.url;
            }, Qt.size(cellItem.width, cellItem.height));
        } catch (e) {}
    }

    function updateDrag(cellItem: var, pos: point): void {
        if (!root.dragging)
            return;
        dragWatchdog.restart();
        const p = cellItem.mapToItem(root, pos.x, pos.y);
        ghost.x = p.x - root.dragGrabOffset.x;
        ghost.y = p.y - root.dragGrabOffset.y;
        // Rail is MRU-ordered, not a drop target: over it the indicator hides
        // and a drop there cancels.
        root.dropTarget = p.x >= grid.width ? null : grid.dropTargetAt(root.mapToItem(grid, p.x, p.y));
        grid.indicatorVisible = root.dropTarget !== null;
        if (root.dropTarget) {
            grid.indicatorX = root.dropTarget.x;
            grid.indicatorY = root.dropTarget.y;
            grid.indicatorH = root.dropTarget.h;
        }
    }

    function endDrag(commit: bool): void {
        if (!root.dragging)
            return;
        const dt = root.dropTarget;
        console.debug(`[windowswitcher] endDrag commit=${commit} addr=${root.dragAddr} target=${dt ? dt.row + "," + dt.insert : "none"}`);
        if (commit && dt && root.dragAddr) {
            // No-op drop: same row with the insert slot touching the source
            // cell on either side.
            const noop = dt.row === root.dragSrcRow && (dt.insert === root.dragSrcCol || dt.insert === root.dragSrcCol + 1);
            if (!noop) {
                const wsId = root.switcher.rows[dt.row]?.wsId ?? -1;
                // Never let a throw skip the cleanup below — a latched
                // dragActive would suppress rebuild and wheel forever.
                try {
                    if (wsId !== -1)
                        root.switcher.reorderWindow(root.dragAddr, wsId, dt.insert);
                } catch (e) {}
            }
        }
        root.dragging = false;
        root.switcher.dragActive = false; // flushes any deferred rebuild
        root.dropTarget = null;
        grid.indicatorVisible = false;
        root.dragAddr = "";
        root.dragSrcRow = -1;
        root.dragSrcCol = -1;
        root.dragSrcWs = -1;
        root.ghostResult = null;
        ghostImage.source = "";
    }

    focus: true
    opacity: 0

    Component.onCompleted: opacity = 1

    Behavior on opacity {
        Anim {
            type: Anim.StandardLarge
        }
    }

    Keys.onPressed: event => {
        // Drag gating first: Esc cancels the DRAG (not the overlay); every
        // other key is swallowed while a right-drag is held.
        if (root.dragging) {
            if (event.key === Qt.Key_Escape)
                root.endDrag(false);
            event.accepted = true;
            return;
        }

        const key = event.key;

        // Super AND Alt both act as the tap-to-commit modifier (the opener is
        // Alt+Tab; a fresh tap of either commits, releasing the held opener
        // modifier does nothing because its press predates the overlay).
        if (key === Qt.Key_Super_L || key === Qt.Key_Super_R || key === Qt.Key_Meta || key === Qt.Key_Alt) {
            root.superDown = true;
            root.superChorded = false;
            event.accepted = true;
            return;
        }

        if (root.superDown)
            root.superChorded = true;

        if (key === Qt.Key_A || key === Qt.Key_Left || key === Qt.Key_H) {
            root.switcher.moveLeft();
            root.noteKeyboardNav();
            event.accepted = true;
        } else if (key === Qt.Key_D || key === Qt.Key_Right || key === Qt.Key_L) {
            root.switcher.moveRight();
            root.noteKeyboardNav();
            event.accepted = true;
        } else if (key === Qt.Key_W || key === Qt.Key_Up || key === Qt.Key_K) {
            root.switcher.moveUp();
            root.noteKeyboardNav();
            event.accepted = true;
        } else if (key === Qt.Key_S || key === Qt.Key_Down || key === Qt.Key_J) {
            root.switcher.moveDown();
            root.noteKeyboardNav();
            event.accepted = true;
        } else if (key === Qt.Key_Tab) {
            if (event.modifiers & (Qt.MetaModifier | Qt.AltModifier))
                root.switcher.dismiss();
            else {
                root.switcher.toggleZone();
                root.noteKeyboardNav();
            }
            event.accepted = true;
        } else if (key === Qt.Key_Backtab) {
            root.switcher.toggleZone();
            root.noteKeyboardNav();
            event.accepted = true;
        } else if ((key >= Qt.Key_1 && key <= Qt.Key_9) || (event.nativeScanCode >= 10 && event.nativeScanCode <= 18)) {
            // nativeScanCode 10-18 = the top digit row (evdev+8 keycodes), so
            // Shift/Alt-shifted digit symbols still select rail cells.
            const n = key >= Qt.Key_1 && key <= Qt.Key_9 ? key - Qt.Key_0 : event.nativeScanCode - 9;
            root.switcher.pressDigit(n);
            root.noteKeyboardNav();
            event.accepted = true;
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            root.switcher.commit();
            event.accepted = true;
        } else if (key === Qt.Key_Escape) {
            root.switcher.dismiss();
            event.accepted = true;
        }
    }

    Keys.onReleased: event => {
        const key = event.key;

        if (key === Qt.Key_Super_L || key === Qt.Key_Super_R || key === Qt.Key_Meta || key === Qt.Key_Alt) {
            if (root.dragging) {
                // superDown was cleared at beginDrag; never commit mid-drag.
                event.accepted = true;
                return;
            }
            if (root.superDown && !root.superChorded)
                root.switcher.commit();
            root.superDown = false;
            event.accepted = true;
        }
    }

    Timer {
        // Safety net: a drag session that latches without a live grab (lost
        // release/cancel event) would wedge keys and rebuild forever — cancel
        // after 10s without any pointer motion.
        id: dragWatchdog

        interval: 10000
        onTriggered: {
            if (root.dragging) {
                console.warn("[windowswitcher] drag watchdog: force-cancelling stale drag session");
                root.endDrag(false);
            }
        }
    }

    Timer {
        id: hoverGuard

        // Must outlast the camera's DefaultSpatial slide (500ms), or cells still
        // sliding under a stationary cursor re-steal the selection at the tail.
        interval: Tokens.anim.durations.expressiveDefaultSpatial + 150
        onTriggered: root.keyboardNavActive = false
    }

    Timer {
        id: wheelIdle

        interval: 500
        onTriggered: {
            root.wheelAccV = 0;
            root.wheelAccH = 0;
        }
    }

    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => root.handleWheel(event)
    }

    // rebuild() reflows the rail Column under a stationary pointer (cells shift
    // when a special window opens/closes → spurious hover-enter → selection
    // steal from the address repair); arm the hover guard on every rail change.
    Connections {
        target: root.switcher

        function onRailChanged(): void {
            root.noteKeyboardNav();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.switcher.dismiss()
    }

    StyledRect {
        anchors.fill: parent

        color: Colours.palette.m3scrim
        opacity: 0.5
    }

    GridCamera {
        id: grid

        switcher: root.switcher
        nav: root
        cellH: root.cellH
        screenName: root.screen?.name ?? ""

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: rail.left
    }

    RailPanel {
        id: rail

        switcher: root.switcher
        nav: root
        cellW: root.cellH * 1.6
        cellH: root.cellH * 0.9

        visible: root.switcher.rail.length > 0
        width: root.switcher.rail.length > 0 ? implicitWidth : 0

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
    }

    StyledText {
        anchors.centerIn: grid

        visible: root.switcher.rows.length === 0
        text: qsTr("No windows — check the rail")
        color: Colours.palette.m3outline
        font.pointSize: Tokens.font.size.large
    }

    // Drag ghost: topmost so it may cross the rail visually even though drops
    // there are invalid.
    Item {
        id: dragLayer

        anchors.fill: parent
        z: 100
        visible: root.dragging

        Item {
            id: ghost

            // x/y set imperatively from begin/updateDrag — NO Behaviors
            // (the ghost must track the pointer 1:1).
            width: root.ghostW * 0.9
            height: root.ghostH * 0.9
            opacity: 0.85

            Image {
                id: ghostImage

                anchors.fill: parent
                visible: status === Image.Ready
            }

            // Plan-B icon ghost: shown until (or unless) grabToImage delivers —
            // dmabuf-backed thumbnails can grab blank/fail on some drivers.
            StyledRect {
                anchors.fill: parent

                visible: ghostImage.status !== Image.Ready
                radius: Tokens.rounding.normal
                color: Colours.tPalette.m3surfaceContainer
                border.width: 2
                border.color: Colours.palette.m3primary

                IconImage {
                    anchors.centerIn: parent

                    visible: root.ghostIcon !== ""
                    asynchronous: true
                    implicitSize: Math.round(Math.min(parent.width, parent.height) * 0.45)
                    source: root.ghostIcon
                }
            }
        }
    }
}
