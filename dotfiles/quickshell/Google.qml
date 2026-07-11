pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Google — THE Google account service (native OAuth, no GNOME Online Accounts).
// Owns sign-in state, token refresh and the thin authorized-API layer; the
// Settings-sync and Calendar features are pure consumers of `api()`. The OAuth
// heavy lifting (PKCE + loopback redirect + Secret Service keyring) lives in
// scripts/google-auth.py — this file never sees the refresh token at all, only
// short-lived access tokens held in memory.
QtObject {
    id: goo

    // ── account state ──────────────────────────────────────────────────────────
    property bool probed: false          // first status probe finished
    property bool configured: false      // client id present in google-oauth.json
    property bool keyringOk: true        // secret-tool usable
    property bool signedIn: false
    property var profile: null           // { name, email, picture } (cached on disk, non-secret)
    property string busy: ""             // "" | "signin" | "refresh"
    property string error: ""            // last auth-level error, human-readable ("" = none)

    signal sessionReady()                // fired on sign-in and on startup when already signed in
    signal sessionClosed()               // fired on sign-out / server-side revocation

    // access-token cache — memory only, never persisted
    property string _accessToken: ""
    property double _expiresAt: 0
    property var _tokenWaiters: []

    readonly property string helper: Quickshell.env("HOME") + "/.config/quickshell/scripts/google-auth.py"

    function refresh() { _statusProc.running = false; _statusProc.running = true }

    property Process _statusProc: Process {
        running: true
        command: ["python3", goo.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    goo.configured = !!j.configured
                    goo.keyringOk = j.keyring !== false
                    var was = goo.signedIn
                    goo.signedIn = !!j.signed_in
                    goo.profile = j.profile || null
                    if (goo.signedIn && !was) goo.sessionReady()
                } catch (e) { /* helper always prints JSON; treat garbage as unconfigured */ }
                goo.probed = true
            }
        }
    }

    // ── sign in / out ──────────────────────────────────────────────────────────
    function signIn() {
        if (goo.busy === "signin" || !goo.configured) return
        goo.error = ""
        goo.busy = "signin"
        _loginProc.running = false; _loginProc.running = true
    }
    function cancelSignIn() {
        if (goo.busy !== "signin") return
        _loginProc.running = false   // kills the helper → loopback server dies
        goo.busy = ""
    }
    property Process _loginProc: Process {
        command: ["python3", goo.helper, "login"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (goo.busy === "signin") goo.busy = ""
                if (this.text.trim() === "") return   // cancelled — process killed mid-flight
                try {
                    var j = JSON.parse(this.text)
                    if (j.ok) {
                        goo.signedIn = true
                        goo.profile = j.profile
                        goo._accessToken = j.access_token
                        goo._expiresAt = j.expires_at * 1000
                        goo.error = ""
                        goo.sessionReady()
                    } else {
                        goo.error = goo._loginErrMsg(j.error)
                    }
                } catch (e) { goo.error = "Sign-in failed — could not parse the helper output." }
            }
        }
    }
    function _loginErrMsg(e) {
        if (e === "access_denied") return "Sign-in was cancelled in the browser."
        if (e === "timeout") return "Sign-in timed out — no response from the browser within 5 minutes."
        if (e === "keyring-unavailable" || e === "keyring-store-failed") return "No Secret Service keyring available — install/enable gnome-keyring, then retry."
        if (e === "not-configured") return "Google client ID not configured — see README → Google account."
        if (e === "no-refresh-token") return "Google returned no refresh token — remove the app at myaccount.google.com/permissions and retry."
        return "Sign-in failed: " + e
    }

    function signOut() {
        _logoutProc.running = false; _logoutProc.running = true
        goo.signedIn = false
        goo.profile = null
        goo._accessToken = ""
        goo._expiresAt = 0
        goo.error = ""
        goo.sessionClosed()
    }
    property Process _logoutProc: Process { command: ["python3", goo.helper, "logout"] }

    // ── token plumbing (single-flight refresh; callers queue) ──────────────────
    function ensureToken(cb) {
        if (goo._accessToken !== "" && Date.now() < goo._expiresAt - 60000) { cb(goo._accessToken); return }
        goo._tokenWaiters.push(cb)
        if (goo.busy !== "refresh") {
            goo.busy = "refresh"
            _refreshProc.running = false; _refreshProc.running = true
        }
    }
    property Process _refreshProc: Process {
        command: ["python3", goo.helper, "refresh"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (goo.busy === "refresh") goo.busy = ""
                var tok = ""
                try {
                    var j = JSON.parse(this.text)
                    if (j.ok) {
                        goo._accessToken = j.access_token
                        goo._expiresAt = j.expires_at * 1000
                        tok = j.access_token
                    } else if (j.error === "signed-out") {
                        // refresh token revoked server-side — drop the session cleanly
                        goo.signedIn = false
                        goo.profile = null
                        goo.sessionClosed()
                    } else {
                        goo.error = "Google token refresh failed: " + j.error
                    }
                } catch (e) { goo.error = "Google token refresh failed — could not parse the helper output." }
                var ws = goo._tokenWaiters
                goo._tokenWaiters = []
                for (var i = 0; i < ws.length; i++) ws[i](tok)   // "" → the api() call reports not-authorized
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Settings sync — one versioned JSON bundle in Drive's appDataFolder (hidden
    // per-app storage; drive.appdata scope only, invisible in the user's Drive).
    // scripts/settings-bundle.py collects/applies the shell's EXISTING state
    // files; this side just moves the document. Restore is always explicit:
    // requestRestore() parks the downloaded bundle in pendingRestore and the
    // Settings pane asks for confirmation before applyRestore() touches disk.
    // ══════════════════════════════════════════════════════════════════════════
    property string syncState: "idle"    // idle | syncing | error
    property string syncError: ""
    property string restoreSummary: ""   // success line after a restore
    property string lastSync: ""         // ISO — last successful push/restore from THIS device
    property string lastHash: ""         // content hash of the last pushed bundle (skip no-op pushes)
    property bool autoSync: false
    property var cloudInfo: null         // { device, updatedAt } of the cloud copy
    property var pendingRestore: null    // downloaded bundle awaiting explicit confirmation
    property var _cloudBundle: null
    property string _cloudFileId: ""

    readonly property string bundleHelper: Quickshell.env("HOME") + "/.config/quickshell/scripts/settings-bundle.py"
    readonly property string syncMetaPath: Quickshell.env("HOME") + "/.config/quickshell/google-sync.json"
    readonly property string restorePath: Quickshell.env("HOME") + "/.config/quickshell/google-restore.json"
    readonly property string driveListUrl: "https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=" + encodeURIComponent("name='hypr-shell-settings.json'") + "&fields=" + encodeURIComponent("files(id,modifiedTime)")

    property Process _metaLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/google-sync.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (j.autoSync !== undefined) goo.autoSync = j.autoSync
                    if (j.lastSync) goo.lastSync = j.lastSync
                    if (j.lastHash) goo.lastHash = j.lastHash
                } catch (e) {}
            }
        }
    }
    property Process _metaWriter: Process {}
    function _saveSyncMeta() {
        HyprMon.atomicWrite(goo._metaWriter, goo.syncMetaPath,
            JSON.stringify({ autoSync: goo.autoSync, lastSync: goo.lastSync, lastHash: goo.lastHash }))
    }
    function setAutoSync(v) { goo.autoSync = v; goo._saveSyncMeta() }

    property Connections _sessionHooks: Connections {
        target: goo
        function onSessionReady() { goo.checkCloud() }
        function onSessionClosed() {
            goo.cloudInfo = null; goo._cloudBundle = null; goo._cloudFileId = ""
            goo.pendingRestore = null; goo.syncState = "idle"; goo.syncError = ""; goo.restoreSummary = ""
        }
    }

    // fetch the cloud copy (6 KB) — feeds both the panel info line and restore
    function checkCloud(cb) {
        goo.api("GET", goo.driveListUrl, null, function (st, j, err) {
            var f = (st === 200 && j && j.files && j.files.length) ? j.files[0] : null
            if (!f) { goo.cloudInfo = null; goo._cloudBundle = null; goo._cloudFileId = ""; if (cb) cb(false); return }
            goo._cloudFileId = f.id
            goo.api("GET", "https://www.googleapis.com/drive/v3/files/" + f.id + "?alt=media", null, function (st2, bundle, err2) {
                if (st2 === 200 && bundle && bundle.settings) {
                    goo._cloudBundle = bundle
                    goo.cloudInfo = { device: bundle.device || "?", updatedAt: bundle.updatedAt || "" }
                    if (cb) cb(true)
                } else { if (cb) cb(false) }
            })
        })
    }

    // ── push ────────────────────────────────────────────────────────────────────
    property bool _autoPushing: false
    function syncNow() {
        if (!goo.signedIn || goo.syncState === "syncing") return
        goo.syncState = "syncing"; goo.syncError = ""; goo.restoreSummary = ""
        _collectProc.running = false; _collectProc.running = true
    }
    property Process _collectProc: Process {
        command: ["python3", goo.bundleHelper, "collect"]
        stdout: StdioCollector { onStreamFinished: goo._pushBundle(this.text) }
    }
    function _pushBundle(text) {
        var bundle = null
        try { bundle = JSON.parse(text) } catch (e) {}
        if (!bundle || !bundle.settings) { goo._syncFail("could not collect local settings"); return }
        if (goo._autoPushing && bundle.hash === goo.lastHash) { goo._autoPushing = false; goo.syncState = "idle"; return }
        var done = function (st, j, err) {
            goo._autoPushing = false
            if (st === 200) {
                goo.lastSync = bundle.updatedAt; goo.lastHash = bundle.hash; goo._saveSyncMeta()
                goo.cloudInfo = { device: bundle.device, updatedAt: bundle.updatedAt }
                goo._cloudBundle = bundle
                goo.syncState = "idle"
            } else goo._syncFail(err === "offline" ? "offline — will keep the local copy" : ("Drive upload failed (HTTP " + st + ")"))
        }
        if (goo._cloudFileId !== "") {
            goo.api("PATCH", "https://www.googleapis.com/upload/drive/v3/files/" + goo._cloudFileId + "?uploadType=media",
                    { body: text, contentType: "application/json" }, done)
        } else {
            var b = "--hsbundle\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
                  + JSON.stringify({ name: "hypr-shell-settings.json", parents: ["appDataFolder"] })
                  + "\r\n--hsbundle\r\nContent-Type: application/json\r\n\r\n" + text + "\r\n--hsbundle--"
            goo.api("POST", "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart",
                    { body: b, contentType: "multipart/related; boundary=hsbundle" },
                    function (st, j, err) { if (st === 200 && j && j.id) goo._cloudFileId = j.id; done(st, j, err) })
        }
    }
    function _syncFail(msg) { goo.syncState = "error"; goo.syncError = "Sync failed: " + msg }

    // auto-sync: debounce-push after Settings closes, only when content changed
    property Connections _autoHook: Connections {
        target: Globals
        function onSettingsOpenChanged() {
            if (!Globals.settingsOpen && goo.autoSync && goo.signedIn) goo._autoPushTimer.restart()
        }
    }
    property Timer _autoPushTimer: Timer {
        interval: 20000
        onTriggered: { if (goo.autoSync && goo.signedIn && goo.syncState !== "syncing") { goo._autoPushing = true; goo.syncNow() } }
    }

    // ── restore (explicit, confirmed) ───────────────────────────────────────────
    function requestRestore() {
        goo.restoreSummary = ""; goo.syncError = ""
        if (goo._cloudBundle) { goo.pendingRestore = goo._cloudBundle; return }
        goo.checkCloud(function (ok) {
            if (ok) goo.pendingRestore = goo._cloudBundle
            else { goo.syncState = "error"; goo.syncError = "No cloud backup found for this account." }
        })
    }
    function cancelRestore() { goo.pendingRestore = null }
    property Process _restoreWriter: Process {}
    property Process _applyProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var j = null
                try { j = JSON.parse(this.text) } catch (e) {}
                if (!j || !j.ok) { goo._syncFail("restore: " + (j && j.error ? j.error : "bundle apply failed")); return }
                // reload everything the bundle touched
                Globals.reloadUserState()
                HyprMon.reloadProfiles()
                if (!HyprMon.virtualSession)
                    Quickshell.execDetached(["sh", "-c",
                        'hyprctl reload >/dev/null 2>&1; "$HOME/.config/hypr/scripts/wallpaper.sh" --reapply >/dev/null 2>&1; pkill -x hypridle; sleep 0.6; hypridle -c "$HOME/.config/hypr/generated/hypridle.conf" >/dev/null 2>&1'])
                goo.lastSync = j.updatedAt; goo.lastHash = ""; goo._saveSyncMeta()
                goo.syncState = "idle"
                goo.restoreSummary = "Restored " + j.applied.length + " sections from “" + j.device + "”. "
                    + (j.packages.repo > 0 ? j.packages.repo + " repo + " + j.packages.aur + " AUR packages captured — reinstall (optional): sudo pacman -S --needed - < ~/.config/quickshell/google-restore-packages.txt" : "")
            }
        }
    }
    function applyRestore() {
        if (!goo.pendingRestore) return
        goo.syncState = "syncing"
        HyprMon.atomicWrite(goo._restoreWriter, goo.restorePath, JSON.stringify(goo.pendingRestore))
        goo.pendingRestore = null
        goo._applyTimer.restart()   // let the atomic write land before apply reads it
    }
    property Timer _applyTimer: Timer {
        interval: 700
        onTriggered: { goo._applyProc.command = ["python3", goo.bundleHelper, "apply", goo.restorePath]; goo._applyProc.running = false; goo._applyProc.running = true }
    }

    // ── thin API layer: Bearer header, one 401-refresh-retry, JSON parse ───────
    // cb(status, json, err) — err ∈ "" | "offline" | "not-authorized"
    function api(method, url, opts, cb) { goo._apiCall(method, url, opts, cb, true) }
    function _apiCall(method, url, opts, cb, retry) {
        goo.ensureToken(function (tok) {
            if (tok === "") { cb(0, null, "not-authorized"); return }
            var xhr = new XMLHttpRequest()
            xhr.open(method, url)
            xhr.setRequestHeader("Authorization", "Bearer " + tok)
            var body = undefined
            if (opts && opts.body !== undefined) {
                body = typeof opts.body === "string" ? opts.body : JSON.stringify(opts.body)
                xhr.setRequestHeader("Content-Type", opts.contentType || "application/json")
            }
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE) return
                if (xhr.status === 401 && retry) {
                    goo._accessToken = ""; goo._expiresAt = 0
                    goo._apiCall(method, url, opts, cb, false)
                    return
                }
                var j = null
                try { j = JSON.parse(xhr.responseText) } catch (e) {}
                cb(xhr.status, j, xhr.status === 0 ? "offline" : "")
            }
            xhr.send(body)
        })
    }
}
