pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import "../../services/ephemera/Markdown.js" as Markdown

// Renders a chat message as a vertical stack of markdown-text + code-block segments. The SAME
// renderer is used while streaming and after finalizing — incomplete code fences are auto-closed so
// a code block shows as soon as it opens, and nothing re-flows or swaps when the message completes.
//
// Segments are diffed into a ListModel in place (changed roles updated, new ones appended, extras
// trimmed) so a growing message never destroys/recreates delegates — no churn, no transient null
// modelData, no leaks. Errors bypass markdown and show the raw text escaped.
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

    // Balance an odd trailing code fence so a mid-stream ``` renders as a block immediately.
    function autoClose(text: string): string {
        const fences = (text.match(/```/g) || []).length;
        return fences % 2 === 1 ? text + "\n```" : text;
    }

    // Pure: split markdown into [{ kind: "text"|"code", body, lang }]. Always emits a leading text
    // segment (possibly empty — the delegate hides empties) so indexing stays stable across rebuilds.
    function computeSegments(text: string): var {
        const out = [];
        const lines = (text || "").split("\n");
        let inCode = false;
        let buf = [];
        let lang = "";
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (/^\s*```/.test(line)) {
                if (!inCode) {
                    out.push({
                        kind: "text",
                        body: buf.join("\n"),
                        lang: ""
                    });
                    buf = [];
                    inCode = true;
                    lang = line.replace(/^\s*```/, "").trim();
                } else {
                    out.push({
                        kind: "code",
                        body: buf.join("\n"),
                        lang: lang
                    });
                    buf = [];
                    inCode = false;
                    lang = "";
                }
            } else {
                buf.push(line);
            }
        }
        out.push({
            kind: inCode ? "code" : "text",
            body: buf.join("\n"),
            lang: inCode ? lang : ""
        });
        return out;
    }

    // Diff computed segments into segModel in place — update changed roles, append new, trim extras.
    function rebuild(): void {
        const segs = computeSegments(autoClose(content));
        const n = segs.length;
        for (let i = 0; i < n; i++) {
            const s = segs[i];
            if (i < segModel.count) {
                const cur = segModel.get(i);
                if (cur.kind !== s.kind || cur.body !== s.body || cur.lang !== s.lang)
                    segModel.set(i, s);
            } else {
                segModel.append(s);
            }
        }
        while (segModel.count > n)
            segModel.remove(segModel.count - 1);
    }

    onContentChanged: if (!isError)
        rebuild()
    Component.onCompleted: if (!isError)
        rebuild()

    ListModel {
        id: segModel
    }

    // Error: raw message as escaped text, no markdown.
    TextEdit {
        visible: root.isError
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
        text: root.isError ? Markdown.escapeHtml(root.content) : ""
    }

    Repeater {
        model: root.isError ? null : segModel

        delegate: Item {
            id: seg

            required property string kind
            required property string body
            required property string lang
            readonly property bool isCode: kind === "code"

            width: root.width
            implicitHeight: isCode ? codeView.implicitHeight : textView.implicitHeight
            height: implicitHeight
            // Hide empty text segments (e.g. the leading one before a code block) so they take no space.
            visible: isCode || body.length > 0

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
                text: seg.isCode ? "" : Markdown.markdownToHtml(seg.body, root.mdColours)
            }

            StyledRect {
                id: codeView

                visible: seg.isCode
                width: parent.width
                // A Rectangle does NOT auto-size from implicitHeight (unlike TextEdit), so without
                // this the whole code card collapses to 0 height and renders invisible.
                implicitHeight: codeCol.implicitHeight + Tokens.padding.normal * 2
                height: implicitHeight
                radius: Tokens.rounding.normal
                color: Colours.palette.m3surfaceContainerHighest

                // Outline so the block always reads as a distinct code card, whatever the bubble bg.
                border.width: 1
                border.color: Colours.palette.m3outlineVariant

                Column {
                    id: codeCol

                    x: Tokens.padding.normal
                    y: Tokens.padding.normal
                    width: parent.width - Tokens.padding.normal * 2
                    spacing: Tokens.spacing.small

                    // Header: language label (left) + per-block copy button (top-right).
                    Item {
                        width: parent.width
                        // Plain Item needs an explicit height inside the Column (no auto-size).
                        implicitHeight: Math.max(langLabel.implicitHeight, copyBtn.implicitHeight)
                        height: implicitHeight

                        StyledText {
                            id: langLabel

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: seg.lang || "code"
                            color: Colours.palette.m3onSurfaceVariant
                            font.pointSize: Tokens.font.size.small
                            font.family: Tokens.font.family.mono
                        }

                        CopyButton {
                            id: copyBtn

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            textToCopy: seg.body
                        }
                    }

                    TextEdit {
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                        text: seg.body
                        color: Colours.palette.m3onSurface
                        selectionColor: Colours.palette.m3primary
                        selectedTextColor: Colours.palette.m3onPrimary
                        font.family: Tokens.font.family.mono
                        font.pointSize: Tokens.font.size.small
                    }
                }
            }
        }
    }
}
