pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// ewe.vpn — THE state behind the tile, the page and the bar glyph: the
// NetworkManager VPN profiles (nmcli), which one is up, the connection in
// flight, and the inline sign-in form. The three entry points are pure
// consumers (the qmldir beside this file makes it a singleton of this
// plugin's own directory). Everything goes through nmcli exactly as the
// shell did; the NetworkManager secret prompt itself stays in the shell
// (Auth.qml) — this add-on only writes secrets INTO a profile on request.
//
// Freshness: one `nmcli monitor` (a single long-lived process that prints a
// line whenever NetworkManager changes anything) drives the re-reads, so a
// VPN coming up from Settings, a script or a cable plug shows at once
// without a timer. Plus one read at start, one after wake, and one whenever
// the tile or the page appears.
QtObject {
    id: vpn

    property var list: []               // [{ name, active }] — every vpn/wireguard/tun profile
    property bool active: false         // any VPN connection activated (the bar glyph)
    property string pending: ""         // "connect to X" / "disconnect from X" — the failure title
    property string busyName: ""        // connection being brought up/down — its row, the tile and the bar spin

    // what is on screen (the host injects panelOpen; the entry points mirror it)
    property bool tileOpen: false
    property bool pageOpen: false
    onTileOpenChanged: if (vpn.tileOpen) vpn.refresh()
    onPageOpenChanged: if (vpn.pageOpen) vpn.refresh()

    function refresh() { scanProc.running = true; activeProc.running = true }
    function rescanSoon() { rescan.restart() }

    // the body of the tile: GNOME semantics — disconnect the active VPN /
    // reconnect the single configured one; only when the choice is ambiguous
    // does the body open the list
    function toggleDefault() {
        var act = null
        for (var i = 0; i < vpn.list.length; i++) if (vpn.list[i].active) { act = vpn.list[i]; break }
        if (act) vpn.toggle(act.name, false)
        else if (vpn.list.length === 1) vpn.toggle(vpn.list[0].name, true)
        else Shell.openQuickSettings("vpn")
    }
    function toggle(name, up) {
        vpn.pending = (up ? "connect to " : "disconnect from ") + name
        vpn.busyName = name
        upProc.name = name
        upProc.command = ["nmcli", "connection", up ? "up" : "down", name]
        upProc.running = true
    }

    // ── credentials, inline ──
    // Nothing in ewe is a NetworkManager secret agent, so a profile without
    // stored secrets can only fail with "secrets were required … --ask". The
    // row then opens a credentials form; the secrets are written INTO the
    // profile (password-flags=0 — GNOME's "store for all users", root-only
    // file under /etc/NetworkManager) and the toggle just works from then on.
    // L2TP/IPsec (the corporate kind: server + user + password + PSK) is the
    // case that surfaced this (metal, 2026-09-02); OpenVPN gets the same form.
    property string credTarget: ""      // profile whose form is open
    property string credService: ""     // …l2tp | …openvpn | …
    property bool credNeedsPsk: false
    property string credUser: ""
    property string credPass: ""
    property string credPsk: ""
    property string credError: ""
    property bool credShow: false
    function askCredentials(name) {
        vpn.credTarget = name; vpn.credError = ""; vpn.credPass = ""; vpn.credPsk = ""
        vpn.credService = ""; vpn.credNeedsPsk = false
        infoProc.command = ["nmcli", "-t", "-g", "vpn.service-type,vpn.data", "connection", "show", name]
        infoProc.running = true
    }
    function closeCredentials() { vpn.credTarget = ""; vpn.credPass = ""; vpn.credPsk = ""; vpn.credError = "" }
    function nmEsc(v) { return String(v).replace(/,/g, "\\,") }   // nmcli splits dict values on ','
    function saveCredentials() {
        var name = vpn.credTarget
        if (name === "" || vpn.credUser === "" || vpn.credPass === "") { vpn.credError = "Enter a username and a password."; return }
        var l2tp = /l2tp$/.test(vpn.credService), ovpn = /openvpn$/.test(vpn.credService)
        var args = ["nmcli", "connection", "modify", name, "vpn.user-name", vpn.credUser, "+vpn.data", "password-flags=0"]
        if (l2tp) args.push("+vpn.data", "user=" + vpn.nmEsc(vpn.credUser))
        if (ovpn) args.push("+vpn.data", "username=" + vpn.nmEsc(vpn.credUser))
        args.push("+vpn.secrets", "password=" + vpn.nmEsc(vpn.credPass))
        if (l2tp && vpn.credPsk !== "") {
            args.push("+vpn.data", "ipsec-enabled=yes", "+vpn.data", "ipsec-psk-flags=0")
            args.push("+vpn.secrets", "ipsec-psk=" + vpn.nmEsc(vpn.credPsk))
        }
        vpn.credError = ""
        vpn.busyName = name
        credProc.name = name
        credProc.command = args
        credProc.running = true
    }

    // ── reads ──
    // every profile with its ACTIVE flag — the list and the tile's existence
    property Process scanProc: Process {
        command: ["sh", "-c", "nmcli -t -f NAME,TYPE,ACTIVE connection show 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n"), arr = []
                for (var i = 0; i < lines.length; i++) {
                    if (!lines[i]) continue
                    var p = lines[i].split(":")
                    var type = p[p.length - 2], active = p[p.length - 1] === "yes"
                    var name = p.slice(0, p.length - 2).join(":")
                    if (type && (type.indexOf("vpn") >= 0 || type.indexOf("wireguard") >= 0 || type.indexOf("tun") >= 0))
                        arr.push({ name: name, active: active })
                }
                vpn.list = arr
            }
        }
    }
    // is any VPN fully activated — what the bar's glyph says (the shell's query)
    property Process activeProc: Process {
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE connection show --active 2>/dev/null | awk -F: '($1 ~ /vpn|wireguard|tun/) && $2==\"activated\"{print \"yes\"; exit}'"]
        stdout: StdioCollector { onStreamFinished: vpn.active = (this.text.trim() === "yes") }
    }
    // NM emits a burst of lines per transition — coalesce them into one re-read
    property Timer debounce: Timer { interval: 400; onTriggered: vpn.refresh() }
    property int _monTries: 0
    property Process monitor: Process {
        running: true
        // --pdeathsig: dies with the shell even on an abrupt exit
        command: ["setpriv", "--pdeathsig", "TERM", "--", "nmcli", "monitor"]
        stdout: SplitParser { onRead: function (line) { vpn._monTries = 0; debounce.restart() } }
        // if NetworkManager isn't running, nmcli monitor exits immediately — back
        // off and stop rather than respawning it forever
        onExited: {
            if (vpn._monTries >= 5) { Log.warn("ewe.vpn", "nmcli monitor keeps exiting — the VPN state is read only when the panel opens"); return }
            vpn._monTries++
            monRestart.interval = 5000 * vpn._monTries
            monRestart.restart()
        }
    }
    property Timer monRestart: Timer { interval: 5000; onTriggered: monitor.running = true }
    // after a toggle: nmcli returns before the list says so
    property Timer rescan: Timer { interval: 2000; onTriggered: vpn.refresh() }
    // after wake: nmcli monitor usually dies with the link it was watching
    property Connections wake: Connections {
        target: Shell
        function onResumed() {
            vpn._monTries = 0
            if (!monitor.running) monitor.running = true
            vpn.refresh()
        }
    }
    Component.onCompleted: vpn.refresh()

    // ── writes ──
    // brings a VPN up/down; on failure raises a system notification with the error
    property Process upProc: Process {
        property string name: ""
        stderr: StdioCollector { id: upErr }
        onExited: function (exitCode, exitStatus) {
            vpn.busyName = ""
            vpn.rescanSoon()
            if (exitCode !== 0) {
                var msg = (upErr.text || "").trim()
                // no stored secrets (and no secret agent to ask): open the
                // credentials form on that row instead of only shouting
                if (/secrets|--ask|no agents|agent/i.test(msg)) { Shell.openQuickSettings("vpn"); vpn.askCredentials(upProc.name); return }
                if (vpn.credTarget === upProc.name) { vpn.credError = msg !== "" ? msg.split("\n")[0] : ("nmcli exited with code " + exitCode); return }
                var title = "Couldn’t " + vpn.pending, body = msg !== "" ? msg : ("nmcli exited with code " + exitCode)
                // "The VPN service failed to start" says nothing — the reason
                // is a journal line back; fetch it before shouting
                if (/VPN service failed to start|activation failed/i.test(msg)) {
                    whyProc.name = upProc.name; whyProc.title = title; whyProc.fallback = body
                    whyProc.running = false; whyProc.running = true
                    return
                }
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "VPN", title, body])
            }
        }
    }
    // NetworkManager reports a VPN plugin failure as "The VPN service failed
    // to start" and keeps the actual reason for the journal:
    //   vpn[…,"work-vpn"]: failed to connect: 'Could not establish IPsec connection.'
    // (that one is the strongSwan-6.1-has-no-IKEv1 case, 2026-09-10). Read the
    // last such line for this profile and put IT in the notification. The
    // journal is readable for wheel/systemd-journal members (the installing
    // user); anyone else just gets nmcli's line.
    property Process whyProc: Process {
        property string name: ""
        property string title: ""
        property string fallback: ""
        command: ["journalctl", "-u", "NetworkManager", "-n", "150", "-o", "cat", "--since", "-3min", "--no-pager"]
        stdout: StdioCollector {
            onStreamFinished: {
                var why = "", lines = (this.text || "").split("\n")
                for (var i = lines.length - 1; i >= 0; i--) {
                    if (lines[i].indexOf('"' + whyProc.name + '"') < 0) continue
                    var m = /failed to connect: '([^']+)'/.exec(lines[i])
                    if (m) { why = m[1]; break }
                }
                var body = whyProc.fallback
                if (why !== "") body = why + (/ipsec/i.test(why) ? " — L2TP/IPsec needs IKEv1: libreswan with ikev1-policy=accept (install.sh sets it up; see the manual's VPN section)" : "")
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "VPN", whyProc.title, body])
            }
        }
    }
    // what kind of profile is asking: service type decides the fields (L2TP
    // gets a pre-shared key), vpn.data prefills the username
    property Process infoProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var rows = this.text.split("\n")
                vpn.credService = (rows[0] || "").trim()
                var data = rows[1] || "", user = ""
                var m = /(?:^|,)\s*user(?:name)?\s*=\s*([^,]*)/.exec(data)
                if (m) user = m[1].trim()
                vpn.credUser = user
                vpn.credNeedsPsk = /l2tp$/.test(vpn.credService)
            }
        }
    }
    // writes the credentials into the profile, then brings it up
    property Process credProc: Process {
        property string name: ""
        stderr: StdioCollector { id: credErr }
        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0) {
                vpn.busyName = ""
                var msg = (credErr.text || "").trim()
                vpn.credError = msg !== "" ? msg.split("\n")[0] : ("nmcli exited with code " + exitCode)
                return
            }
            vpn.closeCredentials()
            vpn.toggle(credProc.name, true)
        }
    }
}
