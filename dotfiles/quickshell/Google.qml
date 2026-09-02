pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Google — the OPTIONAL Google extra (RFC-005): Gmail for the mail badge and
// Google Drive as a folder, and only when the user brings their own OAuth
// client file (~/.config/ewe/oauth-client.json). ewe ships no Google client,
// and the ewe account, settings sync and the restore live in Cloud.qml
// (Nextcloud). The OAuth heavy lifting (PKCE + loopback redirect + Secret
// Service keyring) is bin/ewe-auth — this file never sees the refresh token,
// only short-lived access tokens held in memory.
QtObject {
    id: goo

    // ── account state ──────────────────────────────────────────────────────────
    property bool probed: false          // first status probe finished
    property bool configured: false      // the user's OWN client file exists and the broker accepts it
    property bool personalClient: false  // ~/.config/ewe/oauth-client.json is there
    property bool _brokerConfigured: false
    readonly property string clientPath: Quickshell.env("HOME") + "/.config/ewe/oauth-client.json"
    // a machine that synced through Drive before RFC-005: the account card
    // explains where sync went; the Drive backup itself is untouched
    property bool legacyGoogleSync: false
    property bool keyringOk: true        // secret-tool usable
    property bool signedIn: false
    property var profile: null           // { name, email, picture } (cached on disk, non-secret)
    property string busy: ""             // "" | "signin" | "refresh"
    property string error: ""            // last auth-level error, human-readable ("" = none)
    property string errorCode: ""        // the helper's machine code behind `error` ("" = none)
    property bool keyringResetDone: false // keyring-reset ran: a relogin is what finishes it
    // a keyring that is locked, or that just refused to store: the one repair
    // that always works is a fresh keyring made by PAM at the next login
    readonly property bool keyringTrouble: keyringState === "locked" || errorCode.indexOf("keyring-") === 0
    // 0.9.16-2 (first metal install): the keyring and the browser were both
    // invisible behind the Welcome overlay and ewe-auth killed its own
    // prompt. The broker now reports what the keyring will do and hands the
    // consent URL back, so the UI can say so and offer the link itself.
    property string keyringState: "ok"   // ok | missing | locked | unavailable (from ewe-auth status/login)
    property string consentUrl: ""       // the sign-in page of the login in flight / that just failed
    readonly property bool keyringPromptExpected: keyringState === "missing" || keyringState === "locked"
    function openConsentUrl() { if (goo.consentUrl !== "") Quickshell.execDetached(["xdg-open", goo.consentUrl]) }
    function resetKeyring() { if (goo.busy === "") { goo.busy = "keyring-reset"; _resetProc.running = false; _resetProc.running = true } }
    function logOut() { Quickshell.execDetached(["sh", "-c", "exec \"$HOME/.config/hypr/scripts/power.sh\" logout"]) }
    property Process _resetProc: Process {
        command: ["python3", goo.helper, "keyring-reset"]
        stdout: StdioCollector {
            onStreamFinished: {
                goo.busy = ""
                try {
                    var j = JSON.parse(this.text)
                    if (j.ok) {
                        goo.signedIn = false; goo.profile = null; goo._accessToken = ""
                        goo.keyringState = "missing"; goo.errorCode = ""
                        goo.keyringResetDone = !!j.relogin
                        goo.error = j.relogin ? String(j.message) : ""
                    } else goo.error = j.message ? String(j.message) : ("Keyring reset failed: " + j.error)
                } catch (e) { goo.error = "Keyring reset failed — could not parse the helper output." }
            }
        }
    }
    function copyConsentUrl() { if (goo.consentUrl !== "") Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "sh", goo.consentUrl]) }

    signal sessionReady()                // fired on sign-in and on startup when already signed in
    signal sessionClosed()               // fired on sign-out / server-side revocation

    // access-token cache — memory only, never persisted
    property string _accessToken: ""
    property double _expiresAt: 0
    property var _tokenWaiters: []

    // RFC-002: the OAuth broker is ewe-auth — one Google identity for the
    // shell, Komble and future apps (same JSON contract this file always
    // spoke; the old scripts/google-auth.py path remains as a shim).
    readonly property string helper: Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-auth"

    function refresh() { _statusProc.running = false; _statusProc.running = true }

    // ── IPC for the standalone Settings app ───────────────────────────────────
    // ewe-settings drives the account from out of process: verbs in, a JSON
    // status snapshot out. Tokens never cross this boundary — sign-in runs the
    // same in-shell flow (browser + keyring) it always has. Public API like the
    // `settings` verbs: a shipped binary depends on these names.
    property IpcHandler _ipc: IpcHandler {
        target: "google"
        function signIn(): void { goo.signIn() }
        function cancelSignIn(): void { goo.cancelSignIn() }
        function keyringReset(): void { goo.resetKeyring() }
        // the browser hand-off fallbacks and the post-reset relogin, for a
        // Settings app that has no window of its own into the shell's state
        function openConsentUrl(): void { goo.openConsentUrl() }
        function copyConsentUrl(): void { goo.copyConsentUrl() }
        function logOut(): void { goo.logOut() }
        function signOut(): void { goo.signOut() }
        function refresh(): void { goo.refresh() }
        // RFC-005: settings sync, backup and restore moved to the Nextcloud
        // account (target "cloud"). These names survive so an older
        // ewe-settings/Komble gets a clear answer instead of an IPC error.
        function syncNow(): void { Cloud.syncNow() }
        function syncSoon(): void { Cloud.syncSoon() }
        function backUpNow(): void { Cloud.backUpNow() }
        function pushForce(): void { Cloud.pushForce() }
        function requestRestore(): void { Cloud.requestRestore() }
        function applyRestore(): void { Cloud.applyRestore() }
        function setAutoSync(on: bool): void { Cloud.setAutoSync(on) }
        function fetchPackages(): string { return "retired-see-ewe-conf" }
        function status(): string {
            return JSON.stringify({
                probed: goo.probed, configured: goo.configured, personalClient: goo.personalClient, clientPath: goo.clientPath,
                legacyGoogleSync: goo.legacyGoogleSync, keyringOk: goo.keyringOk,
                keyringState: goo.keyringState, keyringTrouble: goo.keyringTrouble, keyringResetDone: goo.keyringResetDone,
                consentUrl: goo.consentUrl,
                signedIn: goo.signedIn, busy: goo.busy, error: goo.error, errorCode: goo.errorCode,
                mailUnread: goo.mailUnread, mailState: goo.mailState,
                profile: goo.profile
            })
        }
    }

    property Process _statusProc: Process {
        running: true
        command: ["python3", goo.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    goo._brokerConfigured = !!j.configured
                    goo.configured = goo._brokerConfigured && goo.personalClient
                    goo.keyringOk = j.keyring !== false
                    if (j.keyring_state) goo.keyringState = String(j.keyring_state)
                    var was = goo.signedIn
                    goo.signedIn = !!j.signed_in
                    goo.profile = j.profile || null
                    if (goo.signedIn && !was) goo.sessionReady()
                } catch (e) { /* helper always prints JSON; treat garbage as unconfigured */ }
                goo.probed = true
                // right after boot the first probe can race gnome-keyring coming
                // up and report signed-out even though a refresh token is stored
                // — re-probe with backoff instead of staying signed-out forever
                if (!goo.signedIn && goo.configured && goo._probeRetries < 3) {
                    goo._probeRetries++
                    goo._probeRetry.interval = 5000 * goo._probeRetries
                    goo._probeRetry.restart()
                }
            }
        }
    }
    property int _probeRetries: 0
    property Timer _probeRetry: Timer { onTriggered: { if (!goo.signedIn) goo.refresh() } }
    // the shipped client is gone (RFC-005): only the user's own file counts
    property Process _clientProbe: Process {
        running: true
        command: ["sh", "-c", '[ -s "$HOME/.config/ewe/oauth-client.json" ] && echo yes || echo no; [ -s "$HOME/.config/quickshell/google-sync.json" ] && grep -q lastSync "$HOME/.config/quickshell/google-sync.json" && echo legacy || true']
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text
                goo.personalClient = t.indexOf("yes") === 0
                goo.legacyGoogleSync = t.indexOf("legacy") >= 0
                goo.configured = goo._brokerConfigured && goo.personalClient
            }
        }
    }

    // Called by Resume, not by a timer. After a multi-hour suspend every access
    // token is expired and ensureToken's 60s skew check cannot help — the cached
    // token is simply stale. Drop it and force one refresh up front, so the
    // calendar and mail come back on their own instead of the next poll
    // discovering the expiry by failing a request.
    function refreshAfterResume() {
        if (!goo.configured) return
        goo._accessToken = ""
        goo._expiresAt = 0
        if (!goo.signedIn) {
            // the boot probe gives up after 3 tries and never re-arms, so a
            // keyring that was locked at login leaves the shell believing it is
            // signed out forever — a wake is a fair moment to try again
            goo._probeRetries = 0
            goo.refresh()
            return
        }
        goo.ensureToken(function (tok) {
            if (tok === "") { Log.warn("google", "resume: token refresh failed — services keep their own retries"); return }
            goo.fetchCalendar()
            goo.fetchMail()
        })
    }

    // ── sign in / out ──────────────────────────────────────────────────────────
    function signIn() {
        if (goo.busy === "signin" || !goo.configured) return
        goo.error = ""
        goo.errorCode = ""
        goo.consentUrl = ""
        goo.busy = "signin"
        _loginProc.running = false; _loginProc.running = true
    }
    function cancelSignIn() {
        if (goo.busy !== "signin") return
        _loginProc.running = false   // kills the helper → loopback server dies
        goo.busy = ""
    }
    property Process _loginProc: Process {
        // --with-drive: ONE consent covers files too, so ~/Google Drive can be
        // mounted right after sign-in with no second browser round-trip
        command: ["python3", goo.helper, "login", "--with-drive"]
        // the consent URL rides on stderr the moment it exists — long before
        // the JSON result — so "open / copy the link" works while waiting
        stderr: StdioCollector {
            onStreamFinished: {
                var ls = this.text.split("\n")
                for (var i = 0; i < ls.length; i++)
                    if (ls[i].indexOf("consent-url: ") === 0) goo.consentUrl = ls[i].slice(13).trim()
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (goo.busy === "signin") goo.busy = ""
                if (this.text.trim() === "") return   // cancelled — process killed mid-flight
                try {
                    var j = JSON.parse(this.text)
                    if (j.consent_url) goo.consentUrl = String(j.consent_url)
                    if (j.keyring) goo.keyringState = String(j.keyring)
                    if (j.ok) {
                        goo.signedIn = true
                        goo.profile = j.profile
                        goo._accessToken = j.access_token
                        goo._expiresAt = j.expires_at * 1000
                        goo.error = ""
                        goo.errorCode = ""
                        goo.sessionReady()
                        // one sign-in, files too: the fresh token carries the
                        // Drive scope, so finish the ~/Google Drive plumbing
                        // (rclone remote + Nemo bookmark + mount) consent-free
                        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-drive", "setup", "--have-scope"])
                    } else {
                        goo.errorCode = String(j.error || "")
                        goo.error = goo._loginErrMsg(j.error, j.message)
                        Log.warn("google", "sign-in failed:", j.error, j.message || "")
                    }
                } catch (e) { goo.error = "Sign-in failed — could not parse the helper output." }
            }
        }
    }
    function _loginErrMsg(e, detail) {
        if (e === "access_denied") return "Sign-in was cancelled in the browser."
        if (e === "timeout") return "Sign-in timed out — no response from the browser within 5 minutes. Use “Open the sign-in page” if no tab appeared."
        if (e === "browser-failed") return "No browser opened for the sign-in page — use “Open the sign-in page” or copy the link into any browser."
        if (e === "keyring-unavailable") return "No Secret Service keyring is running — gnome-keyring must be installed and started for this session."
        if (e === "keyring-cancelled") return "The keyring prompt was dismissed — sign in again and unlock the keyring with your login password. If it keeps rejecting that password, reset the keyring."
        if (e === "keyring-timeout") return "The keyring did not answer — if a keyring password prompt is open, answer it with your login password, then sign in again. If it keeps rejecting that password, reset the keyring."
        if (e === "keyring-store-failed") return detail ? String(detail) : "The keyring refused to store the token — see Troubleshooting → Google sign-in."
        if (e === "not-configured") return "No Google client — drop your own OAuth client file at ~/.config/ewe/oauth-client.json (docs/GOOGLE-CLIENT.md)."
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
                        // clear a previous failure — a wake-time network blip used
                        // to leave a permanent red banner in Settings long after
                        // everything had recovered
                        goo.error = ""
                    } else if (j.error === "signed-out") {
                        // refresh token revoked server-side — drop the session cleanly
                        goo.signedIn = false
                        goo.profile = null
                        goo.sessionClosed()
                    } else {
                        goo.error = "Google token refresh failed: " + j.error
                        Log.warn("google", "token refresh failed:", j.error)
                    }
                } catch (e) {
                    goo.error = "Google token refresh failed — could not parse the helper output."
                    Log.error("google", "token refresh returned unparseable output")
                }
                var ws = goo._tokenWaiters
                goo._tokenWaiters = []
                for (var i = 0; i < ws.length; i++) ws[i](tok)   // "" → the api() call reports not-authorized
            }
        }
    }

    property Connections _sessionHooks: Connections {
        target: goo
        function onSessionReady() { goo.fetchCalendar(); goo.fetchMail() }
        function onSessionClosed() {
            // reset the fan-out latch too: a sign-out landing mid-fetch left
            // _calPending non-zero, and fetchCalendar early-returns on that —
            // wedging the calendar for the rest of the session
            goo._calPending = 0; goo._calOk = 0; goo._calFail = 0
            goo.events = []; goo.calState = ""; goo._writeEventsCache()
            goo.mailUnread = 0; goo.mailList = []; goo.mailState = ""; goo.mailError = ""
            goo._mailHistoryId = ""; goo._mailIds = []; goo._saveMailState()
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Calendar (secondary source — Agenda.qml prefers the Nextcloud account)
    // — poll events.list across every selected calendar (14-day window,
    // per-calendar colours), cache the last good fetch for offline, and fire
    // de-duped reminder notifications through the shell's own notification
    // server (notify-send → we ARE org.freedesktop.Notifications).
    // ══════════════════════════════════════════════════════════════════════════
    property var events: []              // [{id, summary, start, end, allDay, location, video, color, calendar, reminders:[min]}]
    property string calState: ""         // "" | "offline" (fetch failed, cache shown)
    property double lastFetch: 0
    property int _calPending: 0
    property var _calAccum: []
    property int _calOk: 0               // per-calendar fetches that returned events
    property int _calFail: 0             // …and ones that did not
    readonly property string eventsCachePath: Quickshell.env("HOME") + "/.config/quickshell/google-events.json"

    function fetchCalendar() {
        if (!goo.signedIn || goo._calPending > 0) return
        var now = new Date()
        var t0 = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        var timeMin = encodeURIComponent(t0.toISOString())
        var timeMax = encodeURIComponent(new Date(t0.getTime() + 14 * 86400000).toISOString())
        goo.api("GET", "https://www.googleapis.com/calendar/v3/users/me/calendarList", null, function (st, j, err) {
            // "offline" keeps the cached events on screen AND arms the 60 s
            // retry — right after boot this fetch races Wi-Fi coming up
            if (st !== 200 || !j || !j.items) { goo.calState = "offline"; return }
            var cals = j.items.filter(function (c) { return c.selected !== false })
            if (cals.length === 0) { goo.events = []; goo.calState = ""; goo._writeEventsCache(); return }
            goo._calAccum = []
            goo._calOk = 0; goo._calFail = 0
            goo._calPending = cals.length
            for (var i = 0; i < cals.length; i++) goo._fetchCalEvents(cals[i], timeMin, timeMax)
        })
    }
    function _fetchCalEvents(cal, timeMin, timeMax) {
        var url = "https://www.googleapis.com/calendar/v3/calendars/" + encodeURIComponent(cal.id)
                + "/events?singleEvents=true&orderBy=startTime&maxResults=100&timeMin=" + timeMin + "&timeMax=" + timeMax
        goo.api("GET", url, null, function (st, j, err) {
            if (st !== 200 || !j || !j.items) goo._calFail++
            else {
                goo._calOk++
                var defRem = (cal.defaultReminders || []).filter(function (r) { return r.method === "popup" }).map(function (r) { return r.minutes })
                for (var i = 0; i < j.items.length; i++) {
                    var ev = j.items[i]
                    if (ev.status === "cancelled" || !ev.start) continue
                    var allDay = !!ev.start.date
                    var explicit = !!(ev.reminders && !ev.reminders.useDefault)
                    var rem = explicit
                        ? (ev.reminders.overrides || []).filter(function (r) { return r.method === "popup" }).map(function (r) { return r.minutes })
                        : defRem.slice()
                    if (allDay && !explicit) rem = []          // no surprise 23:50 pings for all-day events
                    else if (!allDay && rem.length === 0) rem = [10]   // shell default lead
                    goo._calAccum.push({
                        id: ev.id, summary: ev.summary || "(untitled)",
                        start: ev.start.dateTime || ev.start.date, end: ev.end ? (ev.end.dateTime || ev.end.date) : "",
                        allDay: allDay, location: ev.location || "", video: ev.hangoutLink || "",
                        color: cal.backgroundColor || "", calendar: cal.summary || "", reminders: rem
                    })
                }
            }
            goo._calPending--
            if (goo._calPending === 0) {
                // every calendar failed → a network/quota problem, not an empty
                // calendar. Committing here used to overwrite the offline cache
                // with [] AND clear calState, so the retry never armed and the
                // card read "No upcoming events" until the next 15-minute poll.
                if (goo._calOk === 0 && goo._calFail > 0) {
                    goo.calState = "offline"
                    Log.warn("google", "calendar: all", goo._calFail, "calendars failed — keeping cache")
                    return
                }
                goo._calAccum.sort(function (a, b) { return a.start < b.start ? -1 : (a.start > b.start ? 1 : 0) })
                goo.events = goo._calAccum
                goo.calState = ""
                goo.lastFetch = Date.now()
                goo._writeEventsCache()
            }
        })
    }
    property Process _evWriter: Process {}
    function _writeEventsCache() {
        HyprMon.atomicWrite(goo._evWriter, goo.eventsCachePath, JSON.stringify({ events: goo.events }))
    }
    property Process _evLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/google-events.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (goo.lastFetch > 0) return   // a live fetch already won
                try { var j = JSON.parse(this.text); if (j && Array.isArray(j.events)) goo.events = j.events } catch (e) {}
            }
        }
    }
    // poll every 15 min while signed in; QS opening refreshes when >5 min stale
    property Timer _calPoll: Timer {
        interval: 15 * 60 * 1000; running: goo.signedIn; repeat: true
        onTriggered: goo.fetchCalendar()
    }
    // a failed fetch retries every minute (boot-time Wi-Fi race, flaky network)
    property Timer _calRetry: Timer {
        interval: 60 * 1000; running: goo.signedIn && goo.calState === "offline"; repeat: true
        onTriggered: goo.fetchCalendar()
    }
    property Connections _qsHook: Connections {
        target: Globals
        function onQuickSettingsOpenChanged() {
            if (!Globals.quickSettingsOpen) return
            if (goo.signedIn && Date.now() - goo.lastFetch > 5 * 60 * 1000) goo.fetchCalendar()
            // signed-out but configured: the boot probe may have raced the
            // keyring — opening QS is a natural moment to re-check
            else if (!goo.signedIn && goo.configured && goo.busy === "") goo.refresh()
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Gmail — INBOX unread badge, new-mail notifications and the Quick Settings
    // mail list. Read-only scope. The History API cursor detects genuinely NEW
    // arrivals (no notification storm for pre-existing unread mail); the cursor
    // and a bounded notified-set persist so restarts never re-notify.
    // ══════════════════════════════════════════════════════════════════════════
    property int mailUnread: 0
    property var mailList: []            // [{id, from, subject, snippet, date, unread}]
    property string mailState: ""        // "" | "offline" | "scope" (re-consent needed) | "api" (API disabled)
    property string mailError: ""
    property bool mailNotify: true       // desktop notifications for new mail
    property double mailLastFetch: 0
    property string _mailHistoryId: ""
    property var _mailNotified: ({})     // messageId -> epoch-ms (bounded, persisted)
    property var _mailIds: []            // current unread id set (change detector)
    readonly property string mailStatePath: Quickshell.env("HOME") + "/.config/quickshell/google-mail.json"

    property Process _mailWriter: Process {}
    // _saveMailState fires from several callbacks that can land in the same tick
    // (history → baseline → list refresh). They all share _mailWriter, and
    // atomicWrite restarts the process, so the earlier `sh` was killed mid-heredoc
    // and its write silently lost — taking the historyId cursor with it and
    // leaving a stray .tmp behind. Coalesce the burst into one write.
    property Timer _mailSaveT: Timer {
        interval: 200
        onTriggered: HyprMon.atomicWrite(goo._mailWriter, goo.mailStatePath, JSON.stringify({
            historyId: goo._mailHistoryId, notified: goo._mailNotified,
            notify: goo.mailNotify, unread: goo.mailUnread, list: goo.mailList.slice(0, 15)
        }))
    }
    function _saveMailState() {
        var cut = Date.now() - 7 * 86400000
        for (var k in goo._mailNotified) if (goo._mailNotified[k] < cut) delete goo._mailNotified[k]
        goo._mailSaveT.restart()
    }
    property Process _mailLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/google-mail.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (j.historyId) goo._mailHistoryId = String(j.historyId)
                    if (j.notified && typeof j.notified === "object") goo._mailNotified = j.notified
                    if (j.notify !== undefined) goo.mailNotify = !!j.notify
                    if (goo.mailLastFetch === 0) {
                        if (j.unread !== undefined) goo.mailUnread = j.unread
                        if (Array.isArray(j.list)) goo.mailList = j.list
                    }
                } catch (e) {}
            }
        }
    }
    function setMailNotify(v) { goo.mailNotify = v; goo._saveMailState() }

    function fetchMail() {
        if (!goo.signedIn) return
        goo.api("GET", "https://gmail.googleapis.com/gmail/v1/users/me/labels/INBOX", null, function (st, j, err) {
            if (st === 200 && j) {
                goo.mailState = ""; goo.mailError = ""
                goo.mailUnread = j.messagesUnread || 0
                goo.mailLastFetch = Date.now()
                goo._mailHistory()
            } else if (st === 403 || st === 401) {
                var m = (j && j.error && j.error.message) ? String(j.error.message) : ""
                if (m.indexOf("disabled") >= 0 || m.indexOf("has not been used") >= 0) {
                    goo.mailState = "api"
                    goo.mailError = "Enable the Gmail API for your project in the Google Cloud console, then retry."
                } else {
                    goo.mailState = "scope"   // token predates the gmail scope
                    goo.mailError = "Gmail needs a new permission — reconnect your Google account."
                }
            } else if (err === "offline" || st === 0) {
                goo.mailState = "offline"
            }
        })
    }
    // How many new-mail toasts a single history walk may fire before it stops
    // naming them individually. A multi-hour suspend can surface dozens at once.
    readonly property int mailNotifyBurst: 5

    property var _mailFresh: ({})        // message ids gathered across history pages

    function _mailHistory() {
        if (goo._mailHistoryId === "") { goo._mailBaseline(); return }
        goo._mailFresh = {}
        goo._mailHistoryPage("", 0)
    }
    // history.list pages at ~100 records. Reading only the first page while still
    // advancing the cursor to j.historyId (which is the mailbox's CURRENT id, not
    // the last id on the page) silently dropped every arrival past page one and
    // left the cursor looking healthy — so walk the pages before committing.
    function _mailHistoryPage(pageToken, depth) {
        var url = "https://gmail.googleapis.com/gmail/v1/users/me/history?historyTypes=messageAdded&labelId=INBOX&startHistoryId="
                + goo._mailHistoryId
        if (pageToken !== "") url += "&pageToken=" + encodeURIComponent(pageToken)
        goo.api("GET", url, null, function (st, j, err) {
            if (st === 404) { goo._mailFresh = {}; goo._mailBaseline(); return }   // cursor aged out — reconcile silently
            if (st !== 200 || !j) { goo._mailFresh = {}; goo._refreshMailList(); return }
            var hs = j.history || []
            for (var h = 0; h < hs.length; h++)
                for (var a = 0; a < (hs[h].messagesAdded || []).length; a++) {
                    var msg = hs[h].messagesAdded[a].message
                    if (msg && msg.id && !goo._mailNotified[msg.id]) goo._mailFresh[msg.id] = true
                }
            if (j.nextPageToken) {
                if (depth < 20) { goo._mailHistoryPage(String(j.nextPageToken), depth + 1); return }
                // gap too large to walk — rebaseline rather than advance the cursor
                // past pages we never read
                Log.warn("google", "gmail history gap over", depth, "pages — rebaselining")
                goo._mailFresh = {}
                goo._mailBaseline()
                return
            }
            if (j.historyId) goo._mailHistoryId = String(j.historyId)
            var ids = Object.keys(goo._mailFresh)
            goo._mailFresh = {}
            if (ids.length > 0) Log.info("google", "gmail:", ids.length, "new message(s) since the cursor")
            for (var i = 0; i < ids.length; i++) {
                goo._mailNotified[ids[i]] = Date.now()
                if (goo.mailNotify && i < goo.mailNotifyBurst) goo._notifyMail(ids[i])
            }
            // one summary instead of a toast storm for the rest
            if (goo.mailNotify && ids.length > goo.mailNotifyBurst)
                Quickshell.execDetached(["notify-send", "-a", "Gmail", "-i", "mail-unread",
                    "New mail", (ids.length - goo.mailNotifyBurst) + " more new messages in your inbox."])
            goo._saveMailState()
            goo._refreshMailList()
        })
    }
    // (re)baseline the history cursor; everything currently unread is "seen"
    function _mailBaseline() {
        goo.api("GET", "https://gmail.googleapis.com/gmail/v1/users/me/profile", null, function (st, j, err) {
            if (st === 200 && j && j.historyId) goo._mailHistoryId = String(j.historyId)
            goo.api("GET", "https://gmail.googleapis.com/gmail/v1/users/me/messages?q=" + encodeURIComponent("is:unread in:inbox") + "&maxResults=15",
                    null, function (st2, j2, err2) {
                var ms = (st2 === 200 && j2 && j2.messages) ? j2.messages : []
                for (var i = 0; i < ms.length; i++) goo._mailNotified[ms[i].id] = Date.now()
                goo._saveMailState()
                goo._refreshMailList()
            })
        })
    }
    function _refreshMailList() {
        goo.api("GET", "https://gmail.googleapis.com/gmail/v1/users/me/messages?q=" + encodeURIComponent("in:inbox") + "&maxResults=10",
                null, function (st, j, err) {
            if (st !== 200 || !j) return
            var ms = j.messages || []
            var ids = ms.map(function (m) { return m.id })
            if (JSON.stringify(ids) === JSON.stringify(goo._mailIds) && goo.mailList.length > 0) return
            goo._mailIds = ids
            if (ids.length === 0) { goo.mailList = []; goo._saveMailState(); return }
            var out = [], pending = ids.length
            for (var i = 0; i < ids.length; i++) goo._mailMeta(ids[i], function (row) {
                if (row) out.push(row)
                if (--pending === 0) {
                    out.sort(function (a, b) { return b.date - a.date })
                    goo.mailList = out
                    goo._saveMailState()
                }
            })
        })
    }
    function _mailMeta(id, cb) {
        goo.api("GET", "https://gmail.googleapis.com/gmail/v1/users/me/messages/" + id
                + "?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date", null, function (st, j, err) {
            if (st !== 200 || !j) { cb(null); return }
            var from = "", subject = ""
            var hs = (j.payload && j.payload.headers) ? j.payload.headers : []
            for (var i = 0; i < hs.length; i++) {
                if (hs[i].name === "From") from = hs[i].value
                else if (hs[i].name === "Subject") subject = hs[i].value
            }
            var nice = from.replace(/\s*<[^>]*>/, "").replace(/^"|"$/g, "").trim() || from
            cb({
                id: j.id, from: nice, subject: subject || "(no subject)",
                snippet: j.snippet || "", date: Number(j.internalDate || 0),
                unread: (j.labelIds || []).indexOf("UNREAD") >= 0
            })
        })
    }
    function _notifyMail(id) {
        goo._mailMeta(id, function (row) {
            if (!row) return
            Quickshell.execDetached(["notify-send", "-a", "Gmail", "-i", "mail-unread",
                row.from || "New mail", (row.subject || "") + (row.snippet ? "\n" + row.snippet : "")])
        })
    }
    function openMail(id) {
        Quickshell.execDetached(["xdg-open", "https://mail.google.com/mail/u/0/#inbox/" + id])
    }

    // back off on battery: each poll is an HTTPS round-trip that wakes the Wi-Fi
    // radio out of power-save, 720 times a day at the 2-minute cadence
    property Timer _mailPoll: Timer {
        interval: (Globals.lowPower ? 5 : 2) * 60 * 1000
        running: goo.signedIn; repeat: true   // sessionReady does the first fetch
        onTriggered: goo.fetchMail()
    }
    property Connections _mailQsHook: Connections {
        target: Globals
        function onQuickSettingsOpenChanged() {
            if (Globals.quickSettingsOpen && goo.signedIn && Date.now() - goo.mailLastFetch > 60 * 1000) goo.fetchMail()
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
