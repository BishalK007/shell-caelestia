pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Compact, FIXED-SIZE vertical workspace switcher: up arrow / current workspace number / down arrow.
// Unlike the native Workspaces widget it never grows or shrinks with occupancy, so it can't shove the
// rest of the bar around. The number is the active workspace of THIS bar's monitor (or the global
// active workspace when per-monitor workspaces are off). Arrows step to the previous/next workspace,
// mirroring the bar's scroll behaviour. Scroll handling lives in Bar.handleWheel (keyed on entry id).
StyledRect {
    id: root

    required property ShellScreen screen

    readonly property int activeWsId: GlobalConfig.bar.workspaces.perMonitorWorkspaces ? (Hypr.monitorFor(screen)?.activeWorkspace?.id ?? 1) : Hypr.activeWsId

    // dir: -1 = previous (up), +1 = next (down). Never step below workspace 1.
    function step(dir: int): void {
        if (dir < 0 && root.activeWsId <= 1)
            return;
        Hypr.dispatch(`workspace r${dir > 0 ? "+" : "-"}1`);
    }

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: layout.implicitHeight + Tokens.padding.small * 2

    radius: Tokens.rounding.full
    color: Colours.tPalette.m3surfaceContainer

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Math.floor(Tokens.spacing.small / 2)

        IconButton {
            Layout.alignment: Qt.AlignHCenter
            type: IconButton.Text
            icon: "keyboard_arrow_up"
            padding: Tokens.padding.small / 2
            disabled: root.activeWsId <= 1
            onClicked: root.step(-1)
        }

        StyledRect {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Math.max(implicitHeight, num.implicitWidth + Tokens.padding.small)
            implicitHeight: num.implicitHeight + Tokens.padding.smaller

            radius: Tokens.rounding.full
            color: Colours.palette.m3primary

            StyledText {
                id: num

                anchors.centerIn: parent
                animate: true
                text: `${root.activeWsId}`
                color: Colours.palette.m3onPrimary
                font.pointSize: Tokens.font.size.normal
                font.weight: 600
            }
        }

        IconButton {
            Layout.alignment: Qt.AlignHCenter
            type: IconButton.Text
            icon: "keyboard_arrow_down"
            padding: Tokens.padding.small / 2
            onClicked: root.step(1)
        }
    }
}
