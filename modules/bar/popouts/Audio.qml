pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property PopoutState popouts

    // Collapsible section state (device pickers start collapsed to keep the popout compact)
    property bool showOutputs: false
    property bool showInputs: false
    property bool showMusicOutputs: false
    property bool showAlsa: false

    readonly property real maxVol: GlobalConfig.services.maxVolume
    // Cap the popout height; everything past this scrolls inside the Flickable.
    readonly property real maxHeight: 700

    implicitWidth: 400
    implicitHeight: Math.min(column.implicitHeight, maxHeight)

    // ALSA reads only run while the popout is open; pin the virtual-sink loopbacks on open too.
    Component.onCompleted: {
        Alsa.refCount++;
        VirtualSink.pinLoopbacks();
    }
    Component.onDestruction: Alsa.refCount--

    function volIcon(vol: real, muted: bool): string {
        if (muted || vol <= 0.001)
            return "volume_off";
        if (vol <= 0.01)
            return "volume_mute";
        if (vol <= 0.5)
            return "volume_down";
        return "volume_up";
    }

    Flickable {
        id: flick

        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        ScrollBar.vertical: ScrollBar {
            policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }

        ColumnLayout {
            id: column

            width: flick.width
            spacing: Tokens.spacing.normal

            // ── Output (default speaker) ────────────────────────────────────────
            Card {
                StyledText {
                    text: qsTr("Main Sound")
                    font.weight: 500
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Output: %1").arg(Audio.sink?.description || qsTr("None"))
                    elide: Text.ElideRight
                    font.pointSize: Tokens.font.size.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                VolumeRow {
                    icon: root.volIcon(Audio.volume, Audio.muted)
                    muted: Audio.muted
                    value: Audio.volume
                    max: root.maxVol
                    onMoved: v => Audio.setVolume(v)
                    onToggle: {
                        if (Audio.sink?.ready && Audio.sink?.audio)
                            Audio.sink.audio.muted = !Audio.muted;
                    }
                }

                SectionHeader {
                    title: qsTr("Output Devices")
                    expanded: root.showOutputs
                    onToggled: root.showOutputs = !root.showOutputs
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.smaller / 2
                    visible: root.showOutputs

                    // Physical devices + the Music Virtual Sink (so it can be the system default,
                    // routing every app's audio through music_sink). notification_sink is hidden —
                    // it's the alert bus (fanned out to all sinks), not a sensible default.
                    Repeater {
                        model: Audio.sinks.filter(n => n && n.name !== "notification_sink")

                        DeviceRow {
                            required property PwNode modelData

                            label: modelData.description || modelData.name
                            selected: Audio.sink?.id === modelData.id
                            onClicked: Audio.setAudioSink(modelData)
                        }
                    }
                }
            }

            // ── Input (default microphone) ──────────────────────────────────────
            Card {
                StyledText {
                    Layout.fillWidth: true
                    text: Audio.source?.description || qsTr("Input device")
                    font.weight: 500
                    elide: Text.ElideRight
                }

                VolumeRow {
                    icon: Audio.sourceMuted ? "mic_off" : "mic"
                    muted: Audio.sourceMuted
                    value: Audio.sourceVolume
                    max: root.maxVol
                    onMoved: v => Audio.setSourceVolume(v)
                    onToggle: {
                        if (Audio.source?.ready && Audio.source?.audio)
                            Audio.source.audio.muted = !Audio.sourceMuted;
                    }
                }

                SectionHeader {
                    title: qsTr("Input Devices")
                    expanded: root.showInputs
                    onToggled: root.showInputs = !root.showInputs
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.smaller / 2
                    visible: root.showInputs

                    Repeater {
                        model: Audio.sources

                        DeviceRow {
                            required property PwNode modelData

                            label: modelData.description || modelData.name
                            selected: Audio.source?.id === modelData.id
                            onClicked: Audio.setAudioSource(modelData)
                        }
                    }
                }
            }

            // ── Per-application streams ─────────────────────────────────────────
            Card {
                id: appsCard

                readonly property var appStreams: Audio.streams.filter(s => s && s.name !== "music_sink.output" && s.name !== "notification_sink.output")

                visible: appsCard.appStreams.length > 0

                StyledText {
                    text: qsTr("Applications")
                    font.weight: 500
                }

                Repeater {
                    model: appsCard.appStreams

                    ColumnLayout {
                        id: streamItem

                        required property PwNode modelData

                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: Audio.getStreamName(streamItem.modelData)
                            elide: Text.ElideRight
                            font.pointSize: Tokens.font.size.small
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        VolumeRow {
                            icon: root.volIcon(streamItem.modelData.audio?.volume ?? 0, streamItem.modelData.audio?.muted ?? false)
                            muted: streamItem.modelData.audio?.muted ?? false
                            value: streamItem.modelData.audio?.volume ?? 0
                            max: root.maxVol
                            onMoved: v => Audio.setStreamVolume(streamItem.modelData, v)
                            onToggle: Audio.setStreamMuted(streamItem.modelData, !(streamItem.modelData.audio?.muted ?? false))
                        }
                    }
                }
            }

            // ── Virtual sinks (music / notification routing) ────────────────────
            Card {
                visible: VirtualSink.available

                StyledText {
                    text: qsTr("Virtual Sinks")
                    font.weight: 500
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Music: %1").arg(VirtualSink.musicOutputLabel)
                    elide: Text.ElideRight
                    font.pointSize: Tokens.font.size.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                // Slider C controls the SELECTED OUTPUT DEVICE's volume, not music_sink's.
                VolumeRow {
                    icon: root.volIcon(VirtualSink.outputVolume, VirtualSink.outputMuted)
                    muted: VirtualSink.outputMuted
                    value: VirtualSink.outputVolume
                    max: root.maxVol
                    onMoved: v => VirtualSink.setOutputVolume(v)
                    onToggle: VirtualSink.setOutputMuted(!VirtualSink.outputMuted)
                }

                SectionHeader {
                    title: qsTr("Music Output Device")
                    expanded: root.showMusicOutputs
                    onToggled: root.showMusicOutputs = !root.showMusicOutputs
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.smaller / 2
                    visible: root.showMusicOutputs

                    Repeater {
                        model: VirtualSink.physicalSinks

                        DeviceRow {
                            required property PwNode modelData

                            label: modelData.description || modelData.name
                            selected: VirtualSink.musicOutput === modelData.name
                            onClicked: VirtualSink.setMusicOutput(modelData)
                        }
                    }
                }

                StyledText {
                    Layout.topMargin: Tokens.spacing.smaller
                    text: qsTr("Notification")
                    font.pointSize: Tokens.font.size.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                VolumeRow {
                    icon: VirtualSink.notificationMuted ? "notifications_off" : "notifications"
                    muted: VirtualSink.notificationMuted
                    value: VirtualSink.notificationVolume
                    max: root.maxVol
                    onMoved: v => VirtualSink.setNotificationVolume(v)
                    onToggle: VirtualSink.setNotificationMuted(!VirtualSink.notificationMuted)
                }
            }

            // ── ALSA hardware controls ──────────────────────────────────────────
            Card {
                visible: Alsa.available

                SectionHeader {
                    title: qsTr("ALSA Hardware Controls")
                    expanded: root.showAlsa
                    onToggled: root.showAlsa = !root.showAlsa
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    visible: root.showAlsa

                    StyledText {
                        text: qsTr("Master")
                        font.pointSize: Tokens.font.size.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    VolumeRow {
                        icon: root.volIcon(Alsa.masterVolume / 100, Alsa.masterMuted)
                        muted: Alsa.masterMuted
                        value: Alsa.masterVolume / 100
                        max: 1
                        onMoved: v => Alsa.setVolume("Master", v * 100)
                        onToggle: Alsa.setMuted("Master", !Alsa.masterMuted)
                    }

                    StyledText {
                        text: qsTr("Speaker")
                        font.pointSize: Tokens.font.size.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    VolumeRow {
                        icon: root.volIcon(Alsa.speakerVolume / 100, Alsa.speakerMuted)
                        muted: Alsa.speakerMuted
                        value: Alsa.speakerVolume / 100
                        max: 1
                        onMoved: v => Alsa.setVolume("Speaker", v * 100)
                        onToggle: Alsa.setMuted("Speaker", !Alsa.speakerMuted)
                    }

                    StyledText {
                        text: qsTr("Headphone/AUX")
                        font.pointSize: Tokens.font.size.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    VolumeRow {
                        icon: Alsa.headphoneMuted ? "headset_off" : "headphones"
                        muted: Alsa.headphoneMuted
                        value: Alsa.headphoneVolume / 100
                        max: 1
                        onMoved: v => Alsa.setVolume("Headphone", v * 100)
                        onToggle: Alsa.setMuted("Headphone", !Alsa.headphoneMuted)
                    }
                }
            }

            // ── Settings ────────────────────────────────────────────────────────
            IconTextButton {
                Layout.fillWidth: true
                inactiveColour: Colours.palette.m3primaryContainer
                inactiveOnColour: Colours.palette.m3onPrimaryContainer
                verticalPadding: Tokens.padding.small
                text: qsTr("Open settings")
                icon: "settings"
                onClicked: root.popouts.detachRequested("audio")
            }
        }
    }

    // ── Reusable inline components ───────────────────────────────────────────────

    component Card: StyledRect {
        default property alias cdata: cardCol.data

        Layout.fillWidth: true
        radius: Tokens.rounding.normal
        color: Colours.tPalette.m3surfaceContainer
        implicitHeight: cardCol.implicitHeight + Tokens.padding.normal * 2

        ColumnLayout {
            id: cardCol

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Tokens.padding.normal
            spacing: Tokens.spacing.small
        }
    }

    component IconButton: StyledRect {
        id: ib

        property alias icon: ibIcon.text
        property bool active

        signal clicked

        implicitWidth: implicitHeight
        implicitHeight: ibIcon.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        color: ib.active ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh

        StateLayer {
            radius: ib.radius
            color: ib.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            onClicked: ib.clicked()
        }

        MaterialIcon {
            id: ibIcon

            anchors.centerIn: parent
            color: ib.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
        }
    }

    component VolumeRow: RowLayout {
        id: vr

        property alias icon: vrBtn.icon
        property bool muted
        property real value
        property real max: 1

        signal moved(real v)
        signal toggle

        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        IconButton {
            id: vrBtn

            active: vr.muted
            onClicked: vr.toggle()
        }

        // Drag-only: no wheel wrapper, so mouse scroll doesn't change the volume.
        StyledSlider {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: Tokens.padding.normal * 3

            from: 0
            to: vr.max
            value: vr.value
            onMoved: vr.moved(value)

            Behavior on value {
                Anim {}
            }
        }

        StyledText {
            Layout.preferredWidth: Tokens.font.size.normal * 3
            horizontalAlignment: Text.AlignRight
            text: `${Math.round(vr.value * 100)}%`
            color: Colours.palette.m3onSurfaceVariant
        }
    }

    component DeviceRow: StyledRect {
        id: dr

        property string label
        property bool selected

        signal clicked

        Layout.fillWidth: true
        implicitHeight: drRow.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.small
        color: dr.selected ? Colours.palette.m3secondaryContainer : "transparent"

        StateLayer {
            radius: dr.radius
            color: dr.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            onClicked: dr.clicked()
        }

        RowLayout {
            id: drRow

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.small
            anchors.rightMargin: Tokens.padding.small
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: dr.selected ? "radio_button_checked" : "radio_button_unchecked"
                color: dr.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: dr.label
                elide: Text.ElideRight
                color: dr.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            }
        }
    }

    component SectionHeader: StyledRect {
        id: sh

        property string title
        property bool expanded

        signal toggled

        Layout.fillWidth: true
        implicitHeight: shRow.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.small
        color: "transparent"

        StateLayer {
            radius: sh.radius
            onClicked: sh.toggled()
        }

        RowLayout {
            id: shRow

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "expand_more"
                rotation: sh.expanded ? 0 : -90
                color: Colours.palette.m3onSurfaceVariant

                Behavior on rotation {
                    Anim {}
                }
            }

            StyledText {
                text: sh.title
                font.weight: 500
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
