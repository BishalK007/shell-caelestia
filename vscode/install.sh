#!/usr/bin/env bash
# Install the Caelestia VS Code integration into every editor fork found on this
# machine. Copies (not symlinks) the extension into each editor's extensions dir
# so the extension's runtime theme writes never touch this repo's working tree.
#
# Re-run after pulling changes to the extension. After installing, reload the
# editor window ONCE (Developer: Reload Window) so it registers the new
# extension; thereafter colours update live with no reload.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/caelestia-vscode-integration" && pwd)"
NAME="caelestia.caelestia-vscode-integration-1.0.0"

# editor extension dirs (MS Code, code-oss/VSCodium, Insiders, Cursor, Windsurf)
CANDIDATES=(
    "$HOME/.vscode/extensions"
    "$HOME/.vscode-oss/extensions"
    "$HOME/.vscode-insiders/extensions"
    "$HOME/.cursor/extensions"
    "$HOME/.windsurf/extensions"
)

# pick a node runner: prefer one on PATH, else go through nix
node_run() {
    if command -v node >/dev/null 2>&1; then
        node "$@"
    elif command -v nix >/dev/null 2>&1; then
        nix shell nixpkgs#nodejs --command node "$@"
    else
        return 1
    fi
}

installed=0
for extdir in "${CANDIDATES[@]}"; do
    # only install where the editor actually has an extensions dir (or its parent exists)
    parent="$(dirname "$extdir")"
    [ -d "$extdir" ] || [ -d "$parent" ] || continue

    mkdir -p "$extdir"
    # drop any previous version, then copy fresh
    rm -rf "$extdir"/caelestia.caelestia-vscode-integration-*
    target="$extdir/$NAME"
    cp -r "$SRC" "$target"

    # best-effort: regenerate the theme from the current scheme in the installed copy
    ( cd "$target" && node_run extension.js >/dev/null 2>&1 ) || true

    echo "installed -> $target"
    installed=$((installed + 1))
done

if [ "$installed" -eq 0 ]; then
    # no editor found yet: default to plain VS Code so a later install of Code works
    mkdir -p "$HOME/.vscode/extensions/$NAME"
    cp -r "$SRC/." "$HOME/.vscode/extensions/$NAME/"
    echo "no editor dir found; staged into ~/.vscode/extensions/$NAME"
fi

echo
echo "Next: reload your editor window once (Ctrl+Shift+P -> Developer: Reload Window)."
echo "The 'Caelestia' theme will be applied automatically on first run; after that,"
echo "colours update live whenever the shell regenerates its scheme."
