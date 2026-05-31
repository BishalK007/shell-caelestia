pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// XWayland / X11 RandR primary-output control. There's no reactive signal for an external
// `xrandr --primary` change without polling, so instead of a poll we re-query on demand
// (callers refresh() when the utilities panel pops up). Used to pick the primary display for
// legacy Xrender/XWayland apps.
Singleton {
    id: root

    // [{ name, primary }] for connected outputs only.
    property var outputs: []
    property string primary: ""
    readonly property bool busy: queryProc.running

    function refresh(): void {
        if (!queryProc.running)
            queryProc.running = true;
    }

    function setPrimary(name: string): void {
        if (!name || name === root.primary)
            return;
        setProc.command = ["xrandr", "--output", name, "--primary"];
        setProc.running = true;
    }

    Process {
        id: queryProc

        command: ["xrandr", "--query"]

        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                let prim = "";
                for (const line of text.split("\n")) {
                    // Output header lines start at column 0; mode lines are indented.
                    if (!line.length || line[0] === " " || line[0] === "\t")
                        continue;
                    const m = line.match(/^(\S+)\s+(connected|disconnected)\b(.*)$/);
                    if (!m || m[2] !== "connected")
                        continue;
                    const isPrimary = /\bprimary\b/.test(m[3]);
                    out.push({
                        name: m[1],
                        primary: isPrimary
                    });
                    if (isPrimary)
                        prim = m[1];
                }
                root.outputs = out;
                root.primary = prim;
            }
        }
    }

    Process {
        id: setProc

        // Re-query after applying so the pill reflects the new primary.
        onExited: root.refresh()
    }
}
