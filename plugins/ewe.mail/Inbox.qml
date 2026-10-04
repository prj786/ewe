pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Inbox — THE inbox model of the ewe.mail add-on, read by the bar envelope,
// the Inbox page and the `mail` IPC target. Two sources, one shape:
//   · any IMAP account — the core `ewe-mail` CLI (account in ewe.conf
//     [accounts.mail], password in the keyring). Was the shell's Mail.qml.
//   · Gmail — through the user's own Google client; the access token comes
//     from the core `ewe-auth token` broker (RFC-002), the refresh token
//     never leaves the keyring. Was the Gmail half of the shell's Google.qml
//     (unread badge, History-API cursor for genuinely NEW mail, the list,
//     the notifications); OAuth, Calendar, Drive and settings sync stay core.
// IMAP wins when it is configured. New-mail notifications fire once per
// message id, persisted so a restart never re-notifies; the toggle is shared.
// Rule 2: nothing secret is ever written — the state files hold ids, flags,
// counts and the latest rows; tokens live in memory only.
QtObject {
    id: ml

    // the core CLIs, called the way the shell calls them: ~/.config/quickshell
    // is a symlink into the payload, so `../../bin` is the payload's bin/
    readonly property string eweMail: Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-mail"
    readonly property string eweAuth: Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-auth"

    // ── IMAP account (from ewe-mail status) ──
    property bool probed: false
    property bool imapConfigured: false
    property string imapHost: ""
    property string imapUser: ""
    property bool imapKeyring: true      // the password is in the keyring
    property int imapUnread: 0
    property var imapList: []
    property string imapState: ""        // "" | "offline" | "auth"
    property string imapError: ""
    property double imapLastFetch: 0

    // ── Gmail session (from ewe-auth status / token) ──
    property bool gmailProbed: false
    property bool gmailConfigured: false // the broker has a client file
    property bool gmailSignedIn: false
    property string busy: ""             // "" | "token"

    // ── the one shape the widgets read ──
    readonly property string source: imapConfigured ? "imap" : (gmailSignedIn ? "gmail" : "")
    readonly property bool available: source !== ""
    readonly property string title: source === "imap" ? imapUser : source === "gmail" ? "Gmail" : "Mail"
    readonly property int unread: source === "imap" ? imapUnread : source === "gmail" ? mailUnread : 0
    readonly property var list: source === "imap" ? imapList : source === "gmail" ? mailList : []
    readonly property string state: source === "imap" ? imapState : source === "gmail" ? mailState : ""
    readonly property string error: source === "imap" ? imapError : source === "gmail" ? mailError : ""
    readonly property bool needsReconnect: source === "gmail" && mailState === "scope"
    property bool notify: true
    function setNotify(v) { ml.notify = v; ml._saveState(); if (ml.gmailConfigured) ml.setMailNotify(v) }
    // a Gmail re-consent happens in the account app (ewe-sync owns Google
    // sign-in since RFC-005/006; the shell's `google signIn` is not ours to call)
    function reconnect() {
        if (ml.source !== "gmail") return
        if (!Shell.launch("io.github.prj786.ewe-sync")) Quickshell.execDetached(["ewe-sync"])
    }
    function fetch() {
        if (source === "imap") ml.fetchImap()
        else if (source === "gmail") ml.fetchMail()
    }
    function open(id) {
        if (source === "gmail") ml.openMail(id)
        else Quickshell.execDetached(["xdg-open", "mailto:"])
    }
    function openInbox() {
        if (source === "gmail") Quickshell.execDetached(["xdg-open", "https://mail.google.com/mail/u/0/"])
        else Quickshell.execDetached(["xdg-open", "mailto:"])
    }
    readonly property string inboxLabel: source === "gmail" ? "Open Gmail" : "Open mail"
    readonly property string hint: "Add a mail account (Settings → Account → Mail) or connect Google to see mail here."

    // the `mail status` snapshot — byte-compatible with the shell's: ewe-settings reads it
    function statusJson() {
        return JSON.stringify({
            probed: ml.probed, source: ml.source, available: ml.available, title: ml.title,
            imapConfigured: ml.imapConfigured, imapHost: ml.imapHost, imapUser: ml.imapUser, imapKeyring: ml.imapKeyring,
            unread: ml.unread, state: ml.state, error: ml.error, notify: ml.notify, needsReconnect: ml.needsReconnect
        })
    }
    // `mail refresh`: re-read both accounts, then fetch
    function refresh() { ml.probe(); ml.probeGmail(); ml.fetch() }

    // ══ IMAP ══════════════════════════════════════════════════════════════════
    function probe() { _statusProc.running = false; _statusProc.running = true }
    property Process _statusProc: Process {
        running: true
        command: ["python3", ml.eweMail, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                var was = ml.imapConfigured
                try {
                    var j = JSON.parse(this.text)
                    ml.imapConfigured = !!j.configured
                    ml.imapHost = String(j.host || ""); ml.imapUser = String(j.user || "")
                    ml.imapKeyring = j.keyring !== false
                } catch (e) { ml.imapConfigured = false }
                ml.probed = true
                if (ml.imapConfigured && !was) ml.fetchImap()
                if (!ml.imapConfigured && was) { ml.imapUnread = 0; ml.imapList = []; ml.imapState = ""; ml.imapError = "" }
            }
        }
    }
    // the account record lives in the one file: re-probe when it changes
    property FileView _confWatch: FileView {
        path: Quickshell.env("HOME") + "/.config/ewe/ewe.conf"
        watchChanges: true
        printErrors: false
        onFileChanged: ml._reprobe.restart()
    }
    property Timer _reprobe: Timer { interval: 1500; onTriggered: ml.probe() }

    property bool _fetching: false
    function fetchImap() {
        if (!ml.imapConfigured || ml._fetching) return
        ml._fetching = true
        _unseenProc.running = false; _unseenProc.running = true
    }
    property Process _unseenProc: Process {
        command: ["python3", ml.eweMail, "unseen", "--limit", "10"]
        stdout: StdioCollector {
            onStreamFinished: {
                ml._fetching = false
                try {
                    var j = JSON.parse(this.text)
                    if (j.ok) {
                        ml.imapState = ""; ml.imapError = ""
                        ml.imapUnread = j.unread || 0
                        ml.imapList = j.list || []
                        // judge "first fetch ever" BEFORE the stamp moves — stamped
                        // first, it never was the first fetch and every already-unread
                        // message toasted on a fresh account (2026-09-20)
                        var first = Object.keys(ml._notified).length === 0 && ml.imapLastFetch === 0
                        ml.imapLastFetch = Date.now()
                        ml._notifyNew(ml.imapList, first)
                        ml._saveState()
                    } else if (j.error === "auth-failed" || j.error === "no-password") {
                        ml.imapState = "auth"; ml.imapError = "The mail server rejected the login — sign in to the mail account again in Settings → Account."
                    } else if (j.error === "not-configured") {
                        ml.imapConfigured = false
                    } else {
                        ml.imapState = "offline"
                    }
                } catch (e) { ml.imapState = "offline" }
            }
        }
    }
    // new-mail toasts: once per message id, at most five named per fetch
    readonly property int notifyBurst: 5
    property var _notified: ({})
    property bool _stateLoaded: false
    // the pre-add-on path, so an upgrade keeps the notified-set (no re-notify storm)
    readonly property string statePath: Quickshell.env("HOME") + "/.config/quickshell/mail-state.json"
    property Process _stateLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/mail-state.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (j.notified && typeof j.notified === "object") ml._notified = j.notified
                    if (j.notify !== undefined) ml.notify = !!j.notify
                    if (ml.imapLastFetch === 0) {
                        if (j.unread !== undefined) ml.imapUnread = j.unread
                        if (Array.isArray(j.list)) ml.imapList = j.list
                    }
                } catch (e) {}
                ml._stateLoaded = true
            }
        }
    }
    // an atomic write (tmp + mv) through one sh — the shell's own files are
    // written the same way; a plugin has no HyprMon, so the helper lives here
    function _atomicWrite(proc, path, content) {
        proc.command = ["sh", "-c",
            'mkdir -p "$(dirname "$1")" && cat > "$1.tmp" <<\'EWE_MAIL_EOF_7f3a\'\n' + content + '\nEWE_MAIL_EOF_7f3a\nmv "$1.tmp" "$1"',
            "ewe-mail", path]
        proc.running = false; proc.running = true
    }
    property Process _stateWriter: Process {}
    property Timer _saveT: Timer {
        interval: 200
        onTriggered: ml._atomicWrite(ml._stateWriter, ml.statePath, JSON.stringify({
            notified: ml._notified, notify: ml.notify, unread: ml.imapUnread, list: ml.imapList.slice(0, 15)
        }))
    }
    function _saveState() {
        var cut = Date.now() - 7 * 86400000
        for (var k in ml._notified) if (ml._notified[k] < cut) delete ml._notified[k]
        ml._saveT.restart()
    }
    function _notifyNew(rows, first) {
        if (!ml._stateLoaded) return
        // first fetch ever: everything currently unseen is "seen" — no storm
        var fresh = []
        for (var i = 0; i < rows.length; i++) {
            var id = String(rows[i].id || "")
            if (id === "" || ml._notified[id]) continue
            ml._notified[id] = Date.now()
            if (!first) fresh.push(rows[i])
        }
        if (!ml.notify || fresh.length === 0) return
        for (var f = 0; f < Math.min(fresh.length, ml.notifyBurst); f++)
            Quickshell.execDetached(["notify-send", "-a", "Mail", "-i", "mail-unread", fresh[f].from || "New mail", fresh[f].subject || ""])
        if (fresh.length > ml.notifyBurst)
            Quickshell.execDetached(["notify-send", "-a", "Mail", "-i", "mail-unread", "New mail", (fresh.length - ml.notifyBurst) + " more new messages in your inbox."])
    }

    // back off on battery: each poll wakes the radio
    property Timer _poll: Timer {
        interval: (Shell.lowPower ? 5 : 2) * 60 * 1000
        running: ml.imapConfigured; repeat: true
        onTriggered: ml.fetchImap()
    }

    // ══ Gmail session: who is signed in, and a token when one is needed ═══════
    // `ewe-auth status` says whether a Google client is configured and a
    // refresh token is stored; `ewe-auth token --json` hands out a short-lived
    // access token (runtime-cached by the broker, refreshed under a lock).
    function probeGmail() { _authStatus.running = false; _authStatus.running = true }
    property Process _authStatus: Process {
        running: true
        command: ["python3", ml.eweAuth, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                var was = ml.gmailSignedIn
                try {
                    var j = JSON.parse(this.text)
                    ml.gmailConfigured = !!j.configured
                    ml.gmailSignedIn = !!j.signed_in
                } catch (e) { /* the broker always prints JSON; treat garbage (or no broker) as signed-out */
                    ml.gmailConfigured = false; ml.gmailSignedIn = false
                }
                ml.gmailProbed = true
                if (ml.gmailSignedIn && !was) ml.fetchMail()          // the session is ready
                if (!ml.gmailSignedIn && was) ml._gmailClosed()
                // right after boot the first probe can race gnome-keyring coming
                // up and report signed-out even though a refresh token is stored
                // — re-probe with backoff instead of staying signed-out forever
                if (!ml.gmailSignedIn && ml.gmailConfigured && ml._probeRetries < 3) {
                    ml._probeRetries++
                    ml._probeRetry.interval = 5000 * ml._probeRetries
                    ml._probeRetry.restart()
                }
            }
        }
    }
    property int _probeRetries: 0
    property Timer _probeRetry: Timer { onTriggered: { if (!ml.gmailSignedIn) ml.probeGmail() } }
    // a sign-in or sign-out in the account app writes or removes this
    // non-secret record (client id + email) — re-probe when it moves
    property FileView _authWatch: FileView {
        path: Quickshell.env("HOME") + "/.config/ewe/auth.json"
        watchChanges: true
        printErrors: false
        onFileChanged: ml._authReprobe.restart()
    }
    property Timer _authReprobe: Timer { interval: 1500; onTriggered: { ml._probeRetries = 0; ml.probeGmail() } }
    function _gmailClosed() {
        ml._accessToken = ""; ml._expiresAt = 0
        ml.mailUnread = 0; ml.mailList = []; ml.mailState = ""; ml.mailError = ""
        ml._mailHistoryId = ""; ml._mailIds = []; ml._saveMailState()
    }

    // access-token cache — memory only, never persisted
    property string _accessToken: ""
    property double _expiresAt: 0
    property var _tokenWaiters: []
    // After a failed refresh, hold off for 5 min instead of asking the broker
    // again on every poll: a dead OAuth client produced 17 "token refresh
    // failed: deleted_client" in 12 minutes (2026-09-10). Cleared by a
    // successful refresh and by the wake path.
    property double _refreshFailedAt: 0
    function ensureToken(cb) {
        if (ml._accessToken !== "" && Date.now() < ml._expiresAt - 60000) { cb(ml._accessToken); return }
        if (ml._refreshFailedAt > 0 && Date.now() - ml._refreshFailedAt < 5 * 60 * 1000) { cb(""); return }
        ml._tokenWaiters.push(cb)
        if (ml.busy !== "token") {
            ml.busy = "token"
            _tokenProc.running = false; _tokenProc.running = true
        }
    }
    property Process _tokenProc: Process {
        command: ["python3", ml.eweAuth, "token", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (ml.busy === "token") ml.busy = ""
                var tok = ""
                try {
                    var j = JSON.parse(this.text)
                    if (j.ok) {
                        ml._accessToken = j.access_token
                        ml._expiresAt = j.expires_at * 1000
                        tok = j.access_token
                        ml._refreshFailedAt = 0
                    } else if (j.error === "signed-out" || j.error === "not-configured") {
                        // refresh token revoked, the client gone, or no client —
                        // the broker has already cleared its side; drop ours
                        var was = ml.gmailSignedIn
                        ml.gmailSignedIn = false
                        if (was) { ml._gmailClosed(); Log.warn("ewe.mail", "Gmail signed out:", j.reason || j.error) }
                    } else {
                        ml._refreshFailedAt = Date.now()
                        Log.warn("ewe.mail", "token refresh failed:", j.error)
                    }
                } catch (e) {
                    ml._refreshFailedAt = Date.now()
                    Log.error("ewe.mail", "ewe-auth token returned unparseable output")
                }
                var ws = ml._tokenWaiters
                ml._tokenWaiters = []
                for (var i = 0; i < ws.length; i++) ws[i](tok)   // "" → the api() call reports not-authorized
            }
        }
    }

    // ══ Gmail — INBOX unread badge, new-mail notifications and the list ═══════
    // Read-only scope. The History API cursor detects genuinely NEW arrivals
    // (no notification storm for pre-existing unread mail); the cursor and a
    // bounded notified-set persist so restarts never re-notify.
    property int mailUnread: 0
    property var mailList: []            // [{id, from, subject, snippet, date, unread}]
    property string mailState: ""        // "" | "offline" | "scope" (re-consent needed) | "api" (API disabled)
    property string mailError: ""
    property bool mailNotify: true       // desktop notifications for new mail
    property double mailLastFetch: 0
    property string _mailHistoryId: ""
    property var _mailNotified: ({})     // messageId -> epoch-ms (bounded, persisted)
    property var _mailIds: []            // current unread id set (change detector)
    // the pre-add-on path: the History cursor and the notified-set survive the upgrade
    readonly property string mailStatePath: Quickshell.env("HOME") + "/.config/quickshell/google-mail.json"

    property Process _mailWriter: Process {}
    // _saveMailState fires from several callbacks that can land in the same tick
    // (history → baseline → list refresh); coalesce the burst into one write
    property Timer _mailSaveT: Timer {
        interval: 200
        onTriggered: ml._atomicWrite(ml._mailWriter, ml.mailStatePath, JSON.stringify({
            historyId: ml._mailHistoryId, notified: ml._mailNotified,
            notify: ml.mailNotify, unread: ml.mailUnread, list: ml.mailList.slice(0, 15)
        }))
    }
    function _saveMailState() {
        var cut = Date.now() - 7 * 86400000
        for (var k in ml._mailNotified) if (ml._mailNotified[k] < cut) delete ml._mailNotified[k]
        ml._mailSaveT.restart()
    }
    property Process _mailLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/google-mail.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (j.historyId) ml._mailHistoryId = String(j.historyId)
                    if (j.notified && typeof j.notified === "object") ml._mailNotified = j.notified
                    if (j.notify !== undefined) ml.mailNotify = !!j.notify
                    if (ml.mailLastFetch === 0) {
                        if (j.unread !== undefined) ml.mailUnread = j.unread
                        if (Array.isArray(j.list)) ml.mailList = j.list
                    }
                } catch (e) {}
            }
        }
    }
    function setMailNotify(v) { ml.mailNotify = v; ml._saveMailState() }

    function fetchMail() {
        if (!ml.gmailSignedIn) return
        ml.api("GET", "https://gmail.googleapis.com/gmail/v1/users/me/labels/INBOX", null, function (st, j, err) {
            if (st === 200 && j) {
                ml.mailState = ""; ml.mailError = ""
                ml.mailUnread = j.messagesUnread || 0
                ml.mailLastFetch = Date.now()
                ml._mailHistory()
            } else if (st === 403 || st === 401) {
                var m = (j && j.error && j.error.message) ? String(j.error.message) : ""
                if (m.indexOf("disabled") >= 0 || m.indexOf("has not been used") >= 0) {
                    ml.mailState = "api"
                    ml.mailError = "Enable the Gmail API for your project in the Google Cloud console, then retry."
                } else {
                    ml.mailState = "scope"   // token predates the gmail scope
                    ml.mailError = "Gmail needs a new permission — reconnect your Google account."
                }
            } else if (err === "offline" || st === 0) {
                ml.mailState = "offline"
            }
        })
    }
    // How many new-mail toasts a single history walk may fire before it stops
    // naming them individually. A multi-hour suspend can surface dozens at once.
    readonly property int mailNotifyBurst: 5

    property var _mailFresh: ({})        // message ids gathered across history pages

    function _mailHistory() {
        if (ml._mailHistoryId === "") { ml._mailBaseline(); return }
        ml._mailFresh = {}
        ml._mailHistoryPage("", 0)
    }
    // history.list pages at ~100 records. Reading only the first page while still
    // advancing the cursor to j.historyId (which is the mailbox's CURRENT id, not
    // the last id on the page) silently dropped every arrival past page one and
    // left the cursor looking healthy — so walk the pages before committing.
    function _mailHistoryPage(pageToken, depth) {
        var url = "https://gmail.googleapis.com/gmail/v1/users/me/history?historyTypes=messageAdded&labelId=INBOX&startHistoryId="
                + ml._mailHistoryId
        if (pageToken !== "") url += "&pageToken=" + encodeURIComponent(pageToken)
        ml.api("GET", url, null, function (st, j, err) {
            if (st === 404) { ml._mailFresh = {}; ml._mailBaseline(); return }   // cursor aged out — reconcile silently
            if (st !== 200 || !j) { ml._mailFresh = {}; ml._refreshMailList(); return }
            var hs = j.history || []
            for (var h = 0; h < hs.length; h++)
                for (var a = 0; a < (hs[h].messagesAdded || []).length; a++) {
                    var msg = hs[h].messagesAdded[a].message
                    if (msg && msg.id && !ml._mailNotified[msg.id]) ml._mailFresh[msg.id] = true
                }
            if (j.nextPageToken) {
                if (depth < 20) { ml._mailHistoryPage(String(j.nextPageToken), depth + 1); return }
                // gap too large to walk — rebaseline rather than advance the cursor
                // past pages we never read
                Log.warn("ewe.mail", "gmail history gap over", depth, "pages — rebaselining")
                ml._mailFresh = {}
                ml._mailBaseline()
                return
            }
            if (j.historyId) ml._mailHistoryId = String(j.historyId)
            var ids = Object.keys(ml._mailFresh)
            ml._mailFresh = {}
            if (ids.length > 0) Log.info("ewe.mail", "gmail:", ids.length, "new message(s) since the cursor")
            for (var i = 0; i < ids.length; i++) {
                ml._mailNotified[ids[i]] = Date.now()
                if (ml.mailNotify && i < ml.mailNotifyBurst) ml._notifyMail(ids[i])
            }
            // one summary instead of a toast storm for the rest
            if (ml.mailNotify && ids.length > ml.mailNotifyBurst)
                Quickshell.execDetached(["notify-send", "-a", "Gmail", "-i", "mail-unread",
                    "New mail", (ids.length - ml.mailNotifyBurst) + " more new messages in your inbox."])
            ml._saveMailState()
            ml._refreshMailList()
        })
    }
    // (re)baseline the history cursor; everything currently unread is "seen"
    function _mailBaseline() {
        ml.api("GET", "https://gmail.googleapis.com/gmail/v1/users/me/profile", null, function (st, j, err) {
            if (st === 200 && j && j.historyId) ml._mailHistoryId = String(j.historyId)
            ml.api("GET", "https://gmail.googleapis.com/gmail/v1/users/me/messages?q=" + encodeURIComponent("is:unread in:inbox") + "&maxResults=15",
                    null, function (st2, j2, err2) {
                var ms = (st2 === 200 && j2 && j2.messages) ? j2.messages : []
                for (var i = 0; i < ms.length; i++) ml._mailNotified[ms[i].id] = Date.now()
                ml._saveMailState()
                ml._refreshMailList()
            })
        })
    }
    function _refreshMailList() {
        ml.api("GET", "https://gmail.googleapis.com/gmail/v1/users/me/messages?q=" + encodeURIComponent("in:inbox") + "&maxResults=10",
                null, function (st, j, err) {
            if (st !== 200 || !j) return
            var ms = j.messages || []
            var ids = ms.map(function (m) { return m.id })
            if (JSON.stringify(ids) === JSON.stringify(ml._mailIds) && ml.mailList.length > 0) return
            ml._mailIds = ids
            if (ids.length === 0) { ml.mailList = []; ml._saveMailState(); return }
            var out = [], pending = ids.length
            for (var i = 0; i < ids.length; i++) ml._mailMeta(ids[i], function (row) {
                if (row) out.push(row)
                if (--pending === 0) {
                    out.sort(function (a, b) { return b.date - a.date })
                    ml.mailList = out
                    ml._saveMailState()
                }
            })
        })
    }
    function _mailMeta(id, cb) {
        ml.api("GET", "https://gmail.googleapis.com/gmail/v1/users/me/messages/" + id
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
        ml._mailMeta(id, function (row) {
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
        interval: (Shell.lowPower ? 5 : 2) * 60 * 1000
        running: ml.gmailSignedIn; repeat: true   // the status probe does the first fetch
        onTriggered: ml.fetchMail()
    }

    // ══ shared hooks ══════════════════════════════════════════════════════════
    // Quick settings opening refreshes a stale inbox (>1 min); signed-out but
    // configured Google re-checks the keyring (the boot probe may have raced it)
    property Connections _qsHook: Connections {
        target: Shell
        function onQuickSettingsOpenChanged() {
            if (!Shell.quickSettingsOpen) return
            if (ml.imapConfigured && Date.now() - ml.imapLastFetch > 60 * 1000) ml.fetchImap()
            if (ml.gmailSignedIn && Date.now() - ml.mailLastFetch > 60 * 1000) ml.fetchMail()
            else if (!ml.gmailSignedIn && ml.gmailConfigured && ml.busy === "") ml.probeGmail()
        }
    }
    // Shell.resumed (the wake sequence's network step): refetch IMAP; every
    // Gmail access token minted before the suspend is stale — drop it and
    // refresh once up front instead of letting the next poll fail a request
    function refreshAfterResume() {
        if (ml.imapConfigured) ml.fetchImap()
        ml._accessToken = ""
        ml._expiresAt = 0
        ml._refreshFailedAt = 0
        if (!ml.gmailConfigured) return
        if (!ml.gmailSignedIn) {
            // a keyring that was locked at login leaves the shell believing it is
            // signed out forever — a wake is a fair moment to try again
            ml._probeRetries = 0
            ml.probeGmail()
            return
        }
        ml.ensureToken(function (tok) {
            if (tok === "") { Log.warn("ewe.mail", "resume: token refresh failed — the poll keeps its own retries"); return }
            ml.fetchMail()
        })
    }

    // ── thin API layer: Bearer header, one 401-refresh-retry, JSON parse ───────
    // cb(status, json, err) — err ∈ "" | "offline" | "not-authorized"
    function api(method, url, opts, cb) { ml._apiCall(method, url, opts, cb, true) }
    function _apiCall(method, url, opts, cb, retry) {
        ml.ensureToken(function (tok) {
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
                    ml._accessToken = ""; ml._expiresAt = 0
                    ml._apiCall(method, url, opts, cb, false)
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
