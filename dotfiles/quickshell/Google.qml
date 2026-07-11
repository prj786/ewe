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
