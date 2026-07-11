pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Accounts — the GNOME Online Accounts (GOA) + evolution-data-server (EDS)
// bridge. GOA (goa-daemon, org.gnome.OnlineAccounts) owns accounts and OAuth
// tokens; EDS (org.gnome.evolution.dataserver.*) is the data layer that GOA
// accounts auto-register into. Both run fine outside GNOME and are OPTIONAL:
// every property here degrades to empty/false when they're missing, and the
// User pane shows what to install instead.
//
//   accounts — from GOA's ObjectManager (busctl -j; no extra deps)
//   events   — upcoming calendar events via scripts/eds-query.py (python-gi)
//   contacts — read-only address-book entries via the same helper
//
// Adding an account reuses GNOME's working OAuth flow (gnome-control-center
// online-accounts) rather than reimplementing provider webflows — the native
// QtWebEngine flow is a later phase (see docs/SETTINGS-BACKEND.md).
QtObject {
    id: acc

    readonly property string home: Quickshell.env("HOME")

    property bool probed: false          // first probe finished (avoid "install…" flash)
    property bool goaAvailable: false    // org.gnome.OnlineAccounts reachable/activatable
    property bool edsAvailable: false    // EDS GI bindings importable
    property bool ccAvailable: false     // gnome-control-center (MVP add-account UI)
    property var accounts: []            // [{path,id,provider,providerName,identity,has*,…Disabled}]
    property var events: []              // [{summary,start,end,allDay,calendar}] next 14 days
    property var contacts: []            // [{name,emails,phones}]
    property string lastError: ""

    function refresh() {
        _envProbe.running = false; _envProbe.running = true
        _goaList.running = false; _goaList.running = true
    }
    function refreshData() {
        if (!edsAvailable) return
        _edsEvents.running = false; _edsEvents.running = true
        _edsContacts.running = false; _edsContacts.running = true
    }

    // ── GOA actions ───────────────────────────────────────────────────────────
    // service ∈ Calendar | Contacts | Mail | Files (the GOA property names are
    // <Service>Disabled, so `enabled` flips to disabled=!enabled)
    function setService(path, service, enabled) {
        _act.command = ["busctl", "--user", "call", "org.gnome.OnlineAccounts", path,
            "org.freedesktop.DBus.Properties", "Set", "ssv",
            "org.gnome.OnlineAccounts.Account", service + "Disabled", "b", enabled ? "false" : "true"]
        _act.running = false; _act.running = true
        _relist.restart()
    }
    function removeAccount(path) {
        _act.command = ["busctl", "--user", "call", "org.gnome.OnlineAccounts", path,
            "org.gnome.OnlineAccounts.Account", "Remove"]
        _act.running = false; _act.running = true
        _relist.restart()
    }
    // MVP add-account: reuse GNOME's OAuth flow, then poll GOA for the result.
    // XDG_CURRENT_DESKTOP=GNOME keeps gnome-control-center from refusing to run.
    function addAccount() {
        Quickshell.execDetached(["sh", "-c", "XDG_CURRENT_DESKTOP=GNOME gnome-control-center online-accounts >/dev/null 2>&1"])
        _pollLeft = 30
        _goaPoll.restart()
    }
    property int _pollLeft: 0

    // ── plumbing ──────────────────────────────────────────────────────────────
    property Process _envProbe: Process {
        command: ["sh", "-c",
            'echo "cc=$(command -v gnome-control-center >/dev/null 2>&1 && echo yes || echo no)";' +
            'echo "eds=$(python3 -c \'import gi; gi.require_version("EDataServer", "1.2")\' 2>/dev/null && echo yes || echo no)"']
        stdout: StdioCollector {
            onStreamFinished: {
                var ls = this.text.split("\n")
                for (var i = 0; i < ls.length; i++) {
                    if (ls[i] === "cc=yes") acc.ccAvailable = true
                    else if (ls[i] === "cc=no") acc.ccAvailable = false
                    else if (ls[i] === "eds=yes") { acc.edsAvailable = true; acc.refreshData() }
                    else if (ls[i] === "eds=no") acc.edsAvailable = false
                }
            }
        }
    }
    property Process _goaList: Process {
        command: ["sh", "-c",
            'busctl --user -j call org.gnome.OnlineAccounts /org/gnome/OnlineAccounts org.freedesktop.DBus.ObjectManager GetManagedObjects 2>/dev/null || echo GOA-UNAVAILABLE']
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim()
                if (t === "" || t.indexOf("GOA-UNAVAILABLE") >= 0) { acc.goaAvailable = false; acc.accounts = []; acc.probed = true; return }
                acc.goaAvailable = true
                acc.accounts = acc._parseGoa(t)
                acc.probed = true
            }
        }
    }
    function _propOf(iface, prop) { return iface && iface[prop] !== undefined ? iface[prop].data : undefined }
    function _parseGoa(text) {
        var out = []
        try {
            var j = JSON.parse(text)
            var objs = (j.data && j.data[0]) ? j.data[0] : {}
            for (var path in objs) {
                var ifaces = objs[path]
                var a = ifaces["org.gnome.OnlineAccounts.Account"]
                if (!a) continue
                out.push({
                    path: path,
                    id: _propOf(a, "Id") || "",
                    provider: _propOf(a, "ProviderType") || "",
                    providerName: _propOf(a, "ProviderName") || _propOf(a, "ProviderType") || "account",
                    identity: _propOf(a, "PresentationIdentity") || _propOf(a, "Identity") || "",
                    attention: _propOf(a, "AttentionNeeded") === true,
                    hasCalendar: !!ifaces["org.gnome.OnlineAccounts.Calendar"],
                    hasContacts: !!ifaces["org.gnome.OnlineAccounts.Contacts"],
                    hasMail: !!ifaces["org.gnome.OnlineAccounts.Mail"],
                    hasFiles: !!ifaces["org.gnome.OnlineAccounts.Files"],
                    calendarDisabled: _propOf(a, "CalendarDisabled") === true,
                    contactsDisabled: _propOf(a, "ContactsDisabled") === true,
                    mailDisabled: _propOf(a, "MailDisabled") === true,
                    filesDisabled: _propOf(a, "FilesDisabled") === true
                })
            }
            out.sort(function (x, y) { return x.providerName < y.providerName ? -1 : 1 })
        } catch (e) {}
        return out
    }
    property Process _act: Process {
        stdout: StdioCollector { onStreamFinished: { var t = this.text.trim(); if (t !== "" && t.indexOf("Call failed") >= 0) acc.lastError = t } }
    }
    property Timer _relist: Timer { interval: 900; onTriggered: { acc._goaList.running = false; acc._goaList.running = true; acc.refreshData() } }
    // after "Add account" — GOA state changes when the user finishes the OAuth
    // flow in gnome-control-center; poll for a couple of minutes
    property Timer _goaPoll: Timer {
        interval: 4000; repeat: true
        onTriggered: {
            acc._pollLeft--
            acc._goaList.running = false; acc._goaList.running = true
            if (acc._pollLeft <= 0) { stop(); acc.refreshData() }
        }
    }

    property Process _edsEvents: Process {
        command: ["python3", acc.home + "/.config/quickshell/scripts/eds-query.py", "events", "14"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    acc.events = j.events || []
                    if (j.error) acc.events = []
                } catch (e) { acc.events = [] }
            }
        }
    }
    property Process _edsContacts: Process {
        command: ["python3", acc.home + "/.config/quickshell/scripts/eds-query.py", "contacts"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    acc.contacts = j.contacts || []
                    if (j.error) acc.contacts = []
                } catch (e) { acc.contacts = [] }
            }
        }
    }
    // keep the calendar model fresh for the shell's calendar widget
    property Timer _dataTick: Timer { interval: 600000; running: acc.edsAvailable; repeat: true; onTriggered: acc.refreshData() }
}
