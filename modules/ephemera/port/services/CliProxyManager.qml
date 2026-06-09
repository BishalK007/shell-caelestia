pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// Manages a local CLIProxyAPI instance on demand (mirrors OllamaManager): it
// generates a config, starts `cli-proxy-api` when a provider is in "login/proxy"
// auth mode, and runs the one-shot OAuth login flows (--login/--codex-login/
// --claude-login) which open the browser and write credentials to auth-dir. The
// running server watches auth-dir and picks up new logins live.
//
// Startup is sequenced (key → config → server/login) so a login never runs
// before its config (which defines auth-dir) exists.
Item {
    id: root

    readonly property int port: 8317
    readonly property string baseUrl: "http://127.0.0.1:" + port
    readonly property string stateDir: `${Paths.state}/cliproxy`
    readonly property string configPath: `${stateDir}/config.yaml`
    readonly property string authDir: `${stateDir}/auths`

    // Local proxy key (clients must send it; generated once, persisted).
    property string proxyKey: ""
    property bool serverRunning: false
    property bool ready: false
    // provider currently being logged in ("" when idle)
    property string loginProvider: ""

    property bool _configReady: false
    property string _pendingLogin: ""

    signal loginStarted(string provider)
    signal loginFinished(string provider, bool ok)

    // OAuth login flag per provider.
    function _loginFlag(provider) {
        if (provider === "gemini")
            return "--login";
        if (provider === "openai")
            return "--codex-login";
        if (provider === "anthropic")
            return "--claude-login";
        return "";
    }
    function loginSupported(provider) {
        return _loginFlag(provider) !== "";
    }

    // Ensure key+config exist and the server is running; optionally queue a login
    // to run once the config is written.
    function _ensure(thenLoginProvider) {
        if (thenLoginProvider)
            _pendingLogin = thenLoginProvider;
        if (!proxyKey) {
            if (!keyGenProc.running)
                keyGenProc.running = true; // → writeConfig → _onConfigWritten
            return;
        }
        if (_configReady)
            _onConfigWritten();
        else
            writeConfig();
    }

    function ensureRunning() {
        _ensure("");
    }

    function runLogin(provider) {
        if (!loginSupported(provider) || loginProc.running)
            return;
        _ensure(provider);
    }

    function writeConfig() {
        if (!proxyKey)
            return;
        var yaml = "host: \"127.0.0.1\"\n"
            + "port: " + port + "\n"
            + "auth-dir: \"" + authDir + "\"\n"
            + "api-keys:\n  - \"" + proxyKey + "\"\n"
            + "remote-management:\n  secret-key: \"\"\n";
        configWriter._yaml = yaml;
        configWriter.command = ["sh", "-c",
            "mkdir -p '" + authDir + "' && cat > '" + configPath + "'"];
        configWriter.running = true;
    }

    function _onConfigWritten() {
        _configReady = true;
        if (!serverProc.running)
            serverProc.running = true;
        pingTimer.restart();
        if (_pendingLogin) {
            var p = _pendingLogin;
            _pendingLogin = "";
            _startLogin(p);
        }
    }

    property double _loginStartMs: 0
    property int _authTries: 0

    function _startLogin(provider) {
        var flag = _loginFlag(provider);
        if (flag === "" || loginProc.running)
            return;
        root.loginProvider = provider;
        root._loginStartMs = Date.now();
        root._authTries = 0;
        // Run in a terminal: after OAuth the CLI prompts interactively on stdin
        // (Gemini login mode / GCP project selection), which needs a TTY. A bare
        // process would block on the prompt forever and never save the credential.
        var inner = "cli-proxy-api --config '" + configPath + "' " + flag
            + "; printf '\\n[Ephemera] Login finished — you can close this window.\\n'; sleep 4";
        loginProc.command = ["kitty", "--title", "Ephemera login", "sh", "-c", inner];
        loginProc.running = true;
        root.loginStarted(provider);
        authWatchTimer.restart();
    }

    // Login succeeds when a credential lands in auth-dir. The one-shot login
    // process itself can linger (e.g. a post-auth step with no TTY), so we don't
    // rely on its exit — we detect the credential (or time out) and reap it.
    function _finishLogin(ok) {
        if (root.loginProvider === "")
            return;
        var p = root.loginProvider;
        root.loginProvider = "";
        authWatchTimer.stop();
        root._authTries = 0;
        if (loginProc.running)
            loginProc.running = false; // reap a lingering one-shot login
        root.loginFinished(p, ok);
        root.ping();
    }

    function ping() {
        if (!proxyKey || pingProc.running)
            return;
        pingProc.command = ["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}",
            "--connect-timeout", "2", "-H", "Authorization: Bearer " + proxyKey,
            baseUrl + "/v1/models"];
        pingProc.running = true;
    }

    // ── Persisted local proxy key ──
    FileView {
        id: keyFile

        path: `${root.stateDir}/proxy-key`
        printErrors: false
        onLoaded: {
            var k = text().trim();
            if (k.length > 0)
                root.proxyKey = k;
        }
    }

    Process {
        id: keyGenProc

        command: ["sh", "-c", "head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40"]
        stdout: StdioCollector {
            onStreamFinished: {
                var k = text.trim();
                if (k.length < 8)
                    k = "caelestia-ephemera-local-proxy-key";
                root.proxyKey = k;
                keyFile.setText(k);
                root.writeConfig();
            }
        }
    }

    Process {
        id: configWriter

        property string _yaml: ""
        stdinEnabled: true
        onRunningChanged: {
            if (running && _yaml) {
                write(_yaml);
                stdinEnabled = false;
                _yaml = "";
            }
        }
        onExited: code => {
            if (code === 0)
                root._onConfigWritten();
        }
    }

    Process {
        id: serverProc

        command: ["cli-proxy-api", "--config", root.configPath]
        onRunningChanged: {
            root.serverRunning = running;
            if (!running)
                root.ready = false;
        }
    }

    Process {
        id: loginProc

        onExited: code => root._finishLogin(code === 0)
    }

    // Polls auth-dir for a credential file created after the login started.
    Process {
        id: authCheckProc

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    root._finishLogin(true);
            }
        }
    }

    Timer {
        id: authWatchTimer

        interval: 1500
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root.loginProvider === "") {
                stop();
                return;
            }
            root._authTries++;
            if (root._authTries > 80) { // ~2 min backstop
                root._finishLogin(false);
                return;
            }
            if (!authCheckProc.running) {
                // -1s so a credential written in the same second still counts.
                var startSec = Math.floor(root._loginStartMs / 1000) - 1;
                authCheckProc.command = ["sh", "-c",
                    "find '" + root.authDir + "' -maxdepth 1 -type f -newermt @" + startSec + " 2>/dev/null | head -1"];
                authCheckProc.running = true;
            }
        }
    }

    Process {
        id: pingProc

        stdout: StdioCollector {
            onStreamFinished: root.ready = text.trim() === "200"
        }
    }

    Timer {
        id: pingTimer

        interval: 1000
        repeat: true
        triggeredOnStart: false
        property int _tries: 0
        onTriggered: {
            root.ping();
            _tries++;
            if (root.ready || _tries > 20) {
                stop();
                _tries = 0;
            }
        }
    }

    Component.onCompleted: keyFile.reload()

    Component.onDestruction: {
        if (serverProc.running)
            serverProc.running = false;
    }
}
