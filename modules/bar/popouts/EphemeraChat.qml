pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.containers
import qs.components.effects
import qs.components.filedialog
import qs.services
import qs.utils
import qs.modules.ephemera

// Ephemera AI chat as a bar popout (connected to the bar, click-triggered + persistent).
Item {
    id: root

    required property PopoutState popouts
    property bool picking: false

    implicitWidth: 480
    implicitHeight: Math.round(((QsWindow.window as QsWindow)?.screen?.height ?? 1000) * 0.82)

    // Focus the composer whenever the chat popout becomes the active one.
    Connections {
        target: root.popouts

        function onCurrentNameChanged(): void {
            if (root.popouts.currentName === "ephemera")
                Qt.callLater(() => input.forceActiveFocus());
        }
    }

    // Loaded lazily once it's already the current popout (e.g. opened via Super+A), so focus here.
    Component.onCompleted: if (root.popouts.currentName === "ephemera")
        Qt.callLater(() => input.forceActiveFocus())

    focus: root.popouts.currentName === "ephemera"
    Keys.onEscapePressed: root.popouts.hasCurrent = false

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.normal

        // ── Header ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                text: qsTr("Ephemera")
                font.weight: 500
                font.pointSize: Tokens.font.size.large
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: modelRow.implicitHeight + Tokens.padding.small
                radius: Tokens.rounding.full
                color: modelState.containsMouse ? Colours.palette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainer

                StateLayer {
                    id: modelState

                    radius: parent.radius
                    onClicked: modelMenu.open = !modelMenu.open
                }

                RowLayout {
                    id: modelRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.small
                    anchors.rightMargin: Tokens.padding.smaller
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Ephemera.modelsLoading && Ephemera.availableModels.length === 0 ? qsTr("Loading models…") : Ephemera.model
                        elide: Text.ElideRight
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Tokens.font.size.small
                    }

                    MaterialIcon {
                        text: "arrow_drop_down"
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }

            IconButton {
                type: IconButton.Text
                icon: "edit_square"
                onClicked: Ephemera.clear()
            }

            IconButton {
                type: IconButton.Text
                icon: "close"
                onClicked: root.popouts.hasCurrent = false
            }
        }

        // ── Messages ──
        StyledListView {
            id: list

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Tokens.spacing.normal
            model: Ephemera.messages

            // Stick to the bottom only while the user is already there, so streaming tokens don't
            // yank the view down when they've scrolled up to read. A new message re-sticks + jumps.
            property bool stickToBottom: true
            onCountChanged: {
                stickToBottom = true;
                Qt.callLater(positionViewAtEnd);
            }
            onContentHeightChanged: if (stickToBottom)
                positionViewAtEnd()
            onMovementEnded: stickToBottom = atYEnd

            delegate: Item {
                id: msg

                required property string role
                required property string content
                required property bool streaming
                required property bool error
                required property string imagesJson

                readonly property bool isUser: role === "user"

                width: ListView.view.width
                implicitHeight: bubble.implicitHeight

                StyledRect {
                    id: bubble

                    anchors.left: msg.isUser ? undefined : parent.left
                    anchors.right: msg.isUser ? parent.right : undefined
                    width: msg.isUser ? parent.width * 0.8 : parent.width
                    implicitHeight: body.implicitHeight + Tokens.padding.normal * 2

                    radius: Tokens.rounding.normal
                    color: msg.error ? Colours.palette.m3errorContainer : msg.isUser ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainer

                    ColumnLayout {
                        id: body

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.padding.normal
                        spacing: Tokens.spacing.smaller

                        ListView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: visible ? 160 : 0
                            visible: msg.imagesJson.length > 2
                            orientation: ListView.Horizontal
                            spacing: Tokens.spacing.small
                            clip: true
                            model: {
                                try {
                                    return JSON.parse(msg.imagesJson || "[]");
                                } catch (e) {
                                    return [];
                                }
                            }

                            delegate: StyledClippingRect {
                                required property var modelData

                                height: 160
                                width: img.implicitWidth * (160 / Math.max(1, img.implicitHeight))
                                radius: Tokens.rounding.small
                                color: Colours.palette.m3surfaceContainerHighest

                                Image {
                                    id: img

                                    anchors.fill: parent
                                    source: "file://" + parent.modelData.path
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                            }
                        }

                        MessageContent {
                            Layout.fillWidth: true
                            visible: msg.content.length > 0
                            content: msg.content
                            streaming: msg.streaming
                            isError: msg.error
                            textColour: msg.error ? Colours.palette.m3onErrorContainer : msg.isUser ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: msg.streaming && msg.content.length === 0
                            text: qsTr("Thinking…")
                            color: Colours.palette.m3onSurfaceVariant
                            font.pointSize: Tokens.font.size.small
                        }

                        // Copy the whole message (raw markdown — text + code together), since a mouse
                        // selection can't span the separate text/code TextEdits within a message.
                        RowLayout {
                            Layout.fillWidth: true
                            visible: msg.content.length > 0 && !msg.streaming && !msg.error
                            spacing: 0

                            Item {
                                Layout.fillWidth: true
                                visible: msg.isUser
                            }

                            CopyButton {
                                textToCopy: msg.content
                                iconSize: Tokens.font.size.small
                            }

                            Item {
                                Layout.fillWidth: true
                                visible: !msg.isUser
                            }
                        }
                    }
                }
            }
        }

        // ── Composer ──
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: composerCol.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: composerCol

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.normal
                anchors.rightMargin: Tokens.padding.smaller
                spacing: Tokens.spacing.small

                // Attached-image previews (horizontal scroll)
                ListView {
                    visible: Ephemera.attachments.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? 60 : 0
                    Layout.topMargin: visible ? Tokens.padding.smaller : 0
                    orientation: ListView.Horizontal
                    spacing: Tokens.spacing.small
                    clip: true
                    model: Ephemera.attachments

                    delegate: Item {
                        id: att

                        required property var modelData
                        required property int index

                        width: 56
                        height: 56

                        StyledClippingRect {
                            anchors.fill: parent
                            radius: Tokens.rounding.small
                            color: Colours.palette.m3surfaceContainerHighest

                            Image {
                                anchors.fill: parent
                                source: "file://" + att.modelData.path
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }

                        IconButton {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            type: IconButton.Text
                            icon: "close"
                            font.pointSize: Tokens.font.size.small
                            onClicked: Ephemera.removeAttachment(att.index)
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    IconButton {
                        type: IconButton.Text
                        icon: "add_photo_alternate"
                        onClicked: root.picking = true
                    }

                    StyledTextField {
                        id: input

                        Layout.fillWidth: true
                        background: null
                        placeholderText: qsTr("Ask Claude…")
                        Keys.onPressed: event => {
                            // Ctrl+V also tries to attach a clipboard image (text paste still proceeds).
                            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V)
                                Ephemera.pasteImage();
                        }
                        Keys.onEscapePressed: root.popouts.hasCurrent = false
                        onAccepted: {
                            Ephemera.send(text);
                            text = "";
                        }
                    }

                    IconButton {
                        icon: Ephemera.streaming ? "stop" : "send"
                        enabled: Ephemera.streaming || input.text.trim().length > 0 || Ephemera.hasAttachment
                        onClicked: {
                            if (Ephemera.streaming) {
                                Ephemera.cancel();
                            } else {
                                Ephemera.send(input.text);
                                input.text = "";
                            }
                        }
                    }
                }
            }
        }
    }

    // In-panel image browser — overlays the chat while picking (no focus-stealing window).
    FilePicker {
        anchors.fill: parent
        anchors.margins: Tokens.padding.normal
        visible: root.picking
        onPicked: path => {
            Ephemera.attachImage(path, "");
            root.picking = false;
        }
        onCloseRequested: root.picking = false
    }

    // ── Model dropdown ──
    StyledRect {
        id: modelMenu

        property bool open: false

        visible: opacity > 0
        opacity: open ? 1 : 0
        z: 10
        x: 0
        y: Tokens.font.size.large * 2.4
        width: Math.min(root.width, 300)
        implicitHeight: menuList.height + Tokens.padding.small * 2
        radius: Tokens.rounding.normal
        color: Colours.palette.m3surfaceContainerHigh

        Behavior on opacity {
            Anim {}
        }

        Elevation {
            anchors.fill: parent
            radius: parent.radius
            z: -1
            level: 3
        }

        StyledListView {
            id: menuList

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.small
            height: Math.min(contentHeight, 320)
            clip: true
            model: Ephemera.availableModels

            delegate: StyledRect {
                id: modelItem

                required property string modelData

                width: menuList.width
                implicitHeight: modelLabel.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.small
                color: modelData === Ephemera.model ? Colours.palette.m3secondaryContainer : "transparent"

                StateLayer {
                    radius: parent.radius
                    onClicked: {
                        Ephemera.setModel(modelItem.modelData);
                        modelMenu.open = false;
                    }
                }

                StyledText {
                    id: modelLabel

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.normal
                    anchors.rightMargin: Tokens.padding.normal
                    text: modelItem.modelData
                    elide: Text.ElideRight
                    color: modelItem.modelData === Ephemera.model ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    font.pointSize: Tokens.font.size.small
                }
            }
        }
    }
}
