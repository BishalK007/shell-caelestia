import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Bar icon that toggles the Ephemera chat as a click-triggered bar popout.
Item {
    id: root

    required property var popouts // BarPopouts.Wrapper
    required property var bar      // Bar root (for mapping the icon position into popout coords)

    readonly property bool active: popouts.currentName === "ephemera" && popouts.hasCurrent

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
        onClicked: {
            if (root.active) {
                root.popouts.hasCurrent = false;
            } else {
                root.popouts.currentName = "ephemera";
                root.popouts.hasCurrent = true;
                root.popouts.guardOpen();
            }
        }
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
