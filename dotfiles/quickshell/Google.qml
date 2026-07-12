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
        function onSessionReady() { goo.checkCloud(); goo.fetchCalendar(); goo.fetchMail() }
        function onSessionClosed() {
            goo.cloudInfo = null; goo._cloudBundle = null; goo._cloudFileId = ""
            goo.pendingRestore = null; goo.syncState = "idle"; goo.syncError = ""; goo.restoreSummary = ""
            goo.events = []; goo.calState = ""; goo._writeEventsCache()
            goo.mailUnread = 0; goo.mailList = []; goo.mailState = ""; goo.mailError = ""
            goo._mailHistoryId = ""; goo._mailIds = []; goo._saveMailState()
        }
    }

    // the last-downloaded cloud bundle (Settings' package-review card diffs it)
    function getCloudBundle() { return goo._cloudBundle }

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
            } else goo._syncFail(err === "offline" ? "offline — will keep the local copy" : goo._httpErrMsg("Drive upload", st, j))
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
    // surface Google's own error reason, not a bare HTTP code — first sentence
    // of the API message ("Google Drive API has not been used in project … or
    // it is disabled.") tells the user exactly what to fix
    function _httpErrMsg(what, st, j) {
        var m = (j && j.error && j.error.message) ? String(j.error.message) : ""
        if (m !== "") {
            var s = m.split(". ")[0]
            return what + ": " + s + (s.indexOf("disabled") >= 0 || s.indexOf("has not been used") >= 0
                ? ". Enable the API in the Google Cloud console, wait a minute, then retry." : " (HTTP " + st + ")")
        }
        return what + " failed (HTTP " + st + ")"
    }

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
                goo.restoreSummary = "Restored " + j.applied.length + " sections from “" + j.device + "”."
                    + (j.vpn && j.vpn.length ? " VPNs to re-import manually (profiles hold secrets and are never synced): " + j.vpn.join(", ") + "." : "")
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

    // ══════════════════════════════════════════════════════════════════════════
    // Calendar — poll events.list across every selected calendar (14-day window,
    // per-calendar colours), cache the last good fetch for offline, and fire
    // de-duped reminder notifications through the shell's own notification
    // server (notify-send → we ARE org.freedesktop.Notifications).
    // ══════════════════════════════════════════════════════════════════════════
    property var events: []              // [{id, summary, start, end, allDay, location, video, color, calendar, reminders:[min]}]
    property string calState: ""         // "" | "offline" (fetch failed, cache shown)
    property double lastFetch: 0
    property int _calPending: 0
    property var _calAccum: []
    readonly property string eventsCachePath: Quickshell.env("HOME") + "/.config/quickshell/google-events.json"
    readonly property string notifiedPath: Quickshell.env("HOME") + "/.config/quickshell/google-notified.json"

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
            goo._calPending = cals.length
            for (var i = 0; i < cals.length; i++) goo._fetchCalEvents(cals[i], timeMin, timeMax)
        })
    }
    function _fetchCalEvents(cal, timeMin, timeMax) {
        var url = "https://www.googleapis.com/calendar/v3/calendars/" + encodeURIComponent(cal.id)
                + "/events?singleEvents=true&orderBy=startTime&maxResults=100&timeMin=" + timeMin + "&timeMax=" + timeMax
        goo.api("GET", url, null, function (st, j, err) {
            if (st === 200 && j && j.items) {
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

    // ── reminders — once per (event, reminder-time), surviving restarts ────────
    property var _notified: ({})
    property bool _notifiedLoaded: false
    property Process _notifLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/google-notified.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { var j = JSON.parse(this.text); if (j && typeof j === "object") goo._notified = j } catch (e) {}
                goo._notifiedLoaded = true
            }
        }
    }
    property Process _notifWriter: Process {}
    property Timer _remTimer: Timer {
        interval: 60000; repeat: true
        running: goo.signedIn && goo.events.length > 0 && goo._notifiedLoaded
        onTriggered: goo._checkReminders()
    }
    function _evStartMs(e) {
        if (e.allDay && /^\d{4}-\d{2}-\d{2}$/.test(String(e.start))) {
            var p = String(e.start).split("-")
            return new Date(+p[0], +p[1] - 1, +p[2]).getTime()   // local midnight, not UTC
        }
        var d = new Date(e.start)
        return isNaN(d.getTime()) ? 0 : d.getTime()
    }
    function _checkReminders() {
        var now = Date.now(), dirty = false
        for (var i = 0; i < goo.events.length; i++) {
            var ev = goo.events[i]
            var start = goo._evStartMs(ev)
            if (start === 0 || start < now - 60000) continue     // started already — too late to remind
            for (var r = 0; r < (ev.reminders || []).length; r++) {
                var t = start - ev.reminders[r] * 60000
                var key = ev.id + "@" + t
                if (now < t || now >= t + 120000 || goo._notified[key]) continue
                goo._notified[key] = start
                dirty = true
                var when = new Date(start)
                var lead = ev.reminders[r]
                var body = (lead <= 0 ? "now" : "in " + lead + " min") + " · " + when.toLocaleTimeString(Qt.locale(), "h:mm AP")
                         + (ev.location !== "" ? "\n" + ev.location : "")
                         + (ev.video !== "" ? "\n" + ev.video : "")
                Quickshell.execDetached(["notify-send", "-a", "Calendar", "-i", "x-office-calendar", ev.summary, body])
            }
        }
        // prune keys whose event start is over a week gone
        for (var k in goo._notified) if (goo._notified[k] < now - 7 * 86400000) { delete goo._notified[k]; dirty = true }
        if (dirty) HyprMon.atomicWrite(goo._notifWriter, goo.notifiedPath, JSON.stringify(goo._notified))
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
    function _saveMailState() {
        var cut = Date.now() - 7 * 86400000
        for (var k in goo._mailNotified) if (goo._mailNotified[k] < cut) delete goo._mailNotified[k]
        HyprMon.atomicWrite(goo._mailWriter, goo.mailStatePath, JSON.stringify({
            historyId: goo._mailHistoryId, notified: goo._mailNotified,
            notify: goo.mailNotify, unread: goo.mailUnread, list: goo.mailList.slice(0, 15)
        }))
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
    function _mailHistory() {
        if (goo._mailHistoryId === "") { goo._mailBaseline(false); return }
        goo.api("GET", "https://gmail.googleapis.com/gmail/v1/users/me/history?historyTypes=messageAdded&labelId=INBOX&startHistoryId="
                + goo._mailHistoryId, null, function (st, j, err) {
            if (st === 404) { goo._mailBaseline(true); return }   // cursor aged out — reconcile silently
            if (st !== 200 || !j) { goo._refreshMailList(); return }
            if (j.historyId) goo._mailHistoryId = String(j.historyId)
            var fresh = {}
            var hs = j.history || []
            for (var h = 0; h < hs.length; h++)
                for (var a = 0; a < (hs[h].messagesAdded || []).length; a++) {
                    var msg = hs[h].messagesAdded[a].message
                    if (msg && msg.id && !goo._mailNotified[msg.id]) fresh[msg.id] = true
                }
            var ids = Object.keys(fresh)
            for (var i = 0; i < ids.length; i++) {
                goo._mailNotified[ids[i]] = Date.now()
                if (goo.mailNotify) goo._notifyMail(ids[i])
            }
            goo._saveMailState()
            goo._refreshMailList()
        })
    }
    // (re)baseline the history cursor; everything currently unread is "seen"
    function _mailBaseline(silent) {
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

    property Timer _mailPoll: Timer {
        interval: 2 * 60 * 1000; running: goo.signedIn; repeat: true   // sessionReady does the first fetch
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
