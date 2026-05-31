pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

// Compact "peek" indicator shown in place of a full popup card when Notifs.mode === "peek":
// just the app's circular logo, so an arriving notification is visible without taking space.
StyledClippingRect {
    id: root

    required property NotifData modelData
    readonly property int urgency: modelData?.urgency ?? NotificationUrgency.Normal
    readonly property bool hasImage: (modelData?.image.length ?? 0) > 0
    readonly property bool hasAppIcon: (modelData?.appIcon.length ?? 0) > 0

    implicitWidth: TokenConfig.sizes.notifs.image
    implicitHeight: TokenConfig.sizes.notifs.image
    radius: Tokens.rounding.full
    color: urgency === NotificationUrgency.Critical ? Colours.palette.m3error : urgency === NotificationUrgency.Low ? Colours.layer(Colours.palette.m3surfaceContainerHigh, 3) : Colours.palette.m3secondaryContainer

    // Clicking the peek badge opens the notification panel (and dismisses the badge).
    StateLayer {
        radius: parent.radius
        onClicked: {
            Visibilities.getForActive().sidebar = true;
            root.modelData.popup = false;
        }
    }

    Loader {
        anchors.centerIn: parent
        sourceComponent: root.hasImage ? imageComp : root.hasAppIcon ? appIconComp : iconComp
    }

    Component {
        id: imageComp

        Image {
            source: Qt.resolvedUrl(root.modelData.image)
            fillMode: Image.PreserveAspectCrop
            width: root.implicitWidth
            height: root.implicitHeight
            sourceSize.width: root.implicitWidth * ((QsWindow.window as QsWindow)?.devicePixelRatio ?? 1)
            sourceSize.height: root.implicitHeight * ((QsWindow.window as QsWindow)?.devicePixelRatio ?? 1)
            cache: false
            asynchronous: true
        }
    }

    Component {
        id: appIconComp

        ColouredIcon {
            implicitSize: Math.round(TokenConfig.sizes.notifs.image * 0.6)
            source: Quickshell.iconPath(root.modelData.appIcon)
            colour: root.urgency === NotificationUrgency.Critical ? Colours.palette.m3onError : root.urgency === NotificationUrgency.Low ? Colours.palette.m3onSurface : Colours.palette.m3onSecondaryContainer
            layer.enabled: root.modelData.appIcon.endsWith("symbolic")
        }
    }

    Component {
        id: iconComp

        MaterialIcon {
            text: Icons.getNotifIcon(root.modelData?.summary, root.urgency)
            color: root.urgency === NotificationUrgency.Critical ? Colours.palette.m3onError : root.urgency === NotificationUrgency.Low ? Colours.palette.m3onSurface : Colours.palette.m3onSecondaryContainer
            font.pointSize: Tokens.font.size.large
        }
    }
}
