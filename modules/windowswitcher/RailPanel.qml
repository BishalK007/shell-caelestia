pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property SwitcherState switcher
    required property var nav

    property real cellW: 160
    property real cellH: cellW * 0.625

    implicitWidth: cellW + Tokens.padding.large * 2

    Column {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: Tokens.padding.large

        spacing: Tokens.spacing.large * 2

        Row {
            spacing: Tokens.spacing.small

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter

                text: "star"
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter

                text: qsTr("special")
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        Repeater {
            model: root.switcher.rail

            WindowCell {
                id: cell

                required property var modelData
                required property int index

                readonly property bool isSelected: root.switcher.zone === "rail" && root.switcher.railIndex === index

                toplevel: modelData
                selected: isSelected
                nav: root.nav
                liveCapture: true
                // Hover never selects (anywhere): rail hover used to steal the
                // grid's selection with no way back. Wheel/Tab/keys/click move
                // selection; hover only highlights.
                hoverSelects: false
                showVisibleDot: {
                    let wsName = "";
                    try {
                        wsName = modelData?.workspace?.name ?? "";
                    } catch (e) {}
                    const vis = Hypr.focusedMonitor?.lastIpcObject?.specialWorkspace?.name ?? "";
                    return wsName !== "" && wsName === vis;
                }

                width: root.cellW
                height: root.cellH
                z: isSelected ? 1 : 0
                // Nudge left instead of scaling — scaled text is unreadable.
                x: isSelected ? -Tokens.spacing.smaller : 0

                Behavior on x {
                    Anim {}
                }

                onSelect: {
                    root.switcher.zone = "rail";
                    root.switcher.railIndex = cell.index;
                }

                onActivate: {
                    root.switcher.zone = "rail";
                    root.switcher.railIndex = cell.index;
                    root.switcher.commit();
                }
            }
        }
    }
}
