pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// DMS-compat I18n shim — Ephemera only reads isRtl and tr(). No translation
// catalogue: tr() returns the key verbatim (English source strings).
Singleton {
    id: root

    readonly property bool isRtl: false

    function tr(key) {
        return key;
    }
}
