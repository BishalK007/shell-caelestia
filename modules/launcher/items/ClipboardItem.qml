import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property var modelData // { id, preview, isImage }
    required property var visibilities
    required property var view // the ListView (to drive currentIndex on hover)
    required property int index

    readonly property bool isImage: root.modelData?.isImage ?? false

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    // "[[ binary data 3 MiB png 1920x1080 ]]" -> "Image · png · 1920×1080"
    function pretty(preview: string): string {
        const p = preview ?? "";
        const m = p.match(/\[\[ binary data\s+.+?\s+(png|jpe?g|gif|bmp|webp|tiff?|ico|svg)\s+(\d+x\d+)/i);
        return m ? qsTr("Image · %1 · %2").arg(m[1]).arg(m[2].replace("x", "×")) : p;
    }

    // Hovering highlights the row so the preview panel follows the mouse,
    // unless keyboard nav is scrolling the list under a stationary cursor
    HoverHandler {
        onHoveredChanged: if (hovered && root.view && !root.view.keyboardNavActive)
            root.view.currentIndex = root.index
    }

    StateLayer {
        radius: Tokens.rounding.normal
        onClicked: {
            if (root.modelData)
                Clipboard.copy(root.modelData);
            root.visibilities.launcher = false;
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.larger
        anchors.rightMargin: Tokens.padding.larger
        anchors.margins: Tokens.padding.smaller

        MaterialIcon {
            id: icon

            anchors.verticalCenter: parent.verticalCenter
            text: root.isImage ? "image" : "content_paste"
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.normal
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            text: root.isImage ? root.pretty(root.modelData?.preview) : (root.modelData?.preview ?? "")
            font.pointSize: Tokens.font.size.normal
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
