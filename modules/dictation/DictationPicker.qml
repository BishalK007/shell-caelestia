pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

// Bottom-middle engine picker for dictation (opened by the dictation hotkey when idle).
// ←/→/Tab (or re-pressing the hotkey) cycles between Wispr Flow and Open Whispr; Enter/Space or a
// click starts the selected engine; Esc or clicking away dismisses. Slides up like DictationWidget.
PanelWindow {
    id: win

    // 0 = shown, 1 = hidden (slid down). Animated.
    property real offsetScale: Dictation.pickerOpen ? 0 : 1

    // Follow the focused monitor so the picker appears where the user is typing.
    screen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? null
    visible: offsetScale < 1
    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "caelestia-dictation-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Dictation.pickerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors.bottom: true
    margins.bottom: 5
    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    Behavior on offsetScale {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    HyprlandFocusGrab {
        active: Dictation.pickerOpen
        windows: [win]
        onCleared: Dictation.dismissPicker()
    }

    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const count = Dictation.providers.length;
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab)
                Dictation.pickerIndex = (Dictation.pickerIndex + count - 1) % count;
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab)
                Dictation.pickerIndex = (Dictation.pickerIndex + 1) % count;
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                Dictation.confirmPicker();
            else if (event.key === Qt.Key_Escape)
                Dictation.closePicker();
            else
                return;
            event.accepted = true;
        }

        StyledRect {
            id: card

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            // Slide down off the (clipped) window when hidden.
            anchors.bottomMargin: -implicitHeight * win.offsetScale

            implicitWidth: row.implicitWidth + Tokens.padding.normal * 2
            implicitHeight: row.implicitHeight + Tokens.padding.normal * 2

            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainer
            opacity: 1 - win.offsetScale

            Elevation {
                anchors.fill: parent
                radius: parent.radius
                z: -1
                level: 2
            }

            Row {
                id: row

                anchors.centerIn: parent
                spacing: Tokens.spacing.small

                Repeater {
                    model: Dictation.providers

                    delegate: StyledRect {
                        id: chip

                        required property var modelData
                        required property int index
                        readonly property bool selected: Dictation.pickerIndex === index

                        implicitWidth: label.implicitWidth + Tokens.padding.large * 2
                        implicitHeight: label.implicitHeight + Tokens.padding.normal * 2

                        radius: Tokens.rounding.normal
                        color: selected ? Colours.palette.m3primaryContainer : "transparent"

                        StateLayer {
                            radius: chip.radius
                            color: chip.selected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface

                            onClicked: {
                                Dictation.pickerIndex = chip.index;
                                Dictation.confirmPicker();
                            }
                        }

                        StyledText {
                            id: label

                            anchors.centerIn: parent
                            text: chip.modelData.name
                            font.weight: 500
                            color: chip.selected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }
        }
    }
}
