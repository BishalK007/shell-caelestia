import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + (IdleInhibitor.active ? chipRow.implicitHeight + chipRow.anchors.topMargin : 0) + Tokens.padding.large * 2

    radius: Tokens.rounding.normal
    color: Colours.tPalette.m3surfaceContainer
    clip: true

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
                color: IdleInhibitor.active ? Colours.palette.m3secondary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: icon

                    anchors.centerIn: parent
                    text: "coffee"
                    color: IdleInhibitor.active ? Colours.palette.m3onSecondary : Colours.palette.m3onSecondaryContainer
                    font.pointSize: Tokens.font.size.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Keep Awake")
                    font.pointSize: Tokens.font.size.normal
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: IdleInhibitor.enabled ? qsTr("Preventing lock, screen off & sleep") : IdleInhibitor.sleepOnly ? qsTr("Locks & blanks normally, never sleeps") : qsTr("Normal power management")
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Tokens.font.size.small
                    elide: Text.ElideRight
                }
            }

            StyledSwitch {
                checked: IdleInhibitor.enabled
                onToggled: IdleInhibitor.enabled = checked
            }
        }

        // Sleep-only mode: idle lock/screen off still fire, only suspend is blocked —
        // for leaving jobs running in the background behind a locked screen.
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.normal

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Block sleep only")
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Tokens.font.size.small
                elide: Text.ElideRight
            }

            StyledSwitch {
                checked: IdleInhibitor.sleepOnly
                onToggled: IdleInhibitor.sleepOnly = checked
            }
        }
    }

    RowLayout {
        id: chipRow

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Tokens.spacing.larger
        anchors.bottomMargin: IdleInhibitor.active ? Tokens.padding.large : -implicitHeight
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        spacing: Tokens.spacing.normal

        opacity: IdleInhibitor.active ? 1 : 0
        scale: IdleInhibitor.active ? 1 : 0.5

        StyledRect {
            implicitWidth: activeText.implicitWidth + Tokens.padding.normal * 2
            implicitHeight: activeText.implicitHeight + Tokens.padding.small * 2

            radius: Tokens.rounding.full
            color: Colours.palette.m3primary

            StyledText {
                id: activeText

                anchors.centerIn: parent
                text: qsTr("Active since %1").arg(Qt.formatTime(IdleInhibitor.enabledSince, GlobalConfig.services.useTwelveHourClock ? "hh:mm a" : "hh:mm"))
                color: Colours.palette.m3onPrimary
                font.pointSize: Math.round(Tokens.font.size.small * 0.9)
            }
        }

        Item {
            Layout.fillWidth: true
        }

        IconTextButton {
            visible: IdleInhibitor.sleepOnly
            type: IconTextButton.Tonal
            icon: "lock"
            text: qsTr("Lock now")
            font.pointSize: Math.round(Tokens.font.size.small * 0.9)
            onClicked: IdleInhibitor.lockAndBlank()
        }

        Behavior on anchors.bottomMargin {
            Anim {
                type: Anim.DefaultSpatial
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.StandardSmall
            }
        }

        Behavior on scale {
            Anim {}
        }
    }

    Behavior on implicitHeight {
        Anim {
            type: Anim.DefaultSpatial
        }
    }
}
