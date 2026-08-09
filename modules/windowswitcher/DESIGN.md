# Window Switcher — Design Spec

A fullscreen modal window switcher for the caelestia shell (Quickshell + Hyprland).
2D camera-centered map: **rows = workspaces, columns = windows within a workspace**,
plus a **right-side rail of special-workspace windows**. The selection never moves
on screen — the grid slides under a fixed, enlarged center slot.

## Mental model

```
      COLUMNS = window order within a workspace (spatial, x-sorted)
      ROWS    = non-empty regular workspaces (sorted by id, empties skipped)
      RAIL    = windows living on special:* workspaces (MRU order)

┌───────────────────────────────────────────────────────────────────────┐
│           ┌─────────┐  ┌─────────┐                    ┃ ① whatsapp ┃  │
│   ws 2    │  nvim   │  │ firefox │      (dimmed)      ┃ ② claude ● ┃  │
│           └─────────┘  └─────────┘                    ┃ ③ gemini   ┃  │
│           ┌────────┐ ╔═════════════╗ ┌─────────┐      ┃ ④ spotify  ┃  │
│   ws 3 ●  │spotify │ ║    kitty    ║ │ discord │      ┃ ⑤ slack    ┃  │
│           └────────┘ ║  (selected) ║ └─────────┘      ┗ rail (MRU) ┛  │
│           ┌─────────┐╚═════════════╝                                  │
│   ws 4    │  gimp   │                                                 │
│           └─────────┘                                                 │
└───────────────────────────────────────────────────────────────────────┘
```

- Center cell = current selection, scaled up (~1.45×). Immediate neighbors full
  opacity; everything further dimmed and slightly shrunk.
- Each grid row is horizontally positioned so its *selected column* sits in the
  center column slot (rows are staggered, like the sketch).
- All movement animates (grid slides, selection stays fixed in the middle).

## Data model

- **Rows**: every regular (non-special) workspace that has ≥1 window, sorted by
  workspace id ascending. Empty workspaces are skipped entirely.
- **Columns**: windows of that workspace sorted by spatial position:
  `lastIpcObject.at[0]` ascending, ties by `at[1]`. On a scrolling layout this
  is exactly the on-screen scroll order.
- **Rail**: all windows whose workspace name starts with `special:`, except
  those in the hidden list (default: `special:whispr`, `special:wisprflow`).
  Sorted by MRU: `lastIpcObject.focusHistoryID` ascending (0 = most recent).
  A dot badge marks windows of the special workspace currently visible on the
  focused monitor. Cells show number badges ①–⑨ matching current MRU order.
- **MRU landing**: when vertical navigation enters a row, the landing column is
  that row's most-recently-used window (min `focusHistoryID` within the row).
- Filter everywhere: only `mapped` clients (skip unmapped/hidden xwayland noise).
- Live updates: rebuild rows/rail on Hyprland openwindow/closewindow/movewindow
  events while open; preserve selection by window `address` across rebuilds
  (fallback: nearest column, then nearest row, then other zone).

## Selection & navigation

State: `zone` ("grid" | "rail"), `rowIndex`, `colIndex`, `railIndex`.
Grid position is remembered while in the rail, and vice versa.

| Key (any modifiers, incl. Alt+Shift held)   | In grid                                      | In rail                       |
| ------------------------------------------- | -------------------------------------------- | ----------------------------- |
| `A` / `←` / `H`                              | column left (clamp at 0)                     | leave rail → back to grid     |
| `D` / `→` / `L`                              | column right; **past last column → rail**    | no-op                         |
| `W` / `↑` / `K`                              | row up, **wraps** (skip if single row)       | rail up, **wraps**            |
| `S` / `↓` / `J`                              | row down, **wraps** (skip if single row)     | rail down, **wraps**          |
| `Tab` / `Shift+Tab`                          | jump to rail (remembered position)           | jump back to grid             |
| `1`–`9`                                      | select rail item N                           | same; **same digit again = commit** |
| `Enter`                                      | commit                                       | commit                        |
| `Esc`                                        | dismiss (no change)                          | dismiss                       |
| `Super` tap (press+release, no chord)        | commit                                       | commit                        |
| `Super+Tab`                                  | dismiss (it's the open/close toggle)         | dismiss                       |
| mouse hover                                  | select (with keyboard-nav guard)             | select (same guard)           |
| mouse click on cell                          | commit that cell                             | commit that cell              |
| mouse click on dim background                | dismiss                                      | dismiss                       |

Super-tap detection: on Meta press, set `superDown = true`, `superChorded = false`;
any other key press while `superDown` sets `superChorded = true`; on Meta release,
commit iff `!superChorded`. Tab arriving with Meta modifier = dismiss (and counts
as a chord).

Digit select-then-confirm: first press of digit N moves selection to rail item N
(entering the rail if needed); pressing the *same* digit while already selected
commits it. A different digit just moves selection.

## Opening

- Trigger: `CustomShortcut { name: "windowSwitcher" }` (toggle) + IPC handler
  `windowswitcher: toggle/open/close`.
- Hyprland bind: `bind = SUPER, Tab, global, caelestia:windowSwitcher`.
- Overlay appears on the **focused monitor only**, fullscreen, `WlrLayer.Overlay`,
  `WlrKeyboardFocus.Exclusive`, scrim-dimmed background (no compositor blur
  dependency in v1).
- Initial selection:
  - If the focused monitor has a visible special workspace and the focused
    window is on it (and it isn't hidden) → `zone = rail` at that window.
  - Otherwise → `zone = grid` at the currently focused window; if none, at the
    globally most-recent regular window.
- **Submap**: on open, dispatch `submap windowswitcher`; on close (any path,
  including component destruction), dispatch `submap reset`. The submap in
  hyprland.conf is intentionally empty (plus a panic-reset bind), so every key
  — including Alt+Shift+WASD muscle memory — falls through to the overlay's
  exclusive keyboard instead of triggering compositor binds:

  ```
  bind = SUPER, Tab, global, caelestia:windowSwitcher
  submap = windowswitcher
  bind = SUPER CTRL ALT, BackSpace, submap, reset   # panic hatch
  submap = reset
  ```

## Commit semantics

Let T = selected toplevel, M = focused monitor, S = special workspace currently
visible on M (may be none).

- **Grid cell**: if S exists → `togglespecialworkspace <S-short-name>` to hide it
  first. Then `focuswindow address:<T.address>`. Never move windows between
  monitors — if T is on another monitor's workspace, focus jumps there.
- **Rail cell**: let W = T's special workspace (`special:<name>`).
  - If S == W → just `focuswindow address:<T.address>`.
  - If S != W → `togglespecialworkspace <name>` (Hyprland replaces the visible
    special), then `focuswindow`.
- Then close the overlay (dismiss animation, `submap reset`).

## Cells

- Card: rounded rect, live thumbnail via `ScreencopyView { captureSource:
  toplevel.wayland; live: true }`, app icon + title label above/overlaid.
- Fallback when capture has no content: icon-centered card (app icon via
  DesktopEntries heuristic lookup from window class, `Quickshell.iconPath`
  fallback chain).
- Cell aspect ratio ≈ monitor aspect. Base size ~220×138 logical px, center
  scale ~1.45, off-center rows/cols dim to ~55% opacity, 0.9 scale.
- Workspace id label at the row's left edge; rail has a header ("special").

## Capture pipeline (hard-won facts, verified against sources + wire traces)

- Quickshell 0.3.0 captures toplevels ONLY via `hyprland-toplevel-export-v1`.
  Buffers are always full window resolution (the compositor dictates the size;
  `constraintSize` is client-side implicit-size scaling and inert when the item
  has an explicit size). Quality comes free; do not add constraintSize back.
- Live mode is a self-chaining request-per-repaint loop that only engages after
  the FIRST frame. `captureFrame()` is a silent no-op while a frame is in
  flight — a stuck frame can only be recovered by bouncing `captureSource`
  (the WindowCell watchdog does exactly this, twice, then the icon stays).
- The overlay's layer (Top vs Overlay) and exclusive keyboard focus provably do
  NOT affect capture. Two Hyprland 0.55.2 bugs do:
  1. **Fence treadmill**: every output commit restarts a pending dmabuf copy
     before its GPU fence signals, so busy visible windows never complete.
     Fixed upstream in v0.56.0 (PR #15429); backported at
     `/etc/nixos/patches/hyprland-pr15429-screenshare-fence.patch`.
     Stopgap without the patch: run quickshell with `QS_DISABLE_DMABUF=1`
     (synchronous SHM copies, fence-free).
  2. **Off-box starvation**: export frames for windows positioned outside
     their monitor's logical box are skipped forever (silent — no ready, no
     failed). The scrolling layout parks scrolled-out columns off-box, so
     those cells can never capture. Still broken upstream as of 0.56.2; local
     fix at `/etc/nixos/patches/hyprland-screenshare-offbox-windows.patch`.
- With both patches applied (NixOS rebuild), every window captures live at
  full resolution with default dmabuf; the icon fallback remains for windows
  that genuinely cannot produce frames (e.g. destroyed mid-open).

## Edge cases

- Zero regular windows → grid shows a small empty-state label; rail still works.
- Zero rail windows → rail hidden; D-overflow/Tab/digits are no-ops.
- Selected window closes while open → selection repair (see Data model).
- Single workspace → W/S no-op (no wrap jitter).
- `hasFullscreen` guard like other shortcuts: do NOT suppress the switcher on
  fullscreen — alt-tabbing away from a fullscreen window is a primary use case.
- Config (v1): `hiddenSpecials` list lives as a readonly property; migrate to
  shell.json config section later if C++ schema allows.

## Files

```
modules/windowswitcher/
  WindowSwitcher.qml   — Scope root: LazyLoader + overlay window lifecycle,
                         CustomShortcut, IpcHandler, submap dispatch, per the
                         AreaPicker open/close protocol
  SwitcherState.qml    — QtObject: rows/rail derivation, selection state,
                         navigation + commit/dismiss logic (all pure logic,
                         no visuals)
  Content.qml          — fullscreen item inside the window: scrim, key
                         handling (table above), hosts GridCamera + RailPanel
  GridCamera.qml       — the sliding 2D grid (rows of WindowCells, camera
                         transform, staggered row alignment, scale/dim)
  RailPanel.qml        — right rail (vertical list, number + visible badges)
  WindowCell.qml       — one window card (thumbnail/icon fallback, label,
                         hover/click with keyboard-nav guard)
```

State/UI contract: `SwitcherState` (a `Scope`) exposes `rows` (array of
`{ ws, windows }`), `rail` (array of toplevels, MRU), `zone`, `rowIndex`,
`colIndex`, `railIndex`, `selected` (readonly derived), functions `rebuild()`,
`initSelection()`, `moveLeft/Right/Up/Down()`, `toggleZone()`, `pressDigit(n)`,
`landingCol(rowIdx)`, `commit()`, `dismiss()`, and a single signal
`closeRequested()` (emitted by both commit and dismiss paths, after any
dispatches) which the window root consumes to run the close animation; the
window dispatches `submap reset` at close start and `submap windowswitcher`
on open.
