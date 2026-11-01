pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// RemoteState — Remote (RFC-009): "Share this computer" and "Your
// computers". One source for the bar glyph, the Control Centre tile and the
// "remote" page; every action is bin/ewe-remote (JSON, exit 0).
//
// Event-driven, no polling loop: a status read at start, when Quick settings
// opens, after every action, and on every login/logout line the sharing
// unit's sshd writes to the journal (followed only while sharing is on).
// The bar glyph is a SECURITY indicator — it shows whenever this computer
// is shared, in the accent while someone is connected.
QtObject {
    id: rs

    readonly property string helper: Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-remote"

    property bool probed: false
    property bool sharing: false
    property int port: 0
    property string code: ""              // only while sharing
    property string codeDisplay: ""       // "4821 9035"
    property var sessions: []             // live: [{id, name, from, since}]
    property var allowed: []              // computers that may log in here: [{id, name, since}]
    property var computers: []            // your other computers: [{id, name, sharing, online, paired, allowed, tunnel}]
    property string thisId: ""
    property string thisName: ""
    property bool tailscaleInstalled: false
    property bool tailscaleRunning: false
    property string registry: ""          // ok · cached · not-signed-in · offline
    property string busy: ""              // "" · share · code · pair · act
    property string pairTarget: ""        // the computer whose code field is open
    property string pairError: ""
    property string lastError: ""

    // real people at the keyboard elsewhere; a pairing in flight is not one
    readonly property var people: sessions.filter(function (s) { return s.id && s.id !== "pairing" })
    readonly property int connectedCount: people.length
    readonly property string connectedNames: {
        var seen = [], n = []
        for (var i = 0; i < people.length; i++) {
            var nm = people[i].name || "a computer"
            if (seen.indexOf(nm) < 0) { seen.push(nm); n.push(nm) }
        }
        return n.join(", ")
    }

    function refresh(fromAccount) {
        rs._refreshAccount = rs._refreshAccount || !!fromAccount
        if (rs._statusProc.running) { rs._again = true; return }
        rs._statusProc.command = ["python3", rs.helper, "status", rs._refreshAccount ? "--refresh" : "--offline"]
        rs._refreshAccount = false
        rs._statusProc.running = true
    }
    property bool _refreshAccount: false
    property bool _again: false

    function _apply(j) {
        if (!j || !j.ok) return
        var t = j["this"] || {}
        var before = {}
        for (var i = 0; i < rs.people.length; i++) before[rs.people[i].id] = true
        rs.sharing = !!t.sharing
        rs.port = t.port || 0
        rs.code = t.code || ""
        rs.codeDisplay = t.code_display || ""
        rs.sessions = t.sessions || []
        rs.allowed = t.allowed || []
        rs.thisId = t.id || ""
        rs.thisName = t.name || ""
        rs.computers = (j.computers || []).filter(function (c) { return c.paired || c.sharing !== null })
        rs.registry = j.registry || ""
        rs.tailscaleInstalled = !!(j.tailscale && j.tailscale.installed)
        rs.tailscaleRunning = !!(j.tailscale && j.tailscale.running)
        rs.probed = true
        // someone just arrived: say so once (the bar glyph keeps saying it)
        if (rs._seenFirst) {
            for (var k = 0; k < rs.people.length; k++) {
                var p = rs.people[k]
                if (!before[p.id]) Shell.toast((p.name || "A computer") + " is connected to this computer", "warning")
            }
        }
        rs._seenFirst = true
    }
    property bool _seenFirst: false

    property Process _statusProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { rs._apply(JSON.parse(this.text)) } catch (e) { Log.warn("remote", "status: unreadable", e) }
                if (rs._again) { rs._again = false; rs.refresh(false) }
            }
        }
    }

    // ── actions: one at a time; each ends in a fresh status ──
    property string _actKind: ""
    property var _actDone: null
    function _act(kind, args, done) {
        if (rs._actProc.running) return false
        rs.busy = kind
        rs.lastError = ""
        rs._actKind = kind
        rs._actDone = done || null
        rs._actProc.command = ["python3", rs.helper].concat(args)
        rs._actProc.running = true
        return true
    }
    property Process _actProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var j = null
                try { j = JSON.parse(this.text) } catch (e) { j = { ok: false, message: "ewe-remote said nothing readable" } }
                rs.busy = ""
                if (!j.ok) {
                    rs.lastError = j.message || j.error || "failed"
                    if (rs._actKind !== "pair") Shell.toast(rs.lastError, "danger")
                }
                if (rs._actDone) rs._actDone(j)
                rs._actDone = null
                rs.refresh(rs._actKind === "share")
            }
        }
    }

    function setSharing(on) { rs._act("share", ["share", on ? "on" : "off"]) }
    function newCode() { rs._act("code", ["code", "--new"]) }
    function openPair(id) { rs.pairTarget = rs.pairTarget === id ? "" : id; rs.pairError = "" }
    function pair(id, code) {
        rs.pairError = ""
        rs._act("pair", ["pair", id, code], function (j) {
            if (j.ok) {
                rs.pairTarget = ""
                Shell.toast("Paired with " + ((j.computer && j.computer.name) || "your computer"))
            } else {
                rs.pairError = j.message || "Pairing failed"
            }
        })
    }
    function revoke(id) { rs._act("act", ["revoke", id]) }
    function disconnect(id) { rs._act("act", ["disconnect", id]) }
    function forget(id) { rs._act("act", ["forget", id]) }
    function terminal(id) {
        rs._act("act", ["terminal", id], function (j) { if (j.ok) Shell.closeQuickSettings() })
    }
    // ewe browser's remote workspace: its traffic leaves from that computer
    function browse(id) {
        Quickshell.execDetached(["ewe-browser", "workspace", "create", "--remote", id])
        Shell.closeQuickSettings()
    }

    // ── who connects: follow the sharing server's own log while it runs ──
    property Process _follow: Process {
        running: rs.sharing
        // --pdeathsig: dies with the shell (see Bar.qml's nmcli monitor)
        command: ["setpriv", "--pdeathsig", "TERM", "--", "journalctl", "--user", "-u", "ewe-remote-sshd.service",
                  "-f", "-n", "0", "-o", "cat"]
        stdout: SplitParser {
            onRead: function (line) {
                if (/Accepted publickey|Disconnected from|Connection closed|Received disconnect|Close session|Connection reset/.test(line))
                    rs._settle.restart()
            }
        }
    }
    property Timer _settle: Timer { interval: 600; onTriggered: rs.refresh(false) }

    // the account listing goes stale; re-read it when Quick settings opens
    property Connections _qs: Connections {
        target: Globals
        function onQuickSettingsOpenChanged() { if (Globals.quickSettingsOpen) rs.refresh(true) }
    }
    property Timer _boot: Timer { interval: 4000; running: true; onTriggered: rs.refresh(false) }
}
