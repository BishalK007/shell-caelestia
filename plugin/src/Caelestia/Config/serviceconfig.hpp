#pragma once

#include "configobject.hpp"

#include <qstring.h>
#include <qvariant.h>

namespace caelestia::config {

using Qt::StringLiterals::operator""_s;

class ServiceConfig : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_GLOBAL_PROPERTY(QString, weatherLocation)
    // Guess based on locale
    CONFIG_GLOBAL_PROPERTY(bool, useFahrenheit,
        QLocale().measurementSystem() == QLocale::ImperialUSSystem ||
            QLocale().measurementSystem() == QLocale::ImperialUKSystem)
    // This is always false by default cause apparently even imperial system users don't use it for perf temps?
    CONFIG_GLOBAL_PROPERTY(bool, useFahrenheitPerformance, false)
    // Attempt to guess based on locale
    CONFIG_GLOBAL_PROPERTY(
        bool, useTwelveHourClock, QLocale().timeFormat(QLocale::ShortFormat).toLower().contains(u"a"_s))
    CONFIG_GLOBAL_PROPERTY(QString, gpuType)
    CONFIG_GLOBAL_PROPERTY(int, visualiserBars, 45)
    CONFIG_GLOBAL_PROPERTY(qreal, audioIncrement, 0.1)
    CONFIG_GLOBAL_PROPERTY(qreal, brightnessIncrement, 0.1)
    // Escape hatch: broken DDC/CI firmware can hang the i2c bus, so all probing/writes can be disabled
    CONFIG_GLOBAL_PROPERTY(bool, ddcEnabled, true)
    // Keep-latest write spacing per DDC monitor; VESA floor is 50ms, raise for flaky HDMI i2c paths
    CONFIG_GLOBAL_PROPERTY(int, ddcMinWriteIntervalMs, 100)
    // Empty = auto-resolve (firmware > platform > raw); set to pin e.g. amdgpu_bl1 on hybrid-GPU laptops
    CONFIG_GLOBAL_PROPERTY(QString, backlightDevice)
    // Slider range for SDR white luminance on HDR monitors (nits); 80 = SDR reference white
    CONFIG_GLOBAL_PROPERTY(int, hdrMinNits, 80)
    CONFIG_GLOBAL_PROPERTY(int, hdrMaxNits, 400)
    // DRM hotplug events arrive in bursts during link training; debounce before re-detecting
    CONFIG_GLOBAL_PROPERTY(int, hotplugDebounceMs, 1500)
    // Per-monitor overrides: { "match": "model:X"|"serial:X"|"name:X", "method": "ddc|backlight|hdr|apple|none",
    // "hdrMinNits": N, "hdrMaxNits": N }
    CONFIG_GLOBAL_PROPERTY(QVariantList, brightnessRules)
    CONFIG_GLOBAL_PROPERTY(qreal, maxVolume, 1.0)
    CONFIG_GLOBAL_PROPERTY(bool, smartScheme, true)
    CONFIG_GLOBAL_PROPERTY(QString, defaultPlayer, u"Spotify"_s)
    CONFIG_GLOBAL_PROPERTY(QVariantList, playerAliases,
        { vmap({ { u"from"_s, u"com.github.th_ch.youtube_music"_s }, { u"to"_s, u"YT Music"_s } }) })
    CONFIG_GLOBAL_PROPERTY(bool, showLyrics, false)
    CONFIG_GLOBAL_PROPERTY(QString, lyricsBackend, u"Auto"_s)

public:
    explicit ServiceConfig(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

} // namespace caelestia::config
