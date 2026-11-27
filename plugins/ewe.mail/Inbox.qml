pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Inbox — THE inbox model of the ewe.mail plugin, read by the bar envelope,
// the Inbox page and the `mail` IPC target.
//
// One source since 2.0: **ewe Mail** (`ewe-mail-app --inbox`), the mail app
// ewe installs with the desktop. It looks at every account — Gmail through
// your own Google client, any other mailbox from ewe Sync → Mail — with the
// one engine and the one cache its window uses, and answers in one JSON
// line. The plugin no longer polls Gmail or IMAP itself: one Gmail poller,
// no token or password anywhere near the shell.
//
// New-mail notifications fire once per message, the first look after an
// upgrade marks everything already there as seen (never a storm), and a
// click on one opens the message in ewe Mail. Rule 2: the state file holds
// ids, flags, counts and the latest rows — nothing secret exists here.
QtObject {
    id: ml

    // ── what ewe Mail said ──
    property bool probed: false          // the first answer is in
    property bool hasApp: true           // ewe-mail-app ran (false: not installed)
    property var accounts: []            // [{id, kind, email, name, state, message, can_send, unread, host?, user?}]
    property var list: []                // [{account, folder, id, thread, from, subject, snippet, date, unread}]
    property int unread: 0
    property string state: ""            // "" | "offline" | "auth" | "app" (ewe Mail missing or failing)
    property string error: ""
    property double lastFetch: 0

    // ── the 1.x status fields, kept (Rule 4: `mail status` is public) ──
    readonly property var _imap: accounts.filter(function (a) { return a.kind === "imap" })
    readonly property var _gmail: accounts.filter(function (a) { return a.kind === "gmail" })
    readonly property bool imapConfigured: _imap.length > 0
    readonly property string imapHost: imapConfigured ? String(_imap[0].host || "") : ""
    readonly property string imapUser: imapConfigured ? String(_imap[0].user || _imap[0].email || "") : ""
    readonly property bool imapKeyring: !imapConfigured || _imap[0].state !== "keyring"
    readonly property string source: imapConfigured ? "imap" : (_gmail.length > 0 ? "gmail" : "")
    readonly property bool available: accounts.length > 0
    readonly property string title: accounts.length === 1 ? String(accounts[0].email) : (available ? "Inbox" : "Mail")
    // Gmail that can only read: ewe Sync's Google page asks Google again
    readonly property bool needsReconnect: _gmail.some(function (a) { return a.state === "scope" })

    readonly property string inboxLabel: "Open ewe Mail"
    readonly property string hint: ml.hasApp
        ? "Add a mail account or connect Google in ewe Sync to see mail here."
        : "ewe Mail isn’t installed — the Inbox reads your mail through it. Install it with Komble."

    // Komble → Plugins → Mail → Options, also flipped by the bell on the
    // Inbox page and `mail setNotify` — those write the setting through
    // Shell.setSetting, so there is one value, not a second copy in a state
    // file. applyNotify is what the setting arriving (Service.qml) calls.
    property bool notify: true
    function applyNotify(v) {
        v = !!v
        if (ml.notify === v) return
        ml.notify = v; ml._saveState()
    }
    function setNotify(v) {
        ml.applyNotify(v)
        if (typeof Shell.setSetting === "function") Shell.setSetting("ewe.mail", "notify", !!v)
    }
    // 1.0 kept the toggle in mail-state.json: an "off" there is carried into
    // the setting once (notifyCarried), then the setting is the only truth
    property bool _notifyCarried: false

    // the `mail status` snapshot — the 1.x field set, in order (test-asserted)
    function statusJson() {
        return JSON.stringify({
            probed: ml.probed, source: ml.source, available: ml.available, title: ml.title,
            imapConfigured: ml.imapConfigured, imapHost: ml.imapHost, imapUser: ml.imapUser, imapKeyring: ml.imapKeyring,
            unread: ml.unread, state: ml.state, error: ml.error, notify: ml.notify, needsReconnect: ml.needsReconnect
        })
    }

    // ══ opening things in ewe Mail ═══════════════════════════════════════════
    function openRow(r) {
        if (!r || !r.account || !r.id) { ml.openInbox(); return }
        Quickshell.execDetached(["ewe-mail-app", "--open", String(r.account), String(r.folder || "INBOX"), String(r.id)])
    }
    function open(id) {
        for (var i = 0; i < ml.list.length; i++)
            if (String(ml.list[i].id) === String(id)) { ml.openRow(ml.list[i]); return }
        ml.openInbox()
    }
    function openInbox() {
        if (!Shell.launch("io.github.prj786.ewe-mail")) Quickshell.execDetached(["ewe-mail-app"])
    }
    // a Gmail re-consent happens in the account app (ewe Sync owns Google
    // sign-in since RFC-005/006): straight to its Google page
    function reconnect() { Quickshell.execDetached(["ewe-sync", "--pane", "google"]) }

    // ══ the look: `ewe-mail-app --inbox` ═════════════════════════════════════
    // `mail refresh` and `mail fetch` are the same look now: the accounts are
    // read again on every one
    function refresh() { ml.fetch() }
    property bool _fetching: false
    function fetch() {
        if (ml._fetching) return
        ml._fetching = true
        _inboxProc.running = false; _inboxProc.running = true
    }
    property Process _inboxProc: Process {
        running: true
        // through sh, so a missing ewe Mail is an answer too, not silence
        command: ["sh", "-c", "command -v ewe-mail-app >/dev/null 2>&1 || { echo NOAPP; exit 0; }; exec ewe-mail-app --inbox --limit 10"]
        stdout: StdioCollector {
            onStreamFinished: ml._took(this.text)
        }
    }
    function _took(text) {
        ml._fetching = false
        var j = null
        try { j = JSON.parse(text) } catch (e) {}
        ml.probed = true
        if (!j) {
            ml.hasApp = text.trim() !== "NOAPP"
            ml.state = "app"
            ml.error = ml.hasApp ? "ewe Mail did not answer." : ""
            if (!ml.hasApp) { ml.accounts = []; ml.list = []; ml.unread = 0 }
            return
        }
        ml.hasApp = true
        if (!j.ok) { ml.state = "app"; ml.error = String(j.message || j.error || "ewe Mail could not look at the mail."); return }
        ml.accounts = j.accounts || []
        ml.unread = Number(j.unread || 0)
        ml.list = j.list || []
        ml.lastFetch = Date.now()
        // the state in words: an account that cannot sign in is worth a line
        var bad = ml.accounts.filter(function (a) { return a.state === "auth" || a.state === "keyring" || a.state === "error" })
        var off = ml.accounts.length > 0 && ml.accounts.every(function (a) { return a.state === "offline" })
        ml.state = off ? "offline" : (bad.length ? "auth" : "")
        ml.error = bad.length ? String(bad[0].message || (bad[0].email + " can’t sign in — open ewe Sync’s Mail page.")) : ""
        ml._notifyNew(ml.list)
        ml._saveState()
    }

    // ══ new-mail notifications ═══════════════════════════════════════════════
    readonly property int notifyBurst: 5
    property var _seen: ({})             // "account/id" → when it was first seen
    property bool _baselined: false      // a look has happened since 2.0 (persisted)
    property bool _stateLoaded: false
    function _notifyNew(rows) {
        if (!ml._stateLoaded) return
        // the first look ever (or since 2.0): what is there now is "seen"
        var first = !ml._baselined
        ml._baselined = true
        var fresh = []
        for (var i = 0; i < rows.length; i++) {
            if (!rows[i].unread) continue
            var key = String(rows[i].account) + "/" + String(rows[i].id)
            if (ml._seen[key]) continue
            ml._seen[key] = Date.now()
            if (!first) fresh.push(rows[i])
        }
        if (!ml.notify || fresh.length === 0) return
        for (var f = 0; f < Math.min(fresh.length, ml.notifyBurst); f++) ml._toast(fresh[f])
        if (fresh.length > ml.notifyBurst)
            Quickshell.execDetached(["notify-send", "-a", "ewe Mail", "-i", "io.github.prj786.ewe-mail",
                "New mail", (fresh.length - ml.notifyBurst) + " more new messages in your inbox."])
    }
    // one message: a click opens it in ewe Mail (notify-send waits for the
    // click; an hour later it lets go). The text goes as arguments, never
    // into the script, and the body is escaped for the shell's markup-reading
    // notification server.
    function _toast(row) {
        var body = String(row.subject || "") + (row.snippet ? "\n" + row.snippet : "")
        var esc = body.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        Quickshell.execDetached(["sh", "-c",
            'a=$(timeout 3600 notify-send -a "ewe Mail" -i io.github.prj786.ewe-mail -A default=Open -- "$1" "$2" 2>/dev/null); '
            + '[ "$a" = default ] && exec ewe-mail-app --open "$3" "$4" "$5"',
            "ewe-mail-notify", String(row.from || "New mail"), esc,
            String(row.account), String(row.folder || "INBOX"), String(row.id)])
    }

    // ══ the state file (the pre-plugin path, kept) ═══════════════════════════
    readonly property string statePath: Quickshell.env("HOME") + "/.config/quickshell/mail-state.json"
    property Process _stateLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/mail-state.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (j.seen && typeof j.seen === "object") ml._seen = j.seen
                    ml._baselined = !!j.baselined
                    ml._notifyCarried = !!j.notifyCarried
                    if (j.notify === false && !ml._notifyCarried) ml.setNotify(false)
                    ml._notifyCarried = true
                    // the last look, until the first one of this session
                    if (ml.lastFetch === 0) {
                        if (j.unread !== undefined) ml.unread = Number(j.unread) || 0
                        if (Array.isArray(j.accounts)) ml.accounts = j.accounts
                        if (Array.isArray(j.list)) ml.list = j.list
                    }
                } catch (e) {}
                ml._stateLoaded = true
                // a look that finished before the file was read: judge it now
                if (ml.lastFetch > 0) ml._notifyNew(ml.list)
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
            seen: ml._seen, baselined: ml._baselined, notify: ml.notify, notifyCarried: ml._notifyCarried,
            unread: ml.unread, accounts: ml.accounts, list: ml.list.slice(0, 15)
        }))
    }
    function _saveState() {
        if (!ml._stateLoaded) return
        var cut = Date.now() - 14 * 86400000
        for (var k in ml._seen) if (ml._seen[k] < cut) delete ml._seen[k]
        ml._saveT.restart()
    }

    // ══ when to look ═════════════════════════════════════════════════════════
    // every 2 min (5 on battery: each look wakes the radio)
    property Timer _poll: Timer {
        interval: (Shell.lowPower ? 5 : 2) * 60 * 1000
        running: true; repeat: true
        onTriggered: ml.fetch()
    }
    // an account added or removed in ewe Sync, a Google sign-in or sign-out
    property FileView _confWatch: FileView {
        path: Quickshell.env("HOME") + "/.config/ewe/ewe.conf"
        watchChanges: true
        printErrors: false
        onFileChanged: ml._soon.restart()
    }
    property FileView _authWatch: FileView {
        path: Quickshell.env("HOME") + "/.config/ewe/auth.json"
        watchChanges: true
        printErrors: false
        onFileChanged: ml._soon.restart()
    }
    property Timer _soon: Timer { interval: 1500; onTriggered: ml.fetch() }
    // Quick settings opening looks again when the last look is over a minute old
    property Connections _qsHook: Connections {
        target: Shell
        function onQuickSettingsOpenChanged() {
            if (Shell.quickSettingsOpen && Date.now() - ml.lastFetch > 60 * 1000) ml.fetch()
        }
    }
    // Shell.resumed (the wake sequence's network step)
    function refreshAfterResume() { ml.fetch() }
}
