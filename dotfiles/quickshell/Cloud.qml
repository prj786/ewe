pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Cloud — THE ewe account: the user's own Nextcloud (RFC-005). Identity,
// settings sync of the one file, the restore offer, the calendar and the
// account-as-a-folder all hang off this singleton; Google.qml is now only
// the optional Gmail + Drive extra. The broker is bin/ewe-cloud (login flow
// v2, app password in the keyring); the sync engine is bin/ewe-conf
// (WebDAV with the server's own If-Match guard); the folder is bin/ewe-files.
// This file never sees the app password — only what the tools print.
QtObject {
    id: cl

    // ── account state ──────────────────────────────────────────────────────────
    property bool probed: false          // first status probe finished
    property bool signedIn: false
    property bool offline: false         // signed in, but the server did not answer the last probe
    property string server: ""
    property string user: ""
    property string loginName: ""        // what the server calls the account (login flow's loginName)
    property string displayName: ""
    property string email: ""
    property var quota: null             // { used, total, relative } bytes / percent
    property string avatarPath: ""       // ~/.cache/ewe/cloud-avatar.png once fetched
    property string busy: ""             // "" | "signin" | "keyring-reset"
    property string error: ""            // last account-level error, human-readable
    property string errorCode: ""        // the helper's machine code behind `error`
    property string reason: ""           // signed-out reason from status (revoked, keyring-locked, …)
    property string loginUrl: ""         // the sign-in page of the login in flight / that just failed
    property string lastServer: ""       // remembered between attempts (cloud-sync.json)
    readonly property string serverHost: server.replace(/^https?:\/\//, "").replace(/\/.*$/, "")
    readonly property string helper: Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-cloud"
    readonly property string eweConf: Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-conf"
    readonly property string eweFiles: Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-files"
    readonly property string eweCaldav: Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-caldav"
    readonly property string authHelper: Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-auth"

    // ── keyring (the same playbook Google.qml learnt on the first metal install)
    property bool keyringOk: true
    property string keyringState: "ok"   // ok | missing | locked | unavailable
    property bool keyringResetDone: false
    readonly property bool keyringTrouble: keyringState === "locked" || errorCode.indexOf("keyring-") === 0
    readonly property bool keyringPromptExpected: keyringState === "missing" || keyringState === "locked"
    function resetKeyring() { if (cl.busy === "") { cl.busy = "keyring-reset"; _resetProc.running = false; _resetProc.running = true } }
    function logOut() { Quickshell.execDetached(["sh", "-c", "exec \"$HOME/.config/hypr/scripts/power.sh\" logout"]) }
    property Process _resetProc: Process {
        command: ["python3", cl.authHelper, "keyring-reset"]
        stdout: StdioCollector {
            onStreamFinished: {
                cl.busy = ""
                try {
                    var j = JSON.parse(this.text)
                    if (j.ok) {
                        cl.signedIn = false; cl.keyringState = "missing"; cl.errorCode = ""
                        cl.keyringResetDone = !!j.relogin
                        cl.error = j.relogin ? String(j.message) : ""
                    } else cl.error = j.message ? String(j.message) : ("Keyring reset failed: " + j.error)
                } catch (e) { cl.error = "Keyring reset failed — could not parse the helper output." }
            }
        }
    }
    function openLoginUrl() { if (cl.loginUrl !== "") Quickshell.execDetached(["xdg-open", cl.loginUrl]) }
    function copyLoginUrl() { if (cl.loginUrl !== "") Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "sh", cl.loginUrl]) }

    signal sessionReady()                // sign-in landed, or already signed in at startup
    signal sessionClosed()               // sign-out / server-side revocation

    function refresh() { _statusProc.running = false; _statusProc.running = true }

    // ── IPC for the standalone Settings app ───────────────────────────────────
    // ewe-settings drives the account from out of process: verbs in, a JSON
    // snapshot out. Public API — a shipped binary depends on these names.
    property IpcHandler _ipc: IpcHandler {
        target: "cloud"
        function signIn(server: string): void { cl.signIn(server) }
        function cancelSignIn(): void { cl.cancelSignIn() }
        function signOut(): void { cl.signOut() }
        function keyringReset(): void { cl.resetKeyring() }
        function openLoginUrl(): void { cl.openLoginUrl() }
        function copyLoginUrl(): void { cl.copyLoginUrl() }
        function logOut(): void { cl.logOut() }
        function syncNow(): void { cl.syncNow() }
        function backUpNow(): void { cl.backUpNow() }
        function pushForce(): void { cl.pushForce() }
        function requestRestore(): void { cl.requestRestore() }
        function applyRestore(): void { cl.applyRestore() }
        function cancelRestore(): void { cl.cancelRestore() }
        function syncSoon(): void { cl.syncSoon() }
        function refresh(): void { cl.refresh() }
        function setAutoSync(on: bool): void { cl.setAutoSync(on) }
        function status(): string {
            return JSON.stringify({
                probed: cl.probed, signedIn: cl.signedIn, offline: cl.offline,
                server: cl.server, serverHost: cl.serverHost, user: cl.user,
                displayName: cl.displayName, email: cl.email, quota: cl.quota, avatarPath: cl.avatarPath,
                busy: cl.busy, error: cl.error, errorCode: cl.errorCode, reason: cl.reason,
                loginUrl: cl.loginUrl, lastServer: cl.lastServer,
                keyringOk: cl.keyringOk, keyringState: cl.keyringState, keyringTrouble: cl.keyringTrouble,
                keyringResetDone: cl.keyringResetDone,
                syncState: cl.syncState, syncError: cl.syncError, syncConflict: cl.syncConflict, inSync: cl.inSync,
                lastSync: cl.lastSync, localSyncedAt: cl.localSyncedAt, autoSync: cl.autoSync,
                remoteMachine: cl.cloudInfo ? String(cl.cloudInfo.device || "") : "",
                remoteModified: cl.cloudInfo ? String(cl.cloudInfo.updatedAt || "") : "",
                restoreSummary: cl.restoreSummary, restoreApps: cl.restoreApps, pendingRestore: cl.pendingRestore,
                filesMounted: cl.filesMounted, filesPath: cl.filesPath, filesApp: cl.filesApp, loginName: cl.loginName,
                calState: cl.calState, eventCount: cl.events.length
            })
        }
    }

    // ── status probe ───────────────────────────────────────────────────────────
    property Process _statusProc: Process {
        running: true
        command: ["python3", cl.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    cl.keyringOk = j.keyring !== false
                    if (j.keyring_state) cl.keyringState = String(j.keyring_state)
                    var was = cl.signedIn
                    cl.signedIn = !!j.signed_in
                    cl.offline = !!j.offline
                    cl.reason = j.reason ? String(j.reason) : ""
                    if (cl.signedIn) {
                        cl.server = String(j.server || ""); cl.user = String(j.user || ""); cl.loginName = String(j.login_name || j.user || "")
                        cl.displayName = String(j.display_name || j.user || ""); cl.email = String(j.email || "")
                        cl.quota = j.quota || null
                        if (cl.server !== "") cl.lastServer = cl.server
                    }
                    if (cl.signedIn && !was) cl.sessionReady()
                    else if (!cl.signedIn && was) cl.sessionClosed()
                } catch (e) { /* the helper always prints JSON; garbage = signed out */ }
                cl.probed = true
                // right after boot the probe can race gnome-keyring coming up
                if (!cl.signedIn && cl.reason === "keyring-locked" && cl._probeRetries < 3) {
                    cl._probeRetries++
                    cl._probeRetry.interval = 5000 * cl._probeRetries
                    cl._probeRetry.restart()
                }
            }
        }
    }
    property int _probeRetries: 0
    property Timer _probeRetry: Timer { onTriggered: { if (!cl.signedIn) cl.refresh() } }

    function refreshAfterResume() {
        if (!cl.signedIn) { cl._probeRetries = 0; cl.refresh(); return }
        cl.refresh(); cl.fetchCalendar(); cl.checkCloud()
    }

    // ── sign in / out ──────────────────────────────────────────────────────────
    function signIn(server) {
        if (cl.busy === "signin") return
        var s = String(server || cl.lastServer || "").trim()
        if (s === "") { cl.error = "Enter the address of your Nextcloud, e.g. cloud.example.org."; cl.errorCode = "no-server"; return }
        cl.error = ""; cl.errorCode = ""; cl.loginUrl = ""; cl.reason = ""
        cl.lastServer = s; cl._saveSyncMeta()
        cl.busy = "signin"
        _loginProc.command = ["python3", cl.helper, "login", s]
        _loginProc.running = false; _loginProc.running = true
    }
    function cancelSignIn() {
        if (cl.busy !== "signin") return
        _loginProc.running = false
        cl.busy = ""
    }
    property Process _loginProc: Process {
        // the login link rides on stderr the moment it exists — long before
        // the JSON result — so "open / copy the link" works while waiting
        stderr: StdioCollector {
            onStreamFinished: {
                var ls = this.text.split("\n")
                for (var i = 0; i < ls.length; i++)
                    if (ls[i].indexOf("login-url: ") === 0) cl.loginUrl = ls[i].slice(11).trim()
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (cl.busy === "signin") cl.busy = ""
                if (this.text.trim() === "") return   // cancelled
                try {
                    var j = JSON.parse(this.text)
                    if (j.login_url) cl.loginUrl = String(j.login_url)
                    if (j.keyring) cl.keyringState = String(j.keyring)
                    if (j.ok) {
                        cl.server = String(j.server || ""); cl.user = String(j.user || ""); cl.loginName = String(j.login_name || j.user || "")
                        cl.displayName = String(j.display_name || j.user || ""); cl.email = String(j.email || "")
                        cl.quota = j.quota || null
                        cl.lastServer = cl.server
                        cl.error = ""; cl.errorCode = ""; cl.loginUrl = ""; cl.reason = ""
                        cl.signedIn = true
                        // the one file learns where its backup lives (identity,
                        // never a secret)
                        Quickshell.execDetached(["sh", "-c",
                            '"$0" set --no-hooks sync.provider nextcloud >/dev/null 2>&1; "$0" set --no-hooks sync.server "$1" >/dev/null 2>&1; '
                            + '"$0" set --no-hooks sync.user "$2" >/dev/null 2>&1; "$0" set --no-hooks sync.folder ewe >/dev/null 2>&1',
                            cl.eweConf, cl.server, cl.user])
                        cl.setUpFiles()
                        cl.sessionReady()
                    } else {
                        cl.errorCode = String(j.error || "")
                        cl.error = cl._loginErrMsg(j.error, j.message)
                        Log.warn("cloud", "sign-in failed:", j.error, j.message || "")
                    }
                } catch (e) { cl.error = "Sign-in failed — could not parse the helper output." }
            }
        }
    }
    function _loginErrMsg(e, detail) {
        if (e === "no-server") return "Enter the address of your Nextcloud, e.g. cloud.example.org."
        if (e === "insecure-server") return "Only https:// servers are accepted."
        if (e === "not-nextcloud") return "That address did not answer like a Nextcloud — use the one you open in the browser, without /index.php/…"
        if (e === "timeout") return "Sign-in timed out — no answer from the browser within 5 minutes. Use “Open the sign-in page” if no tab appeared."
        if (e === "network") return detail ? String(detail) : "The server could not be reached."
        if (e === "keyring-unavailable") return "No Secret Service keyring is running — gnome-keyring must be installed and started for this session."
        if (e === "keyring-cancelled") return "The keyring prompt was dismissed — sign in again and unlock the keyring with your login password. If it keeps rejecting that password, reset the keyring."
        if (e === "keyring-timeout") return "The keyring did not answer — if a keyring password prompt is open, answer it with your login password, then sign in again. If it keeps rejecting that password, reset the keyring."
        if (e === "keyring-store-failed") return detail ? String(detail) : "The keyring refused to store the app password — see Troubleshooting → keyring."
        if (detail) return String(detail)
        return "Sign-in failed: " + e
    }

    function signOut() {
        _logoutProc.running = false; _logoutProc.running = true
        cl.signedIn = false; cl.displayName = ""; cl.email = ""; cl.quota = null; cl.avatarPath = ""
        cl.error = ""; cl.errorCode = ""; cl.reason = ""
        cl.sessionClosed()
    }
    property Process _logoutProc: Process {
        // revoke server-side + keyring, unmount + forget the folder, and the
        // one file stops syncing (its [sync] identity stays for a re-login)
        command: ["sh", "-c",
            'python3 "$0" logout >/dev/null 2>&1; "$1" unmount >/dev/null 2>&1; "$1" forget >/dev/null 2>&1; "$2" set --no-hooks sync.enabled false >/dev/null 2>&1',
            cl.helper, cl.eweFiles, cl.eweConf]
    }

    // ── avatar + the account as a folder ─────────────────────────────────────
    // Owner decision (2026-09-02): the official Nextcloud desktop client is
    // the files path. After sign-in the SAME account is handed to it through
    // its login URL scheme — the app password from the broker, argv only —
    // and it syncs ~/Nextcloud from then on. bin/ewe-files (rclone mount) is
    // only the fallback for a box without the client.
    property bool filesApp: false        // /usr/bin/nextcloud is there
    property Process _filesAppProbe: Process {
        running: true
        command: ["sh", "-c", '[ -x /usr/bin/nextcloud ] && echo yes || echo no']
        stdout: StdioCollector { onStreamFinished: cl.filesApp = this.text.indexOf("yes") === 0 }
    }
    function setUpFiles() { _tokenProc.running = false; _tokenProc.running = true }
    property Process _tokenProc: Process {
        command: ["python3", cl.helper, "token", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                var j = null
                try { j = JSON.parse(this.text) } catch (e) {}
                if (!j || !j.ok || !j.token) { Log.warn("cloud", "files: no app password for the client hand-off"); return }
                if (cl.filesApp) {
                    // the client registers nextcloud:// and completes its account
                    // setup from this URL; the password never touches a shell
                    Quickshell.execDetached(["xdg-open", "nextcloud://login/server:" + cl.server + "&user:" + (cl.loginName || cl.user) + "&password:" + j.token])
                    Quickshell.execDetached(["sh", "-c",
                        'mkdir -p "$HOME/Nextcloud"; f="$HOME/.config/gtk-3.0/bookmarks"; mkdir -p "$(dirname "$f")"; grep -qs "file://$HOME/Nextcloud" "$f" || printf "file://%s/Nextcloud Nextcloud\n" "$HOME" >> "$f"'])
                    cl.filesMounted = true
                } else {
                    Quickshell.execDetached(["sh", "-c", '"$0" setup >/dev/null 2>&1', cl.eweFiles])
                    cl._filesStatusLater.restart()
                }
            }
        }
    }
    property Timer _filesStatusLater: Timer { interval: 4000; onTriggered: cl.checkFiles() }
    function mountFiles() { if (cl.filesApp) cl.setUpFiles(); else { cl._filesMount.running = false; cl._filesMount.running = true } }
    property Process _avatarProc: Process {
        command: ["python3", cl.helper, "avatar"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { var j = JSON.parse(this.text); cl.avatarPath = j.ok && j.path ? String(j.path) + "?" + Date.now() : "" } catch (e) { cl.avatarPath = "" }
            }
        }
    }
    property bool filesMounted: false
    property string filesPath: Quickshell.env("HOME") + "/Nextcloud"
    property Process _filesStatus: Process {
        command: [cl.eweFiles, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { var j = JSON.parse(this.text); cl.filesMounted = !!j.mounted; if (j.path) cl.filesPath = String(j.path) } catch (e) { cl.filesMounted = false }
            }
        }
    }
    function checkFiles() { _filesStatus.running = false; _filesStatus.running = true }
    property Process _filesMount: Process {
        command: [cl.eweFiles, "mount"]
        onExited: cl.checkFiles()
    }

    property Connections _sessionHooks: Connections {
        target: cl
        function onSessionReady() {
            cl.checkCloud(); cl.fetchCalendar()
            cl._avatarProc.running = false; cl._avatarProc.running = true
            if (cl.filesApp) cl.filesMounted = true   // the client keeps ~/Nextcloud itself
            else { cl._filesMount.running = false; cl._filesMount.running = true }
            // login-time sync catches changes made outside the apps since the
            // last session; the content hash makes it a no-op when nothing moved
            cl.syncSoon()
        }
        function onSessionClosed() {
            cl.cloudInfo = null; cl.pendingRestore = null
            cl.syncState = "idle"; cl.syncError = ""; cl.restoreSummary = ""; cl.syncConflict = false
            cl.events = []; cl.calState = ""; cl.filesMounted = false
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Settings sync — the one file (ewe.conf) in <account>/ewe/, engine: ewe-conf
    // (RFC-002 → RFC-005). The shell keeps the same UI contract (syncState,
    // cloudInfo, lastSync, pendingRestore, restore summary); every verb
    // delegates: push/pull/apply/sync-status. Restore is always explicit.
    // ══════════════════════════════════════════════════════════════════════════
    property string syncState: "idle"    // idle | syncing | error
    property string syncError: ""
    property bool syncConflict: false    // the push was refused (remote-newer / remote-exists)
    property bool inSync: false          // ewe-conf's verdict: the recorded remote version is current
    property string restoreSummary: ""
    property string lastSync: ""         // ISO — last successful push/restore from THIS machine
    property string lastHash: ""         // content hash of the last pushed file (skip no-op pushes)
    property bool autoSync: true         // [sync].enabled — THE switch
    property var cloudInfo: null         // { device, updatedAt } of the copy in the account
    property string localSyncedAt: ""    // ewe-conf's own record: when THIS machine last synced
    property int restoreApps: 0          // apps the last restore left waiting in Komble
    property var pendingRestore: null    // marker awaiting explicit confirmation
    readonly property string syncMetaPath: Quickshell.env("HOME") + "/.config/quickshell/cloud-sync.json"

    property Process _metaLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/cloud-sync.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (j.lastSync) cl.lastSync = j.lastSync
                    if (j.lastHash) cl.lastHash = j.lastHash
                    if (j.lastServer && cl.lastServer === "") cl.lastServer = j.lastServer
                } catch (e) {}
            }
        }
    }
    property Process _metaWriter: Process {}
    function _saveSyncMeta() {
        HyprMon.atomicWrite(cl._metaWriter, cl.syncMetaPath,
            JSON.stringify({ lastSync: cl.lastSync, lastHash: cl.lastHash, lastServer: cl.lastServer }))
    }
    // [sync].enabled is the one auto-sync switch; absent = on (the product
    // promise is "everything I change is synced" — the toggle is the opt-out)
    property Process _enabledLoad: Process {
        running: true
        command: [cl.eweConf, "get", "sync.enabled"]
        stdout: StdioCollector {
            onStreamFinished: { var t = this.text.trim(); if (t === "true" || t === "false") cl.autoSync = (t === "true") }
        }
    }
    function setAutoSync(v) {
        cl.autoSync = v
        Quickshell.execDetached([cl.eweConf, "set", "--no-hooks", "sync.enabled", v ? "true" : "false"])
    }

    property bool _autoPushing: false
    property string _pendingHash: ""
    function syncNow() {
        if (!cl.signedIn || cl.syncState === "syncing") return
        cl.syncState = "syncing"; cl.syncError = ""; cl.restoreSummary = ""; cl.syncConflict = false
        _hashProc.running = false; _hashProc.running = true
    }
    property Process _hashProc: Process {
        command: ["sh", "-c", 'sha256sum "$HOME/.config/ewe/ewe.conf" 2>/dev/null | cut -d" " -f1']
        stdout: StdioCollector {
            onStreamFinished: {
                var h = this.text.trim()
                if (cl._autoPushing && h !== "" && h === cl.lastHash) {
                    cl._autoPushing = false; cl.syncState = "idle"; return
                }
                cl._pendingHash = h
                _pushProc.running = false; _pushProc.running = true
            }
        }
    }
    // after a pull the file IS the remote: record its hash so the watcher
    // does not push it straight back as "a change"
    property Process _recordHash: Process {
        command: ["sh", "-c", 'sha256sum "$HOME/.config/ewe/ewe.conf" 2>/dev/null | cut -d" " -f1']
        stdout: StdioCollector { onStreamFinished: { var h = this.text.trim(); if (h !== "") { cl.lastHash = h; cl._saveSyncMeta() } } }
    }
    property Process _pushProc: Process {
        command: [cl.eweConf, "push"]
        stdout: StdioCollector {
            onStreamFinished: {
                var j = null
                try { j = JSON.parse(this.text) } catch (e) {}
                var wasAuto = cl._autoPushing
                cl._autoPushing = false
                if (j && j.ok) {
                    if (cl._pendingHash) { cl.lastHash = cl._pendingHash; cl._pendingHash = "" }
                    cl.lastSync = new Date().toISOString(); cl._saveSyncMeta()
                    cl.localSyncedAt = j.local_synced_at ? String(j.local_synced_at) : cl.lastSync
                    cl.syncState = "idle"
                    cl.checkCloud()
                } else if (j && (j.error === "remote-newer" || j.error === "remote-exists")) {
                    // the server (If-Match) refused: another machine saved a newer
                    // file, or this never-synced machine found a backup it has not
                    // restored — never clobber either silently
                    var who = j.remote_machine || (j.remote && j.remote.appProperties && j.remote.appProperties.machine) || (cl.cloudInfo && cl.cloudInfo.device) || "another machine"
                    cl.syncState = "error"
                    cl.syncConflict = true
                    cl.syncError = j.error === "remote-exists"
                        ? "A backup from “" + who + "” already exists in your account — restore it first, or push anyway to overwrite it."
                        : "Another machine (“" + who + "”) saved newer settings — restore them, or push anyway to overwrite."
                    cl.checkCloud()
                } else if (j && (j.error === "unauthorized" || j.error === "not-signed-in")) {
                    cl.syncState = "error"; cl.syncError = "The account no longer accepts this machine — sign in again (the app password may have been revoked on the server)."
                    cl.refresh()
                } else if (wasAuto) {
                    cl.syncState = "idle"            // offline is normal; the next debounce retries
                } else cl._syncFail(j && j.error ? j.error : "push failed")
            }
        }
    }
    function pushForce() {
        if (!cl.signedIn || cl.syncState === "syncing") return
        cl.syncState = "syncing"; cl.syncError = ""; cl.syncConflict = false
        _pushForceProc.running = false; _pushForceProc.running = true
    }
    property Process _pushForceProc: Process {
        command: [cl.eweConf, "push", "--force"]
        stdout: StdioCollector {
            onStreamFinished: {
                var j = null
                try { j = JSON.parse(this.text) } catch (e) {}
                if (j && j.ok) {
                    cl.lastSync = new Date().toISOString(); cl._saveSyncMeta()
                    cl.localSyncedAt = j.local_synced_at ? String(j.local_synced_at) : cl.lastSync
                    cl.syncState = "idle"; cl.checkCloud()
                    cl._recordHash.running = false; cl._recordHash.running = true
                } else cl._syncFail(j && j.error ? j.error : "push failed")
            }
        }
    }
    function _syncFail(msg) { cl.syncState = "error"; cl.syncError = "Sync failed: " + msg }

    property var _statusCb: null
    function checkCloud(cb) {
        cl._statusCb = cb || null
        _cloudStatusProc.running = false; _cloudStatusProc.running = true
    }
    property Process _cloudStatusProc: Process {
        command: [cl.eweConf, "sync-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                var j = null
                try { j = JSON.parse(this.text) } catch (e) {}
                var ok = !!(j && j.ok && j.remote)
                cl.cloudInfo = ok ? {
                    device: j.remote_machine || (j.remote.appProperties && j.remote.appProperties.machine) || "your account",
                    updatedAt: j.remote_modified || j.remote.modifiedTime || ""
                } : null
                if (j && j.local_synced_at) cl.localSyncedAt = String(j.local_synced_at)
                if (j && j.in_sync !== undefined) cl.inSync = !!j.in_sync
                var cb = cl._statusCb; cl._statusCb = null
                if (cb) cb(ok)
                if (ok) cl._maybeOfferRestore()
            }
        }
    }

    // ── first-login restore offer — "log in, get your machine back" ─────────
    property bool _restoreOffered: false
    function _maybeOfferRestore() {
        if (cl._restoreOffered || cl.lastSync !== "" || !cl.cloudInfo) return
        cl._restoreOffered = true
        cl.pendingRestore = { updatedAt: cl.cloudInfo.updatedAt, device: cl.cloudInfo.device }
        if (!Globals.welcomeOpen)
            Quickshell.execDetached(["notify-send", "-a", "ewe", "-i", "cloud",
                "Restore this machine?",
                "A backup from “" + cl.cloudInfo.device + "” is in your account — open Settings → Account to bring your desktop and apps back."])
    }

    // ── auto-sync: NEVER from a never-synced machine, nor while a restore is
    // on offer or the Welcome flow is up (the first metal install: a fresh
    // near-empty file went up and the restore pulled it back down)
    function autoPushAllowed() {
        return cl.autoSync && cl.signedIn && cl.lastSync !== ""
            && cl.pendingRestore === null && !Globals.welcomeOpen
    }
    property Connections _autoHook: Connections {
        target: Globals
        function onSettingsOpenChanged() { if (!Globals.settingsOpen && cl.autoPushAllowed()) cl._autoPushTimer.restart() }
    }
    // Komble and ewe-settings no longer poke the shell after a write: the one
    // file itself is the signal. Every change to ewe.conf — an install, a
    // Settings write, ewe-conf from a terminal — lands here, debounced.
    property FileView _confWatch: FileView {
        path: Quickshell.env("HOME") + "/.config/ewe/ewe.conf"
        watchChanges: true
        printErrors: false
        onFileChanged: cl.syncSoon()
    }
    function syncSoon() {
        if (!cl.autoPushAllowed()) return
        cl._autoPushTimer.restart()
    }
    property Timer _autoPushTimer: Timer {
        interval: 20000
        onTriggered: { if (cl.autoPushAllowed() && cl.syncState !== "syncing") { cl._autoPushing = true; cl.syncNow() } }
    }
    function backUpNow() { cl.syncNow() }

    // ── restore (explicit, confirmed): pull the file, apply, reload ──────────
    function requestRestore() {
        cl.restoreSummary = ""; cl.syncError = ""
        cl.checkCloud(function (ok) {
            if (ok) cl.pendingRestore = { updatedAt: cl.cloudInfo.updatedAt, device: cl.cloudInfo.device }
            else { cl.syncState = "error"; cl.syncError = "No backup found in this account." }
        })
    }
    function cancelRestore() { cl.pendingRestore = null }
    function applyRestore() {
        if (!cl.pendingRestore) return
        cl.pendingRestore = null
        cl.syncState = "syncing"
        _restoreProc.running = false; _restoreProc.running = true
    }
    property Process _restoreProc: Process {
        // pull writes ewe.conf (timestamped backup of the old one); apply WITH
        // hooks re-themes, pokes the shell and reloads Hyprland
        command: ["sh", "-c", '"$0" pull && "$0" apply --no-hooks', cl.eweConf]
        stdout: StdioCollector {
            onStreamFinished: {
                var j = null
                try { j = JSON.parse(this.text.split("\n")[0]) } catch (e) {}
                if (!j || !j.ok) { cl._syncFail("restore: " + (j && j.error ? j.error : "pull failed")); return }
                Globals.reloadUserState()
                HyprMon.reloadProfiles()
                if (!HyprMon.virtualSession) {
                    Globals.saverDimming = false
                    Quickshell.execDetached(["sh", "-c",
                        'hyprctl reload >/dev/null 2>&1; "$HOME/.config/hypr/scripts/wallpaper.sh" --reapply >/dev/null 2>&1; pkill -x hypridle; sleep 0.6; hypridle -c "$HOME/.config/hypr/generated/hypridle.conf" >/dev/null 2>&1'])
                    Wallpaper.reapplied()
                }
                cl.lastSync = new Date().toISOString(); cl._saveSyncMeta()
                cl.localSyncedAt = cl.lastSync
                cl._recordHash.running = false; cl._recordHash.running = true
                cl.syncState = "idle"; cl.syncConflict = false
                cl.restoreSummary = "Restored the machine file" + (j.machine ? " saved by “" + j.machine + "”" : "") + " from your account"
                    + (j.backup ? " (previous kept as " + String(j.backup).split("/").pop() + ")" : "") + "."
                cl._manifestProc.running = false; cl._manifestProc.running = true
                cl.checkCloud()
            }
        }
    }
    // after a restore: how many apps does the pulled file want back? ewe
    // never installs anything — Komble's For-you pane does, when asked
    property Process _manifestProc: Process {
        command: [cl.eweConf, "get", "apps.installed"]
        stdout: StdioCollector {
            onStreamFinished: {
                var n = 0
                try {
                    var m = JSON.parse(this.text)
                    if (m && typeof m === "object") {
                        if (Array.isArray(m.packages)) n += m.packages.length
                        if (Array.isArray(m.appimages)) n += m.appimages.length
                    }
                } catch (e) {}
                cl.restoreApps = n
                if (n === 0) { Log.info("cloud", "restore: the backup carries no app manifest — nothing for Komble"); return }
                cl._appsNotify.running = false; cl._appsNotify.running = true
            }
        }
    }
    property Process _appsNotify: Process {
        command: ["notify-send", "-a", "Komble", "-i", "system-software-install", "-A", "open=Open Komble",
                  cl.restoreApps + (cl.restoreApps === 1 ? " app is" : " apps are") + " waiting in Komble",
                  "Your backup lists them under For you — reinstalling is one click, never automatic."]
        stdout: StdioCollector { onStreamFinished: if (this.text.trim() === "open") Globals.openStore() }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Calendar — CalDAV through bin/ewe-caldav (14-day window, five-minute
    // helper cache, offline fallback). Agenda.qml picks this source first.
    // ══════════════════════════════════════════════════════════════════════════
    property var events: []              // the shell's event shape (see ewe-caldav)
    property string calState: ""         // "" | "offline"
    property double lastFetch: 0
    property bool _calBusy: false
    function fetchCalendar(force) {
        if (!cl.signedIn || cl._calBusy) return
        cl._calBusy = true
        _calProc.command = force ? ["python3", cl.eweCaldav, "events", "--days", "14", "--no-cache"]
                                 : ["python3", cl.eweCaldav, "events", "--days", "14"]
        _calProc.running = false; _calProc.running = true
    }
    property Process _calProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                cl._calBusy = false
                try {
                    var j = JSON.parse(this.text)
                    if (Array.isArray(j.events)) cl.events = j.events
                    if (j.ok && !j.offline) { cl.calState = ""; cl.lastFetch = Date.now() }
                    else if (j.error === "unauthorized" || j.error === "not-signed-in") { cl.calState = ""; cl.refresh() }
                    else cl.calState = "offline"
                } catch (e) { cl.calState = "offline" }
            }
        }
    }
    property Timer _calPoll: Timer {
        interval: 15 * 60 * 1000; running: cl.signedIn; repeat: true
        onTriggered: cl.fetchCalendar(true)
    }
    property Timer _calRetry: Timer {
        interval: 60 * 1000; running: cl.signedIn && cl.calState === "offline"; repeat: true
        onTriggered: cl.fetchCalendar(true)
    }
    property Connections _qsHook: Connections {
        target: Globals
        function onQuickSettingsOpenChanged() {
            if (!Globals.quickSettingsOpen) return
            if (cl.signedIn && Date.now() - cl.lastFetch > 5 * 60 * 1000) cl.fetchCalendar(true)
            else if (!cl.signedIn && cl.probed && cl.busy === "" && cl.reason === "keyring-locked") cl.refresh()
        }
    }
}
