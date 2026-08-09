import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property var toplevel
    required property bool selected
    required property var nav

    property string badge: ""
    property bool showVisibleDot: false
    // Grid cells set this false: hover-select on a camera-centered grid slides
    // cells under the stationary cursor, which re-hovers and re-selects — an
    // auto-scroll feedback loop. Hover then only highlights; click commits.
    property bool hoverSelects: true
    // Window lives on a different monitor than the overlay — marked with a chip
    // so cross-monitor windows aren't mistaken for local ones.
    property bool onOtherMonitor: false
    // Live screencopy streams are expensive with many windows; parents enable
    // them only near the selection. Static cells keep the frame captured below.
    property bool liveCapture: true
    // Left-hold drag-reorder plumbing: grid cells set dragEnabled true; the
    // rail leaves it false (MRU-ordered, not reorderable). dragging is
    // internal — true between dragPressed and dragReleased/dragCanceled.
    property bool dragEnabled: false
    property bool dragging: false

    // If the Content session dies without this cell's release/cancel arriving
    // (Esc-cancel, grab lost to delegate churn), reset so the cursor and the
    // left-click gate don't stay latched.
    Connections {
        target: root.nav
        enabled: root.dragEnabled

        function onDraggingChanged(): void {
            if (!root.nav.dragging && root.dragging)
                root.dragging = false;
        }
    }

    // Wrapper reads throw once the window dies (?. alone doesn't protect a
    // destroyed QObject wrapper) — bindings route through these guards.
    readonly property string safeTitle: {
        try {
            return root.toplevel?.title ?? "";
        } catch (e) {
            return "";
        }
    }
    readonly property var waylandHandle: {
        try {
            return root.toplevel?.wayland ?? null; // qmllint disable unresolved-type
        } catch (e) {
            return null;
        }
    }

    // Resolved once; empty when the desktop-entry lookup fails (the icon theme
    // has no "image-missing", so a theme fallback would 404 too — cells show a
    // Material glyph instead).
    readonly property string iconSource: {
        let cls = "";
        try {
            cls = root.toplevel?.lastIpcObject?.["class"] ?? "";
        } catch (e) {}
        const icon = cls ? (DesktopEntries.heuristicLookup(cls)?.icon ?? "") : "";
        return icon ? Quickshell.iconPath(icon) : "";
    }

    signal select
    signal activate
    signal dragPressed(point pos)
    signal dragMoved(point pos)
    signal dragReleased
    signal dragCanceled

    Item {
        id: label

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.top
        anchors.bottomMargin: Tokens.spacing.small

        height: Math.max(labelIcon.height, title.implicitHeight)

        IconImage {
            id: labelIcon

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            visible: root.iconSource !== ""
            asynchronous: true
            implicitSize: 16
            source: root.iconSource
        }

        StyledText {
            id: title

            anchors.left: labelIcon.visible ? labelIcon.right : parent.left
            anchors.leftMargin: Tokens.spacing.small
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            text: root.safeTitle
            elide: Text.ElideRight
            // Real size change (not a transform) so the text re-renders crisply.
            font.pointSize: root.selected ? Tokens.font.size.normal : Tokens.font.size.small
        }
    }

    StyledRect {
        id: card

        anchors.fill: parent

        radius: Tokens.rounding.normal
        color: Colours.tPalette.m3surfaceContainer
        border.width: root.selected ? 2 : 1
        border.color: root.selected ? Colours.palette.m3primary : cellHover.hovered ? Qt.alpha(Colours.palette.m3primary, 0.5) : Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

        Behavior on border.color {
            CAnim {}
        }

        StyledClippingRect {
            id: thumb

            anchors.fill: parent
            anchors.margins: 2

            radius: Tokens.rounding.normal - 2

            ScreencopyView {
                id: view

                // Rendered 1:1 at native buffer size, never shown directly —
                // mipSource below re-renders it into a mipmapped texture. A
                // single bilinear pass from full res to cell size samples only
                // 4 texels per output pixel and turns text to shimmer; the mip
                // chain averages ALL source pixels (what Windows' DWM does).
                width: Math.max(1, sourceSize.width)
                height: Math.max(1, sourceSize.height)

                captureSource: root.waylandHandle
                // Stream until the first frame lands, then keep streaming while
                // liveCapture. Buffers are always full window resolution (the
                // compositor dictates size).
                live: root.liveCapture || !hasContent
                smooth: true
            }

            ShaderEffectSource {
                id: mipSource

                readonly property real srcAspect: {
                    if (view.sourceSize.height > 0)
                        return view.sourceSize.width / view.sourceSize.height;
                    let s = null;
                    try {
                        s = root.toplevel?.lastIpcObject?.size ?? null;
                    } catch (e) {}
                    if (s && s[1] > 0)
                        return s[0] / s[1];
                    return parent.height > 0 ? parent.width / parent.height : 1.6;
                }

                anchors.centerIn: parent
                // Fill (cover) the cell, not fit: scale so both dimensions reach
                // the frame and let the clipping card crop the overflow evenly.
                width: Math.max(parent.width, parent.height * srcAspect)
                height: srcAspect > 0 ? width / srcAspect : parent.height

                visible: view.hasContent
                sourceItem: view
                hideSource: true
                live: true
                mipmap: true
                smooth: true
                // Cap the texture at 1280 on the long edge: a 2560-wide source
                // hits it as an exact 2:1 first pass (lossless averaging), mips
                // handle the rest — near-DWM quality at ~5MB/cell instead of
                // ~20MB/cell for full native textures across ~40 cells.
                // The SELECTED cell displays ~2x larger, where the cap costs
                // visible sharpness — it gets the full native texture.
                textureSize: {
                    const sw = view.sourceSize.width;
                    const sh = view.sourceSize.height;
                    if (sw <= 0 || sh <= 0)
                        return Qt.size(0, 0);
                    const cap = root.selected ? 4096 : 1280;
                    const s = Math.min(1, cap / Math.max(sw, sh));
                    return Qt.size(Math.max(1, Math.round(sw * s)), Math.max(1, Math.round(sh * s)));
                }
            }

            Timer {
                // Watchdog: a frame stuck server-side cannot be retried with
                // captureFrame() (silent no-op while one is in flight, quickshell
                // hyprland_screencopy.cpp:64) — destroying and recreating the
                // capture via captureSource is the only client-side recovery.
                // Two bounces with backoff, then the icon fallback stays.
                property int bounces: 0

                running: !view.hasContent && root.waylandHandle !== null && bounces < 2
                interval: 700 + bounces * 900
                onTriggered: {
                    bounces++;
                    view.captureSource = null;
                    view.captureSource = Qt.binding(() => root.waylandHandle);
                }
            }

            IconImage {
                anchors.centerIn: parent

                visible: !view.hasContent && root.iconSource !== ""
                asynchronous: true
                implicitSize: Math.round(Math.min(parent.width, parent.height) * 0.45)
                source: root.iconSource
            }

            MaterialIcon {
                anchors.centerIn: parent

                visible: !view.hasContent && root.iconSource === ""
                text: "web_asset"
                color: Colours.palette.m3outline
                font.pointSize: Tokens.font.size.extraLarge
            }
        }
    }

    StyledRect {
        visible: root.badge !== ""

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Tokens.padding.small

        implicitWidth: 20
        implicitHeight: 20
        radius: Tokens.rounding.full
        color: Colours.palette.m3secondaryContainer

        StyledText {
            anchors.centerIn: parent

            text: root.badge
            color: Colours.palette.m3onSecondaryContainer
            font.pointSize: Tokens.font.size.small
        }
    }

    StyledRect {
        visible: root.showVisibleDot

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Tokens.padding.small

        implicitWidth: 8
        implicitHeight: 8
        radius: Tokens.rounding.full
        color: Colours.palette.m3primary
    }

    StyledRect {
        visible: root.onOtherMonitor

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Tokens.padding.small

        implicitWidth: monIcon.implicitWidth + Tokens.padding.smaller * 2
        implicitHeight: 20
        radius: Tokens.rounding.full
        color: Colours.palette.m3tertiaryContainer

        MaterialIcon {
            id: monIcon

            anchors.centerIn: parent

            text: "desktop_windows"
            font.pointSize: Tokens.font.size.small
            color: Colours.palette.m3onTertiaryContainer
        }
    }

    HoverHandler {
        id: cellHover

        onHoveredChanged: {
            if (hovered && root.hoverSelects && !root.nav.keyboardNavActive && !root.nav.dragging)
                root.select();
        }
    }

    MouseArea {
        id: cellMouse

        anchors.fill: parent

        acceptedButtons: Qt.LeftButton
        // During an implicit grab the grabber's cursorShape governs (honored
        // by Hyprland through cursor-shape-v1).
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor

        // Left-HOLD + move beyond the threshold = drag; a plain left click
        // (press + release without movement) commits. suppressClick is the
        // disambiguator: once a drag started, the release must not commit.
        property point pressPos: Qt.point(0, 0)
        property bool suppressClick: false

        onPressed: mouse => {
            pressPos = Qt.point(mouse.x, mouse.y);
            suppressClick = false;
        }
        onPositionChanged: mouse => {
            // Only fires while pressed (no hoverEnabled).
            if (root.dragging) {
                root.dragMoved(Qt.point(mouse.x, mouse.y));
            } else if (root.dragEnabled && pressed && (Math.abs(mouse.x - pressPos.x) > 10 || Math.abs(mouse.y - pressPos.y) > 10)) {
                root.dragging = true;
                suppressClick = true;
                root.dragPressed(pressPos);
                root.dragMoved(Qt.point(mouse.x, mouse.y));
            }
        }
        onReleased: {
            if (root.dragging) {
                root.dragging = false;
                root.dragReleased();
            }
        }
        // Grab-loss safety net (compositor steal, shell reload, monitor
        // unplug): a missed cancel would latch dragActive true forever.
        onCanceled: {
            if (root.dragging) {
                root.dragging = false;
                root.dragCanceled();
            }
        }
        onClicked: {
            // suppressClick is load-bearing: the release that ends a drag (or
            // an Esc-cancelled drag) must NOT commit the cell.
            if (!suppressClick && !root.dragging)
                root.activate();
        }
    }
}
