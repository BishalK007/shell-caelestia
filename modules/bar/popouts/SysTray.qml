pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

// Grid of system-tray items, shown in the bar's tray popout.
Column {
    id: root

    required property PopoutState popouts

    readonly property int cellSize: Tokens.sizes.bar.innerWidth
    readonly property int columns: Math.min(Math.max(items.count, 1), 5)

    spacing: Tokens.spacing.small

    StyledText {
        text: qsTr("System Tray")
        font.weight: 500
    }

    Grid {
        columns: root.columns
        spacing: Tokens.spacing.small

        Repeater {
            id: items

            model: ScriptModel {
                values: SystemTray.items.values.filter(i => !GlobalConfig.bar.tray.hiddenIcons.includes(i.id))
            }

            Item {
                id: cell

                required property SystemTrayItem modelData
                required property int index

                implicitWidth: root.cellSize
                implicitHeight: root.cellSize

                StyledRect {
                    anchors.fill: parent
                    radius: Tokens.rounding.normal
                    color: Colours.palette.m3onSurface
                    opacity: mouse.containsMouse ? 0.08 : 0

                    Behavior on opacity {
                        Anim {}
                    }
                }

                // Exactly how the inline tray (TrayItem.qml) renders icons
                ColouredIcon {
                    id: trayIcon

                    anchors.fill: parent
                    anchors.margins: Math.round(root.cellSize * 0.2)
                    source: Icons.getTrayIcon(cell.modelData.id, cell.modelData.icon)
                    colour: Colours.palette.m3secondary
                    layer.enabled: Config.bar.tray.recolour
                }

                // Fallback only when the icon truly can't be resolved (doesn't gate good icons)
                MaterialIcon {
                    anchors.centerIn: parent
                    visible: trayIcon.status === Image.Null || trayIcon.status === Image.Error
                    text: "extension"
                    color: Colours.palette.m3secondary
                    font.pointSize: Tokens.font.size.large
                }

                MouseArea {
                    id: mouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor

                    // Left: activate. Right: open the item's context menu (the existing traymenu popout)
                    onClicked: event => {
                        if (event.button === Qt.LeftButton)
                            cell.modelData.activate();
                        else
                            root.popouts.currentName = `traymenu${cell.index}`;
                    }
                }
            }
        }
    }

    StyledText {
        visible: items.count === 0
        text: qsTr("No tray items")
        color: Colours.palette.m3onSurfaceVariant
        font.pointSize: Tokens.font.size.small
    }
}
