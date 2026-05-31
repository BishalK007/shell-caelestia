pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Caelestia.Config
import qs.components
import qs.services

// A single bar icon that opens the "systray" grid popout. The actual tray items
// live in that popout (modules/bar/popouts/SysTray.qml), not inline on the bar.
StyledRect {
    id: root

    readonly property int count: SystemTray.items.values.filter(i => !GlobalConfig.bar.tray.hiddenIcons.includes(i.id)).length

    // Vestigial: Bar.qml's closeTray() still assigns this; no compact/expand behaviour anymore
    property bool expanded

    visible: count > 0
    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: visible ? icon.implicitHeight + Tokens.padding.normal * 2 : 0

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, Config.bar.tray.background ? Colours.tPalette.m3surfaceContainer.a : 0)
    radius: Tokens.rounding.full

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        text: "widgets"
        color: Colours.palette.m3secondary
        font.pointSize: Tokens.font.size.large
    }

    Behavior on implicitHeight {
        Anim {
            type: Anim.DefaultSpatial
        }
    }
}
