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
        applyPapirusFolders();
        applyThunarExtra();
        applyKdeColours();
    }

    // Toolbar + menubar rules missing from the CLI's thunar.css template (Thunar looks unstyled there
    // without them). The CLI fully rewrites ~/.config/gtk-3.0/thunar.css on every `caelestia scheme
    // set`, so we re-append a MARKED block carrying the live palette after each change. applyExternal-
    // Colours() runs from load(), which only fires once the CLI has written the scheme file (and thus
    // thunar.css), so we append after — never before. The sed strips any prior block first, so it's
    // idempotent across re-runs. Colours map the same way the template does: $primary→m3primary (the
    // #9ecedb accent), $surface→m3surface (the #0a0f10 background). Thunar is GTK3, so only gtk-3.0
    // matters; thunar.css is @imported by gtk-3.0/gtk.css. CSS only applies at Thunar launch (GTK3 on
    // Wayland won't hot-reload user CSS), which is why a brief CLI-wrote-but-not-yet-appended window
    // is harmless — the block is present by the time a new window opens.
    function applyThunarExtra(): void {
        const primary = `#${toHex(current.m3primary)}`;
        const surface = `#${toHex(current.m3surface)}`;
        const block = [
            "/* caelestia-shell:thunar-extra BEGIN (managed by Colours.qml — toolbar/menubar) */",
            `.thunar toolbar { background-color: alpha(${primary}, 0.08); }`,
            `.thunar toolbar toolbutton button:hover { background: alpha(${primary}, 0.15); border-radius: 100%; }`,
            `.thunar toolbar toolitem button, .thunar toolbar toolitem entry { background: ${surface}; }`,
            `.thunar menubar { background: ${surface}; }`,
            `.thunar menubar menuitem menu { background: ${surface}; }`,
            `.thunar menubar menuitem menu menuitem:hover { background: alpha(${primary}, 0.15); }`,
            "/* caelestia-shell:thunar-extra END */"
        ].join("\n");
        // Quoted heredoc (<<'EOF') → no shell expansion; the block is fully substituted in QML and
        // contains no $ / quotes, so it's emitted verbatim. Guard on the file existing so we never
        // create an orphan thunar.css before the CLI has run.
        Quickshell.execDetached(["sh", "-c", `f="$HOME/.config/gtk-3.0/thunar.css"; [ -f "$f" ] || exit 0; sed -i '/caelestia-shell:thunar-extra BEGIN/,/caelestia-shell:thunar-extra END/d' "$f" 2>/dev/null; cat >> "$f" <<'CAELEOF'\n${block}\nCAELEOF\n`]);
    }

    // Recolour Papirus folder icons to the accent. caelestia's CLI does this too, but via
    // `sudo papirus-folders` — which runs as root, so it can't reach the user's writable theme copy
    // and only targets the read-only nix store. We run it as the USER (no sudo) so papirus-folders
    // resolves to the writable copy at ~/.local/share/icons/Papirus-Dark (placed by home-manager's
    // home.activation.papirusWritable). The colour NAME is derived from the accent hue, mirroring
    // caelestia's own hue→Papirus-colour mapping (utils/theme.py).
    function applyPapirusFolders(): void {
        // Recolour the writable Papirus-Dark copy to the accent. New GTK windows pick this up on
        // launch. We intentionally do NOT bounce the GSettings icon theme to force already-open apps
        // to repaint: that toggle (icon-theme → Adwaita → back) raced across rapid theme switches and
        // could leave the icon theme stuck on Adwaita. The recolour-on-disk is enough.
        const c = root.papirusFolderColour();
        Quickshell.execDetached(["sh", "-c", `papirus-folders -C ${c} -t Papirus-Dark`]);
    }

    function papirusFolderColour(): string {
        const c = current.m3primary;
        const r = Math.round(c.r * 255);
        const g = Math.round(c.g * 255);
        const b = Math.round(c.b * 255);
        const maxV = Math.max(r, g, b);
        const minV = Math.min(r, g, b);
        const brightness = maxV;
        const saturation = maxV === 0 ? 0 : Math.floor((maxV - minV) * 100 / maxV);

        // Low saturation → greyscale folders
        if (saturation < 20)
            return brightness < 85 ? "black" : brightness < 170 ? "grey" : "white";

        // Medium-low saturation + bright → pale variants (matches caelestia's use_pale)
        const pale = saturation < 60 && brightness > 180;

        // Blue dominant
        if (b > r && b > g) {
            const rRatio = b > 0 ? Math.floor(r * 100 / b) : 0;
            const gRatio = b > 0 ? Math.floor(g * 100 / b) : 0;
            if (rRatio > 70 && gRatio > 70)
                return Math.abs(r - g) < 15 ? "blue" : r > g ? "violet" : "cyan";
            if (rRatio > 60 && r > g)
                return "violet";
            if (gRatio > 60 && g > r)
                return "cyan";
            return "blue";
        }

        // Red dominant
        if (r > g && r > b) {
            if (g > b + 30) {
                const rgRatio = r > 0 ? Math.floor(g * 100 / r) : 0;
                if (pale)
                    return rgRatio > 70 && brightness < 220 ? "palebrown" : "paleorange";
                return rgRatio > 70 && brightness < 180 ? "brown" : "orange";
            }
            if (b > g + 20)
                return "pink";
            return pale ? "pink" : "red";
        }

        // Green dominant
        if (g > r && g > b)
            return r > b + 30 ? "yellow" : "green";

        return "grey";
    }

    // Theme KDE/Qt apps (Dolphin, Ark, Gwenview, Kate, …) the way KColorScheme actually reads
    // colours: the [Colors:*]/[WM]/[ColorEffects:*] groups in ~/.config/kdeglobals. We MERGE into
    // kdeglobals (a small python pass preserves the user's other keys — icons, fonts, shortcuts),
    // also drop a self-owned ~/.local/share/color-schemes/Caelestia.colors so the scheme shows in
    // any KDE picker, then emit the legacy KGlobalSettings "notifyChange" DBus signal so ALREADY-
    // OPEN KDE apps recolour live — no app restart, no plasmashell, no plasma-apply-colorscheme
    // (unreliable off Plasma). Same end result as end-4's kde-material-you-colors, but self-contained.
    function applyKdeColours(): void {
        const c = current;
        const rgb = col => `${Math.round(col.r * 255)},${Math.round(col.g * 255)},${Math.round(col.b * 255)}`;

        const groups = {
            "General": {
                Name: "Caelestia",
                ColorScheme: "Caelestia"
            },
            "Colors:View": {
                BackgroundNormal: rgb(c.m3surface),
                BackgroundAlternate: rgb(c.m3surfaceContainerLow),
                ForegroundNormal: rgb(c.m3onSurface),
                ForegroundInactive: rgb(c.m3onSurfaceVariant),
                ForegroundActive: rgb(c.m3primary),
                ForegroundLink: rgb(c.m3primary),
                ForegroundVisited: rgb(c.m3secondary),
                ForegroundNegative: rgb(c.m3error),
                ForegroundNeutral: rgb(c.m3tertiary),
                ForegroundPositive: rgb(c.m3success),
                DecorationFocus: rgb(c.m3primary),
                DecorationHover: rgb(c.m3primary)
            },
            "Colors:Window": {
                BackgroundNormal: rgb(c.m3surface),
                BackgroundAlternate: rgb(c.m3surfaceContainer),
                ForegroundNormal: rgb(c.m3onSurface),
                ForegroundInactive: rgb(c.m3onSurfaceVariant),
                ForegroundActive: rgb(c.m3primary),
                ForegroundLink: rgb(c.m3primary),
                ForegroundNegative: rgb(c.m3error),
                ForegroundNeutral: rgb(c.m3tertiary),
                ForegroundPositive: rgb(c.m3success),
                DecorationFocus: rgb(c.m3primary),
                DecorationHover: rgb(c.m3primary)
            },
            "Colors:Button": {
                BackgroundNormal: rgb(c.m3surfaceContainer),
                BackgroundAlternate: rgb(c.m3surfaceContainerHigh),
                ForegroundNormal: rgb(c.m3onSurface),
                ForegroundInactive: rgb(c.m3onSurfaceVariant),
                ForegroundActive: rgb(c.m3primary),
                ForegroundNegative: rgb(c.m3error),
                ForegroundNeutral: rgb(c.m3tertiary),
                ForegroundPositive: rgb(c.m3success),
                DecorationFocus: rgb(c.m3primary),
                DecorationHover: rgb(c.m3primary)
            },
            "Colors:Selection": {
                BackgroundNormal: rgb(c.m3primary),
                BackgroundAlternate: rgb(c.m3primaryContainer),
                ForegroundNormal: rgb(c.m3onPrimary),
                ForegroundInactive: rgb(c.m3onPrimary),
                ForegroundActive: rgb(c.m3onPrimary),
                ForegroundLink: rgb(c.m3onPrimary),
                ForegroundNegative: rgb(c.m3error),
                ForegroundNeutral: rgb(c.m3tertiary),
                ForegroundPositive: rgb(c.m3success),
                DecorationFocus: rgb(c.m3primary),
                DecorationHover: rgb(c.m3primary)
            },
            "Colors:Tooltip": {
                BackgroundNormal: rgb(c.m3surfaceContainer),
                BackgroundAlternate: rgb(c.m3surfaceContainerHigh),
                ForegroundNormal: rgb(c.m3onSurface),
                ForegroundInactive: rgb(c.m3onSurfaceVariant),
                DecorationFocus: rgb(c.m3primary),
                DecorationHover: rgb(c.m3primary)
            },
            "Colors:Complementary": {
                BackgroundNormal: rgb(c.m3surfaceContainer),
                BackgroundAlternate: rgb(c.m3surfaceContainerHigh),
                ForegroundNormal: rgb(c.m3onSurface),
                ForegroundInactive: rgb(c.m3onSurfaceVariant),
                DecorationFocus: rgb(c.m3primary),
                DecorationHover: rgb(c.m3primary)
            },
            "Colors:Header": {
                BackgroundNormal: rgb(c.m3surfaceContainer),
                BackgroundAlternate: rgb(c.m3surfaceContainerHigh),
                ForegroundNormal: rgb(c.m3onSurface),
                ForegroundInactive: rgb(c.m3onSurfaceVariant),
                DecorationFocus: rgb(c.m3primary),
                DecorationHover: rgb(c.m3primary)
            },
            "WM": {
                activeBackground: rgb(c.m3surfaceContainer),
                activeForeground: rgb(c.m3onSurface),
                inactiveBackground: rgb(c.m3surface),
                inactiveForeground: rgb(c.m3onSurfaceVariant)
            },
            "ColorEffects:Inactive": {
                Enable: "true",
                ChangeSelectionColor: "true",
                Color: rgb(c.m3surface),
                ColorAmount: "0.025",
                ColorEffect: "2",
                ContrastAmount: "0.1",
                ContrastEffect: "2",
                IntensityAmount: "0",
                IntensityEffect: "0"
            },
            "ColorEffects:Disabled": {
                Enable: "true",
                Color: rgb(c.m3surfaceContainer),
                ColorAmount: "0",
                ColorEffect: "0",
                ContrastAmount: "0.65",
                ContrastEffect: "1",
                IntensityAmount: "0.1",
                IntensityEffect: "0"
            }
        };

        // payload is plain JSON (no single quotes in any key/value), so it's safe inside the shell
        // single-quoted env var. The python body is a quoted heredoc (no shell/QML expansion).
        const payload = JSON.stringify(groups);
        Quickshell.execDetached(["sh", "-c", `CAEL_KDE_JSON='${payload}' python3 - <<'PY'
import os, json, configparser
from pathlib import Path

data = json.loads(os.environ["CAEL_KDE_JSON"])
home = Path.home()

# Self-owned standalone scheme file (safe to fully overwrite)
def render(groups):
    lines = []
    for g, kv in groups.items():
        lines.append("[" + g + "]")
        for k, v in kv.items():
            lines.append(k + "=" + str(v))
        lines.append("")
    return "\\n".join(lines)

cs = home / ".local/share/color-schemes"
cs.mkdir(parents=True, exist_ok=True)
(cs / "Caelestia.colors").write_text(render(data))

# Merge colour groups into kdeglobals WITHOUT touching the user's other keys
kg = home / ".config/kdeglobals"
cfg = configparser.ConfigParser(strict=False, interpolation=None)
cfg.optionxform = str
ok = True
if kg.exists():
    try:
        cfg.read(kg, encoding="utf-8")
    except Exception:
        ok = False  # unparseable — don't risk clobbering it
if ok:
    for g, kv in data.items():
        if not cfg.has_section(g):
            cfg.add_section(g)
        for k, v in kv.items():
            cfg.set(g, k, str(v))
    kg.parent.mkdir(parents=True, exist_ok=True)
    with open(kg, "w", encoding="utf-8") as f:
        cfg.write(f, space_around_delimiters=False)
PY
dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0 2>/dev/null || true`]);
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

        // Dedicated prompt-accent slots — shell-colors.sh references these as \e[38;5;16m / 17m.
        // Palette-indexed (not absolute RGB) so kitty re-renders the already-drawn bash prompt in
        // place when the scheme changes — no Ctrl-C / fresh prompt needed.
        const promptAccent = current.m3primary;
        const promptDim = Qt.rgba(promptAccent.r * 0.82, promptAccent.g * 0.82, promptAccent.b * 0.82, 1);
        map["color16"] = `#${toHex(promptDim)}`;
        map["color17"] = `#${toHex(promptAccent)}`;

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
        // Prompt colours are PALETTE-INDEXED: kitty term colour 16 = dim accent, 17 = accent (set in
        // applyKittyColours). Because PS1 references those palette slots rather than absolute RGB,
        // kitty re-renders the already-drawn prompt IN PLACE the instant the scheme changes — no
        // Ctrl-C, no fresh prompt, same line. This file just maps the CL_* vars PS1 uses onto the
        // slots; its contents are static (only the palette behind 16/17 changes).
        const accent = current.m3primary;
        const lines = [
            "# Generated by caelestia (Colours.qml) — PS1 colours via kitty palette slots 16/17",
            `# accent = #${toHex(accent)}  (CL_FG_SECONDARY = colour17 = accent, CL_FG_PRIMARY = colour16 = darker)`,
            "# Bash-bracketed (non-printing markers)",
            `export CL_FG_PRIMARY_BASH="\\[\\e[38;5;16m\\]"`,
            `export CL_FG_SECONDARY_BASH="\\[\\e[38;5;17m\\]"`,
            `export CL_BG_PRIMARY_BASH="\\[\\e[48;5;16m\\]"`,
            `export CL_BG_SECONDARY_BASH="\\[\\e[48;5;17m\\]"`,
            `export CL_RESET_BASH="\\[\\e[0m\\]"`,
            "# Raw ANSI (no markers)",
            `export CL_FG_PRIMARY_RAW=$'\\e[38;5;16m'`,
            `export CL_FG_SECONDARY_RAW=$'\\e[38;5;17m'`,
            `export CL_BG_PRIMARY_RAW=$'\\e[48;5;16m'`,
            `export CL_BG_SECONDARY_RAW=$'\\e[48;5;17m'`,
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
        // No Ctrl-C push needed: existing prompts recolour live via the palette (applyKittyColours).
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
        path: `${Paths.state}/shell-colors.sh`
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
