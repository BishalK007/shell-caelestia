pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Picks the XWayland/X11 RandR primary output (for legacy Xrender apps). The list is re-queried
// whenever the utilities panel pops up rather than polled — see Xrandr.refresh().
StyledRect {
    id: root

    required property DrawerVisibilities visibilities

    // Tracks the output names currently materialised as menu items, so we only rebuild the
    // (dynamically created) MenuItems when the set of displays actually changes.
    property var _names: []

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + layout.anchors.margins * 2

    radius: Tokens.rounding.normal
    color: Colours.tPalette.m3surfaceContainer

    function syncMenu(): void {
        const names = Xrandr.outputs.map(o => o.name);
        const changed = names.length !== root._names.length || names.some((n, i) => n !== root._names[i]);

        if (changed) {
            const old = splitBtn.menuItems;
            const arr = [];
            for (const o of Xrandr.outputs) {
                const it = itemComp.createObject(root, {
                    icon: "desktop_windows",
                    text: o.name
                });
                it.clicked.connect(() => Xrandr.setPrimary(o.name));
                arr.push(it);
            }
            splitBtn.menuItems = arr;
            root._names = names;
            Qt.callLater(() => {
                for (const o of old)
                    o.destroy();
            });
        }

        splitBtn.active = splitBtn.menuItems.find(m => m.text === Xrandr.primary) ?? splitBtn.menuItems[0] ?? null;
    }

    Component.onCompleted: {
        Xrandr.refresh();
        syncMenu();
    }

    // Re-query each time the panel becomes visible (utilities popup or sidebar) — no polling.
    Connections {
        target: root.visibilities

        function onUtilitiesChanged(): void {
            if (root.visibilities.utilities)
                Xrandr.refresh();
        }

        function onSidebarChanged(): void {
            if (root.visibilities.sidebar)
                Xrandr.refresh();
        }
    }

    Connections {
        target: Xrandr

        function onOutputsChanged(): void {
            root.syncMenu();
        }

        function onPrimaryChanged(): void {
            root.syncMenu();
        }
    }

    Component {
        id: itemComp

        MenuItem {}
    }

    RowLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.normal
        z: 1

        StyledRect {
            implicitWidth: implicitHeight
            implicitHeight: icon.implicitHeight + Tokens.padding.smaller * 2

            radius: Tokens.rounding.full
            color: Colours.palette.m3secondaryContainer

            MaterialIcon {
                id: icon

                anchors.centerIn: parent
                text: "desktop_windows"
                color: Colours.palette.m3onSecondaryContainer
                font.pointSize: Tokens.font.size.large
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Primary Display")
                font.pointSize: Tokens.font.size.normal
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: Xrandr.outputs.length === 0 ? qsTr("No displays detected") : Xrandr.primary ? qsTr("Primary: %1").arg(Xrandr.primary) : qsTr("No primary set")
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Tokens.font.size.small
                elide: Text.ElideRight
            }
        }

        SplitButton {
            id: splitBtn

            disabled: Xrandr.outputs.length === 0
            fallbackIcon: "desktop_windows"
            fallbackText: qsTr("Select")
        }
    }
}
