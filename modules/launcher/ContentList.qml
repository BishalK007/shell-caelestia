pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property var content
    required property DrawerVisibilities visibilities
    required property var panels
    required property real maxHeight
    required property StyledTextField search
    required property int padding
    required property int rounding

    readonly property bool showWallpapers: search.text.startsWith(`${GlobalConfig.launcher.actionPrefix}wallpaper `)
    readonly property bool showClipboard: search.text.startsWith(Clipboard.prefix)
    readonly property bool showBrowser: search.text.startsWith(Browsers.prefix)
    readonly property var currentList: showClipboard ? clipboardList.item?.view : showBrowser ? browserList.item : showWallpapers ? wallpaperList.item : appList.item // ListView or PathView, so can't type properly

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom

    clip: true
    state: showClipboard ? "clipboard" : showBrowser ? "browser" : showWallpapers ? "wallpapers" : "apps"

    states: [
        State {
            name: "apps"

            PropertyChanges {
                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth
                root.implicitHeight: Math.min(root.maxHeight, appList.implicitHeight > 0 ? appList.implicitHeight : empty.implicitHeight)
                appList.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        },
        State {
            name: "wallpapers"

            PropertyChanges {
                root.implicitWidth: Math.max(root.Tokens.sizes.launcher.itemWidth * 1.2, wallpaperList.implicitWidth)
                root.implicitHeight: root.Tokens.sizes.launcher.wallpaperHeight
                wallpaperList.active: true
            }
        },
        State {
            name: "clipboard"

            PropertyChanges {
                root.implicitWidth: clipboardList.item?.implicitWidth ?? root.Tokens.sizes.launcher.itemWidth
                root.implicitHeight: clipboardList.item?.implicitHeight ?? 0
                clipboardList.active: true
            }
        },
        State {
            name: "browser"

            PropertyChanges {
                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth
                root.implicitHeight: Math.min(root.maxHeight, (browserList.item?.implicitHeight ?? 0) > 0 ? browserList.item.implicitHeight : empty.implicitHeight)
                browserList.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        }
    ]

    Behavior on state {
        SequentialAnimation {
            Anim {
                target: root
                property: "opacity"
                from: 1
                to: 0
                type: Anim.StandardSmall
            }
            PropertyAction {}
            Anim {
                target: root
                property: "opacity"
                from: 0
                to: 1
                type: Anim.StandardSmall
            }
        }
    }

    Loader {
        id: appList

        active: false

        anchors.fill: parent

        sourceComponent: AppList {
            search: root.search
            visibilities: root.visibilities
        }
    }

    Loader {
        id: wallpaperList

        asynchronous: true
        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        sourceComponent: WallpaperList {
            search: root.search
            visibilities: root.visibilities
            panels: root.panels
            content: root.content
        }
    }

    Loader {
        id: clipboardList

        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        sourceComponent: ClipboardList {
            search: root.search
            visibilities: root.visibilities
        }
    }

    Loader {
        id: browserList

        active: false

        anchors.fill: parent

        sourceComponent: BrowserList {
            search: root.search
            visibilities: root.visibilities
        }
    }

    Row {
        id: empty

        opacity: root.currentList?.count === 0 ? 1 : 0
        scale: root.currentList?.count === 0 ? 1 : 0.5

        spacing: Tokens.spacing.normal
        padding: Tokens.padding.large

        anchors.horizontalCenter: parent.horizontalCenter
        // In clipboard mode the widget is list + preview panel; centre the
        // placeholder over the list column only, not the combined width.
        anchors.horizontalCenterOffset: root.state === "clipboard" ? -((clipboardList.item?.previewWidth ?? 0) + Tokens.spacing.large) / 2 : 0
        anchors.verticalCenter: parent.verticalCenter

        MaterialIcon {
            text: root.state === "clipboard" ? "content_paste" : root.state === "browser" ? "public" : root.state === "wallpapers" ? "wallpaper_slideshow" : "manage_search"
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Tokens.font.size.extraLarge

            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: root.state === "clipboard" ? qsTr("No clipboard history") : root.state === "browser" ? qsTr("No browsers found") : root.state === "wallpapers" ? qsTr("No wallpapers found") : qsTr("No results")
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Tokens.font.size.larger
                font.weight: 500
            }

            StyledText {
                text: root.state === "clipboard" ? qsTr("Copy something first") : root.state === "wallpapers" && Wallpapers.list.length === 0 ? qsTr("Try putting some wallpapers in %1").arg(Paths.shortenHome(Paths.wallsdir)) : qsTr("Try searching for something else")
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Tokens.font.size.normal
            }
        }

        Behavior on opacity {
            Anim {}
        }

        Behavior on scale {
            Anim {}
        }
    }

    Behavior on implicitWidth {
        enabled: root.visibilities.launcher

        Anim {
            duration: Tokens.anim.durations.large
            easing: Tokens.anim.emphasizedDecel
        }
    }

    Behavior on implicitHeight {
        enabled: root.visibilities.launcher

        Anim {
            duration: Tokens.anim.durations.large
            easing: Tokens.anim.emphasizedDecel
        }
    }
}
