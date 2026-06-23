pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Clipboard history backed by cliphist (Wayland-native, via wl-clipboard).
// Entries are plain JS objects ({ id, preview, isImage }) to avoid QObject
// lifecycle issues with the launcher's recycling list view.
Singleton {
    id: root

    // Prefix that switches the launcher into clipboard mode
    readonly property string prefix: ":"

    // [{ id: string, preview: string, isImage: bool }], most-recent first
    property var entries: []

    function query(search: string): var {
        const s = (search.startsWith(prefix) ? search.slice(prefix.length) : search).trim().toLowerCase();
        return s ? entries.filter(e => e.preview.toLowerCase().includes(s)) : entries;
    }

    function reload(): void {
        listProc.running = true;
    }

    // Copy a history entry back to the live clipboard (cliphist decode -> wl-copy)
    function copy(entry: var): void {
        if (entry && entry.id)
            Quickshell.execDetached(["sh", "-c", `cliphist decode ${entry.id} | wl-copy`]);
    }

    // Copy arbitrary text to the Wayland clipboard (passed as argv, so no shell quoting issues).
    function copyText(text: string): void {
        if (text.length > 0)
            Quickshell.execDetached(["wl-copy", "--", text]);
    }

    // Remove an entry from history
    function remove(entry: var): void {
        if (entry && entry.id) {
            Quickshell.execDetached(["sh", "-c", `cliphist decode ${entry.id} | cliphist delete`]);
            reload();
        }
    }

    // Wipe the entire clipboard history
    function clearAll(): void {
        wipeProc.running = true;
    }

    // Ensure the wl-paste -> cliphist watchers run (text + images), once per session.
    Component.onCompleted: {
        Quickshell.execDetached(["sh", "-c", 'f="${XDG_RUNTIME_DIR:-/tmp}/caelestia-cliphist.pid"; if [ -e "$f" ] && kill -0 "$(cat "$f" 2>/dev/null)" 2>/dev/null; then exit 0; fi; wl-paste --type text --watch cliphist store & echo $! > "$f"; wl-paste --type image --watch cliphist store &']);
        reload();
    }

    Process {
        id: wipeProc

        command: ["cliphist", "wipe"]
        onExited: root.reload()
    }

    Process {
        id: listProc

        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    if (!line)
                        continue;
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    const preview = line.slice(tab + 1);
                    out.push({
                        id: line.slice(0, tab),
                        preview,
                        isImage: /^\[\[ binary data .*\b(png|jpe?g|gif|bmp|webp|tiff?|ico|svg)\b/i.test(preview)
                    });
                }
                root.entries = out;
            }
        }
    }
}
