pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.components.controls
import qs.services
import "../../services/ephemera/Markdown.js" as Markdown

// Renders a chat message. While streaming (or on errors) it shows ONE rich-text view, re-rendered
// in place with any unterminated code fence auto-closed — avoiding the flicker/overlap of
// re-segmenting incomplete markdown every token. Once finalized it splits into selectable markdown
// text + monospace code boxes (with a copy button). Delegates bind modelData directly (a Loader +
// seg indirection left the code box blank), and it's a Column so child implicitHeights are honoured.
Column {
    id: root

    required property string content
    property bool streaming: false
    property bool isError: false
    property color textColour: Colours.palette.m3onSurface

    readonly property var mdColours: ({
            codeBg: String(Colours.palette.m3surfaceContainerHighest),
            inlineCodeBg: String(Colours.palette.m3surfaceContainerHighest),
            blockquoteBg: String(Colours.palette.m3surfaceContainerHigh),
            blockquoteBorder: String(Colours.palette.m3primary)
        })

    spacing: Tokens.spacing.small

    function autoClose(text: string): string {
        const fences = (text.match(/```/g) || []).length;
        return fences % 2 === 1 ? text + "\n```" : text;
    }

    function segments(text: string): var {
        const out = [];
        const lines = (text || "").split("\n");
        let inCode = false;
        let buf = [];
        let lang = "";
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (/^\s*```/.test(line)) {
                if (!inCode) {
                    if (buf.length > 0)
                        out.push({ type: "text", text: buf.join("\n"), lang: "" });
                    buf = [];
                    inCode = true;
                    lang = line.replace(/^\s*```/, "").trim();
                } else {
                    out.push({ type: "code", text: buf.join("\n"), lang: lang });
                    buf = [];
                    inCode = false;
                    lang = "";
                }
            } else {
                buf.push(line);
            }
        }
        if (inCode)
            out.push({ type: "code", text: buf.join("\n"), lang: lang });
        else if (buf.length > 0)
            out.push({ type: "text", text: buf.join("\n"), lang: "" });
        return out;
    }

    // Streaming / error: single in-place rich-text view (incomplete fences auto-closed).
    TextEdit {
        visible: root.streaming || root.isError
        width: root.width
        readOnly: true
        selectByMouse: true
        textFormat: TextEdit.RichText
        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
        color: root.textColour
        selectionColor: Colours.palette.m3primary
        selectedTextColor: Colours.palette.m3onPrimary
        font.family: Tokens.font.family.sans
        font.pointSize: Tokens.font.size.normal
        text: root.isError ? Markdown.escapeHtml(root.content) : Markdown.markdownToHtml(root.autoClose(root.content), root.mdColours)
    }

    // Finalized: selectable markdown + code boxes with copy buttons.
    Repeater {
        model: (root.streaming || root.isError) ? [] : root.segments(root.content)

        delegate: Item {
            id: seg

            required property var modelData
            readonly property bool isCode: modelData.type === "code"
            property bool copied: false

            width: root.width
            implicitHeight: isCode ? codeView.implicitHeight : textView.implicitHeight

            TextEdit {
                id: textView

                visible: !seg.isCode
                width: parent.width
                readOnly: true
                selectByMouse: true
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                color: root.textColour
                selectionColor: Colours.palette.m3primary
                selectedTextColor: Colours.palette.m3onPrimary
                font.family: Tokens.font.family.sans
                font.pointSize: Tokens.font.size.normal
                text: seg.isCode ? "" : Markdown.markdownToHtml(seg.modelData.text, root.mdColours)
            }

            StyledRect {
                id: codeView

                visible: seg.isCode
                width: parent.width
                implicitHeight: codeCol.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHighest

                Column {
                    id: codeCol

                    x: Tokens.padding.small
                    y: Tokens.padding.small
                    width: parent.width - Tokens.padding.small * 2
                    spacing: Tokens.spacing.smaller

                    Item {
                        width: parent.width
                        implicitHeight: Math.max(langLabel.implicitHeight, copyBtn.implicitHeight)

                        StyledText {
                            id: langLabel

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: seg.modelData.lang || "code"
                            color: Colours.palette.m3onSurfaceVariant
                            font.pointSize: Tokens.font.size.small
                            font.family: Tokens.font.family.mono
                        }

                        IconButton {
                            id: copyBtn

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            type: IconButton.Text
                            icon: seg.copied ? "check" : "content_copy"
                            font.pointSize: Tokens.font.size.normal
                            onClicked: {
                                Quickshell.execDetached(["wl-copy", "--", seg.modelData.text]);
                                seg.copied = true;
                                copyTimer.restart();
                            }
                        }
                    }

                    TextEdit {
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                        text: seg.modelData.text
                        color: Colours.palette.m3onSurface
                        selectionColor: Colours.palette.m3primary
                        selectedTextColor: Colours.palette.m3onPrimary
                        font.family: Tokens.font.family.mono
                        font.pointSize: Tokens.font.size.small
                    }
                }

                Timer {
                    id: copyTimer

                    interval: 1500
                    onTriggered: seg.copied = false
                }
            }
        }
    }
}
