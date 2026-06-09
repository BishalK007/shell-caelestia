import QtQuick
import qs.modules.ephemera.port.Common
import qs.modules.ephemera.port.Services

TextMetrics {
    property bool isMonospace: false

    readonly property string resolvedFontFamily: {
        const requestedFont = isMonospace ? SettingsData.monoFontFamily : SettingsData.fontFamily;
        const defaultFont = isMonospace ? Theme.defaultMonoFontFamily : Theme.defaultFontFamily;

        if (requestedFont === defaultFont) {
            const availableFonts = Qt.fontFamilies();
            if (!availableFonts.includes(requestedFont)) {
                return isMonospace ? "Monospace" : "DejaVu Sans";
            }
        }
        return requestedFont;
    }

    font.pixelSize: Appearance.fontSize.normal
    font.family: resolvedFontFamily
    font.weight: SettingsData.fontWeight
}
