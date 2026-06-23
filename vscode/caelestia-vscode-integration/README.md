# Caelestia VS Code integration

A live VS Code colour theme driven by the Caelestia shell's generated palette.

## How it works

The shell's CLI writes the active Material-3 scheme to
`$XDG_STATE_HOME/caelestia/scheme.json` (default
`~/.local/state/caelestia/scheme.json`) — the same file the QML shell watches.

This extension contributes a colour theme named **Caelestia**. On activation it
reads `scheme.json` and regenerates its own `themes/caelestia.json`, then
`fs.watchFile`s the scheme. Whenever the shell changes the scheme, the theme
file is rewritten. Because that file is the *active* registered theme (and the
contribution carries the private `"_watch": true` flag), VS Code re-reads it and
re-applies colours **live — no window reload**.

No shell changes are required: the extension is a passive consumer of the same
`scheme.json` the shell already produces.

## Install

```sh
../install.sh
```

This copies the extension into every editor fork found (`Code`, `code-oss` /
`VSCodium`, `Code - Insiders`, `Cursor`, `Windsurf`). Reload the editor window
once afterwards; the theme is then applied automatically and updates live.

To install manually for one editor:

```sh
cp -r caelestia-vscode-integration ~/.vscode/extensions/caelestia.caelestia-vscode-integration-1.0.0
```

## Settings

- `caelestia.autoApply` (default `true`) — set Caelestia as the active theme the
  first time the extension activates.
- `caelestia.schemePath` (default empty) — override the scheme.json location.

## Commands

- **Caelestia: Apply Theme** — set `workbench.colorTheme` to `Caelestia`.
- **Caelestia: Rebuild Theme From Scheme** — force-regenerate from `scheme.json`.

## Colour mapping

Workbench chrome uses the M3 surface/primary roles; syntax tokens use the
Catppuccin-named accents (`red`, `green`, `yellow`, `blue`, `mauve`, `peach`,
`teal`, …) and the integrated terminal uses `term0`–`term15`. Light vs dark is
taken from the scheme's `mode` field. The mapping lives in `extension.js`
(`buildTheme`); regenerate a theme standalone with `node extension.js`.
