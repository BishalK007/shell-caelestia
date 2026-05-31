import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property var modelData // { id, name, subtitle, icon, command }
    required property var visibilities
    required property var view // the ListView (drives currentIndex on hover)
    required property int index

    readonly property bool fav: root.modelData ? Browsers.favs.indexOf(root.modelData.id) !== -1 : false

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    HoverHandler {
        onHoveredChanged: if (hovered && root.view)
            root.view.currentIndex = root.index
    }

    StateLayer {
        radius: Tokens.rounding.normal
        onClicked: {
            if (root.modelData)
                Browsers.launch(root.modelData);
            root.visibilities.launcher = false;
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.larger
        anchors.rightMargin: Tokens.padding.larger
        anchors.margins: Tokens.padding.smaller

        Item {
            id: icon

            implicitWidth: parent.height * 0.8
            implicitHeight: parent.height * 0.8
            anchors.verticalCenter: parent.verticalCenter

            // True only once the avatar file actually loads (else fall back to the icon)
            readonly property bool hasPicture: (root.modelData?.picture ?? "") !== "" && avatar.status === Image.Ready

            StyledClippingRect {
                anchors.fill: parent
                visible: icon.hasPicture
                radius: width / 2
                color: "transparent"

                Image {
                    id: avatar

                    anchors.fill: parent
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectCrop
                    source: (root.modelData?.picture ?? "") !== "" ? `file://${root.modelData.picture}` : ""
                    sourceSize.width: width * 2
                    sourceSize.height: height * 2
                }
            }

            IconImage {
                anchors.fill: parent
                visible: !icon.hasPicture
                asynchronous: true
                source: Quickshell.iconPath(root.modelData?.icon, "applications-internet")
            }
        }

        Item {
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.normal
            anchors.verticalCenter: icon.verticalCenter

            implicitWidth: parent.width - icon.width - favIcon.width
            implicitHeight: name.implicitHeight + sub.implicitHeight

            StyledText {
                id: name

                text: root.modelData?.name ?? ""
                font.pointSize: Tokens.font.size.normal
            }

            StyledText {
                id: sub

                anchors.top: name.bottom

                text: root.modelData?.subtitle ?? ""
                font.pointSize: Tokens.font.size.small
                color: Colours.palette.m3outline
                elide: Text.ElideRight
                width: root.width - icon.width - favIcon.width - Tokens.rounding.normal * 2
            }
        }

        Loader {
            id: favIcon

            asynchronous: true
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            active: root.fav

            sourceComponent: MaterialIcon {
                text: "favorite"
                fill: 1
                color: Colours.palette.m3primary
            }
        }
    }
}
