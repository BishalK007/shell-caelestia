pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.Models
import qs.components
import qs.components.controls
import qs.components.containers
import qs.components.images
import qs.services
import qs.utils

// In-panel image file browser (reuses caelestia's FileSystemModel + CachingIconImage thumbnails),
// so picking doesn't open a separate focus-stealing window. Folders navigate; images are picked.
Item {
    id: root

    signal picked(path: string)
    signal closeRequested

    property var pathStack: [Paths.home]
    readonly property string currentPath: pathStack[pathStack.length - 1]

    function up(): void {
        if (pathStack.length > 1)
            pathStack = pathStack.slice(0, pathStack.length - 1);
    }

    function enter(p: string): void {
        pathStack = pathStack.concat([p]);
    }

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainerHigh

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.normal
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                IconButton {
                    type: IconButton.Text
                    icon: "arrow_back"
                    enabled: root.pathStack.length > 1
                    onClicked: root.up()
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.currentPath.startsWith(Paths.home) ? "~" + root.currentPath.slice(Paths.home.length) : root.currentPath
                    elide: Text.ElideMiddle
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Tokens.font.size.small
                    font.family: Tokens.font.family.mono
                }

                IconButton {
                    type: IconButton.Text
                    icon: "close"
                    onClicked: root.closeRequested()
                }
            }

            GridView {
                id: grid

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: 104
                cellHeight: 116

                model: FileSystemModel {
                    path: root.currentPath
                }

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: grid
                }

                delegate: Item {
                    id: entry

                    required property FileSystemEntry modelData

                    width: grid.cellWidth
                    height: grid.cellHeight

                    StyledRect {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacing.smaller
                        radius: Tokens.rounding.small
                        color: "transparent"

                        StateLayer {
                            radius: parent.radius
                            onClicked: {
                                if (entry.modelData.isDir)
                                    root.enter(entry.modelData.path);
                                else if (entry.modelData.isImage)
                                    root.picked(entry.modelData.path);
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.smaller
                            spacing: Tokens.spacing.smaller / 2

                            CachingIconImage {
                                Layout.alignment: Qt.AlignHCenter
                                implicitSize: 56
                                source: entry.modelData.isImage ? Qt.resolvedUrl(entry.modelData.path) : entry.modelData.isDir ? Quickshell.iconPath("inode-directory") : Quickshell.iconPath(entry.modelData.mimeType.replace("/", "-"), "application-x-zerosize")
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: entry.modelData.name
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                color: entry.modelData.isImage || entry.modelData.isDir ? Colours.palette.m3onSurface : Colours.palette.m3outline
                                font.pointSize: Tokens.font.size.small
                            }
                        }
                    }
                }
            }
        }
    }
}
