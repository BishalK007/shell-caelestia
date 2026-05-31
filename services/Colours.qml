pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.services
import qs.utils

Singleton {
    id: root

    property bool showPreview
    property string scheme
    property string flavour
    readonly property bool light: showPreview ? previewLight : currentLight
    property bool currentLight
    property bool previewLight
    readonly property M3Palette palette: showPreview ? preview : current
    readonly property M3TPalette tPalette: M3TPalette {}
    readonly property M3Palette current: M3Palette {}
    readonly property M3Palette preview: M3Palette {}
    readonly property Transparency transparency: Transparency {}
    readonly property alias wallLuminance: analyser.luminance

    function getLuminance(c: color): real {
        if (c.r == 0 && c.g == 0 && c.b == 0)
            return 0;
        return Math.sqrt(0.299 * (c.r ** 2) + 0.587 * (c.g ** 2) + 0.114 * (c.b ** 2));
    }

    function alterColour(c: color, a: real, layer: int): color {
        const luminance = getLuminance(c);

        const offset = (!light || layer == 1 ? 1 : -layer / 2) * (light ? 0.2 : 0.3) * (1 - transparency.base) * (1 + wallLuminance * (light ? (layer == 1 ? 3 : 1) : 2.5));
        const scale = (luminance + offset) / luminance;
        const r = Math.max(0, Math.min(1, c.r * scale));
        const g = Math.max(0, Math.min(1, c.g * scale));
        const b = Math.max(0, Math.min(1, c.b * scale));

        return Qt.rgba(r, g, b, a);
    }

    function layer(c: color, layer: var): color {
        if (!transparency.enabled)
            return c;

        return layer === 0 ? Qt.alpha(c, transparency.base) : alterColour(c, transparency.layers, layer ?? 1);
    }

    function on(c: color): color {
        if (c.hslLightness < 0.5)
            return Qt.hsla(c.hslHue, c.hslSaturation, 0.9, 1);
        return Qt.hsla(c.hslHue, c.hslSaturation, 0.1, 1);
    }

    function load(data: string, isPreview: bool): void {
        const colours = isPreview ? preview : current;
        const scheme = JSON.parse(data);

        if (!isPreview) {
            root.scheme = scheme.name;
            flavour = scheme.flavour;
            currentLight = scheme.mode === "light";
        } else {
            previewLight = scheme.mode === "light";
        }

        for (const [name, colour] of Object.entries(scheme.colours)) {
            const propName = name.startsWith("term") ? name : `m3${name}`;
            if (colours.hasOwnProperty(propName))
                colours[propName] = `#${colour}`;
        }

        if (!isPreview)
            root.applyExternalColours();
    }

    function setMode(mode: string): void {
        Quickshell.execDetached(["caelestia", "scheme", "set", "--notify", "-m", mode]);
    }

    function reloadHyprRules(): void {
        const str = "keyword layerrule %1 %2, match:namespace caelestia-drawers";
        Hypr.extras.batchMessage([str.arg("blur").arg(transparency.enabled ? 1 : 0), str.arg("ignore_alpha").arg(transparency.base - 0.03)]);
    }

    // Base of the socket kitty listens on (kitty.conf: listen_on). kitty appends -<pid>,
    // so live apply globs "<base>-*".
    readonly property string kittySocketBase: "/tmp/kitty-bishal"

    // "rrggbb" from a QML color (channels are 0..1)
    function toHex(c: color): string {
        const h = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return h(c.r) + h(c.g) + h(c.b);
    }

    // Push the current scheme out to external apps (called from load() on every real scheme change)
    function applyExternalColours(): void {
        applyHyprColours();
        applyKittyColours();
        applyShellColours();
    }

    // Live border colours via hyprctl keyword IPC — no file edits, no reload
    function applyHyprColours(): void {
        const accent = toHex(current.m3primary);
        const muted = toHex(current.m3surfaceVariant);
        Hypr.extras.batchMessage([`keyword general:col.active_border rgba(${accent}ff)`, `keyword general:col.inactive_border rgba(${muted}aa)`]);
    }

    // Persist kitty colours (for new windows) + live-apply to running ones
    function applyKittyColours(): void {
        const map = {
            background: `#${toHex(current.m3surface)}`,
            foreground: `#${toHex(current.m3onSurface)}`,
            cursor: `#${toHex(current.m3primary)}`,
            cursor_text_color: `#${toHex(current.m3surface)}`,
            selection_background: `#${toHex(current.m3primary)}`,
            selection_foreground: `#${toHex(current.m3onPrimary)}`,
            url_color: `#${toHex(current.m3primary)}`
        };
        for (let i = 0; i < 16; i++)
            map[`color${i}`] = `#${toHex(current[`term${i}`])}`;

        // Persisted file, included by kitty.conf, so new terminals pick it up
        const lines = ["# Colours managed by caelestia (Colours.qml)"];
        for (const [k, v] of Object.entries(map))
            lines.push(`${k} ${v}`);
        kittyColours.setText(lines.join("\n") + "\n");

        // Live-apply to every running kitty. Sockets are <base>-<pid>, so glob them; inline
        // values (not the file) avoid a read-after-write race with setText above.
        const kv = Object.entries(map).map(([k, v]) => `${k}=${v}`).join(" ");
        Quickshell.execDetached(["sh", "-c", `for s in ${root.kittySocketBase}-*; do kitty @ --to "unix:$s" set-colors --all ${kv} 2>/dev/null; done`]);
    }

    // PS1 colours for bash. We ONLY write the file the user's PROMPT_COMMAND re-sources each
    // prompt (__cl_ps1_reload). No `kitty @ send-text` push — that types into whatever is in the
    // foreground (Claude Code, vim, ...) and corrupts it. Long-lived shells recolour on next prompt.
    function applyShellColours(): void {
        const accent = current.m3primary;
        const dim = Qt.rgba(accent.r * 0.82, accent.g * 0.82, accent.b * 0.82, 1);
        const trip = c => `${Math.round(c.r * 255)};${Math.round(c.g * 255)};${Math.round(c.b * 255)}`;
        const s = trip(accent);
        const d = trip(dim);
        const lines = [
            "# Generated by caelestia (Colours.qml) — PS1 colours, pulled each prompt",
            `# accent = #${toHex(accent)}  (CL_FG_SECONDARY = accent, CL_FG_PRIMARY = darker)`,
            "# Bash-bracketed (non-printing markers)",
            `export CL_FG_PRIMARY_BASH="\\[\\e[38;2;${d}m\\]"`,
            `export CL_FG_SECONDARY_BASH="\\[\\e[38;2;${s}m\\]"`,
            `export CL_BG_PRIMARY_BASH="\\[\\e[48;2;${d}m\\]"`,
            `export CL_BG_SECONDARY_BASH="\\[\\e[48;2;${s}m\\]"`,
            `export CL_RESET_BASH="\\[\\e[0m\\]"`,
            "# Raw ANSI (no markers)",
            `export CL_FG_PRIMARY_RAW=$'\\e[38;2;${d}m'`,
            `export CL_FG_SECONDARY_RAW=$'\\e[38;2;${s}m'`,
            `export CL_BG_PRIMARY_RAW=$'\\e[48;2;${d}m'`,
            `export CL_BG_SECONDARY_RAW=$'\\e[48;2;${s}m'`,
            `export CL_RESET_RAW=$'\\e[0m'`,
            "# Select appropriate set",
            `if [ -n "$BASH_VERSION" ]; then`,
            `  export CL_FG_PRIMARY="$CL_FG_PRIMARY_BASH"`,
            `  export CL_FG_SECONDARY="$CL_FG_SECONDARY_BASH"`,
            `  export CL_BG_PRIMARY="$CL_BG_PRIMARY_BASH"`,
            `  export CL_BG_SECONDARY="$CL_BG_SECONDARY_BASH"`,
            `  export CL_RESET="$CL_RESET_BASH"`,
            "else",
            `  export CL_FG_PRIMARY=$CL_FG_PRIMARY_RAW`,
            `  export CL_FG_SECONDARY=$CL_FG_SECONDARY_RAW`,
            `  export CL_BG_PRIMARY=$CL_BG_PRIMARY_RAW`,
            `  export CL_BG_SECONDARY=$CL_BG_SECONDARY_RAW`,
            `  export CL_RESET=$CL_RESET_RAW`,
            "fi"
        ];
        shellColours.setText(lines.join("\n") + "\n");

        // Instant refresh for IDLE shells: send Ctrl-C only to kitty windows whose sole foreground
        // process is a shell — that starts a fresh prompt which re-sources the colours above.
        // Windows running a TUI (Claude Code, vim, yazi, ...) are skipped and stay queued.
        Quickshell.execDetached(["sh", "-c", `for s in ${root.kittySocketBase}-*; do [ -S "$s" ] || continue; for w in $(kitty @ --to "unix:$s" ls 2>/dev/null | jq -r '.[].tabs[].windows[] | select((.foreground_processes|length)==1) | select(.foreground_processes[0].cmdline[0]|test("(^|/)-?(bash|zsh|fish|dash|sh)$")) | .id' 2>/dev/null); do printf '\\003' | kitty @ --to "unix:$s" send-text --match "id:$w" --stdin 2>/dev/null; done; done`]);
    }

    Component.onCompleted: debounceTimer.triggered()

    Connections {
        function onConfigReloaded(): void {
            root.reloadHyprRules();
            root.applyHyprColours();
        }

        target: Hypr
    }

    FileView {
        path: `${Paths.state}/scheme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.load(text(), false)
    }

    // Write-only: caelestia-managed kitty palette, included by kitty.conf
    FileView {
        id: kittyColours

        printErrors: false
        path: `${Paths.home}/.config/kitty/colors-generated.conf`
    }

    // Write-only: PS1 colour vars, re-sourced each prompt by ~/.bashrc (__cl_ps1_reload)
    FileView {
        id: shellColours

        printErrors: false
        path: `${Paths.home}/.config/dotfiles/shell-colors.sh`
    }

    ImageAnalyser {
        id: analyser

        source: Wallpapers.current
    }

    Timer {
        id: debounceTimer

        interval: 300
        onTriggered: root.reloadHyprRules()
    }

    component Transparency: QtObject {
        readonly property bool enabled: Tokens.transparency.enabled
        readonly property real base: Math.max(0, Math.min(1, Tokens.transparency.base - (root.light ? 0.1 : 0)))
        readonly property real layers: Tokens.transparency.layers

        onEnabledChanged: debounceTimer.restart()
        onBaseChanged: debounceTimer.restart()
    }

    component M3TPalette: QtObject {
        readonly property color m3primary_paletteKeyColor: root.layer(root.palette.m3primary_paletteKeyColor)
        readonly property color m3secondary_paletteKeyColor: root.layer(root.palette.m3secondary_paletteKeyColor)
        readonly property color m3tertiary_paletteKeyColor: root.layer(root.palette.m3tertiary_paletteKeyColor)
        readonly property color m3neutral_paletteKeyColor: root.layer(root.palette.m3neutral_paletteKeyColor)
        readonly property color m3neutral_variant_paletteKeyColor: root.layer(root.palette.m3neutral_variant_paletteKeyColor)
        readonly property color m3background: root.layer(root.palette.m3background, 0)
        readonly property color m3onBackground: root.layer(root.palette.m3onBackground)
        readonly property color m3surface: root.layer(root.palette.m3surface, 0)
        readonly property color m3surfaceDim: root.layer(root.palette.m3surfaceDim, 0)
        readonly property color m3surfaceBright: root.layer(root.palette.m3surfaceBright, 0)
        readonly property color m3surfaceContainerLowest: root.layer(root.palette.m3surfaceContainerLowest)
        readonly property color m3surfaceContainerLow: root.layer(root.palette.m3surfaceContainerLow)
        readonly property color m3surfaceContainer: root.layer(root.palette.m3surfaceContainer)
        readonly property color m3surfaceContainerHigh: root.layer(root.palette.m3surfaceContainerHigh)
        readonly property color m3surfaceContainerHighest: root.layer(root.palette.m3surfaceContainerHighest)
        readonly property color m3onSurface: root.layer(root.palette.m3onSurface)
        readonly property color m3surfaceVariant: root.layer(root.palette.m3surfaceVariant, 0)
        readonly property color m3onSurfaceVariant: root.layer(root.palette.m3onSurfaceVariant)
        readonly property color m3inverseSurface: root.layer(root.palette.m3inverseSurface, 0)
        readonly property color m3inverseOnSurface: root.layer(root.palette.m3inverseOnSurface)
        readonly property color m3outline: root.layer(root.palette.m3outline)
        readonly property color m3outlineVariant: root.layer(root.palette.m3outlineVariant)
        readonly property color m3shadow: root.layer(root.palette.m3shadow)
        readonly property color m3scrim: root.layer(root.palette.m3scrim)
        readonly property color m3surfaceTint: root.layer(root.palette.m3surfaceTint)
        readonly property color m3primary: root.layer(root.palette.m3primary)
        readonly property color m3onPrimary: root.layer(root.palette.m3onPrimary)
        readonly property color m3primaryContainer: root.layer(root.palette.m3primaryContainer)
        readonly property color m3onPrimaryContainer: root.layer(root.palette.m3onPrimaryContainer)
        readonly property color m3inversePrimary: root.layer(root.palette.m3inversePrimary)
        readonly property color m3secondary: root.layer(root.palette.m3secondary)
        readonly property color m3onSecondary: root.layer(root.palette.m3onSecondary)
        readonly property color m3secondaryContainer: root.layer(root.palette.m3secondaryContainer)
        readonly property color m3onSecondaryContainer: root.layer(root.palette.m3onSecondaryContainer)
        readonly property color m3tertiary: root.layer(root.palette.m3tertiary)
        readonly property color m3onTertiary: root.layer(root.palette.m3onTertiary)
        readonly property color m3tertiaryContainer: root.layer(root.palette.m3tertiaryContainer)
        readonly property color m3onTertiaryContainer: root.layer(root.palette.m3onTertiaryContainer)
        readonly property color m3error: root.layer(root.palette.m3error)
        readonly property color m3onError: root.layer(root.palette.m3onError)
        readonly property color m3errorContainer: root.layer(root.palette.m3errorContainer)
        readonly property color m3onErrorContainer: root.layer(root.palette.m3onErrorContainer)
        readonly property color m3success: root.layer(root.palette.m3success)
        readonly property color m3onSuccess: root.layer(root.palette.m3onSuccess)
        readonly property color m3successContainer: root.layer(root.palette.m3successContainer)
        readonly property color m3onSuccessContainer: root.layer(root.palette.m3onSuccessContainer)
        readonly property color m3primaryFixed: root.layer(root.palette.m3primaryFixed)
        readonly property color m3primaryFixedDim: root.layer(root.palette.m3primaryFixedDim)
        readonly property color m3onPrimaryFixed: root.layer(root.palette.m3onPrimaryFixed)
        readonly property color m3onPrimaryFixedVariant: root.layer(root.palette.m3onPrimaryFixedVariant)
        readonly property color m3secondaryFixed: root.layer(root.palette.m3secondaryFixed)
        readonly property color m3secondaryFixedDim: root.layer(root.palette.m3secondaryFixedDim)
        readonly property color m3onSecondaryFixed: root.layer(root.palette.m3onSecondaryFixed)
        readonly property color m3onSecondaryFixedVariant: root.layer(root.palette.m3onSecondaryFixedVariant)
        readonly property color m3tertiaryFixed: root.layer(root.palette.m3tertiaryFixed)
        readonly property color m3tertiaryFixedDim: root.layer(root.palette.m3tertiaryFixedDim)
        readonly property color m3onTertiaryFixed: root.layer(root.palette.m3onTertiaryFixed)
        readonly property color m3onTertiaryFixedVariant: root.layer(root.palette.m3onTertiaryFixedVariant)
    }

    component M3Palette: QtObject {
        property color m3primary_paletteKeyColor: "#a8627b"
        property color m3secondary_paletteKeyColor: "#8e6f78"
        property color m3tertiary_paletteKeyColor: "#986e4c"
        property color m3neutral_paletteKeyColor: "#807477"
        property color m3neutral_variant_paletteKeyColor: "#837377"
        property color m3background: "#191114"
        property color m3onBackground: "#efdfe2"
        property color m3surface: "#191114"
        property color m3surfaceDim: "#191114"
        property color m3surfaceBright: "#403739"
        property color m3surfaceContainerLowest: "#130c0e"
        property color m3surfaceContainerLow: "#22191c"
        property color m3surfaceContainer: "#261d20"
        property color m3surfaceContainerHigh: "#31282a"
        property color m3surfaceContainerHighest: "#3c3235"
        property color m3onSurface: "#efdfe2"
        property color m3surfaceVariant: "#514347"
        property color m3onSurfaceVariant: "#d5c2c6"
        property color m3inverseSurface: "#efdfe2"
        property color m3inverseOnSurface: "#372e30"
        property color m3outline: "#9e8c91"
        property color m3outlineVariant: "#514347"
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        property color m3surfaceTint: "#ffb0ca"
        property color m3primary: "#ffb0ca"
        property color m3onPrimary: "#541d34"
        property color m3primaryContainer: "#6f334a"
        property color m3onPrimaryContainer: "#ffd9e3"
        property color m3inversePrimary: "#8b4a62"
        property color m3secondary: "#e2bdc7"
        property color m3onSecondary: "#422932"
        property color m3secondaryContainer: "#5a3f48"
        property color m3onSecondaryContainer: "#ffd9e3"
        property color m3tertiary: "#f0bc95"
        property color m3onTertiary: "#48290c"
        property color m3tertiaryContainer: "#b58763"
        property color m3onTertiaryContainer: "#000000"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
        property color m3errorContainer: "#93000a"
        property color m3onErrorContainer: "#ffdad6"
        property color m3success: "#B5CCBA"
        property color m3onSuccess: "#213528"
        property color m3successContainer: "#374B3E"
        property color m3onSuccessContainer: "#D1E9D6"
        property color m3primaryFixed: "#ffd9e3"
        property color m3primaryFixedDim: "#ffb0ca"
        property color m3onPrimaryFixed: "#39071f"
        property color m3onPrimaryFixedVariant: "#6f334a"
        property color m3secondaryFixed: "#ffd9e3"
        property color m3secondaryFixedDim: "#e2bdc7"
        property color m3onSecondaryFixed: "#2b151d"
        property color m3onSecondaryFixedVariant: "#5a3f48"
        property color m3tertiaryFixed: "#ffdcc3"
        property color m3tertiaryFixedDim: "#f0bc95"
        property color m3onTertiaryFixed: "#2f1500"
        property color m3onTertiaryFixedVariant: "#623f21"
        property color term0: "#353434"
        property color term1: "#ff4c8a"
        property color term2: "#ffbbb7"
        property color term3: "#ffdedf"
        property color term4: "#b3a2d5"
        property color term5: "#e98fb0"
        property color term6: "#ffba93"
        property color term7: "#eed1d2"
        property color term8: "#b39e9e"
        property color term9: "#ff80a3"
        property color term10: "#ffd3d0"
        property color term11: "#fff1f0"
        property color term12: "#dcbc93"
        property color term13: "#f9a8c2"
        property color term14: "#ffd1c0"
        property color term15: "#ffffff"
    }
}
