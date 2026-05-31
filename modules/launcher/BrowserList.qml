pragma ComponentBehavior: Bound

import "items"
import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

StyledListView {
    id: root

    required property StyledTextField search
    required property var visibilities

    spacing: Tokens.spacing.small
    implicitHeight: (Tokens.sizes.launcher.itemHeight + spacing) * Math.min(Config.launcher.maxShown, count) - spacing
    clip: true

    preferredHighlightBegin: 0
    preferredHighlightEnd: height
    highlightRangeMode: ListView.ApplyRange

    model: ScriptModel {
        // read items/favs lengths so the binding re-runs when the list or pins change
        values: (Browsers.items.length, Browsers.favs.length, Browsers.query(root.search.text))
        onValuesChanged: root.currentIndex = 0
    }

    highlightFollowsCurrentItem: false
    highlight: StyledRect {
        radius: Tokens.rounding.normal
        color: Colours.palette.m3onSurface
        opacity: 0.08

        y: root.currentItem?.y ?? 0
        implicitWidth: root.width
        implicitHeight: root.currentItem?.implicitHeight ?? 0

        Behavior on y {
            Anim {
                type: Anim.DefaultSpatial
            }
        }
    }

    delegate: BrowserItem {
        visibilities: root.visibilities
        view: root
    }

    StyledScrollBar.vertical: StyledScrollBar {
        flickable: root
    }

    Component.onCompleted: Browsers.reload()
}
