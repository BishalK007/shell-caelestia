pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// Browser launcher: installed browsers + Chromium-family profiles (from Local State).
// Favourites are pinned (sorted first) and persisted to a state file.
Singleton {
    id: root

    // Launcher prefix that switches into browser mode
    readonly property string prefix: ">browser "

    property var browsers: [] // [{ bin, name, icon }]
    property var chromeProfiles: [] // [{ dir, name, picture }]
    property var heliumProfiles: [] // [{ dir, name, picture }]
    property var favs: [] // [id]

    // Combined entries: [{ id, name, subtitle, icon, command }]
    // Profiles are only listed while their browser binary is installed —
    // leftover config dirs from uninstalled browsers would otherwise show
    // ghost entries that fail to launch.
    readonly property var items: {
        const out = [];
        const bins = browsers.map(b => b.bin);
        for (const b of browsers)
            out.push({
                id: `browser:${b.bin}`,
                name: b.name,
                subtitle: qsTr("Browser"),
                icon: b.icon,
                picture: "",
                command: [b.bin]
            });
        if (bins.includes("google-chrome-stable"))
            for (const p of chromeProfiles)
                out.push({
                    id: `chrome:${p.dir}`,
                    name: p.name,
                    subtitle: qsTr("Chrome — %1").arg(p.dir),
                    icon: "google-chrome",
                    picture: p.picture,
                    command: ["google-chrome-stable", `--profile-directory=${p.dir}`]
                });
        if (bins.includes("helium"))
            for (const p of heliumProfiles)
                out.push({
                    id: `helium:${p.dir}`,
                    name: p.name,
                    subtitle: qsTr("Helium — %1").arg(p.dir),
                    icon: "helium",
                    picture: p.picture,
                    command: ["helium", `--profile-directory=${p.dir}`]
                });
        return out;
    }

    function query(search: string): var {
        const s = (search.startsWith(prefix) ? search.slice(prefix.length) : search).trim().toLowerCase();
        const list = s ? items.filter(e => `${e.name} ${e.subtitle}`.toLowerCase().includes(s)) : items;
        // Favourites first (stable otherwise)
        return [...list].sort((a, b) => (favs.includes(b.id) ? 1 : 0) - (favs.includes(a.id) ? 1 : 0));
    }

    function launch(entry: var): void {
        if (entry && entry.command)
            Quickshell.execDetached(entry.command);
    }

    function toggleFav(id: string): void {
        favs = favs.includes(id) ? favs.filter(x => x !== id) : [...favs, id];
        favFile.setText(JSON.stringify(favs));
    }

    function reload(): void {
        browsersProc.running = true;
        chromeState.reload();
        heliumState.reload();
    }

    // Parse a Chromium-family "Local State" JSON into [{ dir, name, picture }]
    function parseChromiumProfiles(jsonText: string, configDir: string): var {
        const ic = JSON.parse(jsonText)?.profile?.info_cache ?? ({});
        const raw = [];
        for (const dir in ic) {
            const v = ic[dir] ?? ({});
            raw.push({
                dir,
                name: v.name || dir,
                gaia_name: v.gaia_name || "",
                user_name: v.user_name || "",
                picture_file: (v.is_using_custom_avatar && v.custom_avatar_picture_file_name) || v.gaia_picture_file_name || ""
            });
        }
        resolveDisplayNames(raw);
        const out = raw.map(p => ({
            dir: p.dir,
            name: p.display,
            picture: p.picture_file ? `${Paths.home}/.config/${configDir}/${p.dir}/${p.picture_file}` : ""
        }));
        out.sort((a, b) => a.name.localeCompare(b.name));
        return out;
    }

    // Port of the elephant chromeprofiles dedup:
    // name -> "name [gaia_name]" -> "name [gaia_name] [user_name]" -> "... [n]"
    function resolveDisplayNames(profiles: var): void {
        const byName = {};
        for (const p of profiles) {
            if (!byName[p.name])
                byName[p.name] = [];
            byName[p.name].push(p);
        }
        for (const name in byName) {
            const group = byName[name];
            if (group.length === 1) {
                group[0].display = name;
                continue;
            }
            const byGaia = {};
            for (const p of group) {
                const k = `${name} [${p.gaia_name || ""}]`;
                if (!byGaia[k])
                    byGaia[k] = [];
                byGaia[k].push(p);
            }
            for (const k in byGaia) {
                const sub = byGaia[k];
                if (sub.length === 1) {
                    sub[0].display = k;
                    continue;
                }
                const byUser = {};
                for (const p of sub) {
                    const uk = `${k} [${p.user_name || ""}]`;
                    if (!byUser[uk])
                        byUser[uk] = [];
                    byUser[uk].push(p);
                }
                for (const uk in byUser) {
                    const fin = byUser[uk];
                    if (fin.length === 1)
                        fin[0].display = uk;
                    else
                        for (let i = 0; i < fin.length; i++)
                            fin[i].display = `${uk} [${i + 1}]`;
                }
            }
        }
    }

    Component.onCompleted: reload()

    // Detect installed browser binaries
    Process {
        id: browsersProc

        command: ["sh", "-c", 'for b in firefox brave google-chrome-stable chromium vivaldi-stable librewolf microsoft-edge-stable qutebrowser zen zen-beta helium; do command -v "$b" >/dev/null 2>&1 && echo "$b"; done']
        stdout: StdioCollector {
            onStreamFinished: {
                const names = {
                    "firefox": "Firefox",
                    "brave": "Brave",
                    "google-chrome-stable": "Chrome",
                    "chromium": "Chromium",
                    "vivaldi-stable": "Vivaldi",
                    "librewolf": "LibreWolf",
                    "microsoft-edge-stable": "Edge",
                    "qutebrowser": "qutebrowser",
                    "zen": "Zen",
                    "zen-beta": "Zen",
                    "helium": "Helium"
                };
                const icons = {
                    "firefox": "firefox",
                    "brave": "brave-browser",
                    "google-chrome-stable": "google-chrome",
                    "chromium": "chromium",
                    "vivaldi-stable": "vivaldi",
                    "librewolf": "librewolf",
                    "microsoft-edge-stable": "microsoft-edge",
                    "qutebrowser": "qutebrowser",
                    "zen": "zen-browser",
                    "zen-beta": "zen-browser",
                    "helium": "helium"
                };
                const out = [];
                for (const line of text.split("\n")) {
                    const b = line.trim();
                    if (b)
                        out.push({
                            bin: b,
                            name: names[b] ?? b,
                            icon: icons[b] ?? b
                        });
                }
                root.browsers = out;
            }
        }
    }

    // Chrome profiles from Local State (JSON)
    FileView {
        id: chromeState

        printErrors: false
        path: `${Paths.home}/.config/google-chrome/Local State`
        onLoaded: {
            try {
                root.chromeProfiles = root.parseChromiumProfiles(text(), "google-chrome");
            } catch (e) {
                root.chromeProfiles = [];
            }
        }
        onLoadFailed: root.chromeProfiles = []
    }

    // Helium profiles from Local State (JSON)
    FileView {
        id: heliumState

        printErrors: false
        path: `${Paths.home}/.config/net.imput.helium/Local State`
        onLoaded: {
            try {
                root.heliumProfiles = root.parseChromiumProfiles(text(), "net.imput.helium");
            } catch (e) {
                root.heliumProfiles = [];
            }
        }
        onLoadFailed: root.heliumProfiles = []
    }

    // Persisted favourites
    FileView {
        id: favFile

        printErrors: false
        path: `${Paths.state}/browser-favourites.json`
        onLoaded: {
            try {
                root.favs = JSON.parse(text()) ?? [];
            } catch (e) {
                root.favs = [];
            }
        }
        onLoadFailed: root.favs = []
    }
}
