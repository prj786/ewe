pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Mail — THE inbox model the bar badge and the Control Center card read.
// Two sources, one shape: any IMAP account (bin/ewe-mail, recorded in
// ewe.conf [accounts.mail], password in the keyring) or Gmail through the
// optional Google client (Google.qml). IMAP wins when it is configured.
// New-mail notifications fire once per message id, persisted so a restart
// never re-notifies; the toggle is shared with Google's.
QtObject {
    id: ml

    readonly property string eweMail: Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-mail"

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

    // ── the one shape the widgets read ──
    readonly property string source: imapConfigured ? "imap" : (Google.signedIn ? "gmail" : "")
    readonly property bool available: source !== ""
    readonly property string title: source === "imap" ? imapUser : source === "gmail" ? "Gmail" : "Mail"
    readonly property int unread: source === "imap" ? imapUnread : source === "gmail" ? Google.mailUnread : 0
    readonly property var list: source === "imap" ? imapList : source === "gmail" ? Google.mailList : []
    readonly property string state: source === "imap" ? imapState : source === "gmail" ? Google.mailState : ""
    readonly property string error: source === "imap" ? imapError : source === "gmail" ? Google.mailError : ""
    readonly property bool needsReconnect: source === "gmail" && Google.mailState === "scope"
    property bool notify: true
    function setNotify(v) { ml.notify = v; ml._saveState(); if (Google.configured) Google.setMailNotify(v) }
    function reconnect() { if (source === "gmail") Google.signIn() }
    function fetch() {
        if (source === "imap") ml.fetchImap()
        else if (source === "gmail") Google.fetchMail()
    }
    function open(id) {
        if (source === "gmail") Google.openMail(id)
        else Quickshell.execDetached(["xdg-open", "mailto:"])
    }
    function openInbox() {
        if (source === "gmail") Quickshell.execDetached(["xdg-open", "https://mail.google.com/mail/u/0/"])
        else Quickshell.execDetached(["xdg-open", "mailto:"])
    }
    readonly property string inboxLabel: source === "gmail" ? "Open Gmail" : "Open mail"
    readonly property string hint: "Add a mail account (Settings → Account → Mail) or connect Google to see mail here."

    // ── IPC for the Settings app (mail account setup lives there) ──
    property IpcHandler _ipc: IpcHandler {
        target: "mail"
        function refresh(): void { ml.probe(); ml.fetch() }
        function fetch(): void { ml.fetch() }
        function setNotify(on: bool): void { ml.setNotify(on) }
        function status(): string {
            return JSON.stringify({
                probed: ml.probed, source: ml.source, available: ml.available, title: ml.title,
                imapConfigured: ml.imapConfigured, imapHost: ml.imapHost, imapUser: ml.imapUser, imapKeyring: ml.imapKeyring,
                unread: ml.unread, state: ml.state, error: ml.error, notify: ml.notify, needsReconnect: ml.needsReconnect
            })
        }
    }

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
                        ml.imapLastFetch = Date.now()
                        ml._notifyNew(ml.imapList)
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
    property Process _stateWriter: Process {}
    property Timer _saveT: Timer {
        interval: 200
        onTriggered: HyprMon.atomicWrite(ml._stateWriter, ml.statePath, JSON.stringify({
            notified: ml._notified, notify: ml.notify, unread: ml.imapUnread, list: ml.imapList.slice(0, 15)
        }))
    }
    function _saveState() {
        var cut = Date.now() - 7 * 86400000
        for (var k in ml._notified) if (ml._notified[k] < cut) delete ml._notified[k]
        ml._saveT.restart()
    }
    function _notifyNew(rows) {
        if (!ml._stateLoaded) return
        // first fetch ever: everything currently unseen is "seen" — no storm
        var first = Object.keys(ml._notified).length === 0 && ml.imapLastFetch === 0
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
        interval: (Globals.lowPower ? 5 : 2) * 60 * 1000
        running: ml.imapConfigured; repeat: true
        onTriggered: ml.fetchImap()
    }
    property Connections _qsHook: Connections {
        target: Globals
        function onQuickSettingsOpenChanged() {
            if (Globals.quickSettingsOpen && ml.imapConfigured && Date.now() - ml.imapLastFetch > 60 * 1000) ml.fetchImap()
        }
    }
    function refreshAfterResume() { if (ml.imapConfigured) ml.fetchImap() }
}
