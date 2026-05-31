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

    // Decode ONLY the currently-highlighted image to a cache file (one at a time)
    property string previewId: ""
    property bool previewReady: false
    readonly property string previewFile: previewId ? `${Paths.cache}/clipboard/${previewId}` : ""

    onCurrentChanged: {
        previewReady = false;
        if (current && current.isImage) {
            previewId = current.id;
            decodeProc.running = true;
        } else {
            previewId = "";
        }
    }

    implicitWidth: listView.width + (previewing ? previewWidth + Tokens.spacing.large : 0)
    implicitHeight: listView.implicitHeight

    Process {
        id: decodeProc

        command: ["sh", "-c", `mkdir -p ${Paths.cache}/clipboard && { [ -s '${root.previewFile}' ] || cliphist decode ${root.previewId} > '${root.previewFile}'; }`]
        onExited: code => {
            if (code === 0 && root.previewId)
                root.previewReady = true;
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

        width: root.previewing ? root.previewWidth : 0
        clip: true
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer

        Image {
            anchors.fill: parent
            anchors.margins: Tokens.padding.normal

            asynchronous: true
            cache: false
            fillMode: Image.PreserveAspectFit
            source: root.previewReady ? `file://${root.previewFile}` : ""
            sourceSize.width: width
            sourceSize.height: height
        }

        Behavior on width {
            Anim {
                duration: Tokens.anim.durations.large
                easing: Tokens.anim.emphasizedDecel
            }
        }
    }
}
