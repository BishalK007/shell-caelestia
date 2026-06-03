pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Picks the XWayland/X11 RandR primary output (for legacy Xrender apps). Connected outputs are shown
// as selectable chips rendered straight from Xrandr.outputs (a plain array Repeater — no dropdown,
// no dynamically-created menu items), so there's nothing to mis-render or get clipped. The list is
// re-queried whenever the panel pops up rather than polled (see Xrandr.refresh()).
StyledRect {
    id: root

    required property DrawerVisibilities visibilities

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2

    radius: Tokens.rounding.normal
    color: Colours.tPalette.m3surfaceContainer

    Component.onCompleted: Xrandr.refresh()

    // Re-query each time the panel becomes visible (utilities popup or sidebar) — no polling.
    Connections {
        target: root.visibilities

        function onUtilitiesChanged(): void {
            if (root.visibilities.utilities)
                Xrandr.refresh();
        }

        function onSidebarChanged(): void {
            if (root.visibilities.sidebar)
                Xrandr.refresh();
        }
    }

    ColumnLayout {
        id: layout

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.normal

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.normal

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: icon.implicitHeight + Tokens.padding.smaller * 2

                radius: Tokens.rounding.full
                color: Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: icon

                    anchors.centerIn: parent
                    text: "desktop_windows"
                    color: Colours.palette.m3onSecondaryContainer
                    font.pointSize: Tokens.font.size.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Primary Display")
                    font.pointSize: Tokens.font.size.normal
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Xrandr.outputs.length === 0 ? qsTr("No displays detected") : Xrandr.primary ? qsTr("Primary: %1").arg(Xrandr.primary) : qsTr("Tap a display to set it primary")
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Tokens.font.size.small
                    elide: Text.ElideRight
                }
            }
        }

        // Selectable chips, one per connected output. The current primary is highlighted.
        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            visible: Xrandr.outputs.length > 0

            Repeater {
                model: Xrandr.outputs

                delegate: StyledRect {
                    id: chip

                    required property var modelData
                    readonly property bool isPrimary: modelData.primary

                    implicitWidth: chipRow.implicitWidth + Tokens.padding.normal * 2
                    implicitHeight: chipRow.implicitHeight + Tokens.padding.small * 2

                    radius: Tokens.rounding.full
                    color: isPrimary ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh

                    StateLayer {
                        color: chip.isPrimary ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                        onClicked: Xrandr.setPrimary(chip.modelData.name)
                    }

                    RowLayout {
                        id: chipRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            Layout.alignment: Qt.AlignVCenter
                            text: chip.isPrimary ? "check" : "desktop_windows"
                            color: chip.isPrimary ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            font.pointSize: Tokens.font.size.normal
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: chip.modelData.name
                            color: chip.isPrimary ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                            font.pointSize: Tokens.font.size.small
                        }
                    }
                }
            }
        }
    }
}
