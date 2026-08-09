pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property SwitcherState switcher
    required property var nav
    required property real cellH
    // Overlay's monitor name — cells for windows on other monitors get a chip.
    property string screenName: ""

    // Selected cell grows in REAL size (a scale transform would blur the label
    // text and the thumbnail).
    readonly property real selGrow: 1.35
    readonly property real rowPitch: cellH * selGrow + Tokens.spacing.large * 3

    // Drop indicator (written by Content.updateDrag from dropTarget).
    property bool indicatorVisible: false
    property real indicatorX: 0
    property real indicatorY: 0
    property real indicatorH: 0

    function aspectOf(t: var): real {
        let s = null;
        try {
            s = t?.lastIpcObject?.size ?? null;
        } catch (e) {}
        const a = s && s[1] > 0 ? s[0] / s[1] : 1.6;
        return Math.max(0.6, Math.min(2.4, a));
    }

    // --- layout single-source: pure functions shared by the rendered delegates
    // and the drag drop math, so the two can never diverge. All values are
    // settled TARGETS (what the Behaviors animate toward), never animated
    // item positions.

    function rowAnchorCol(r: int): int {
        return (switcher.zone === "grid" && r === switcher.rowIndex) ? switcher.colIndex : switcher.landingCol(r);
    }

    // Per-cell geometry of one row: width follows each window's own aspect
    // ratio, the selected cell grows in real size. xs = prefix-sum x positions.
    function rowLayoutFor(r: int, wins: var): var {
        const sel = switcher.zone === "grid" && r === switcher.rowIndex ? switcher.colIndex : -1;
        const gap = Tokens.spacing.large;
        const list = wins ?? [];
        const xs = [];
        const ws = [];
        let cx = 0;
        for (let i = 0; i < list.length; i++) {
            const w = cellH * (i === sel ? selGrow : 1) * aspectOf(list[i]);
            xs.push(cx);
            ws.push(w);
            cx += w + gap;
        }
        return {
            xs,
            ws
        };
    }

    function rowOriginX(r: int, layout: var): real {
        const a = rowAnchorCol(r);
        return width / 2 - (layout.xs[a] ?? 0) - (layout.ws[a] ?? cellH * 1.6) / 2;
    }

    // Drop-target math in target space (imperative — called per drag move, no
    // bindings). p in GridCamera coords; null when there are no rows.
    function dropTargetAt(p: point): var {
        const rows = switcher.rows;
        if (rows.length === 0)
            return null;
        // Row: rows settle at y-center = H/2 + (r - rowIndex) * rowPitch.
        // Invert + clamp (vertical overshoot snaps to the nearest row —
        // intentional, forgiving).
        const r = Math.max(0, Math.min(rows.length - 1, Math.round((p.y - height / 2) / rowPitch) + switcher.rowIndex));
        const layout = rowLayoutFor(r, rows[r].windows);
        const originX = rowOriginX(r, layout);
        const lx = p.x - originX;
        // Insert slot: before the first cell whose horizontal midpoint exceeds lx.
        let insert = layout.xs.length;
        for (let i = 0; i < layout.xs.length; i++) {
            if (lx < layout.xs[i] + layout.ws[i] / 2) {
                insert = i;
                break;
            }
        }
        // Indicator anchor: gap position in GridCamera coords. An empty row has
        // no gaps — center the indicator over its placeholder slot.
        const gap = Tokens.spacing.large;
        const n = layout.xs.length;
        const ix = n === 0 ? originX + (cellH * 1.6) / 2 : originX + (insert < n ? layout.xs[insert] - gap / 2 : layout.xs[n - 1] + layout.ws[n - 1] + gap / 2);
        const iy = height / 2 - (cellH * selGrow) / 2 + (r - switcher.rowIndex) * rowPitch;
        return {
            row: r,
            insert,
            x: ix,
            y: iy,
            h: cellH * selGrow
        };
    }

    // Suppress the position Behaviors for the first layout: the layer surface
    // sizes 0 -> screen after creation, which would otherwise fly every cell in.
    property bool ready: false

    onWidthChanged: {
        if (width > 0 && !ready)
            Qt.callLater(() => ready = true);
    }

    // Cells slide past the viewport edges by design, but must not extend under
    // the rail: overlapping HoverHandlers BOTH receive hover in Qt 6.
    clip: true

    Repeater {
        model: root.switcher.rows

        Item {
            id: rowItem

            required property var modelData
            required property int index

            // NOTE: rowLayoutFor/rowOriginX are plain functions (one layout
            // source shared with the drop math); reference rows/zone/rowIndex/
            // colIndex explicitly so moves and rebuilds re-trigger this binding.
            readonly property var cellLayout: {
                const deps = [root.switcher.rows, root.switcher.zone, root.switcher.rowIndex, root.switcher.colIndex]; // retrigger
                return deps && root.rowLayoutFor(index, modelData.windows);
            }

            x: root.rowOriginX(index, cellLayout)
            y: root.height / 2 - (root.cellH * root.selGrow) / 2 + (index - root.switcher.rowIndex) * root.rowPitch
            z: index === root.switcher.rowIndex ? 1 : 0

            implicitHeight: root.cellH * root.selGrow

            // FastSpatial (350ms, was DefaultSpatial 500ms): the camera slide is
            // the wheel's visual feedback — the shorter glide keeps rapid
            // scrolling feeling responsive instead of laggy.
            Behavior on x {
                enabled: root.ready
                Anim {
                    type: Anim.FastSpatial
                }
            }

            Behavior on y {
                enabled: root.ready
                Anim {
                    type: Anim.FastSpatial
                }
            }

            StyledText {
                anchors.right: parent.left
                anchors.rightMargin: Tokens.spacing.large
                anchors.verticalCenter: parent.verticalCenter

                text: {
                    try {
                        return rowItem.modelData.ws?.name ?? String(rowItem.modelData.wsId);
                    } catch (e) {
                        return String(rowItem.modelData.wsId);
                    }
                }
                color: Colours.palette.m3onSurfaceVariant
            }

            // Empty-workspace placeholder: selectable, committable (switches to
            // that workspace) and a drag-drop target — dropping a window here
            // occupies it and a fresh trailing empty row appears on rebuild.
            Loader {
                active: rowItem.modelData.empty === true

                // Same slot geometry rowOriginX assumes for an empty layout.
                x: 0
                y: (root.cellH * root.selGrow - height) / 2
                width: root.cellH * 1.6
                height: root.cellH * (emptySelected ? root.selGrow : 1)

                readonly property bool emptySelected: root.switcher.zone === "grid" && root.switcher.rowIndex === rowItem.index

                Behavior on height {
                    enabled: root.ready
                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }

                sourceComponent: StyledRect {
                    radius: Tokens.rounding.normal
                    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, 0.4)
                    border.width: 2
                    border.color: parent.emptySelected ? Colours.palette.m3primary : emptyHover.hovered ? Qt.alpha(Colours.palette.m3primary, 0.5) : Qt.alpha(Colours.palette.m3outlineVariant, 0.6)
                    opacity: parent.emptySelected ? 1 : 0.7

                    Behavior on border.color {
                        CAnim {}
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "add_circle"
                            color: Colours.palette.m3outline
                            font.pointSize: Tokens.font.size.extraLarge
                        }

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: qsTr("empty")
                            color: Colours.palette.m3outline
                        }
                    }

                    // Existing empty workspace parked on another monitor —
                    // same chip as cross-monitor window cells.
                    StyledRect {
                        visible: (rowItem.modelData.monitor ?? "") !== "" && root.screenName !== "" && rowItem.modelData.monitor !== root.screenName

                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Tokens.padding.small

                        implicitWidth: emptyMonIcon.implicitWidth + Tokens.padding.smaller * 2
                        implicitHeight: 20
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3tertiaryContainer

                        MaterialIcon {
                            id: emptyMonIcon

                            anchors.centerIn: parent

                            text: "desktop_windows"
                            font.pointSize: Tokens.font.size.small
                            color: Colours.palette.m3onTertiaryContainer
                        }
                    }

                    HoverHandler {
                        id: emptyHover
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.switcher.zone = "grid";
                            root.switcher.rowIndex = rowItem.index;
                            root.switcher.colIndex = 0;
                            root.switcher.commit();
                        }
                    }
                }
            }

            Repeater {
                model: rowItem.modelData.windows

                WindowCell {
                    id: cell

                    required property var modelData
                    required property int index

                    readonly property bool isSelected: root.switcher.zone === "grid" && root.switcher.rowIndex === rowItem.index && root.switcher.colIndex === index
                    readonly property int chebyshev: Math.max(Math.abs(rowItem.index - root.switcher.rowIndex), Math.abs(index - root.switcher.colIndex))

                    toplevel: modelData
                    selected: isSelected
                    nav: root.nav
                    liveCapture: true // all cells live (user requirement); dial back to chebyshev <= 1 if perf demands
                    hoverSelects: false
                    // Left-hold drag reorder: GRID cells only (the rail is
                    // MRU-sorted, not reorderable).
                    dragEnabled: true
                    onDragPressed: pos => root.nav.beginDrag(cell, rowItem.index, cell.index, pos)
                    onDragMoved: pos => root.nav.updateDrag(cell, pos)
                    onDragReleased: root.nav.endDrag(true)
                    onDragCanceled: root.nav.endDrag(false)
                    onOtherMonitor: {
                        let m = "";
                        try {
                            m = modelData?.monitor?.name ?? "";
                        } catch (e) {}
                        return m !== "" && root.screenName !== "" && m !== root.screenName;
                    }

                    x: rowItem.cellLayout.xs[index] ?? 0
                    y: (root.cellH * root.selGrow - height) / 2
                    width: rowItem.cellLayout.ws[index] ?? root.cellH * 1.6
                    height: root.cellH * (isSelected ? root.selGrow : 1)
                    z: isSelected ? 2 : 0

                    opacity: isSelected ? 1 : chebyshev <= 1 ? 0.95 : 0.55

                    // NO Behavior on y: y is a pure function of the animated
                    // height (vertical centering) — its own Behavior would chase
                    // the height animation through a second spring, making the
                    // cell visibly scale FIRST and re-center AFTER. Tracking the
                    // height animation directly grows the cell from its center
                    // in one motion.

                    Behavior on x {
                        enabled: root.ready
                        Anim {
                            type: Anim.DefaultSpatial
                        }
                    }

                    Behavior on width {
                        enabled: root.ready
                        Anim {
                            type: Anim.DefaultSpatial
                        }
                    }

                    Behavior on height {
                        enabled: root.ready
                        Anim {
                            type: Anim.DefaultSpatial
                        }
                    }

                    Behavior on opacity {
                        Anim {}
                    }

                    onSelect: {
                        root.switcher.zone = "grid";
                        root.switcher.rowIndex = rowItem.index;
                        root.switcher.colIndex = cell.index;
                    }

                    onActivate: {
                        root.switcher.zone = "grid";
                        root.switcher.rowIndex = rowItem.index;
                        root.switcher.colIndex = cell.index;
                        root.switcher.commit();
                    }
                }
            }
        }
    }

    // Drop indicator: a line, not a gap — a gap would animate xs mid-drag,
    // exactly the layout churn the drag freeze avoids. Owned by GridCamera so
    // clip: true crops it correctly at the rail boundary.
    StyledRect {
        visible: root.indicatorVisible
        x: root.indicatorX - 1.5
        y: root.indicatorY

        implicitWidth: 3
        height: root.indicatorH
        radius: Tokens.rounding.full
        color: Colours.palette.m3primary
        z: 50

        Behavior on x {
            Anim {
                type: Anim.FastSpatial
            }
        }

        Behavior on y {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }
}
