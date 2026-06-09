pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config

// DMS-compat SettingsData shim — only the members the vendored Ephemera UI +
// Dank widgets actually read.
Singleton {
    id: root

    enum AnimationSpeed {
        None,
        Short,
        Medium,
        Long,
        Custom
    }

    enum TextRenderType {
        Qt,
        Native,
        Curve
    }

    enum TextRenderQuality {
        Default,
        Low,
        Normal,
        High,
        VeryHigh
    }

    readonly property real popupTransparency: 1.0
    readonly property bool enableRippleEffects: true
    readonly property bool popoutElevationEnabled: true
    readonly property int animationSpeed: SettingsData.AnimationSpeed.Short

    readonly property int textRenderType: SettingsData.TextRenderType.Qt
    readonly property int textRenderQuality: SettingsData.TextRenderQuality.Default

    readonly property string fontFamily: Tokens.font.family.sans
    readonly property string monoFontFamily: Tokens.font.family.mono
    readonly property int fontWeight: Font.Normal
}
