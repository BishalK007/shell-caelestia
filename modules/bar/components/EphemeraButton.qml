import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Bar icon that toggles the Ephemera chat as a click-triggered bar popout.
Item {
    id: root

    required property var popouts // BarPopouts.Wrapper
    required property var bar      // Bar root (for mapping the icon position into popout coords)

    // Click now opens the full upstream Ephemera UI (the vendored port slideout).
    // The original caelestia-native popout stays reachable via the Super+A keybind.
    readonly property bool active: EphemeraPort.visible

    implicitWidth: icon.implicitHeight + Tokens.padding.small * 2
    implicitHeight: icon.implicitHeight

    // Keep the popout anchored at this icon whenever it's the active popout (covers keybind opens too).
    Binding {
        when: root.popouts.currentName === "ephemera"
        target: root.popouts
        property: "currentCenter"
        value: root.mapToItem(root.bar, 0, root.implicitHeight / 2).y
        restoreMode: Binding.RestoreNone
    }

    StateLayer {
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: implicitHeight
        implicitHeight: icon.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        onClicked: EphemeraPort.toggle()
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        text: "forum"
        color: root.active ? Colours.palette.m3primary : Colours.palette.m3onSurface
        fill: root.active ? 1 : 0
        font.pointSize: Tokens.font.size.normal

        Behavior on fill {
            Anim {}
        }
    }
}
