pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils
import "ephemera"
import "ephemera/Providers.js" as Providers

// Ephemera AI chat (ported core from github.com/nicolasgarcia214/Ephemera).
// Native-core: reuses Ephemera's curl/SSE streaming (Streaming.qml + the JS libs) and Anthropic
// request builder, driven by a caelestia-native UI. Phase 1 = Anthropic/Claude Haiku.
Singleton {
    id: root

    // ── Provider config ──
    property string provider: "anthropic"
    property string model: "claude-haiku-4-5"
    // Fetched live from the Anthropic API (GET /v1/models) and cached to disk — never a static list.
    property var availableModels: []
    property bool modelsLoading: false

    function setModel(m: string): void {
        model = m;
    }

    // Secure fetch: url + key go through a curl config on stdin (-K -), never argv/proc.
    function fetchModels(): void {
        if (!hasKey || modelsProc.running)
            return;
        modelsLoading = true;
        modelsProc._cfg = `url = "https://api.anthropic.com/v1/models?limit=1000"\nheader = "x-api-key: ${apiKey}"\nheader = "anthropic-version: 2023-06-01"\n`;
        modelsProc.command = ["curl", "-K", "-", "-sS", "--max-time", "15"];
        modelsProc.stdinEnabled = true;
        modelsProc.running = true;
    }

    onHasKeyChanged: if (hasKey)
        fetchModels()

    // ── Image attachments (Claude vision) — multiple images ──
    property var attachments: []   // [{ path, data, type }]; data (base64) filled async
    readonly property bool hasAttachment: attachments.length > 0
    readonly property bool attaching: attachments.some(a => a.data === "")
    property int _attachIdx: -1

    function attachImage(path: string, type: string): void {
        const p = ("" + path).replace(/^file:\/\//, "");
        const a = attachments.slice();
        a.push({
            path: p,
            type: type || _mediaType(p),
            data: ""
        });
        attachments = a;
        _processAttachQueue();
    }

    function removeAttachment(i: int): void {
        const a = attachments.slice();
        a.splice(i, 1);
        attachments = a;
    }

    function clearAttachments(): void {
        attachments = [];
    }

    // Encode pending attachments to base64 one at a time (single shared Process).
    function _processAttachQueue(): void {
        if (attachProc.running)
            return;
        for (let i = 0; i < attachments.length; i++) {
            if (attachments[i].data === "") {
                _attachIdx = i;
                attachProc.command = ["base64", "-w0", attachments[i].path];
                attachProc.running = true;
                return;
            }
        }
    }

    function _mediaType(p: string): string {
        const ext = ("" + p).split(".").pop().toLowerCase();
        if (ext === "png")
            return "image/png";
        if (ext === "gif")
            return "image/gif";
        if (ext === "webp")
            return "image/webp";
        return "image/jpeg";
    }

    function pasteImage(): void {
        if (!pasteProc.running)
            pasteProc.running = true;
    }
    property real temperature: 1
    property int maxTokens: 4096
    property int timeout: 120
    property string systemPrompt: ""

    // ── UI state ──
    property bool panelVisible: false
    readonly property bool streaming: streamer.isStreaming

    // ── API key resolution (Phase 1: state file then env; keyring/secret-tool comes in Phase 2) ──
    property string _fileKey: ""
    readonly property string apiKey: _fileKey || Quickshell.env("ANTHROPIC_API_KEY") || ""
    readonly property bool hasKey: apiKey.length > 0

    // ── Conversation ──
    readonly property alias messages: messagesModel
    property int _assistantIdx: -1

    ListModel {
        id: messagesModel
    }

    function toggle(): void {
        panelVisible = !panelVisible;
    }

    function clear(): void {
        if (streamer.isStreaming)
            streamer.cancel();
        messagesModel.clear();
        _assistantIdx = -1;
    }

    function cancel(): void {
        if (streamer.isStreaming)
            streamer.cancel();
    }

    function send(text: string): void {
        const t = (text || "").trim();
        const imgs = attachments.filter(a => a.data && a.data.length > 0);
        if ((!t && imgs.length === 0) || streamer.isStreaming)
            return;

        const imagesJson = imgs.length > 0 ? JSON.stringify(imgs) : "";
        clearAttachments();

        messagesModel.append({
            role: "user",
            content: t,
            thinking: "",
            streaming: false,
            error: false,
            imagesJson: imagesJson
        });

        if (!root.hasKey) {
            messagesModel.append({
                role: "assistant",
                content: "No Anthropic API key found.\nSet ANTHROPIC_API_KEY, or store it in " + Paths.state + "/ephemera-keys.json as {\"anthropic\": \"sk-...\"}.",
                thinking: "",
                streaming: false,
                error: true,
                imagesJson: ""
            });
            return;
        }

        // Build the conversation context from existing turns (incl. the user message just added).
        // Messages with attached images use Anthropic's array content (image blocks + text block).
        const convo = [];
        if (root.systemPrompt)
            convo.push({
                role: "system",
                content: root.systemPrompt
            });
        for (let i = 0; i < messagesModel.count; i++) {
            const m = messagesModel.get(i);
            if (m.error)
                continue;
            let mImgs = [];
            try {
                mImgs = m.imagesJson ? JSON.parse(m.imagesJson) : [];
            } catch (e) {}
            if (mImgs.length > 0) {
                const blocks = mImgs.map(im => ({
                            type: "image",
                            source: {
                                type: "base64",
                                media_type: im.type,
                                data: im.data
                            }
                        }));
                if (m.content && m.content.length > 0)
                    blocks.push({
                        type: "text",
                        text: m.content
                    });
                convo.push({
                    role: m.role,
                    content: blocks
                });
            } else {
                convo.push({
                    role: m.role,
                    content: m.content
                });
            }
        }

        // Assistant placeholder that the stream fills in.
        messagesModel.append({
            role: "assistant",
            content: "",
            thinking: "",
            streaming: true,
            error: false,
            imagesJson: ""
        });
        root._assistantIdx = messagesModel.count - 1;

        const payload = {
            baseUrl: "https://api.anthropic.com",
            model: root.model,
            messages: convo,
            max_tokens: root.maxTokens,
            temperature: root.temperature,
            thinkingEnabled: false,
            timeout: root.timeout,
            stream: true
        };

        const curlResult = Providers.buildCurlCommand("anthropic", payload, root.apiKey);
        if (!curlResult) {
            root._setAssistant("Failed to build request (missing/invalid API key).", true);
            root._assistantIdx = -1;
            return;
        }

        streamer.provider = "anthropic";
        streamer.beginStream("eph" + Date.now(), 0);
        streamer.launchCurl(curlResult, JSON.stringify(payload));
    }

    function _appendAssistant(delta, isThinking): void {
        if (_assistantIdx < 0 || _assistantIdx >= messagesModel.count)
            return;
        const m = messagesModel.get(_assistantIdx);
        if (isThinking)
            messagesModel.setProperty(_assistantIdx, "thinking", (m.thinking || "") + delta);
        else
            messagesModel.setProperty(_assistantIdx, "content", (m.content || "") + delta);
    }

    function _setAssistant(textVal, isError): void {
        if (_assistantIdx < 0 || _assistantIdx >= messagesModel.count)
            return;
        messagesModel.setProperty(_assistantIdx, "content", textVal);
        messagesModel.setProperty(_assistantIdx, "streaming", false);
        messagesModel.setProperty(_assistantIdx, "error", isError);
    }

    function _finishAssistant(): void {
        if (_assistantIdx < 0 || _assistantIdx >= messagesModel.count)
            return;
        messagesModel.setProperty(_assistantIdx, "streaming", false);
        _assistantIdx = -1;
    }

    Connections {
        target: streamer

        function onStreamContentUpdated(streamId, delta) {
            root._appendAssistant(delta, false);
        }

        function onStreamThinkingUpdated(streamId, delta) {
            root._appendAssistant(delta, true);
        }

        function onStreamFinalized(streamId, stats) {
            root._finishAssistant();
        }

        function onStreamCancelled(streamId, stats) {
            root._finishAssistant();
        }

        function onStreamError(streamId, message) {
            root._setAssistant(message, true);
            root._assistantIdx = -1;
        }
    }

    Streaming {
        id: streamer
    }

    // Phase-1 key source. JSON: { "anthropic": "sk-ant-..." }. Not committed; lives in user state.
    FileView {
        id: keyFile

        path: `${Paths.state}/ephemera-keys.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text());
                root._fileKey = c[root.provider] || c.anthropic || "";
            } catch (e) {}
        }
    }

    Process {
        id: modelsProc

        property string _cfg: ""

        stdinEnabled: true
        onRunningChanged: {
            if (running && _cfg) {
                write(_cfg);
                stdinEnabled = false;
                _cfg = "";
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                root.modelsLoading = false;
                try {
                    const r = JSON.parse(text);
                    if (Array.isArray(r.data) && r.data.length > 0) {
                        root.availableModels = r.data.map(m => m.id);
                        modelsCache.setText(JSON.stringify(root.availableModels));
                    }
                } catch (e) {}
            }
        }
    }

    // Cached model list (shown instantly on next launch; refreshed live when the key is present).
    FileView {
        id: modelsCache

        path: `${Paths.cache}/ephemera-models.json`
        printErrors: false
        onLoaded: {
            try {
                const c = JSON.parse(text());
                if (Array.isArray(c) && c.length > 0 && root.availableModels.length === 0)
                    root.availableModels = c;
            } catch (e) {}
        }
    }

    // base64-encode pending attachments (one at a time) for the API request.
    Process {
        id: attachProc

        stdout: StdioCollector {
            onStreamFinished: {
                if (root._attachIdx >= 0 && root._attachIdx < root.attachments.length) {
                    const a = root.attachments.slice();
                    a[root._attachIdx] = {
                        path: a[root._attachIdx].path,
                        type: a[root._attachIdx].type,
                        data: text.trim()
                    };
                    root.attachments = a;
                }
                root._attachIdx = -1;
                root._processAttachQueue();
            }
        }
    }

    // Paste an image from the clipboard: save the first image/* type to a temp file, then attach it.
    Process {
        id: pasteProc

        command: ["sh", "-c", "ts=$(wl-paste --list-types 2>/dev/null); for t in image/png image/jpeg image/webp image/gif; do if printf '%s\\n' \"$ts\" | grep -qx \"$t\"; then f=$(mktemp --suffix=.${t#image/}); wl-paste --type \"$t\" > \"$f\" 2>/dev/null && printf '%s|%s' \"$f\" \"$t\"; exit 0; fi; done"]

        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim();
                const sep = out.indexOf("|");
                if (sep > 0)
                    root.attachImage(out.slice(0, sep), out.slice(sep + 1));
            }
        }
    }

    IpcHandler {
        function toggle(): void {
            root.toggle();
        }

        function clear(): void {
            root.clear();
        }

        target: "ephemera"
    }
}
