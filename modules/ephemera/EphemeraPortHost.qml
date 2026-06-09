pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.ephemera.port.services
import qs.modules.ephemera.port.components

// Hosts the upstream Ephemera UI (vendored verbatim under port/) as its own
// per-screen slideout, driven by the EphemeraPort visibility singleton. This is
// the "proper Ephemera UI" the bar button opens; the original caelestia-native
// chat popout is kept and remains reachable via the Super+A keybind.
Scope {
    id: root

    // Single shared service — conversation state is shared across all screens.
    EphemeraService {
        id: ephemeraService

        pluginId: "ephemera"
    }

    Variants {
        model: Quickshell.screens

        delegate: EphemeraPanel {
            id: panel

            required property var modelData

            panelWidth: 480
            expandable: true
            expandedWidth: 960
            gap: 6

            Connections {
                target: EphemeraPort

                function onVisibleChanged(): void {
                    if (EphemeraPort.visible)
                        panel.show();
                    else
                        panel.hide();
                }
            }

            content: EphemeraChat {
                aiService: ephemeraService
                slideoutExpandable: panel.expandable
                slideoutExpanded: panel.expanded
                onExpandToggled: panel.expanded = !panel.expanded
                onHideRequested: EphemeraPort.visible = false
            }
        }
    }
}
