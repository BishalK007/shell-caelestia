// Caelestia VS Code integration.
//
// Family-(B) dynamic theming: this extension owns a registered colour theme
// ("Caelestia"). It watches the Caelestia shell's generated scheme.json and,
// on every change, regenerates its own bundled themes/caelestia.json. Because
// that file is the *active* theme (and the contribution carries "_watch": true),
// VS Code re-reads it and re-applies colours live — no window reload.
//
// Written as plain CommonJS with no npm dependencies so it can be copied into an
// editor's extensions dir as-is (no build step). `require('vscode')` is lazy so
// the file also runs under plain node for one-shot theme generation:
//     node extension.js            # regenerate themes/caelestia.json from the scheme

const fs = require("fs");
const os = require("os");
const path = require("path");

const THEME_PATH = path.join(__dirname, "themes", "caelestia.json");

function defaultSchemePath() {
    const state = process.env.XDG_STATE_HOME || path.join(os.homedir(), ".local", "state");
    return path.join(state, "caelestia", "scheme.json");
}

function readScheme(schemePath) {
    return JSON.parse(fs.readFileSync(schemePath, "utf8"));
}

// Build a complete VS Code colour theme from a Caelestia scheme object.
// Scheme colours are 6-digit hex WITHOUT a leading '#'.
function buildTheme(scheme) {
    const C = scheme.colours || scheme.colors || {};

    // hex helper: prepend '#', optionally append an 8-bit alpha (2 hex digits)
    const h = (key, alpha) => {
        let v = C[key];
        if (!v)
            v = "000000";
        if (v[0] !== "#")
            v = "#" + v;
        return alpha ? v + alpha : v;
    };
    // first existing key wins, so the theme degrades gracefully on partial schemes
    const pick = (...keys) => {
        for (const k of keys)
            if (C[k])
                return h(k);
        return "#000000";
    };

    const isLight = scheme.mode === "light";

    // Semantic shortcuts (M3 surfaces for chrome, Catppuccin-named accents for syntax)
    const bg = pick("surface", "base", "background");
    const bgDim = pick("surfaceContainerLowest", "crust", "mantle", "surface");
    const bgLow = pick("surfaceContainerLow", "mantle", "surface");
    const bgPanel = pick("surfaceContainer", "mantle", "surface");
    const bgHigh = pick("surfaceContainerHigh", "surface1", "surfaceVariant");
    const bgHigher = pick("surfaceContainerHighest", "surface2", "surfaceVariant");
    const fg = pick("onSurface", "text", "onBackground");
    const fgDim = pick("onSurfaceVariant", "subtext1", "subtext0");
    const fgMuted = pick("outline", "overlay1", "subtext0");
    const border = pick("outlineVariant", "surface2", "overlay0");
    const accent = pick("primary", "mauve");
    const onAccent = pick("onPrimary", "crust", "base");
    const err = pick("error", "red");

    const red = pick("red", "error");
    const green = pick("green", "success");
    const yellow = pick("yellow", "tertiary");
    const blue = pick("blue", "primary");
    const mauve = pick("mauve", "primary");
    const peach = pick("peach", "tertiary");
    const teal = pick("teal", "secondary");
    const sky = pick("sky", "secondary");
    const sapphire = pick("sapphire", "blue");
    const lavender = pick("lavender", "primary");
    const pink = pick("pink", "mauve");
    const comment = pick("overlay1", "subtext0", "outline");

    const colors = {
        focusBorder: accent,
        foreground: fg,
        "icon.foreground": fgDim,
        "selection.background": h(C.primary ? "primary" : "mauve") + "40",
        "widget.border": border,
        descriptionForeground: fgDim,
        errorForeground: err,

        "editor.background": bg,
        "editor.foreground": fg,
        "editorLineNumber.foreground": fgMuted,
        "editorLineNumber.activeForeground": fg,
        "editorCursor.foreground": accent,
        "editor.selectionBackground": accent + "33",
        "editor.selectionHighlightBackground": accent + "22",
        "editor.wordHighlightBackground": accent + "22",
        "editor.findMatchBackground": peach + "55",
        "editor.findMatchHighlightBackground": peach + "33",
        "editor.lineHighlightBackground": bgHigh + "66",
        "editor.lineHighlightBorder": "#00000000",
        "editorIndentGuide.background1": border,
        "editorIndentGuide.activeBackground1": fgMuted,
        "editorWhitespace.foreground": border,
        "editorBracketMatch.background": accent + "22",
        "editorBracketMatch.border": accent,
        "editorRuler.foreground": border,
        "editorError.foreground": red,
        "editorWarning.foreground": yellow,
        "editorInfo.foreground": blue,
        "editorHint.foreground": teal,
        "editorGutter.modifiedBackground": blue,
        "editorGutter.addedBackground": green,
        "editorGutter.deletedBackground": red,
        "editorOverviewRuler.border": "#00000000",
        "editorLink.activeForeground": accent,

        "editorWidget.background": bgPanel,
        "editorWidget.foreground": fg,
        "editorWidget.border": border,
        "editorSuggestWidget.background": bgPanel,
        "editorSuggestWidget.border": border,
        "editorSuggestWidget.selectedBackground": accent + "33",
        "editorSuggestWidget.highlightForeground": accent,
        "editorHoverWidget.background": bgPanel,
        "editorHoverWidget.border": border,

        "peekViewEditor.background": bgLow,
        "peekViewResult.background": bgPanel,
        "peekViewTitle.background": bgPanel,

        "activityBar.background": bgLow,
        "activityBar.foreground": fg,
        "activityBar.inactiveForeground": fgMuted,
        "activityBar.activeBorder": accent,
        "activityBarBadge.background": accent,
        "activityBarBadge.foreground": onAccent,

        "sideBar.background": bgLow,
        "sideBar.foreground": fgDim,
        "sideBar.border": border,
        "sideBarTitle.foreground": fg,
        "sideBarSectionHeader.background": bgLow,
        "sideBarSectionHeader.foreground": fg,

        "list.activeSelectionBackground": accent + "33",
        "list.activeSelectionForeground": fg,
        "list.inactiveSelectionBackground": bgHigh,
        "list.hoverBackground": bgHigh + "99",
        "list.focusBackground": accent + "33",
        "list.highlightForeground": accent,
        "list.errorForeground": red,
        "list.warningForeground": yellow,
        "tree.indentGuidesStroke": border,

        "statusBar.background": bgLow,
        "statusBar.foreground": fgDim,
        "statusBar.border": border,
        "statusBar.noFolderBackground": bgLow,
        "statusBar.debuggingBackground": peach,
        "statusBar.debuggingForeground": onAccent,
        "statusBarItem.remoteBackground": accent,
        "statusBarItem.remoteForeground": onAccent,
        "statusBarItem.hoverBackground": "#ffffff1a",

        "titleBar.activeBackground": bgLow,
        "titleBar.activeForeground": fg,
        "titleBar.inactiveBackground": bgLow,
        "titleBar.inactiveForeground": fgMuted,
        "titleBar.border": border,

        "menu.background": bgPanel,
        "menu.foreground": fg,
        "menu.selectionBackground": accent + "33",
        "menubar.selectionBackground": accent + "33",

        "tab.activeBackground": bg,
        "tab.activeForeground": fg,
        "tab.inactiveBackground": bgLow,
        "tab.inactiveForeground": fgMuted,
        "tab.activeBorderTop": accent,
        "tab.activeBorder": "#00000000",
        "tab.border": border,
        "tab.hoverBackground": bgHigh,
        "editorGroupHeader.tabsBackground": bgLow,
        "editorGroupHeader.tabsBorder": border,
        "editorGroup.border": border,

        "panel.background": bg,
        "panel.border": border,
        "panelTitle.activeForeground": fg,
        "panelTitle.inactiveForeground": fgMuted,
        "panelTitle.activeBorder": accent,

        "button.background": accent,
        "button.foreground": onAccent,
        "button.hoverBackground": pick("primaryContainer", "mauve"),
        "button.secondaryBackground": bgHigh,
        "button.secondaryForeground": fg,

        "input.background": bgHigh,
        "input.foreground": fg,
        "input.border": border,
        "input.placeholderForeground": fgMuted,
        "inputOption.activeBorder": accent,
        "inputValidation.errorBackground": pick("errorContainer", "red"),
        "inputValidation.errorBorder": red,

        "dropdown.background": bgHigh,
        "dropdown.foreground": fg,
        "dropdown.border": border,

        "badge.background": accent,
        "badge.foreground": onAccent,

        "scrollbar.shadow": "#00000000",
        "scrollbarSlider.background": fgMuted + "44",
        "scrollbarSlider.hoverBackground": fgMuted + "66",
        "scrollbarSlider.activeBackground": fgMuted + "88",

        "progressBar.background": accent,

        "checkbox.background": bgHigh,
        "checkbox.border": border,

        "terminal.background": bg,
        "terminal.foreground": fg,
        "terminalCursor.foreground": accent,
        "terminal.ansiBlack": h(C.term0 ? "term0" : "crust"),
        "terminal.ansiRed": h(C.term1 ? "term1" : "red"),
        "terminal.ansiGreen": h(C.term2 ? "term2" : "green"),
        "terminal.ansiYellow": h(C.term3 ? "term3" : "yellow"),
        "terminal.ansiBlue": h(C.term4 ? "term4" : "blue"),
        "terminal.ansiMagenta": h(C.term5 ? "term5" : "mauve"),
        "terminal.ansiCyan": h(C.term6 ? "term6" : "teal"),
        "terminal.ansiWhite": h(C.term7 ? "term7" : "subtext1"),
        "terminal.ansiBrightBlack": h(C.term8 ? "term8" : "overlay0"),
        "terminal.ansiBrightRed": h(C.term9 ? "term9" : "red"),
        "terminal.ansiBrightGreen": h(C.term10 ? "term10" : "green"),
        "terminal.ansiBrightYellow": h(C.term11 ? "term11" : "yellow"),
        "terminal.ansiBrightBlue": h(C.term12 ? "term12" : "blue"),
        "terminal.ansiBrightMagenta": h(C.term13 ? "term13" : "mauve"),
        "terminal.ansiBrightCyan": h(C.term14 ? "term14" : "teal"),
        "terminal.ansiBrightWhite": h(C.term15 ? "term15" : "text"),

        "gitDecoration.modifiedResourceForeground": blue,
        "gitDecoration.deletedResourceForeground": red,
        "gitDecoration.untrackedResourceForeground": green,
        "gitDecoration.ignoredResourceForeground": fgMuted,
        "gitDecoration.conflictingResourceForeground": peach,

        "diffEditor.insertedTextBackground": green + "22",
        "diffEditor.removedTextBackground": red + "22",

        "minimap.background": bg,
        "breadcrumb.foreground": fgMuted,
        "breadcrumb.focusForeground": fg,
        "breadcrumbPicker.background": bgPanel,

        "notificationCenterHeader.background": bgPanel,
        "notifications.background": bgPanel,
        "notifications.border": border,

        "textLink.foreground": accent,
        "textLink.activeForeground": pick("primaryContainer", "mauve"),
        "textPreformat.foreground": peach,
        "textBlockQuote.background": bgLow,

        "welcomePage.tileBackground": bgPanel,
        "walkThrough.embeddedEditorBackground": bgLow
    };

    const tc = (scope, foreground, fontStyle) => {
        const settings = { foreground };
        if (fontStyle)
            settings.fontStyle = fontStyle;
        return { scope, settings };
    };

    const tokenColors = [
        tc(["comment", "punctuation.definition.comment"], comment, "italic"),
        tc(["string", "string.quoted", "constant.other.symbol"], green),
        tc(["string.regexp", "constant.character.escape"], peach),
        tc(["constant.numeric", "constant.language", "keyword.other.unit"], peach),
        tc(["constant.language.boolean", "constant.language.null", "constant.language.undefined"], peach),
        tc(["variable", "variable.other", "meta.definition.variable.name", "support.variable"], fg),
        tc(["variable.parameter", "variable.parameter.function"], pick("maroon", "peach")),
        tc(["variable.language", "variable.language.this", "keyword.other.self"], red),
        tc(["keyword", "keyword.control", "storage", "storage.modifier"], mauve),
        tc(["storage.type", "keyword.type"], yellow),
        tc(["keyword.operator", "punctuation.accessor"], sky),
        tc(["entity.name.function", "support.function", "meta.function-call.generic"], blue),
        tc(["entity.name.type", "entity.name.class", "entity.name.namespace", "support.type", "support.class"], yellow),
        tc(["entity.other.inherited-class"], yellow, "italic"),
        tc(["entity.name.tag", "punctuation.definition.tag"], blue),
        tc(["entity.other.attribute-name"], yellow),
        tc(["support.type.property-name", "meta.object-literal.key", "variable.object.property"], lavender),
        tc(["punctuation", "meta.brace", "punctuation.separator", "punctuation.terminator"], fgDim),
        tc(["constant.character", "constant.other"], peach),
        tc(["markup.heading", "markup.heading entity.name"], blue, "bold"),
        tc(["markup.bold"], peach, "bold"),
        tc(["markup.italic"], mauve, "italic"),
        tc(["markup.inline.raw", "markup.fenced_code"], green),
        tc(["markup.underline.link", "markup.underline.link.image"], sapphire),
        tc(["invalid", "invalid.illegal"], red),
        tc(["tag.decorator", "meta.decorator", "punctuation.decorator"], blue, "italic")
    ];

    return {
        $schema: "vscode://schemas/color-theme",
        name: "Caelestia" + (scheme.name ? " (" + scheme.name + ")" : ""),
        type: isLight ? "light" : "dark",
        semanticHighlighting: true,
        colors,
        tokenColors
    };
}

function writeTheme(schemePath) {
    const theme = buildTheme(readScheme(schemePath || defaultSchemePath()));
    fs.mkdirSync(path.dirname(THEME_PATH), { recursive: true });
    fs.writeFileSync(THEME_PATH, JSON.stringify(theme, null, 4));
    return theme;
}

function activate(context) {
    const vscode = require("vscode");

    const schemePath = () => {
        const override = vscode.workspace.getConfiguration("caelestia").get("schemePath");
        return override && override.trim() ? override.trim().replace(/^~/, os.homedir()) : defaultSchemePath();
    };

    const rebuild = () => {
        try {
            writeTheme(schemePath());
        } catch (e) {
            console.error("[caelestia] theme rebuild failed:", e.message);
        }
    };

    // Build once on activation so the theme reflects the current scheme immediately.
    rebuild();

    context.subscriptions.push(
        vscode.commands.registerCommand("caelestia.applyTheme", () =>
            vscode.workspace
                .getConfiguration("workbench")
                .update("colorTheme", "Caelestia", vscode.ConfigurationTarget.Global))
    );
    context.subscriptions.push(
        vscode.commands.registerCommand("caelestia.rebuildTheme", rebuild)
    );

    // First-run convenience: make Caelestia the active theme once (never override again).
    if (vscode.workspace.getConfiguration("caelestia").get("autoApply") && !context.globalState.get("caelestia.applied")) {
        vscode.commands.executeCommand("caelestia.applyTheme");
        context.globalState.update("caelestia.applied", true);
    }

    // Poll-watch the scheme file (survives the atomic write+rename the CLI uses).
    let current = schemePath();
    fs.watchFile(current, { interval: 500 }, (curr, prev) => {
        if (curr.mtimeMs !== prev.mtimeMs)
            rebuild();
    });
    context.subscriptions.push({ dispose: () => fs.unwatchFile(current) });
}

function deactivate() {}

module.exports = { activate, deactivate, buildTheme, writeTheme, defaultSchemePath };

// One-shot CLI generation: `node extension.js [schemePath]`
if (require.main === module) {
    const out = writeTheme(process.argv[2]);
    console.log("Wrote " + THEME_PATH + " (" + out.type + ", " + Object.keys(out.colors).length + " colours)");
}
