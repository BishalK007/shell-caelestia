pragma ComponentBehavior: Bound

import "items"
import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property StyledTextField search
    required property var visibilities

    // Exposed so ContentList/Content can drive keyboard nav + read the current item
    property alias view: listView

    readonly property var current: listView.currentItem?.modelData ?? null
    readonly property bool previewing: current?.isImage ?? false
    readonly property int previewWidth: Tokens.sizes.launcher.itemWidth * 0.85

    // Decode the currently-highlighted entry: images -> cache file, text -> full string.
    // (cliphist's list preview is truncated, so text is decoded here for the full view.)
    property string previewId: ""
    property bool previewReady: false
    property string previewText: ""
    readonly property string previewFile: previewId ? `${Paths.cache}/clipboard/${previewId}` : ""

    onCurrentChanged: {
        previewReady = false;
        previewText = "";
        if (!current) {
            previewId = "";
            return;
        }
        previewId = current.id;
        if (current.isImage)
            decodeProc.running = true;
        else
            textProc.running = true;
    }

    // Height of a full maxShown-row list; used as a floor so the widget (and the
    // preview panel) keeps a usable size even when only a few items are present.
    readonly property int minHeight: (Tokens.sizes.launcher.itemHeight + Tokens.spacing.small) * Config.launcher.maxShown - Tokens.spacing.small

    // Right-hand preview is always present (constant width) so the list never shifts
    implicitWidth: listView.width + previewWidth + Tokens.spacing.large
    implicitHeight: Math.max(listView.implicitHeight, minHeight)

    // Re-read cliphist each time clipboard mode opens, so copies made after shell
    // startup show up (the service only auto-loads once, on Component.onCompleted).
    Component.onCompleted: Clipboard.reload()

    Process {
        id: decodeProc

        command: ["sh", "-c", `mkdir -p ${Paths.cache}/clipboard && { [ -s '${root.previewFile}' ] || cliphist decode ${root.previewId} > '${root.previewFile}'; }`]
        onExited: code => {
            if (code === 0 && root.previewId)
                root.previewReady = true;
        }
    }

    Process {
        id: textProc

        command: ["cliphist", "decode", root.previewId]
        stdout: StdioCollector {
            onStreamFinished: root.previewText = text
        }
    }

    StyledListView {
        id: listView

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Tokens.sizes.launcher.itemWidth

        clip: true
        spacing: Tokens.spacing.small
        implicitHeight: (Tokens.sizes.launcher.itemHeight + spacing) * Math.min(Config.launcher.maxShown, count) - spacing

        // Keyboard nav owns the selection briefly: when the list auto-scrolls, rows
        // slide under a stationary cursor and fire hover-enters that would steal
        // currentIndex back to the hovered row. Delegates skip hover-select while set.
        property bool keyboardNavActive: false

        function noteKeyboardNav(): void {
            keyboardNavActive = true;
            hoverGuard.restart();
        }

        Timer {
            id: hoverGuard

            interval: 250
            onTriggered: listView.keyboardNavActive = false
        }

        preferredHighlightBegin: 0
        preferredHighlightEnd: height
        highlightRangeMode: ListView.ApplyRange

        model: ScriptModel {
            values: Clipboard.entries.length >= 0 ? Clipboard.query(root.search.text) : []
            onValuesChanged: listView.currentIndex = 0
        }

        highlightFollowsCurrentItem: false
        highlight: StyledRect {
            radius: Tokens.rounding.normal
            color: Colours.palette.m3onSurface
            opacity: 0.08

            y: listView.currentItem?.y ?? 0
            implicitWidth: listView.width
            implicitHeight: listView.currentItem?.implicitHeight ?? 0

            Behavior on y {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
        }

        delegate: ClipboardItem {
            visibilities: root.visibilities
            view: listView
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: listView
        }
    }

    StyledClippingRect {
        id: previewPanel

        anchors.left: listView.right
        anchors.leftMargin: Tokens.spacing.large
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        width: root.previewWidth
        clip: true
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer

        // Image entries: show the decoded image
        Image {
            anchors.fill: parent
            anchors.margins: Tokens.padding.normal

            visible: root.previewing
            asynchronous: true
            cache: false
            fillMode: Image.PreserveAspectFit
            source: root.previewReady ? `file://${root.previewFile}` : ""
            sourceSize.width: width
            sourceSize.height: height
        }

        // Text entries: full content, scrollable when it overflows
        StyledFlickable {
            id: textFlick

            anchors.fill: parent
            anchors.margins: Tokens.padding.larger

            visible: !root.previewing
            clip: true
            contentWidth: width
            contentHeight: previewLabel.implicitHeight

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: textFlick
            }

            StyledText {
                id: previewLabel

                width: textFlick.width
                text: root.previewText
                wrapMode: Text.Wrap
                font.pointSize: Tokens.font.size.normal
            }
        }
    }
}
