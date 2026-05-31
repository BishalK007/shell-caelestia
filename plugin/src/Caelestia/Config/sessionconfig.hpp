#pragma once

#include "configobject.hpp"

#include <qstring.h>
#include <qstringlist.h>

namespace caelestia::config {

using Qt::StringLiterals::operator""_s;

class SessionIcons : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(QString, lock, u"lock"_s)
    CONFIG_PROPERTY(QString, logout, u"logout"_s)
    CONFIG_PROPERTY(QString, suspend, u"bedtime"_s)
    CONFIG_PROPERTY(QString, hibernate, u"downloading"_s)
    CONFIG_PROPERTY(QString, reboot, u"cached"_s)
    CONFIG_PROPERTY(QString, rebootForce, u"restart_alt"_s)
    CONFIG_PROPERTY(QString, shutdown, u"power_settings_new"_s)
    CONFIG_PROPERTY(QString, shutdownForce, u"power_off"_s)

public:
    explicit SessionIcons(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

class SessionCommands : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(QStringList, lock, { u"loginctl"_s, u"lock-session"_s })
    CONFIG_PROPERTY(QStringList, logout, { u"loginctl"_s, u"terminate-user"_s, u""_s })
    CONFIG_PROPERTY(QStringList, suspend, { u"systemctl"_s, u"suspend"_s })
    CONFIG_PROPERTY(QStringList, hibernate, { u"systemctl"_s, u"hibernate"_s })
    CONFIG_PROPERTY(QStringList, reboot, { u"systemctl"_s, u"reboot"_s })
    CONFIG_PROPERTY(QStringList, rebootForce, { u"systemctl"_s, u"reboot"_s, u"-f"_s })
    CONFIG_PROPERTY(QStringList, shutdown, { u"systemctl"_s, u"poweroff"_s })
    CONFIG_PROPERTY(QStringList, shutdownForce, { u"systemctl"_s, u"poweroff"_s, u"-f"_s })

public:
    explicit SessionCommands(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

class SessionConfig : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_PROPERTY(int, dragThreshold, 30)
    CONFIG_PROPERTY(bool, vimKeybinds, false)
    CONFIG_SUBOBJECT(SessionIcons, icons)
    CONFIG_SUBOBJECT(SessionCommands, commands)

public:
    explicit SessionConfig(QObject* parent = nullptr)
        : ConfigObject(parent)
        , m_icons(new SessionIcons(this))
        , m_commands(new SessionCommands(this)) {}
};

} // namespace caelestia::config
