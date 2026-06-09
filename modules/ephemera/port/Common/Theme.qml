pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.services

// DMS-compat Theme shim for the vendored Ephemera UI.
// Colours map to caelestia's live palette (Colours) so the Ephemera UI follows
// the user's theme; fonts map to caelestia's Tokens; metrics/animation use
// DMS's own scale so the Ephemera layout stays visually faithful.
Singleton {
    id: root

    // ── Palette → caelestia Colours ──
    readonly property color primary: Colours.palette.m3primary
    readonly property color onPrimary: Colours.palette.m3onPrimary
    readonly property color primaryContainer: Colours.palette.m3primaryContainer
    readonly property color primaryHover: withAlpha(Colours.palette.m3primary, 0.12)
    readonly property color primaryHoverLight: withAlpha(Colours.palette.m3primary, 0.08)
    readonly property color tertiary: Colours.palette.m3tertiary
    readonly property color error: Colours.palette.m3error
    readonly property color success: Colours.palette.m3success
    readonly property color background: Colours.palette.m3background
    readonly property color surfaceContainer: Colours.palette.m3surfaceContainer
    readonly property color surfaceContainerHigh: Colours.palette.m3surfaceContainerHigh
    readonly property color surfaceContainerHighest: Colours.palette.m3surfaceContainerHighest
    readonly property color surfaceVariant: Colours.palette.m3surfaceVariant
    readonly property color surfaceVariantAlpha: withAlpha(Colours.palette.m3surfaceVariant, 0.4)
    readonly property color surfaceText: Colours.palette.m3onSurface
    readonly property color surfaceTextMedium: withAlpha(Colours.palette.m3onSurface, 0.68)
    readonly property color surfaceVariantText: Colours.palette.m3onSurfaceVariant
    readonly property color onSurface: Colours.palette.m3onSurface
    readonly property color onSurface_38: withAlpha(Colours.palette.m3onSurface, 0.38)
    readonly property color outline: Colours.palette.m3outline
    readonly property color outlineVariant: Colours.palette.m3outlineVariant
    readonly property color outlineMedium: withAlpha(Colours.palette.m3outline, 0.5)
    readonly property color outlineStrong: Colours.palette.m3outline
    readonly property color outlineButton: withAlpha(Colours.palette.m3outline, 0.5)
    readonly property color buttonBg: Colours.palette.m3primary
    readonly property color buttonText: Colours.palette.m3onPrimary

    readonly property bool isLightMode: Colours.light

    // ── Fonts → caelestia Tokens ──
    readonly property string fontFamily: Tokens.font.family.sans
    readonly property string monoFontFamily: Tokens.font.family.mono
    readonly property string iconFontFamily: Tokens.font.family.material
    // Sentinels: kept different from the requested families so StyledText's
    // "use bundled font" branch never triggers (we have no bundled fonts).
    readonly property string defaultFontFamily: "__caelestia_sans__"
    readonly property string defaultMonoFontFamily: "__caelestia_mono__"
    readonly property int fontWeight: Font.Normal

    // ── Metrics (DMS scale, for Ephemera-faithful layout) ──
    readonly property real spacingXS: 4
    readonly property real spacingS: 8
    readonly property real spacingM: 12
    readonly property real spacingL: 16
    readonly property real spacingXL: 24
    readonly property real fontSizeSmall: 12
    readonly property real fontSizeMedium: 14
    readonly property real fontSizeLarge: 16
    readonly property real cornerRadius: 12
    readonly property real iconSize: 24
    readonly property real iconSizeSmall: 16

    // ── Transparency (solid; caelestia popouts handle their own blur) ──
    readonly property real popupTransparency: 1.0

    // ── Animation ──
    readonly property int shortDuration: 200
    readonly property int shorterDuration: 150
    readonly property int standardEasing: Easing.OutCubic
    readonly property int currentAnimationSpeed: 1 // Short (≠ None)

    readonly property var expressiveCurves: ({
            "emphasized": [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1],
            "emphasizedAccel": [0.3, 0, 0.8, 0.15, 1, 1],
            "emphasizedDecel": [0.05, 0.7, 0.1, 1, 1, 1],
            "standard": [0.2, 0, 0, 1, 1, 1],
            "standardAccel": [0.3, 0, 1, 1, 1, 1],
            "standardDecel": [0, 0, 0, 1, 1, 1],
            "expressiveFastSpatial": [0.42, 1.67, 0.21, 0.9, 1, 1],
            "expressiveDefaultSpatial": [0.38, 1.21, 0.22, 1, 1, 1],
            "expressiveEffects": [0.34, 0.8, 0.34, 1, 1, 1]
        })

    readonly property var expressiveDurations: ({
            "fast": 200,
            "normal": 400,
            "large": 600,
            "extraLarge": 1000,
            "expressiveFastSpatial": 350,
            "expressiveDefaultSpatial": 500,
            "expressiveEffects": 200
        })

    // ── Elevation (self-contained downward drop shadow) ──
    readonly property bool elevationEnabled: true
    readonly property real elevationBlurMax: 64
    readonly property string elevationLightDirection: "bottom"
    readonly property var elevationLevel2: ({
            blurPx: 8,
            offsetX: 0,
            offsetY: 4,
            spreadPx: 0,
            alpha: 0.25
        })

    function elevationOffsetXFor(level, direction, fallback) {
        return (level && level.offsetX !== undefined) ? level.offsetX : 0;
    }
    function elevationOffsetYFor(level, direction, fallback) {
        return (level && level.offsetY !== undefined) ? level.offsetY : (fallback || 4);
    }
    function elevationShadowColor(level) {
        return Qt.rgba(0, 0, 0, (level && level.alpha !== undefined) ? level.alpha : 0.25);
    }

    // ── Helpers (verbatim from DMS Theme) ──
    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }
    function px(value, dpr) {
        const s = dpr || 1;
        return Math.round(value * s) / s;
    }
    function snap(value, dpr) {
        const s = dpr || 1;
        return Math.round(value * s) / s;
    }
}
