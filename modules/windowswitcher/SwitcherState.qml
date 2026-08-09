pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

Scope {
    id: root

    required property var hiddenSpecials

    property var rows: []
    property var rail: []
    property string zone: "grid"
    property int rowIndex: 0
    property int colIndex: 0
    property int railIndex: 0

    // Right-drag session (owned by Content): while true, rebuild() is deferred
    // so the Repeater model is never replaced under an implicit mouse grab.
    property bool dragActive: false
    property bool rebuildPending: false

    // Captured once at open: Hyprland.activeToplevel goes NULL while our
    // surface holds exclusive keyboard focus (hyprland emits an empty
    // activewindow), so reorderWindow's focused-window rules read these.
    property string focusedAddrAtOpen: ""
    property int focusedWsAtOpen: -1

    onDragActiveChanged: {
        if (!dragActive && rebuildPending) {
            rebuildPending = false;
            rebuild();
        }
    }

    readonly property var selected: {
        const g = root.rows[root.rowIndex]?.windows?.[root.colIndex] ?? null;
        const r = root.rail[root.railIndex] ?? null;
        return root.zone === "grid" ? g : r;
    }

    // focusAddr is the committed window's address ("" on dismiss) — the window
    // root re-asserts it after teardown: dispatching focus while our surface
    // still holds EXCLUSIVE keyboard means hyprland's post-destroy refocus (and
    // follow_mouse=2's detached pointer state) can steal it back.
    signal closeRequested(string focusAddr)

    // Hyprland's default special workspace is named exactly "special" (no colon).
    function isSpecialName(name: string): bool {
        return name === "special" || name.startsWith("special:");
    }

    function toggleSpecial(name: string): void {
        const arg = name.startsWith("special:") ? name.slice(8) : "";
        Hypr.dispatch(arg ? `togglespecialworkspace ${arg}` : "togglespecialworkspace");
    }

    function rebuild(): void {
        if (root.dragActive) {
            root.rebuildPending = true;
            return;
        }

        // The selected toplevel may have just been destroyed (rebuild runs on
        // closewindow); reading properties of a dangling wrapper throws.
        let prevAddr = "";
        try {
            prevAddr = root.selected?.address ?? "";
        } catch (e) {}

        const newRows = [];
        for (const ws of Hypr.workspaces.values) {
            if (!ws || root.isSpecialName(ws.name ?? ""))
                continue;
            const wins = (ws.toplevels?.values ?? []).filter(t => t?.lastIpcObject?.mapped !== false);
            wins.sort((a, b) => {
                const aAt = a?.lastIpcObject?.at ?? [0, 0];
                const bAt = b?.lastIpcObject?.at ?? [0, 0];
                return ((aAt[0] ?? 0) - (bAt[0] ?? 0)) || ((aAt[1] ?? 0) - (bAt[1] ?? 0));
            });
            // EXISTING empty workspaces (persistent / currently viewed) get a
            // row too — an "empty" placeholder cell, selectable and a drop
            // target. wsId/monitor are plain scalars so nothing dangles.
            let wsMonitor = "";
            try {
                wsMonitor = ws.monitor?.name ?? "";
            } catch (e) {}
            newRows.push({
                ws,
                wsId: ws.id,
                monitor: wsMonitor,
                empty: wins.length === 0,
                windows: wins
            });
        }
        newRows.sort((a, b) => a.wsId - b.wsId);

        // Always exactly one synthetic empty row below the last workspace:
        // dropping a window there occupies it, and the next rebuild grows a
        // fresh one beneath (workspace ids auto-create on silent move).
        const maxId = newRows.reduce((m, r) => Math.max(m, r.wsId), 0);
        if (newRows.length === 0 || !newRows[newRows.length - 1].empty)
            newRows.push({
                ws: null,
                wsId: maxId + 1,
                monitor: "", // created on the focused monitor when used — no chip
                empty: true,
                windows: []
            });

        const newRail = Hypr.toplevels.values.filter(t => {
            const wsName = t?.workspace?.name ?? "";
            return root.isSpecialName(wsName) && !(root.hiddenSpecials ?? []).includes(wsName) && t?.lastIpcObject?.mapped !== false;
        });
        newRail.sort((a, b) => (a?.lastIpcObject?.focusHistoryID ?? Number.MAX_SAFE_INTEGER) - (b?.lastIpcObject?.focusHistoryID ?? Number.MAX_SAFE_INTEGER));

        root.rows = newRows;
        root.rail = newRail;

        // Selection repair: re-locate the previously selected toplevel by address
        if (prevAddr) {
            for (let r = 0; r < newRows.length; r++) {
                const c = newRows[r].windows.findIndex(t => t?.address === prevAddr);
                if (c >= 0) {
                    root.zone = "grid";
                    root.rowIndex = r;
                    root.colIndex = c;
                    return;
                }
            }
            const i = newRail.findIndex(t => t?.address === prevAddr);
            if (i >= 0) {
                root.zone = "rail";
                root.railIndex = i;
                return;
            }
        }

        // Gone (or nothing selected): clamp indices, possibly switch zone
        root.rowIndex = Math.max(0, Math.min(root.rowIndex, newRows.length - 1));
        root.colIndex = Math.max(0, Math.min(root.colIndex, (newRows[root.rowIndex]?.windows.length ?? 1) - 1));
        root.railIndex = Math.max(0, Math.min(root.railIndex, newRail.length - 1));

        if (root.zone === "grid" && newRows.length === 0 && newRail.length > 0)
            root.zone = "rail";
        else if (root.zone === "rail" && newRail.length === 0 && newRows.length > 0)
            root.zone = "grid";
    }

    function initSelection(): void {
        const active = Hyprland.activeToplevel;
        const vis = Hypr.focusedMonitor?.lastIpcObject?.specialWorkspace?.name ?? "";

        if (vis && !(root.hiddenSpecials ?? []).includes(vis) && active?.workspace?.name === vis) {
            const i = root.rail.findIndex(t => t?.address === active.address);
            if (i >= 0) {
                root.zone = "rail";
                root.railIndex = i;
                return;
            }
            const j = root.rail.findIndex(t => t?.workspace?.name === vis);
            if (j >= 0) {
                root.zone = "rail";
                root.railIndex = j;
                return;
            }
        }

        if (active) {
            for (let r = 0; r < root.rows.length; r++) {
                const c = root.rows[r].windows.findIndex(t => t?.address === active.address);
                if (c >= 0) {
                    root.zone = "grid";
                    root.rowIndex = r;
                    root.colIndex = c;
                    return;
                }
            }
        }

        // Grid window with the globally smallest focusHistoryID
        let bestR = -1;
        let bestC = 0;
        let bestId = Infinity;
        for (let r = 0; r < root.rows.length; r++) {
            const wins = root.rows[r].windows;
            for (let c = 0; c < wins.length; c++) {
                const id = wins[c]?.lastIpcObject?.focusHistoryID ?? Number.MAX_SAFE_INTEGER;
                if (id < bestId) {
                    bestId = id;
                    bestR = r;
                    bestC = c;
                }
            }
        }
        if (bestR >= 0) {
            root.zone = "grid";
            root.rowIndex = bestR;
            root.colIndex = bestC;
            return;
        }

        if (root.rail.length > 0) {
            root.zone = "rail";
            root.railIndex = 0;
        }
    }

    function landingCol(rowIdx: int): int {
        const wins = root.rows[rowIdx]?.windows;
        if (!wins || wins.length === 0)
            return 0;
        let best = 0;
        let bestId = Infinity;
        for (let i = 0; i < wins.length; i++) {
            // Reachable on dead wrappers mid-drag (rebuild deferred) — guard.
            let id = Number.MAX_SAFE_INTEGER;
            try {
                id = wins[i]?.lastIpcObject?.focusHistoryID ?? Number.MAX_SAFE_INTEGER;
            } catch (e) {}
            if (id < bestId) {
                bestId = id;
                best = i;
            }
        }
        return best;
    }

    function moveUp(): void {
        if (root.zone === "grid") {
            if (root.rows.length <= 1)
                return;
            root.rowIndex = (root.rowIndex - 1 + root.rows.length) % root.rows.length;
            root.colIndex = root.landingCol(root.rowIndex);
        } else {
            if (root.rail.length === 0)
                return;
            root.railIndex = (root.railIndex - 1 + root.rail.length) % root.rail.length;
        }
    }

    function moveDown(): void {
        if (root.zone === "grid") {
            if (root.rows.length <= 1)
                return;
            root.rowIndex = (root.rowIndex + 1) % root.rows.length;
            root.colIndex = root.landingCol(root.rowIndex);
        } else {
            if (root.rail.length === 0)
                return;
            root.railIndex = (root.railIndex + 1) % root.rail.length;
        }
    }

    function moveLeft(): void {
        if (root.zone === "grid") {
            root.colIndex = Math.max(0, root.colIndex - 1);
        } else if (root.rows.length > 0) {
            // Clamp the remembered grid position — rows may have shrunk while
            // we were in the rail (rebuild's repair early-returns there).
            root.rowIndex = Math.max(0, Math.min(root.rowIndex, root.rows.length - 1));
            root.colIndex = Math.max(0, Math.min(root.colIndex, (root.rows[root.rowIndex]?.windows.length ?? 1) - 1));
            root.zone = "grid";
        }
    }

    function moveRight(): void {
        if (root.zone !== "grid")
            return;
        const len = root.rows[root.rowIndex]?.windows.length ?? 0;
        if (root.colIndex >= len - 1) {
            if (root.rail.length === 0)
                return;
            // Enter the rail: prefer the cell of the visible special on the focused monitor
            const vis = Hypr.focusedMonitor?.lastIpcObject?.specialWorkspace?.name ?? "";
            let idx = Math.max(0, Math.min(root.railIndex, root.rail.length - 1));
            if (vis) {
                const i = root.rail.findIndex(t => {
                    try {
                        return t?.workspace?.name === vis;
                    } catch (e) {
                        return false;
                    }
                });
                if (i >= 0)
                    idx = i;
            }
            root.railIndex = idx;
            root.zone = "rail";
        } else {
            root.colIndex = Math.min(len - 1, root.colIndex + 1);
        }
    }

    // Wheel navigation: each forces the zone to match the pointer region.
    // Horizontal within the current row — CLAMPED, never overflows into the
    // rail (unlike moveRight(); keyboard D remains the way to enter the rail).
    function scrollColBy(delta: int): void {
        if (root.zone === "rail") {
            if (root.rows.length === 0)
                return;
            // Clamp the remembered grid position — rows may have shrunk while
            // we were in the rail (rebuild's repair early-returns there).
            root.rowIndex = Math.max(0, Math.min(root.rowIndex, root.rows.length - 1));
            root.colIndex = Math.max(0, Math.min(root.colIndex, (root.rows[root.rowIndex]?.windows.length ?? 1) - 1));
            root.zone = "grid";
        }
        const len = root.rows[root.rowIndex]?.windows.length ?? 0;
        if (len === 0)
            return;
        root.colIndex = Math.max(0, Math.min(len - 1, root.colIndex + delta));
    }

    // Vertical, CLAMPED at the first/last row (keyboard W/S keeps its wrap;
    // a wheel flick overshooting the end must not teleport back to row 1).
    function scrollRowBy(delta: int): void {
        if (root.zone === "rail") {
            if (root.rows.length === 0)
                return;
            root.rowIndex = Math.max(0, Math.min(root.rowIndex, root.rows.length - 1));
            root.colIndex = Math.max(0, Math.min(root.colIndex, (root.rows[root.rowIndex]?.windows.length ?? 1) - 1));
            root.zone = "grid";
        }
        if (root.rows.length <= 1)
            return;
        const next = Math.max(0, Math.min(root.rows.length - 1, root.rowIndex + delta));
        if (next === root.rowIndex)
            return;
        root.rowIndex = next;
        root.colIndex = root.landingCol(root.rowIndex);
    }

    // Rail scroll — WRAPS, for parity with keyboard rail nav and the grid wrap.
    function scrollRailBy(delta: int): void {
        if (root.rail.length === 0)
            return;
        root.zone = "rail";
        root.railIndex = ((root.railIndex + delta) % root.rail.length + root.rail.length) % root.rail.length;
    }

    // Reorder addr (plain string, NO 0x prefix) within/into workspace wsId so
    // it lands before the window currently DISPLAYED at insertIndex
    // (insertIndex === length = append). Live-verified dispatch semantics
    // (hyprland 0.56.2, scrolling layout): movetoworkspacesilent appends at the
    // strip end when the focused window is not on the destination; a scratch
    // "bounce" (silent move out + back) re-appends a window at the end, so
    // bouncing the out-of-place suffix in desired order yields the target
    // permutation with zero focus/visible-workspace changes.
    function reorderWindow(addr: string, wsId: int, insertIndex: int): void {
        if (!addr)
            return;

        // D = the target row's displayed order as plain address strings
        // (toplevel wrapper reads throw once the object dies — skip dead ones;
        // rows can hold dead wrappers for the whole drag). wsId on the row is
        // a plain scalar, safe to read.
        const row = root.rows.find(r => r?.wsId === wsId) ?? null;
        const D = [];
        for (const t of row?.windows ?? []) {
            try {
                const a = t?.address ?? "";
                if (a)
                    D.push(a);
            } catch (e) {}
        }

        const cur = D.indexOf(addr);
        const desired = D.slice();
        if (cur >= 0) {
            // Same-row: remove first, then adjust the slot for the removal.
            desired.splice(cur, 1);
            const adjusted = insertIndex > cur ? insertIndex - 1 : insertIndex;
            desired.splice(Math.max(0, Math.min(adjusted, desired.length)), 0, addr);
        } else {
            desired.splice(Math.max(0, Math.min(insertIndex, D.length)), 0, addr);
        }

        const batch = [];
        let current = D;
        if (cur < 0) {
            // Cross-row: the silent move appends at the strip end (verified:
            // no focus change, workspace stays hidden), so the post-move order
            // is D + [addr].
            batch.push(Hypr.dispatchRequest(`movetoworkspacesilent ${wsId},address:0x${addr}`));
            current = D.concat([addr]);
        }

        // Bounce suffix: the longest prefix of `desired` whose members already
        // sit in the same relative order in `current` stays put; every address
        // after it must be bounced (scratch + back = re-append at strip end).
        const pos = new Map();
        for (let i = 0; i < current.length; i++)
            pos.set(current[i], i);
        let keep = 0;
        let last = -1;
        while (keep < desired.length) {
            const p = pos.get(desired[keep]);
            if (p === undefined || p <= last)
                break;
            last = p;
            keep++;
        }

        // Hyprland.activeToplevel is NULL while our surface holds exclusive
        // keyboard focus (hyprland emits an empty activewindow) — use the
        // scalars captured at open instead.
        const focusedAddr = root.focusedAddrAtOpen;
        const focusedWs = root.focusedWsAtOpen;

        // On the focused window's workspace, kept elements sitting after the
        // focused column get displaced behind the re-inserted block (re-entries
        // land directly AFTER the focused column, not at the strip end) —
        // truncate the kept prefix at the focused window so EVERYTHING after it
        // is bounced (in reverse, below), which reproduces `desired` exactly
        // for all slots after the focused column.
        if (wsId === focusedWs) {
            const fi = desired.indexOf(focusedAddr);
            keep = fi >= 0 ? Math.min(keep, fi + 1) : 0;
        }

        // SCRATCH: an unused hidden workspace id above every existing one
        // (auto-created hidden on silent move, auto-destroyed when emptied).
        let maxId = 40;
        for (const w of Hypr.workspaces.values) {
            let id = 0;
            try {
                id = w?.id ?? 0;
            } catch (e) {}
            if (id > maxId)
                maxId = id;
        }
        const scratch = maxId + 17;

        const pairs = [];
        for (let i = keep; i < desired.length; i++) {
            const a = desired[i];
            // NEVER bounce the focused window — silently moving it would yank
            // the user's focus. Skip its pair; accept the approximate order.
            if (a === focusedAddr)
                continue;
            pairs.push([Hypr.dispatchRequest(`movetoworkspacesilent ${scratch},address:0x${a}`), Hypr.dispatchRequest(`movetoworkspacesilent ${wsId},address:0x${a}`)]);
        }

        // On the focused window's own workspace, each bounced window re-enters
        // directly AFTER the focused column (not at the strip end), successive
        // insertions each landing right behind it — emit the pairs in REVERSE
        // order to compensate. Slots before the focused column are unreachable
        // there; the resulting order is approximate by design.
        if (wsId === focusedWs)
            pairs.reverse();

        for (const pair of pairs) {
            batch.push(pair[0]);
            batch.push(pair[1]);
        }

        // Already in the desired order (or only the focused window would have
        // moved): nothing to dispatch.
        if (batch.length === 0)
            return;

        console.debug(`[windowswitcher] reorder batch: ${batch.join(" ; ")}`);
        Hypr.extras.batchMessage(batch);
    }

    function toggleZone(): void {
        if (root.zone === "grid") {
            if (root.rail.length > 0) {
                root.railIndex = Math.max(0, Math.min(root.railIndex, root.rail.length - 1));
                root.zone = "rail";
            }
        } else if (root.rows.length > 0) {
            root.rowIndex = Math.max(0, Math.min(root.rowIndex, root.rows.length - 1));
            root.colIndex = Math.max(0, Math.min(root.colIndex, (root.rows[root.rowIndex]?.windows.length ?? 1) - 1));
            root.zone = "grid";
        }
    }

    function pressDigit(n: int): void {
        if (root.rail.length === 0 || n > root.rail.length)
            return;
        if (root.zone === "rail" && root.railIndex === n - 1) {
            root.commit();
            return;
        }
        root.zone = "rail";
        root.railIndex = n - 1;
    }

    function commit(): void {
        // Empty workspace row: committing means "go to that (possibly not yet
        // created) workspace" — hyprland auto-creates it on switch.
        if (root.zone === "grid") {
            const row = root.rows[root.rowIndex] ?? null;
            if (row && row.empty) {
                Hypr.dispatch(`workspace ${row.wsId}`);
                root.closeRequested("");
                return;
            }
        }

        // Selected toplevel can be a dangling wrapper (window closed this frame);
        // property reads on it throw, and Enter must never leave the overlay stuck.
        let addr = "";
        let wsName = "";
        try {
            const t = root.selected;
            if (t) {
                addr = t.address ?? "";
                wsName = t.workspace?.name ?? "";
            }
        } catch (e) {}
        if (!addr) {
            root.dismiss();
            return;
        }

        if (root.zone === "grid") {
            const vis = Hypr.focusedMonitor?.lastIpcObject?.specialWorkspace?.name ?? "";
            if (vis)
                root.toggleSpecial(vis);
        } else {
            const shown = Hypr.monitors.values.some(m => m?.lastIpcObject?.specialWorkspace?.name === wsName);
            if (!shown && wsName)
                root.toggleSpecial(wsName);
        }
        Hypr.dispatch(`focuswindow address:0x${addr}`);

        root.closeRequested(addr);
    }

    function dismiss(): void {
        root.closeRequested("");
    }

    Component.onCompleted: {
        try {
            const t = Hyprland.activeToplevel;
            focusedAddrAtOpen = t?.address ?? "";
            focusedWsAtOpen = t?.workspace?.id ?? -1;
        } catch (e) {}
        if (!focusedAddrAtOpen) {
            // Exclusive focus may already have nulled activeToplevel — fall
            // back to the most-recently-focused toplevel.
            try {
                for (const t of Hypr.toplevels.values) {
                    if (t?.lastIpcObject?.focusHistoryID === 0) {
                        focusedAddrAtOpen = t?.address ?? "";
                        focusedWsAtOpen = t?.workspace?.id ?? -1;
                        break;
                    }
                }
            } catch (e) {}
        }
        rebuild();
        initSelection();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (["openwindow", "closewindow", "movewindow"].includes(event.name))
                Qt.callLater(root.rebuild);
        }
    }
}
