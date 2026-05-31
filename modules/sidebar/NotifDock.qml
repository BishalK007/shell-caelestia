pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    required property Props props
    required property DrawerVisibilities visibilities
    readonly property int notifCount: Notifs.list.reduce((acc, n) => n.closed ? acc : acc + 1, 0)

    anchors.fill: parent
    anchors.margins: Tokens.padding.normal

    Component.onCompleted: Notifs.list.forEach(n => n.popup = false)

    Item {
        id: title

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.small

        implicitHeight: Math.max(count.implicitHeight, titleText.implicitHeight)

        StyledText {
            id: count

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: root.notifCount > 0 ? 0 : -width - titleText.anchors.leftMargin
            opacity: root.notifCount > 0 ? 1 : 0

            text: root.notifCount
            color: Colours.palette.m3outline
            font.pointSize: Tokens.font.size.normal
            font.family: Tokens.font.family.mono
            font.weight: 500

            Behavior on anchors.leftMargin {
                Anim {}
            }

            Behavior on opacity {
                Anim {}
            }
        }

        StyledText {
            id: titleText

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: count.right
            anchors.right: parent.right
            anchors.leftMargin: Tokens.spacing.small

            text: root.notifCount > 0 ? qsTr("notification%1").arg(root.notifCount === 1 ? "" : "s") : qsTr("Notifications")
            color: Colours.palette.m3outline
            font.pointSize: Tokens.font.size.normal
            font.family: Tokens.font.family.mono
            font.weight: 500
            elide: Text.ElideRight
        }
    }

    ClippingRectangle {
        id: clipRect

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: title.bottom
        anchors.bottom: bottomBar.top
        anchors.topMargin: Tokens.spacing.smaller
        anchors.bottomMargin: Tokens.spacing.smaller

        radius: Tokens.rounding.small
        color: "transparent"

        Loader {
            asynchronous: true
            anchors.centerIn: parent
            active: opacity > 0
            opacity: root.notifCount > 0 ? 0 : 1

            sourceComponent: ColumnLayout {
                spacing: Tokens.spacing.large

                Image {
                    asynchronous: true
                    source: Paths.absolutePath(Config.paths.noNotifsPic)
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: clipRect.width * 0.8 * ((QsWindow.window as QsWindow)?.devicePixelRatio ?? 1)

                    layer.enabled: true
                    layer.effect: Colouriser {
                        colorizationColor: Colours.palette.m3outlineVariant
                        brightness: 1
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("No Notifications")
                    color: Colours.palette.m3outlineVariant
                    font.pointSize: Tokens.font.size.large
                    font.family: Tokens.font.family.mono
                    font.weight: 500
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.StandardExtraLarge
                }
            }
        }

        StyledFlickable {
            id: view

            anchors.fill: parent

            flickableDirection: Flickable.VerticalFlick
            contentWidth: width
            contentHeight: notifList.implicitHeight

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: view
            }

            NotifDockList {
                id: notifList

                props: root.props
                visibilities: root.visibilities
                container: view
            }
        }
    }

    Timer {
        id: clearTimer

        repeat: true
        triggeredOnStart: true
        interval: Math.max(15, Math.min(80, 69.8 - 12.3 * Math.log(Notifs.notClosed.length)))
        onTriggered: {
            const first = Notifs.notClosed[0];
            if (!first) {
                stop();
                return;
            }

            const appName = first.appName;
            let cleared = 0;
            for (const n of Notifs.notClosed.filter(n => n.appName === appName)) {
                n.close();
                cleared++;
                if (cleared > 30) {
                    interval = 5;
                    return;
                }
            }
        }
    }

    // Bottom bar: A (display mode) + B (sound) + clear-all on top, the notification-volume
    // slider ("notification channel") underneath. The list is docked above this (see clipRect).
    Column {
        id: bottomBar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.normal
        spacing: Tokens.spacing.small

        RowLayout {
            width: parent.width
            spacing: Tokens.spacing.small

            IconButton {
                type: IconButton.Tonal
                checked: Notifs.mode !== "default"
                icon: Notifs.mode === "dnd" ? "do_not_disturb_on" : Notifs.mode === "peek" ? "notifications_paused" : "notifications_active"
                radius: Tokens.rounding.normal
                padding: Tokens.padding.normal
                font.pointSize: Math.round(Tokens.font.size.large * 1.2)
                onClicked: Notifs.cycleMode()
            }

            IconButton {
                type: IconButton.Tonal
                checked: Notifs.soundEnabled
                icon: Notifs.soundEnabled ? "volume_up" : "volume_off"
                radius: Tokens.rounding.normal
                padding: Tokens.padding.normal
                font.pointSize: Math.round(Tokens.font.size.large * 1.2)
                onClicked: Notifs.toggleSound()
            }

            Item {
                Layout.fillWidth: true
            }

            IconButton {
                id: clearBtn

                opacity: root.notifCount > 0 ? 1 : 0
                visible: opacity > 0
                icon: "clear_all"
                radius: Tokens.rounding.normal
                padding: Tokens.padding.normal
                font.pointSize: Math.round(Tokens.font.size.large * 1.2)
                onClicked: clearTimer.start()

                Elevation {
                    anchors.fill: parent
                    radius: parent.radius
                    z: -1
                    level: clearBtn.stateLayer.containsMouse ? 4 : 3
                }

                Behavior on opacity {
                    Anim {
                        duration: Tokens.anim.durations.expressiveFastSpatial
                    }
                }
            }
        }

        // Notification volume — same control as the audio widget's Notification slider; both drive
        // notification_sink's volume. The shell no longer overrides this, so it's yours to set.
        RowLayout {
            width: parent.width
            spacing: Tokens.spacing.small
            visible: VirtualSink.available

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                text: VirtualSink.notificationMuted ? "notifications_off" : "notifications"
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledSlider {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: Tokens.padding.normal * 3
                from: 0
                to: GlobalConfig.services.maxVolume
                value: VirtualSink.notificationVolume
                onMoved: VirtualSink.setNotificationVolume(value)

                Behavior on value {
                    Anim {}
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: `${Math.round(VirtualSink.notificationVolume * 100)}%`
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Tokens.font.size.small
            }
        }
    }
}
