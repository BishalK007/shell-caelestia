import QtQuick
import qs.modules.ephemera.port.Common

Item {
    id: root

    property alias name: icon.text
    property alias size: icon.font.pixelSize
    property alias color: icon.color
    property bool filled: false
    property real fill: filled ? 1.0 : 0.0
    property int grade: Theme.isLightMode ? 0 : -25
    property int weight: filled ? 500 : 400
    property bool smoothTransform: false

    implicitWidth: Math.round(size)
    implicitHeight: Math.round(size)

    signal rotationCompleted

    FontLoader {
        id: materialSymbolsFont
        source: "" // caelestia ships Material Symbols system-wide (Theme.iconFontFamily)
    }

    StyledText {
        id: icon

        anchors.fill: parent

        font.family: Theme.iconFontFamily
        font.pixelSize: Math.round(Theme.fontSizeMedium)
        font.weight: root.weight
        font.hintingPreference: Font.PreferNoHinting
        color: Theme.surfaceText
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        renderType: root.smoothTransform ? Text.QtRendering : Text.NativeRendering

        Behavior on color {
            enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
            DankColorAnim {
                duration: Theme.shorterDuration
                easing.bezierCurve: Theme.expressiveCurves.standard
            }
        }
        font.variableAxes: {
            "FILL": root.fill.toFixed(1),
            "GRAD": root.grade,
            "opsz": 24,
            "wght": root.weight
        }

        Behavior on font.weight {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }
    }

    Behavior on fill {
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }

    Timer {
        id: rotationTimer
        interval: 16
        repeat: false
        onTriggered: root.rotationCompleted()
    }

    onRotationChanged: {
        rotationTimer.restart();
    }
}
