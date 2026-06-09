pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// DMS-compat PluginService shim — Ephemera persists its settings + (optional)
// chat history through load/savePluginData. Backed by a JSON state file.
Singleton {
    id: root

    property var _data: ({})
    property bool _loaded: false

    signal pluginDataChanged(string pId)

    function loadPluginData(pluginId, key, def) {
        const p = root._data[pluginId];
        if (p && p[key] !== undefined && p[key] !== null)
            return p[key];
        return def;
    }

    function savePluginData(pluginId, key, value) {
        const d = root._data || ({});
        if (!d[pluginId])
            d[pluginId] = ({});
        d[pluginId][key] = value;
        root._data = d;
        file.setText(JSON.stringify(d));
        // Chat persistence churns frequently while streaming — don't trigger a
        // settings reload for it; only signal genuine setting changes.
        if (key !== "chatHistory" && key !== "chatVariants")
            root.pluginDataChanged(pluginId);
    }

    FileView {
        id: file

        path: `${Paths.state}/ephemera-plugin.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root._data = JSON.parse(text()) || ({});
            } catch (e) {
                root._data = ({});
            }
            root._loaded = true;
        }
        onLoadFailed: root._loaded = true
    }
}
