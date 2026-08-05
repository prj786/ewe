import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Bluetooth

// QuickSettings — full-height sidebar, slides in from the right.
// Layout: header · quick toggles (a tile's options expand inline, right under
// its own row) · brightness+volume sliders + audio output · media (only when a
// live player exists) · system load · calendar · notifications grouped by app.
Scope {
    id: root

    // all colours come from Theme.qml (single source of truth)
    function g(c) { return String.fromCodePoint(c) }   // handles MDI glyphs > U+FFFF

    // calendar
    property var today: new Date()
    property int calYear:  today.getFullYear()
    property int calMonth: today.getMonth()
    property int calDate:  today.getDate()
    readonly property int firstW: new Date(calYear, calMonth, 1).getDay()
    readonly property int daysIn: new Date(calYear, calMonth + 1, 0).getDate()
    readonly property var monthNames: ["January","February","March","April","May","June","July","August","September","October","November","December"]
    // calendar events — the native Google account when signed in, else the
    // optional GOA/EDS pipeline; empty → no dots, no agenda, a gentle hint.
    // Keyed on the events themselves, NOT Google.signedIn: right after boot the
    // signed-in probe can lag (keyring/Wi-Fi race) while the cached events are
    // already loaded — sign-out clears Google.events, so nothing stale leaks.
    readonly property var calEvents: Google.events.length > 0 ? Google.events : (Accounts.events || [])
    // all-day events carry a bare YYYY-MM-DD — parse as LOCAL midnight, not UTC
    function evDate(e) {
        if (e.allDay && /^\d{4}-\d{2}-\d{2}/.test(String(e.start))) {
            var p = String(e.start).slice(0, 10).split("-")
            return new Date(+p[0], +p[1] - 1, +p[2])
        }
        return new Date(e.start)
    }
    // day-of-month → calendar colour of the first event that day (shown month)
    readonly property var eventDays: {
        var days = {}, evs = root.calEvents
        for (var i = 0; i < evs.length; i++) {
            var d = root.evDate(evs[i])
            if (!isNaN(d.getTime()) && d.getFullYear() === root.calYear && d.getMonth() === root.calMonth && days[d.getDate()] === undefined)
                days[d.getDate()] = evs[i].color || ""
        }
        return days
    }
    // GNOME-style agenda: upcoming events grouped per day (next 7 days)
    readonly property var agenda: {
        var evs = root.calEvents, groups = {}, now = new Date()
        var t0 = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        for (var i = 0; i < evs.length; i++) {
            var d = root.evDate(evs[i])
            if (isNaN(d.getTime())) continue
            var day0 = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
            if (day0 < t0 || day0 >= t0 + 7 * 86400000) continue
            if (!evs[i].allDay && d.getTime() < now.getTime() - 3600000) continue   // hide long-finished timed events today
            if (!groups[day0]) groups[day0] = []
            groups[day0].push(evs[i])
        }
        var keys = Object.keys(groups).map(Number).sort(function (a, b) { return a - b })
        var out = []
        for (var k = 0; k < keys.length && out.length < 4; k++) {
            var dd = new Date(keys[k])
            out.push({
                label: keys[k] === t0 ? "Today" : (keys[k] === t0 + 86400000 ? "Tomorrow" : Qt.formatDateTime(dd, "dddd d MMMM")),
                events: groups[keys[k]].slice(0, 4)
            })
        }
        return out
    }
    function fmtEventTime(e) {
        if (e.allDay) return "All day"
        var d = new Date(e.start)
        if (isNaN(d.getTime())) return ""
        var s = Qt.formatTime(d, "h:mm AP")
        var de = new Date(e.end)
        if (!isNaN(de.getTime())) s += " – " + Qt.formatTime(de, "h:mm AP")
        return s
    }

    // which tile's section is expanded: "" | "wifi" | "bt" | "vpn" | "ssh" | "mobile" | "mail"
    property string expanded: ""

    // mobile (KDE Connect) sub-state
    property string mobileView: "notifs"      // "notifs" | "msgs"
    property string replyTarget: ""           // notification id with the reply box open
    function fmtMsgTime(ms) {
        var d = new Date(ms), now = new Date()
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "h:mm AP")
        if (now.getTime() - ms < 6 * 86400000) return Qt.formatDateTime(d, "ddd")
        return Qt.formatDateTime(d, "d MMM")
    }

    // wifi
    property var wifiList: []
    property bool wifiOn: true
    property bool wiredUp: false   // a wired (ethernet) link is the active connection
    property string pwTarget: ""
    property string pwText: ""
    function curSsid() { for (var i = 0; i < wifiList.length; i++) if (wifiList[i].active) return wifiList[i].ssid; return "" }

    // vpn
    property var vpnList: []

    // ssh — hosts parsed from ~/.ssh/config (+ config.d/*). Each entry:
    //   { host, tunnel (bool), script (bool) }
    // "tunnel" = a background `ssh -f -N` we started is alive for that host;
    // "script" = the user saved a browse script (ssh-browse/<host>.sh, see below).
    property var sshList: []
    property string scriptTarget: ""    // host whose browse-script editor is open
    property string scriptText: ""      // editor prefill (existing script when editing)
    function sq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }   // shell single-quote

    // sliders (0..1), read on open, updated optimistically on drag
    property real brightnessVal: 0.5
    property real volumeVal: 0.5

    // power menu (floating popover). Power profiles come from the PowerProfiles
    // service, which talks to the net.hadess.PowerProfiles D-Bus iface — provided
    // by power-profiles-daemon (installed in phase 20), so no powerprofilesctl needed.
    property bool powerOpen: false

    function refresh() {
        var d = new Date()
        Globals.openDd = ""   // never reopen with a stale dropdown expanded
        root.today = d; root.calYear = d.getFullYear(); root.calMonth = d.getMonth(); root.calDate = d.getDate()
        wifiState.running = true; wiredState.running = true; brightnessProc.running = true; volumeProc.running = true
        sshScan.running = true   // always: the SSH tile's sub-label needs the host count
        if (root.expanded === "wifi") wifiScan.running = true
        if (root.expanded === "vpn") vpnScan.running = true
    }
    function clearAll() {
        if (!Globals.server) return
        var v = Globals.server.trackedNotifications.values.slice()
        for (var i = 0; i < v.length; i++) v[i].dismiss()
    }

    // ── notification list, grouped by app ──
    // One card per app; a card holding several notifications expands/collapses
    // on click (nExpanded holds the app whose card is open).
    property string nExpanded: ""
    readonly property var noteGroups: {
        var vals = (Globals.server ? Globals.server.trackedNotifications.values : []) || []
        var by = {}, order = [], out = []
        for (var i = 0; i < vals.length; i++) {
            var k = String(vals[i].appName || "Notification")
            if (!by[k]) { by[k] = []; order.push(k) }
            by[k].push(vals[i])
        }
        for (var j = 0; j < order.length; j++) {
            var items = by[order[j]]
            out.push({ app: order[j], items: items, latest: items[items.length - 1] })
        }
        return out
    }
    // Focus the window a notification came from (same matching Notifications.qml
    // uses for toasts), fire its default action, close the panel.
    function noteFocus(n) {
        var cands = []
        if (n.desktopEntry && String(n.desktopEntry).length) cands.push(String(n.desktopEntry))
        if (n.appName && String(n.appName).length) cands.push(String(n.appName))
        for (var c = 0; c < cands.length; c++) {
            var seg = cands[c].split(".").pop().replace(/[^A-Za-z0-9]/g, "")
            if (seg.length) { Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "class:(?i).*" + seg + ".*"]); break }
        }
        try { if (n.actions) for (var i = 0; i < n.actions.length; i++) if (n.actions[i].identifier === "default") { n.actions[i].invoke(); break } } catch (e) {}
        Globals.quickSettingsOpen = false
    }
    function noteIcon(n) {
        if (n.image && n.image != "") return n.image
        if (n.appIcon && n.appIcon != "") return Quickshell.iconPath(n.appIcon, "dialog-information")
        return Quickshell.iconPath("dialog-information")
    }
    function dismissAllOf(items) {
        var v = items.slice()
        for (var i = 0; i < v.length; i++) v[i].dismiss()
    }
    property string wifiPending: ""   // SSID being joined — its row + the bar show a spinner
    function connectWifi(ssid, sec) {
        if (sec && sec !== "" && root.pwText === "") {
            root.pwTarget = (root.pwTarget === ssid) ? "" : ssid   // toggle the password field
            return
        }
        var cmd = ["nmcli", "device", "wifi", "connect", ssid]
        if (root.pwText !== "") cmd = cmd.concat(["password", root.pwText])
        // through a tracked Process, not execDetached: joining can take seconds
        // and used to look like nothing was happening until the list refreshed
        root.wifiPending = ssid
        Globals.netBusy = "wifi"
        wifiConnProc.command = cmd
        wifiConnProc.running = true
        root.pwTarget = ""; root.pwText = ""
    }
    // ── ssh actions ──
    // Open a terminal already ssh'd into the host (kitty runs the command directly).
    function sshTerm(host) {
        Quickshell.execDetached(["kitty", "ssh", host])
        Globals.quickSettingsOpen = false
    }
    // Browse: run the user's saved per-host script (a proxied-browser launcher,
    // pasted once via the inline editor and kept forever in
    // ~/.config/quickshell/ssh-browse/<host>.sh — gitignored user state). Before
    // the script runs, a background SOCKS5 tunnel `ssh -f -N -D $SOCKS_PORT` to
    // the host is brought up if none is alive (BatchMode: needs key/agent auth —
    // there is no terminal to type a password into), and SSH_HOST + SOCKS_PORT
    // (default 1080) are exported so the script can point a browser at
    // socks5://127.0.0.1:$SOCKS_PORT. No saved script yet → open the editor.
    function sshBrowse(host, hasScript) {
        if (!hasScript) {
            root.scriptText = ""
            root.scriptTarget = root.scriptTarget === host ? "" : host
            return
        }
        Quickshell.execDetached(["sh", "-c", root.sshRunCmd(host)])
        sshRescan.restart()
        Globals.quickSettingsOpen = false
    }
    // The tunnel-then-script shell command (shared by sshBrowse and Save & Run).
    function sshRunCmd(host) {
        var pat = root.sq("^ssh -f -N .*" + host + "$")
        return "export SSH_HOST=" + root.sq(host) + " SOCKS_PORT=\"${SOCKS_PORT:-1080}\"; " +
               "if ! pgrep -f " + pat + " >/dev/null 2>&1; then " +
               "ssh -f -N -D \"$SOCKS_PORT\" -o BatchMode=yes -o ConnectTimeout=5 -o ExitOnForwardFailure=yes " + root.sq(host) +
               " || { notify-send -u critical -a SSH " + root.sq("Tunnel to " + host + " failed") +
               " 'Needs key/agent auth (no password prompt in the background).'; exit 1; }; fi; " +
               "exec \"$HOME/.config/quickshell/ssh-browse/" + host + ".sh\""
    }
    // Save the pasted script (quoted heredoc: content lands verbatim), mark it
    // executable, then immediately run it via the same tunnel-first path.
    function sshSaveScript(host, text) {
        var p = "\"$HOME/.config/quickshell/ssh-browse/" + host + ".sh\""
        var cmd = "mkdir -p \"$HOME/.config/quickshell/ssh-browse\" && cat > " + p +
                  " <<'QS_EOF'\n" + text.replace(/\n+$/, "") + "\nQS_EOF\nchmod +x " + p + " && " + root.sshRunCmd(host)
        Quickshell.execDetached(["sh", "-c", cmd])
        root.scriptTarget = ""
        sshRescan.restart()
        Globals.quickSettingsOpen = false
    }
    // Pencil button: load the saved script into the editor (or close it again).
    function sshEditScript(host) {
        if (root.scriptTarget === host) { root.scriptTarget = ""; return }
        sshScriptLoad.host = host
        sshScriptLoad.command = ["sh", "-c", "cat \"$HOME/.config/quickshell/ssh-browse/" + host + ".sh\" 2>/dev/null"]
        sshScriptLoad.running = false; sshScriptLoad.running = true
    }
    function sshDeleteScript(host) {
        Quickshell.execDetached(["sh", "-c", "rm -f \"$HOME/.config/quickshell/ssh-browse/" + host + ".sh\""])
        root.scriptTarget = ""
        sshRescan.restart()
    }
    function sshStopTunnel(host) {
        Quickshell.execDetached(["sh", "-c", "pkill -f " + root.sq("^ssh -f -N .*" + host + "$")])
        sshRescan.restart()
    }

    property string vpnPending: ""
    property string vpnBusyName: ""   // connection being brought up/down — its row + the bar spin
    function toggleVpn(name, up) {
        root.vpnPending = (up ? "Connecting to " : "Disconnecting from ") + name
        root.vpnBusyName = name
        Globals.netBusy = "vpn"
        vpnUpProc.command = ["nmcli", "connection", up ? "up" : "down", name]
        vpnUpProc.running = true
    }
    // logind writes the backlight for us (no udev rule, no setuid helper); fall
    // back to brightnessctl when the bridge is down or the machine has no
    // backlight device logind will accept
    function setBrightness(v) {
        root.brightnessVal = v
        if (Logind.setBrightness(v)) return
        Quickshell.execDetached(["brightnessctl", "set", Math.round(v * 100) + "%"])
    }
    function setVolume(v) { root.volumeVal = v; Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", Math.round(v * 100) + "%"]) }
    // ── power actions ──
    // All session/power actions go through ~/.config/hypr/scripts/power.sh: one
    // tested, distro-agnostic path per action (logout via loginctl, not the
    // unreliable Lua `hyprctl dispatch exit`). Destructive actions (Log Out,
    // Restart, Shut Down) ask for confirmation via a themed popover first;
    // reversible ones (Lock, Suspend) run immediately.
    property string confirmAction: ""   // "" = no confirmation showing
    property string confirmTitle: ""
    property string confirmVerb: ""
    function runPower(action) {
        Quickshell.execDetached(["sh", "-c", "exec \"$HOME/.config/hypr/scripts/power.sh\" " + action])
        root.confirmAction = ""; root.powerOpen = false; Globals.quickSettingsOpen = false
    }
    function askPower(action, title, verb) {
        root.powerOpen = false
        root.confirmTitle = title; root.confirmVerb = verb; root.confirmAction = action
    }

    Connections { target: Globals; function onQuickSettingsOpenChanged() { if (Globals.quickSettingsOpen) root.refresh() } }
    IpcHandler {
        target: "quicksettings"
        function toggle(): void { Globals.quickSettingsOpen = !Globals.quickSettingsOpen }
        function show(): void { Globals.quickSettingsOpen = true }
        function hide(): void { Globals.quickSettingsOpen = false }
        // Power-button press (XF86PowerOff bind in hyprland.lua; logind ignores
        // the key so a stray tap can't hard-poweroff): open the panel with the
        // shutdown confirmation already up.
        function powerdialog(): void { Globals.quickSettingsOpen = true; root.askPower("poweroff", "Shut down this computer?", "Shut Down") }
    }

    Process {
        id: wifiScan
        command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "device", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n"), seen = {}, arr = []
                for (var i = 0; i < lines.length; i++) {
                    if (!lines[i]) continue
                    var p = lines[i].split(":")
                    var ssid = p.slice(3).join(":")
                    if (!ssid || seen[ssid]) continue
                    seen[ssid] = true
                    arr.push({ ssid: ssid, signal: parseInt(p[1]) || 0, sec: p[2] || "", active: p[0] === "*" })
                }
                arr.sort(function (a, b) { return (b.active - a.active) || (b.signal - a.signal) })
                root.wifiList = arr
            }
        }
    }
    Process { id: wifiState; command: ["nmcli", "-t", "-f", "WIFI", "radio"]; stdout: StdioCollector { onStreamFinished: root.wifiOn = this.text.trim() === "enabled" } }
    Process { id: wiredState; command: ["sh", "-c", "nmcli -t -f TYPE,STATE device 2>/dev/null | awk -F: '$1==\"ethernet\" && $2==\"connected\"{print \"yes\"; exit}'"]; stdout: StdioCollector { onStreamFinished: root.wiredUp = this.text.trim() === "yes" } }
    Process {
        id: vpnScan
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
                root.vpnList = arr
            }
        }
    }
    Process { id: brightnessProc; command: ["sh", "-c", "brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%'"]; stdout: StdioCollector { onStreamFinished: { var n = parseInt(this.text.trim()); if (!isNaN(n)) root.brightnessVal = n / 100 } } }
    Process { id: volumeProc; command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oE '[0-9]+\\.[0-9]+'"]; stdout: StdioCollector { onStreamFinished: { var f = parseFloat(this.text.trim()); if (!isNaN(f)) root.volumeVal = Math.min(1, f) } } }
    Timer { id: rescanTimer; interval: 2500; onTriggered: { wifiState.running = true; wifiScan.running = true } }
    Timer { id: vpnRescan; interval: 2000; onTriggered: vpnScan.running = true }
    Timer { id: sshRescan; interval: 1500; onTriggered: sshScan.running = true }

    // ── ssh host scan: ~/.ssh/config (+ config.d/*) + live tunnels + scripts ──
    // One process emits the config, then (behind marker lines) `pgrep -af` of the
    // background tunnels we start (they all match "^ssh -f -N") and the saved
    // browse scripts (ssh-browse/<host>.sh).
    Process {
        id: sshScan
        command: ["sh", "-c", "cat \"$HOME/.ssh/config\" \"$HOME/.ssh/config.d\"/* 2>/dev/null; printf '\\n@TUNNELS@\\n'; pgrep -af '^ssh -f -N' 2>/dev/null; printf '@SCRIPTS@\\n'; ls \"$HOME/.config/quickshell/ssh-browse\" 2>/dev/null; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var ls = this.text.split("\n"), sec = 0   // 0 config · 1 tunnels · 2 scripts
                var hosts = [], seen = {}, tunHosts = {}, scripts = {}
                for (var i = 0; i < ls.length; i++) {
                    var ln = ls[i].trim()
                    if (ln === "@TUNNELS@") { sec = 1; continue }
                    if (ln === "@SCRIPTS@") { sec = 2; continue }
                    if (!ln || (sec === 0 && ln.charAt(0) === "#")) continue
                    if (sec === 1) {
                        // "PID ssh -f -N [-o …] [-D …] host" — host is the last token
                        var tk = ln.split(/\s+/)
                        tunHosts[tk[tk.length - 1]] = true
                        continue
                    }
                    if (sec === 2) {
                        if (/\.sh$/.test(ln)) scripts[ln.slice(0, -3)] = true
                        continue
                    }
                    var mh = ln.match(/^Host\s+(.+)$/i)
                    if (mh) {
                        var names = mh[1].split(/\s+/)
                        for (var n = 0; n < names.length; n++) {
                            var h = names[n]
                            if (!h || /[*?!]/.test(h)) continue   // skip wildcard/negated patterns
                            if (!seen[h]) { seen[h] = true; hosts.push(h) }
                        }
                    }
                }
                var arr = [], anyTun = false
                for (var k = 0; k < hosts.length; k++) {
                    var t = tunHosts[hosts[k]] === true
                    if (t) anyTun = true
                    arr.push({ host: hosts[k], tunnel: t, script: scripts[hosts[k]] === true })
                }
                root.sshList = arr
                Globals.sshTunnelUp = anyTun
            }
        }
    }
    // cat's an existing browse script into the editor, then opens it
    Process {
        id: sshScriptLoad
        property string host: ""
        stdout: StdioCollector {
            onStreamFinished: {
                root.scriptText = this.text
                root.scriptTarget = sshScriptLoad.host
            }
        }
    }
    // brings a VPN up/down; on failure raises a system notification with the error
    Process {
        id: vpnUpProc
        stderr: StdioCollector { id: vpnErr }
        onExited: function (exitCode, exitStatus) {
            root.vpnBusyName = ""
            Globals.netBusy = ""
            vpnRescan.restart()
            if (exitCode !== 0) {
                var msg = (vpnErr.text || "").trim()
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "VPN", root.vpnPending + " failed", msg !== "" ? msg : ("nmcli exited with code " + exitCode)])
            }
        }
    }
    // joins a Wi-Fi network; same deal — spinner while running, notify on failure
    Process {
        id: wifiConnProc
        stderr: StdioCollector { id: wifiConnErr }
        onExited: function (exitCode, exitStatus) {
            var failed = root.wifiPending
            root.wifiPending = ""
            Globals.netBusy = ""
            rescanTimer.restart()
            if (exitCode !== 0) {
                var msg = (wifiConnErr.text || "").trim()
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Wi-Fi", "Joining " + failed + " failed", msg !== "" ? msg : ("nmcli exited with code " + exitCode)])
            }
        }
    }
    // gated on the panel, not just no-op'd inside it: this used to wake every 6 s
    // for the whole session only to hit the early return on the first line
    Timer { interval: 6000; running: Globals.quickSettingsOpen; repeat: true; onTriggered: { wifiState.running = true; wiredState.running = true; if (root.expanded === "wifi") wifiScan.running = true; if (root.expanded === "ssh") sshScan.running = true } }

    PanelWindow {
        id: win
        visible: Globals.quickSettingsOpen || closeTimer.running
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:control"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        anchors { top: true; bottom: true; left: true; right: true }

        Timer { id: closeTimer; interval: Math.max(1, Theme.durSlow) }
        Connections { target: Globals; function onQuickSettingsOpenChanged() { if (!Globals.quickSettingsOpen) { closeTimer.restart(); root.powerOpen = false } } }
        MouseArea { anchors.fill: parent; onClicked: Globals.quickSettingsOpen = false }

        Rectangle {
            id: panel
            width: 380
            y: 10                              // equal gap top & bottom (matches the 10px right inset)
            height: parent.height - 20
            radius: Theme.radius
            color: Theme.panel
            border.color: Theme.stroke
            border.width: 1
            clip: true
            layer.enabled: true
            layer.effect: Elevation {}
            Sheen { radius: parent.radius }
            property real off: Globals.quickSettingsOpen ? 0 : (width + 60)
            x: parent.width - width - 10 + off
            Behavior on off { NumberAnimation { duration: Theme.durSlow; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }

            // catches Esc to close (Quick Settings is otherwise mouse-driven)
            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: { if (root.powerOpen) root.powerOpen = false; else Globals.quickSettingsOpen = false }
            }
            Connections {
                target: Globals
                function onQuickSettingsOpenChanged() { if (Globals.quickSettingsOpen) keyCatcher.forceActiveFocus() }
            }

            // ── round close button (centered MDI glyph) ──
            component CloseBtn: Rectangle {
                id: cb
                signal pressed()
                width: 22; height: 22; radius: 11
                color: cbMa.containsMouse ? Theme.hover : Theme.elevated
                Behavior on color { ColorAnimation { duration: 120 } }
                Text { anchors.centerIn: parent; text: Theme.icClose; font.family: Theme.fontIcons; font.pixelSize: 13; color: Theme.fg }
                MouseArea { id: cbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cb.pressed() }
            }

            // ── a row in the power popover ──
            component PowerItem: Rectangle {
                id: pit
                property int ic: 0
                property string label: ""
                property bool danger: false
                signal go()
                width: parent ? parent.width : 200
                height: 32
                radius: 9
                color: pitMa.containsMouse ? (danger ? Theme.danger : Theme.accent) : "transparent"
                Row {
                    anchors.left: parent.left; anchors.leftMargin: 9; anchors.verticalCenter: parent.verticalCenter; spacing: 11
                    Text { anchors.verticalCenter: parent.verticalCenter; width: 16; text: root.g(pit.ic); font.family: Theme.fontIcons; font.pixelSize: 14; color: pitMa.containsMouse ? Theme.accentText : (pit.danger ? Theme.danger : Theme.fg) }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: pit.label; color: pitMa.containsMouse ? Theme.accentText : (pit.danger ? Theme.danger : Theme.fg); font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.Medium }
                }
                MouseArea { id: pitMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pit.go() }
            }

            // ── quick-toggle tile ──
            component Tile: Rectangle {
                id: tile
                property string ic: ""
                property string label: ""
                property string sub: ""
                property bool active: false
                signal clicked()
                width: (inner.width - 10) / 2
                height: 62
                radius: Theme.radiusInner
                color: active ? Theme.accent : Theme.elevated
                Behavior on color { ColorAnimation { duration: 150 } }
                Column {
                    anchors.fill: parent; anchors.margins: 11; spacing: 5
                    Text { text: tile.ic; font.family: Theme.fontIcons; font.pixelSize: 17; color: tile.active ? Theme.accentText : Theme.fg }
                    Text { width: parent.width; text: tile.label; color: tile.active ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; elide: Text.ElideRight }
                }
                Text { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 11; text: tile.sub; color: tile.active ? Theme.accentText : Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10; elide: Text.ElideRight }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tile.clicked() }
            }

            // ── slider ──
            component Slider: Item {
                id: sld
                property string icon: ""
                property real value: 0
                signal moved(real v)
                height: 26
                Text { id: sIco; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: 20; text: sld.icon; font.family: Theme.fontIcons; font.pixelSize: 14; color: Theme.fgDim }
                Rectangle {
                    id: trk
                    anchors.left: sIco.right; anchors.leftMargin: 8; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    height: 8; radius: 4; color: Theme.hover
                    Rectangle { height: parent.height; radius: 4; width: parent.width * Math.max(0, Math.min(1, sld.value)); color: Theme.accent }
                    Rectangle { width: 14; height: 14; radius: 7; color: "white"; anchors.verticalCenter: parent.verticalCenter; x: Math.max(0, Math.min(trk.width - width, trk.width * sld.value - width / 2)) }
                    MouseArea {
                        anchors.fill: parent; anchors.topMargin: -8; anchors.bottomMargin: -8
                        onPressed: function (m) { sld.moved(Math.max(0, Math.min(1, m.x / trk.width))) }
                        onPositionChanged: function (m) { if (pressed) sld.moved(Math.max(0, Math.min(1, m.x / trk.width))) }
                    }
                }
            }

            Flickable {
                id: flick
                anchors.fill: parent
                anchors.margins: 14
                contentHeight: inner.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: inner
                    width: flick.width
                    spacing: 13

                    // ── header: date + battery ──
                    Item {
                        width: parent.width; height: hdr.implicitHeight
                        Column {
                            id: hdr
                            spacing: 0
                            Text { text: Qt.formatDateTime(root.today, "dddd"); color: Theme.accent; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsBody; font.weight: Font.Bold }
                            Text { text: Qt.formatDateTime(root.today, "d MMMM"); color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge; font.weight: Font.Bold }
                        }
                        Row {
                            anchors.right: parent.right; anchors.verticalCenter: hdr.verticalCenter; spacing: 10
                            // battery (only on a laptop)
                            Row {
                                anchors.verticalCenter: parent.verticalCenter; spacing: 5
                                visible: UPower.displayDevice && UPower.displayDevice.isLaptopBattery
                                property var dev: UPower.displayDevice
                                property real pct: dev ? (dev.percentage <= 1 ? dev.percentage * 100 : dev.percentage) : 0
                                property bool charging: dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged)
                                Text { anchors.verticalCenter: parent.verticalCenter; text: Math.round(parent.pct) + "%"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: parent.charging ? Theme.icBolt : (parent.pct >= 60 ? Theme.icBattFull : parent.pct >= 30 ? Theme.icBatt50 : Theme.icBattEmpty); font.family: Theme.fontIcons; font.pixelSize: 13; color: parent.charging ? Theme.success : (parent.pct <= 15 ? Theme.danger : Theme.fgDim) }
                            }
                            // settings gear → Globals.openSettings(): the
                            // standalone ewe-settings app, with the in-shell
                            // panel only as a fallback while the binary is absent.
                            Rectangle {
                                id: gearBtn
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28; height: 28; radius: 14
                                color: gbMa.containsMouse ? Theme.hover : Theme.elevated
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text { anchors.centerIn: parent; text: Theme.icCog; font.family: Theme.fontIcons; font.pixelSize: 15; color: Theme.fg }
                                MouseArea {
                                    id: gbMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Globals.quickSettingsOpen = false
                                        Globals.openSettings()
                                    }
                                }
                            }
                            // power button → opens the floating power menu
                            Rectangle {
                                id: powerBtn
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28; height: 28; radius: 14
                                color: (pbMa.containsMouse || root.powerOpen) ? Theme.hover : Theme.elevated
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text { anchors.centerIn: parent; text: Theme.icPower; font.family: Theme.fontIcons; font.pixelSize: 15; color: root.powerOpen ? Theme.accent : Theme.fg }
                                MouseArea { id: pbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.powerOpen = !root.powerOpen }
                            }
                        }
                    }

                    // ── quick toggles — a tile's options expand INLINE, in a box right
                    //    under the row holding that tile (pushes the rows below down) ──
                    Row {
                        width: parent.width; spacing: 10
                        Tile {
                            // adapts to the live link: shows the wired/ethernet glyph + "Wired"
                            // when a cable is the active connection and Wi-Fi isn't (e.g. VMs).
                            readonly property bool onWired: root.wiredUp && root.curSsid() === ""
                            ic: onWired ? Theme.icEthernet : Theme.icWifi   // mdi-ethernet : wifi
                            label: onWired ? "Network" : "Wi-Fi"; active: root.expanded === "wifi"
                            sub: root.curSsid() !== "" ? root.curSsid() : (onWired ? "Wired" : (root.wifiOn ? "On" : "Off"))
                            onClicked: { root.expanded = root.expanded === "wifi" ? "" : "wifi"; if (root.expanded === "wifi") wifiScan.running = true }
                        }
                        Tile {
                            ic: Theme.icBluetooth; label: "Bluetooth"; active: root.expanded === "bt"
                            sub: (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled) ? "On" : "Off"
                            onClicked: {
                                root.expanded = root.expanded === "bt" ? "" : "bt"
                                if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = (root.expanded === "bt")
                            }
                        }
                    }

                    // ── options for row 1 (Wi-Fi / Bluetooth) ──
                    Rectangle {
                        width: parent.width
                        visible: root.expanded === "wifi" || root.expanded === "bt"
                        height: visible ? d1Col.implicitHeight + 20 : 0
                        radius: Theme.radiusInner
                        color: Theme.elevated
                        Column {
                            id: d1Col
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                            spacing: 4

                            // WIFI
                            Column {
                                width: parent.width; spacing: 2; visible: root.expanded === "wifi"
                                Item {
                                    width: parent.width; height: 26
                                    Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Wi-Fi"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                    Rectangle {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: 38; height: 22; radius: 11; color: root.wifiOn ? Theme.accent : Theme.hover
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Rectangle { width: 18; height: 18; radius: 9; color: "white"; anchors.verticalCenter: parent.verticalCenter; x: root.wifiOn ? parent.width-width-2 : 2; Behavior on x { NumberAnimation { duration: 150 } } }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { Quickshell.execDetached(["nmcli","radio","wifi", root.wifiOn ? "off" : "on"]); rescanTimer.restart() } }
                                    }
                                }
                                // network list — same inset panel style as the DropRow options
                                Rectangle {
                                    width: parent.width
                                    visible: root.wifiOn && root.wifiList.length > 0
                                    height: visible ? wifiOptCol.implicitHeight + 10 : 0
                                    radius: 7; color: Theme.bg; border.color: Theme.stroke; border.width: 1
                                    Column {
                                        id: wifiOptCol
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 5
                                Repeater {
                                    model: root.wifiOn ? root.wifiList : []
                                    delegate: Column {
                                        required property var modelData
                                        width: wifiOptCol.width
                                        Item {
                                            width: parent.width; height: 28
                                            Rectangle { anchors.fill: parent; radius: 6; color: wMa.containsMouse ? Theme.hover : "transparent" }
                                            Text { anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: modelData.signal >= 66 ? Theme.icWifi : (modelData.signal >= 33 ? Theme.icWifiMed : Theme.icWifiLow); font.family: Theme.fontIcons; font.pixelSize: 13; color: modelData.active ? Theme.accent : Theme.fgDim }
                                            Text { anchors.left: parent.left; anchors.leftMargin: 32; anchors.right: parent.right; anchors.rightMargin: 40; anchors.verticalCenter: parent.verticalCenter; text: modelData.ssid; color: modelData.active ? Theme.accent : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: modelData.active ? Font.DemiBold : Font.Normal; elide: Text.ElideRight }
                                            Text { anchors.right: parent.right; anchors.rightMargin: modelData.active ? 26 : 8; anchors.verticalCenter: parent.verticalCenter; visible: modelData.sec !== ""; text: Theme.icLock; font.family: Theme.fontIcons; font.pixelSize: 10; color: Theme.fgDim }
                                            Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; visible: modelData.active && root.wifiPending !== modelData.ssid; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: 11; color: Theme.accent }
                                            Spinner { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; visible: root.wifiPending === modelData.ssid; font.pixelSize: 12 }
                                            MouseArea { id: wMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.connectWifi(modelData.ssid, modelData.sec) }
                                        }
                                        Item {
                                            width: parent.width; height: visible ? 34 : 0; visible: root.pwTarget === modelData.ssid
                                            Rectangle {
                                                anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 4; radius: 7; color: Theme.bg; border.color: Theme.accent; border.width: 1
                                                TextInput {
                                                    id: pwInput
                                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 56; verticalAlignment: TextInput.AlignVCenter
                                                    echoMode: TextInput.Password; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                                    onTextChanged: root.pwText = text
                                                    Component.onCompleted: if (root.pwTarget === modelData.ssid) forceActiveFocus()
                                                    onAccepted: root.connectWifi(modelData.ssid, modelData.sec)
                                                    Keys.onEscapePressed: Globals.quickSettingsOpen = false
                                                    Text { anchors.verticalCenter: parent.verticalCenter; visible: pwInput.text.length === 0; text: "Password"; color: Theme.fgDim; font: pwInput.font }
                                                }
                                                Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "Join"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.connectWifi(modelData.ssid, modelData.sec) } }
                                            }
                                        }
                                    }
                                }
                                    }
                                }
                            }

                            // BLUETOOTH
                            Column {
                                width: parent.width; spacing: 2; visible: root.expanded === "bt"
                                Item {
                                    width: parent.width; height: 26
                                    property var adapter: Bluetooth.defaultAdapter
                                    Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: (parent.adapter && parent.adapter.discovering) ? "Bluetooth · searching…" : "Bluetooth"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                    Rectangle {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: 38; height: 22; radius: 11
                                        readonly property bool on: parent.adapter ? parent.adapter.enabled : false
                                        color: on ? Theme.accent : Theme.hover
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Rectangle { width: 18; height: 18; radius: 9; color: "white"; anchors.verticalCenter: parent.verticalCenter; x: parent.on ? parent.width-width-2 : 2; Behavior on x { NumberAnimation { duration: 150 } } }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (parent.parent.adapter) parent.parent.adapter.enabled = !parent.parent.adapter.enabled }
                                    }
                                }
                                // device list — same inset panel style as the DropRow options
                                Rectangle {
                                    width: parent.width
                                    visible: btOptCol.shown > 0
                                    height: visible ? btOptCol.implicitHeight + 10 : 0
                                    radius: 7; color: Theme.bg; border.color: Theme.stroke; border.width: 1
                                    Column {
                                        id: btOptCol
                                        property int shown: { var c = 0, d = Bluetooth.devices ? Bluetooth.devices.values : []; for (var i = 0; i < d.length; i++) if (d[i].paired || d[i].connected || (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering)) c++; return c }
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 5
                                        Repeater {
                                            model: Bluetooth.devices ? Bluetooth.devices.values : []
                                            delegate: Item {
                                                required property var modelData
                                                visible: modelData.paired || modelData.connected || (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering)
                                                width: btOptCol.width; height: visible ? 28 : 0
                                                Rectangle { anchors.fill: parent; radius: 6; color: bMa.containsMouse ? Theme.hover : "transparent" }
                                                Text { anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: (modelData.connected ? Theme.icBluetoothOn : Theme.icBluetooth); font.family: Theme.fontIcons; font.pixelSize: 12; color: modelData.connected ? Theme.accent : Theme.fgDim }
                                                Text { anchors.left: parent.left; anchors.leftMargin: 30; anchors.right: parent.right; anchors.rightMargin: 26; anchors.verticalCenter: parent.verticalCenter; text: (modelData.name || modelData.deviceName || modelData.address) + (modelData.connected ? "" : (modelData.paired ? "" : "  ·  new")); color: modelData.connected ? Theme.accent : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: modelData.connected ? Font.DemiBold : Font.Normal; elide: Text.ElideRight }
                                                Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; visible: modelData.connected; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: 11; color: Theme.accent }
                                                MouseArea { id: bMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: modelData.connected ? modelData.disconnect() : (modelData.paired ? modelData.connect() : modelData.pair()) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width; spacing: 10
                        Tile {
                            ic: Theme.icVpn; label: "VPN"; active: Globals.vpnActive || root.expanded === "vpn"
                            sub: root.vpnBusyName !== "" ? "Connecting…" : (Globals.vpnActive ? "On" : "Off")
                            onClicked: { root.expanded = root.expanded === "vpn" ? "" : "vpn"; if (root.expanded === "vpn") vpnScan.running = true }
                        }
                        Tile {
                            ic: Theme.icSsh; label: "SSH"; active: Globals.sshTunnelUp || root.expanded === "ssh"
                            sub: Globals.sshTunnelUp ? "Tunnel on"
                               : root.sshList.length > 0 ? root.sshList.length + (root.sshList.length === 1 ? " host" : " hosts")
                               : "Not set up"
                            onClicked: { root.expanded = root.expanded === "ssh" ? "" : "ssh"; if (root.expanded === "ssh") sshScan.running = true }
                        }
                    }

                    // ── options for row 2 (VPN / SSH) ──
                    Rectangle {
                        width: parent.width
                        visible: root.expanded === "vpn" || root.expanded === "ssh"
                        height: visible ? detailCol.implicitHeight + 20 : 0
                        radius: Theme.radiusInner
                        color: Theme.elevated
                        Column {
                            id: detailCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                            spacing: 4

                            // VPN
                            Column {
                                width: parent.width; spacing: 2; visible: root.expanded === "vpn"
                                Text { text: "VPN"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; bottomPadding: 4 }
                                Text { width: parent.width; visible: root.vpnList.length === 0; text: "No VPN connections configured."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap }
                                // connection list — same inset panel style as the DropRow options
                                Rectangle {
                                    width: parent.width
                                    visible: root.vpnList.length > 0
                                    height: visible ? vpnOptCol.implicitHeight + 10 : 0
                                    radius: 7; color: Theme.bg; border.color: Theme.stroke; border.width: 1
                                    Column {
                                        id: vpnOptCol
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 5
                                        Repeater {
                                            model: root.vpnList
                                            delegate: Item {
                                                required property var modelData
                                                width: vpnOptCol.width; height: 28
                                                Rectangle { anchors.fill: parent; radius: 6; color: vMa.containsMouse ? Theme.hover : "transparent" }
                                                Text { anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: Theme.icVpn; font.family: Theme.fontIcons; font.pixelSize: 12; color: modelData.active ? Theme.accent : Theme.fgDim }
                                                Text { anchors.left: parent.left; anchors.leftMargin: 30; anchors.right: parent.right; anchors.rightMargin: 26; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; color: modelData.active ? Theme.accent : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: modelData.active ? Font.DemiBold : Font.Normal; elide: Text.ElideRight }
                                                Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; visible: modelData.active && root.vpnBusyName !== modelData.name; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: 11; color: Theme.accent }
                                                Spinner { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; visible: root.vpnBusyName === modelData.name; font.pixelSize: 12 }
                                                MouseArea { id: vMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleVpn(modelData.name, !modelData.active) }
                                            }
                                        }
                                    }
                                }
                            }

                            // SSH — hosts from ~/.ssh/config. Row click → terminal
                            // ssh'd in; globe → SOCKS tunnel + the host's saved browse
                            // script (first click opens a paste-once editor); pencil
                            // edits the script; ■ stops a running tunnel.
                            Column {
                                width: parent.width; spacing: 2; visible: root.expanded === "ssh"
                                Text { text: "SSH  ·  ~/.ssh/config"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; bottomPadding: 4 }
                                Text {
                                    width: parent.width; visible: root.sshList.length === 0; wrapMode: Text.Wrap
                                    text: "No hosts configured. Add one to ~/.ssh/config:\nHost mypc\n    HostName 192.168.1.20\n    User you"
                                    color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                }
                                // host list — same inset panel style as the DropRow options
                                Rectangle {
                                    width: parent.width
                                    visible: root.sshList.length > 0
                                    height: visible ? sshOptCol.implicitHeight + 10 : 0
                                    radius: 7; color: Theme.bg; border.color: Theme.stroke; border.width: 1
                                    Column {
                                        id: sshOptCol
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 5
                                Repeater {
                                    model: root.sshList
                                    delegate: Column {
                                        id: sshRow
                                        required property var modelData
                                        width: sshOptCol.width
                                        Item {
                                            width: parent.width; height: 28
                                            Rectangle { anchors.fill: parent; radius: 6; color: sMa.containsMouse ? Theme.hover : "transparent" }
                                            Text { anchors.left: parent.left; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: Theme.icSsh; font.family: Theme.fontIcons; font.pixelSize: 12; color: sshRow.modelData.tunnel ? Theme.accent : Theme.fgDim }
                                            Text {
                                                anchors.left: parent.left; anchors.leftMargin: 26; anchors.right: btns.left; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                                                text: sshRow.modelData.host + (sshRow.modelData.tunnel ? "  ·  tunnel on" : "")
                                                color: sshRow.modelData.tunnel ? Theme.accent : Theme.fg
                                                font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: sshRow.modelData.tunnel ? Font.DemiBold : Font.Normal; elide: Text.ElideRight
                                            }
                                            // whole row (under the buttons) → terminal
                                            MouseArea { id: sMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.sshTerm(sshRow.modelData.host) }
                                            Row {
                                                id: btns
                                                anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                                // stop tunnel (only while one is up)
                                                Rectangle {
                                                    visible: sshRow.modelData.tunnel
                                                    width: 22; height: 22; radius: 6
                                                    color: stMa.containsMouse ? Theme.danger : Theme.hover
                                                    Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 2; color: stMa.containsMouse ? Theme.accentText : Theme.fg }
                                                    MouseArea { id: stMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.sshStopTunnel(sshRow.modelData.host) }
                                                }
                                                // pencil: edit the saved browse script
                                                Rectangle {
                                                    visible: sshRow.modelData.script
                                                    width: 22; height: 22; radius: 6
                                                    color: edMa.containsMouse ? Theme.accent : Theme.hover
                                                    Text { anchors.centerIn: parent; text: Theme.icPencil; font.family: Theme.fontIcons; font.pixelSize: 12; color: edMa.containsMouse ? Theme.accentText : Theme.fg }
                                                    MouseArea { id: edMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.sshEditScript(sshRow.modelData.host) }
                                                }
                                                // globe: run the host's browse script (or open
                                                // the editor if none is saved yet)
                                                Rectangle {
                                                    width: 22; height: 22; radius: 6
                                                    color: gwMa.containsMouse ? Theme.accent : Theme.hover
                                                    Text { anchors.centerIn: parent; text: Theme.icWeb; font.family: Theme.fontIcons; font.pixelSize: 13; color: gwMa.containsMouse ? Theme.accentText : Theme.fg }
                                                    MouseArea { id: gwMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.sshBrowse(sshRow.modelData.host, sshRow.modelData.script) }
                                                }
                                            }
                                        }
                                        // browse-script editor — paste once, kept forever in
                                        // ~/.config/quickshell/ssh-browse/<host>.sh
                                        Column {
                                            width: parent.width; spacing: 4; bottomPadding: 4
                                            visible: root.scriptTarget === sshRow.modelData.host
                                            onVisibleChanged: if (visible) { seEdit.text = root.scriptText; seEdit.forceActiveFocus() }
                                            Rectangle {
                                                width: parent.width; height: 150; radius: 7
                                                color: Theme.bg; border.color: Theme.accent; border.width: 1
                                                Flickable {
                                                    id: seFlick
                                                    anchors.fill: parent; anchors.margins: 8; clip: true
                                                    contentWidth: width; contentHeight: seEdit.implicitHeight
                                                    TextEdit {
                                                        id: seEdit
                                                        width: seFlick.width
                                                        textFormat: TextEdit.PlainText; wrapMode: TextEdit.WrapAnywhere
                                                        selectByMouse: true
                                                        color: Theme.fg; font.family: Theme.fontMono; font.pixelSize: 11
                                                        Keys.onEscapePressed: root.scriptTarget = ""
                                                        // keep the cursor in view while typing/pasting
                                                        onCursorRectangleChanged: {
                                                            if (cursorRectangle.y < seFlick.contentY) seFlick.contentY = cursorRectangle.y
                                                            else if (cursorRectangle.y + cursorRectangle.height > seFlick.contentY + seFlick.height)
                                                                seFlick.contentY = cursorRectangle.y + cursorRectangle.height - seFlick.height
                                                        }
                                                    }
                                                }
                                                Text {
                                                    visible: seEdit.text.length === 0
                                                    anchors.fill: parent; anchors.margins: 8; wrapMode: Text.Wrap
                                                    text: "Paste the shell script to run for “" + sshRow.modelData.host + "” — e.g. launch a browser through the tunnel.\n\nIt runs with SSH_HOST and SOCKS_PORT set, after a SOCKS5 tunnel to the host is up on 127.0.0.1:$SOCKS_PORT (port 1080; needs key/agent auth). Saved to ~/.config/quickshell/ssh-browse/."
                                                    color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                                }
                                            }
                                            Row {
                                                spacing: 6
                                                Rectangle {
                                                    width: svTxt.implicitWidth + 20; height: 24; radius: 12
                                                    color: svMa.containsMouse ? Qt.lighter(Theme.accent, 1.15) : Theme.accent
                                                    Text { id: svTxt; anchors.centerIn: parent; text: "Save & Run"; color: Theme.accentText; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                                    MouseArea { id: svMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (seEdit.text.trim().length > 0) root.sshSaveScript(sshRow.modelData.host, seEdit.text) }
                                                }
                                                Rectangle {
                                                    width: caTxt.implicitWidth + 20; height: 24; radius: 12
                                                    color: caMa.containsMouse ? Theme.hover : "transparent"
                                                    border.color: Theme.hover; border.width: 1
                                                    Text { id: caTxt; anchors.centerIn: parent; text: "Cancel"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                                    MouseArea { id: caMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.scriptTarget = "" }
                                                }
                                                Rectangle {
                                                    visible: sshRow.modelData.script
                                                    width: dlTxt.implicitWidth + 20; height: 24; radius: 12
                                                    color: dlMa.containsMouse ? Theme.danger : "transparent"
                                                    border.color: Theme.danger; border.width: 1
                                                    Text { id: dlTxt; anchors.centerIn: parent; text: "Delete"; color: dlMa.containsMouse ? Theme.accentText : Theme.danger; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                                    MouseArea { id: dlMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.sshDeleteScript(sshRow.modelData.host) }
                                                }
                                            }
                                        }
                                    }
                                }
                                    }
                                }
                            }
                        }
                    }

                    // ── row 3: Mobile (KDE Connect) / Mail (Gmail) ──
                    Row {
                        width: parent.width; spacing: 10
                        Tile {
                            ic: Theme.icPhone; label: "Mobile"
                            active: KdeConnect.connected || root.expanded === "mobile"
                            sub: !KdeConnect.installed ? "Not set up"
                               : KdeConnect.connected ? (KdeConnect.unreadCount > 0 ? KdeConnect.unreadCount + " new"
                                                        : KdeConnect.device.batteryCharge >= 0 ? KdeConnect.device.batteryCharge + "%" : "Connected")
                               : (KdeConnect.device && KdeConnect.device.isPaired) ? "Offline" : "Not connected"
                            onClicked: {
                                root.expanded = root.expanded === "mobile" ? "" : "mobile"
                                if (root.expanded === "mobile") { root.mobileView = "notifs"; KdeConnect.refresh() }
                            }
                        }
                        Tile {
                            ic: Theme.icMail; label: "Mail"
                            active: root.expanded === "mail"
                            sub: !Google.signedIn ? "Not connected"
                               : Google.mailState === "offline" ? "Offline"
                               : Google.mailUnread > 0 ? Google.mailUnread + " unread" : "No unread"
                            onClicked: {
                                root.expanded = root.expanded === "mail" ? "" : "mail"
                                if (root.expanded === "mail" && Google.signedIn) Google.fetchMail()
                            }
                        }
                    }

                    // ── options for row 3 (Mobile / Mail) ──
                    Rectangle {
                        width: parent.width
                        visible: root.expanded === "mobile" || root.expanded === "mail"
                        height: visible ? d3Col.implicitHeight + 20 : 0
                        radius: Theme.radiusInner
                        color: Theme.elevated
                        Column {
                            id: d3Col
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                            spacing: 4

                            // ═══ MOBILE (KDE Connect) ═══
                            Column {
                                width: parent.width; spacing: 6; visible: root.expanded === "mobile"

                                // mark everything seen while the list is on screen
                                Connections {
                                    target: KdeConnect
                                    function onNotifsChanged() {
                                        if (Globals.quickSettingsOpen && root.expanded === "mobile" && root.mobileView === "notifs")
                                            KdeConnect.markAllSeen()
                                    }
                                }
                                onVisibleChanged: if (visible) KdeConnect.markAllSeen()

                                // header
                                Item {
                                    width: parent.width; height: 26
                                    Text {
                                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                        text: KdeConnect.connected ? KdeConnect.device.name : "Mobile  ·  KDE Connect"
                                        color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold
                                    }
                                    Row {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                        // battery of the connected phone
                                        Row {
                                            visible: KdeConnect.connected && KdeConnect.device.batteryCharge >= 0
                                            anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: KdeConnect.connected && KdeConnect.device.isCharging ? Theme.icBolt : Theme.icBattFull
                                                font.family: Theme.fontIcons; font.pixelSize: 11
                                                color: KdeConnect.connected && KdeConnect.device.isCharging ? Theme.success : Theme.fgDim
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: KdeConnect.connected ? KdeConnect.device.batteryCharge + "%" : ""
                                                color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold
                                            }
                                        }
                                        // refresh / rescan
                                        Rectangle {
                                            width: 22; height: 22; radius: 6
                                            color: mrfMa.containsMouse ? Theme.hover : "transparent"
                                            Text { anchors.centerIn: parent; text: Theme.icRefresh; font.family: Theme.fontIcons; font.pixelSize: 12; color: Theme.fgDim }
                                            MouseArea { id: mrfMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: KdeConnect.refresh() }
                                        }
                                    }
                                }

                                // — not installed —
                                Text {
                                    width: parent.width; visible: KdeConnect.bridgeUp && !KdeConnect.installed; wrapMode: Text.Wrap
                                    text: "KDE Connect is not installed.\nsudo pacman -S kdeconnect — then install the app on your phone (same Wi-Fi network)."
                                    color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                }
                                // — installed, daemon down —
                                Row {
                                    visible: KdeConnect.installed && !KdeConnect.daemonRunning; spacing: 8
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "KDE Connect daemon is not running."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                    Rectangle {
                                        width: sdTxt.implicitWidth + 20; height: 24; radius: 12
                                        color: sdMa.containsMouse ? Qt.lighter(Theme.accent, 1.15) : Theme.accent
                                        Text { id: sdTxt; anchors.centerIn: parent; text: "Start"; color: Theme.accentText; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                        MouseArea { id: sdMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: KdeConnect.refresh() }
                                    }
                                }

                                // — incoming pair request —
                                Column {
                                    width: parent.width; spacing: 6
                                    visible: KdeConnect.device !== null && KdeConnect.device.pairRequestedByPeer
                                    Text {
                                        width: parent.width; wrapMode: Text.Wrap
                                        text: "“" + (KdeConnect.device ? KdeConnect.device.name : "") + "” wants to pair with this computer."
                                        color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                    }
                                    Row {
                                        spacing: 6
                                        Rectangle {
                                            width: apTxt.implicitWidth + 22; height: 24; radius: 12
                                            color: apMa.containsMouse ? Qt.lighter(Theme.accent, 1.15) : Theme.accent
                                            Text { id: apTxt; anchors.centerIn: parent; text: "Accept"; color: Theme.accentText; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                            MouseArea { id: apMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: KdeConnect.acceptPair(KdeConnect.device.id) }
                                        }
                                        Rectangle {
                                            width: rjTxt.implicitWidth + 22; height: 24; radius: 12
                                            color: rjMa.containsMouse ? Theme.hover : "transparent"; border.color: Theme.hover; border.width: 1
                                            Text { id: rjTxt; anchors.centerIn: parent; text: "Reject"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                            MouseArea { id: rjMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: KdeConnect.cancelPair(KdeConnect.device.id) }
                                        }
                                    }
                                }

                                // — pairing in progress (we asked) —
                                Row {
                                    visible: KdeConnect.pairingId !== ""; spacing: 8
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Pairing — accept the request on your phone…"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                    Rectangle {
                                        width: cpTxt.implicitWidth + 20; height: 24; radius: 12
                                        color: cpMa.containsMouse ? Theme.hover : "transparent"; border.color: Theme.hover; border.width: 1
                                        Text { id: cpTxt; anchors.centerIn: parent; text: "Cancel"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                        MouseArea { id: cpMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: KdeConnect.cancelPair(KdeConnect.pairingId) }
                                    }
                                }
                                Text {
                                    width: parent.width; visible: KdeConnect.pairError !== ""; wrapMode: Text.Wrap
                                    text: KdeConnect.pairError
                                    color: Theme.danger; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                }

                                // — no paired device: reachable-device picker —
                                Column {
                                    width: parent.width; spacing: 2
                                    visible: KdeConnect.installed && KdeConnect.daemonRunning
                                             && (KdeConnect.device === null || (!KdeConnect.device.isPaired && !KdeConnect.device.pairRequestedByPeer))
                                             && KdeConnect.pairingId === ""
                                    Text {
                                        width: parent.width; wrapMode: Text.Wrap
                                        visible: KdeConnect.devices.length === 0
                                        text: "No phones found. Open KDE Connect on your phone — both devices must be on the same network."
                                        color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                    }
                                    Rectangle {
                                        width: parent.width
                                        visible: KdeConnect.devices.length > 0
                                        height: visible ? kdcPickCol.implicitHeight + 10 : 0
                                        radius: 7; color: Theme.bg; border.color: Theme.stroke; border.width: 1
                                        Column {
                                            id: kdcPickCol
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 5
                                            Repeater {
                                                model: KdeConnect.devices
                                                delegate: Item {
                                                    required property var modelData
                                                    width: kdcPickCol.width; height: 28
                                                    Rectangle { anchors.fill: parent; radius: 6; color: kpMa.containsMouse ? Theme.hover : "transparent" }
                                                    Text { anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: Theme.icPhone; font.family: Theme.fontIcons; font.pixelSize: 12; color: modelData.isReachable ? Theme.fg : Theme.fgDim }
                                                    Text {
                                                        anchors.left: parent.left; anchors.leftMargin: 30; anchors.right: parent.right; anchors.rightMargin: 60; anchors.verticalCenter: parent.verticalCenter
                                                        text: modelData.name + (modelData.isReachable ? "" : "  ·  offline")
                                                        color: modelData.isReachable ? Theme.fg : Theme.fgDim
                                                        font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                                        visible: modelData.isReachable
                                                        text: "Pair"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold
                                                    }
                                                    MouseArea { id: kpMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (modelData.isReachable) KdeConnect.requestPair(modelData.id) }
                                                }
                                            }
                                        }
                                    }
                                }

                                // — paired but unreachable —
                                Text {
                                    width: parent.width; wrapMode: Text.Wrap
                                    visible: KdeConnect.device !== null && KdeConnect.device.isPaired && !KdeConnect.device.isReachable
                                    text: "“" + (KdeConnect.device ? KdeConnect.device.name : "") + "” is offline — same network + KDE Connect running on the phone, then Refresh."
                                    color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                }

                                // — connected: quick actions + notifications ⇄ messages —
                                Column {
                                    width: parent.width; spacing: 6
                                    visible: KdeConnect.connected

                                    Row {
                                        spacing: 6
                                        // view switch: Notifications | Messages
                                        Rectangle {
                                            width: nvTxt.implicitWidth + 20; height: 24; radius: 12
                                            color: root.mobileView === "notifs" ? Theme.accent : (nvMa.containsMouse ? Theme.hover : "transparent")
                                            border.color: root.mobileView === "notifs" ? Theme.accent : Theme.hover; border.width: 1
                                            Text { id: nvTxt; anchors.centerIn: parent; text: "Notifications" + (KdeConnect.unreadCount > 0 ? " · " + KdeConnect.unreadCount : ""); color: root.mobileView === "notifs" ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                            MouseArea { id: nvMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.mobileView = "notifs"; KdeConnect.markAllSeen() } }
                                        }
                                        Rectangle {
                                            width: mvTxt.implicitWidth + 20; height: 24; radius: 12
                                            color: root.mobileView === "msgs" ? Theme.accent : (mvvMa.containsMouse ? Theme.hover : "transparent")
                                            border.color: root.mobileView === "msgs" ? Theme.accent : Theme.hover; border.width: 1
                                            Text { id: mvTxt; anchors.centerIn: parent; text: "Messages"; color: root.mobileView === "msgs" ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                            MouseArea { id: mvvMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.mobileView = "msgs"; KdeConnect.loadConversations() } }
                                        }
                                        // ring (find my phone)
                                        Rectangle {
                                            width: 24; height: 24; radius: 12
                                            color: rgMa.containsMouse ? Theme.accent : "transparent"; border.color: Theme.hover; border.width: 1
                                            Text { anchors.centerIn: parent; text: Theme.icBellRing; font.family: Theme.fontIcons; font.pixelSize: 12; color: rgMa.containsMouse ? Theme.accentText : Theme.fg }
                                            MouseArea { id: rgMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: KdeConnect.ring() }
                                        }
                                    }

                                    // ── notifications list ──
                                    Column {
                                        width: parent.width; spacing: 2; visible: root.mobileView === "notifs"
                                        Text {
                                            visible: KdeConnect.notifs.length === 0
                                            text: "No notifications on the phone."
                                            color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                        }
                                        Rectangle {
                                            width: parent.width
                                            visible: KdeConnect.notifs.length > 0
                                            height: visible ? Math.min(kdcNotifCol.implicitHeight + 10, 260) : 0
                                            radius: 7; color: Theme.bg; border.color: Theme.stroke; border.width: 1
                                            Flickable {
                                                anchors.fill: parent; anchors.margins: 5; clip: true
                                                contentHeight: kdcNotifCol.implicitHeight
                                                boundsBehavior: Flickable.StopAtBounds
                                                Column {
                                                    id: kdcNotifCol
                                                    width: parent.width
                                                    Repeater {
                                                        model: KdeConnect.notifs
                                                        delegate: Column {
                                                            id: knRow
                                                            required property var modelData
                                                            width: kdcNotifCol.width
                                                            Item {
                                                                width: parent.width
                                                                height: knBody.implicitHeight + 12
                                                                Rectangle { anchors.fill: parent; radius: 6; color: knMa.containsMouse ? Theme.hover : "transparent" }
                                                                Image {
                                                                    id: knIcon
                                                                    anchors.left: parent.left; anchors.leftMargin: 6; anchors.top: parent.top; anchors.topMargin: 8
                                                                    width: 18; height: 18
                                                                    visible: knRow.modelData.iconPath !== ""
                                                                    source: knRow.modelData.iconPath !== "" ? "file://" + knRow.modelData.iconPath : ""
                                                                    sourceSize.width: 36; sourceSize.height: 36
                                                                }
                                                                Text {
                                                                    visible: knRow.modelData.iconPath === ""
                                                                    anchors.left: parent.left; anchors.leftMargin: 6; anchors.top: parent.top; anchors.topMargin: 8
                                                                    text: Theme.icPhone; font.family: Theme.fontIcons; font.pixelSize: 14; color: Theme.fgDim
                                                                }
                                                                Column {
                                                                    id: knBody
                                                                    anchors.left: parent.left; anchors.leftMargin: 32
                                                                    anchors.right: parent.right; anchors.rightMargin: 44
                                                                    anchors.top: parent.top; anchors.topMargin: 6
                                                                    spacing: 1
                                                                    Text {
                                                                        width: parent.width
                                                                        text: (knRow.modelData.title || knRow.modelData.appName)
                                                                        color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; elide: Text.ElideRight
                                                                    }
                                                                    Text {
                                                                        width: parent.width
                                                                        visible: text !== ""
                                                                        text: knRow.modelData.text || knRow.modelData.ticker
                                                                        color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: 11
                                                                        wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                                                    }
                                                                    Text {
                                                                        text: knRow.modelData.appName
                                                                        color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10
                                                                    }
                                                                }
                                                                MouseArea { id: knMa; anchors.fill: parent; hoverEnabled: true }
                                                                Row {
                                                                    anchors.right: parent.right; anchors.rightMargin: 4; anchors.top: parent.top; anchors.topMargin: 6; spacing: 2
                                                                    // reply (only when the app allows it)
                                                                    Rectangle {
                                                                        visible: knRow.modelData.replyId !== ""
                                                                        width: 20; height: 20; radius: 6
                                                                        color: krMa.containsMouse ? Theme.accent : "transparent"
                                                                        Text { anchors.centerIn: parent; text: Theme.icSend; font.family: Theme.fontIcons; font.pixelSize: 10; color: krMa.containsMouse ? Theme.accentText : Theme.fgDim }
                                                                        MouseArea { id: krMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.replyTarget = root.replyTarget === knRow.modelData.id ? "" : knRow.modelData.id }
                                                                    }
                                                                    // dismiss
                                                                    Rectangle {
                                                                        visible: knRow.modelData.dismissable
                                                                        width: 20; height: 20; radius: 6
                                                                        color: kdMa.containsMouse ? Theme.danger : "transparent"
                                                                        Text { anchors.centerIn: parent; text: Theme.icClose; font.family: Theme.fontIcons; font.pixelSize: 10; color: kdMa.containsMouse ? Theme.accentText : Theme.fgDim }
                                                                        MouseArea { id: kdMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: KdeConnect.dismissNotif(knRow.modelData.id) }
                                                                    }
                                                                }
                                                            }
                                                            // inline reply box
                                                            Item {
                                                                width: parent.width; height: visible ? 34 : 0
                                                                visible: root.replyTarget === knRow.modelData.id
                                                                Rectangle {
                                                                    anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 4; radius: 7
                                                                    color: Theme.bg; border.color: Theme.accent; border.width: 1
                                                                    TextInput {
                                                                        id: knReply
                                                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 52; verticalAlignment: TextInput.AlignVCenter
                                                                        color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                                                        Component.onCompleted: if (root.replyTarget === knRow.modelData.id) forceActiveFocus()
                                                                        onAccepted: { if (text.trim() !== "") { KdeConnect.replyNotif(knRow.modelData.replyId, text.trim()); root.replyTarget = "" } }
                                                                        Text { anchors.verticalCenter: parent.verticalCenter; visible: knReply.text.length === 0; text: "Reply…"; color: Theme.fgDim; font: knReply.font }
                                                                    }
                                                                    Text {
                                                                        anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                                                        text: "Send"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold
                                                                        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: { if (knReply.text.trim() !== "") { KdeConnect.replyNotif(knRow.modelData.replyId, knReply.text.trim()); root.replyTarget = "" } } }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // ── messages: conversation list ⇄ thread ──
                                    Column {
                                        width: parent.width; spacing: 4; visible: root.mobileView === "msgs"

                                        // conversation list
                                        Column {
                                            width: parent.width; spacing: 2; visible: KdeConnect.openThread < 0
                                            Text {
                                                visible: KdeConnect.conversations.length === 0
                                                width: parent.width; wrapMode: Text.Wrap
                                                text: KdeConnect.convsRequested ? "Loading conversations from the phone…" : "No conversations yet."
                                                color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                            }
                                            Rectangle {
                                                width: parent.width
                                                visible: KdeConnect.conversations.length > 0
                                                height: visible ? Math.min(kdcConvCol.implicitHeight + 10, 280) : 0
                                                radius: 7; color: Theme.bg; border.color: Theme.stroke; border.width: 1
                                                Flickable {
                                                    anchors.fill: parent; anchors.margins: 5; clip: true
                                                    contentHeight: kdcConvCol.implicitHeight
                                                    boundsBehavior: Flickable.StopAtBounds
                                                    Column {
                                                        id: kdcConvCol
                                                        width: parent.width
                                                        Repeater {
                                                            model: KdeConnect.conversations
                                                            delegate: Item {
                                                                id: kcRow
                                                                required property var modelData
                                                                width: kdcConvCol.width; height: 40
                                                                Rectangle { anchors.fill: parent; radius: 6; color: kcMa.containsMouse ? Theme.hover : "transparent" }
                                                                Rectangle {
                                                                    visible: kcRow.modelData.unread
                                                                    anchors.left: parent.left; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter
                                                                    width: 6; height: 6; radius: 3; color: Theme.accent
                                                                }
                                                                Column {
                                                                    anchors.left: parent.left; anchors.leftMargin: 14
                                                                    anchors.right: parent.right; anchors.rightMargin: 52
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    spacing: 1
                                                                    Text {
                                                                        width: parent.width
                                                                        text: kcRow.modelData.display
                                                                        color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                                                        font.weight: kcRow.modelData.unread ? Font.Bold : Font.DemiBold; elide: Text.ElideRight
                                                                    }
                                                                    Text {
                                                                        width: parent.width
                                                                        text: kcRow.modelData.body
                                                                        color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; elide: Text.ElideRight
                                                                    }
                                                                }
                                                                Text {
                                                                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.top: parent.top; anchors.topMargin: 5
                                                                    text: root.fmtMsgTime(kcRow.modelData.date)
                                                                    color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10
                                                                }
                                                                MouseArea { id: kcMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: KdeConnect.openConversation(kcRow.modelData.threadId) }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // thread view
                                        Column {
                                            width: parent.width; spacing: 4; visible: KdeConnect.openThread >= 0
                                            Item {
                                                width: parent.width; height: 24
                                                Rectangle {
                                                    width: 24; height: 24; radius: 6
                                                    color: bkMa.containsMouse ? Theme.hover : "transparent"
                                                    Text { anchors.centerIn: parent; text: Theme.icBack; font.family: Theme.fontIcons; font.pixelSize: 13; color: Theme.fg }
                                                    MouseArea { id: bkMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: KdeConnect.openThread = -1 }
                                                }
                                                Text {
                                                    anchors.left: parent.left; anchors.leftMargin: 30; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                                    text: {
                                                        for (var i = 0; i < KdeConnect.conversations.length; i++)
                                                            if (KdeConnect.conversations[i].threadId === KdeConnect.openThread) return KdeConnect.conversations[i].display
                                                        return "Conversation"
                                                    }
                                                    color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; elide: Text.ElideRight
                                                }
                                            }
                                            Rectangle {
                                                width: parent.width; height: 260
                                                radius: 7; color: Theme.bg; border.color: Theme.stroke; border.width: 1
                                                Flickable {
                                                    id: kdcThreadFlick
                                                    anchors.fill: parent; anchors.margins: 8; clip: true
                                                    contentHeight: kdcThreadCol.implicitHeight
                                                    boundsBehavior: Flickable.StopAtBounds
                                                    // stick to the newest message
                                                    onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                                                    // pull past the top → page older messages in
                                                    onAtYBeginningChanged: if (atYBeginning && contentHeight > height) KdeConnect.loadOlder()
                                                    Column {
                                                        id: kdcThreadCol
                                                        width: parent.width; spacing: 4
                                                        Repeater {
                                                            model: KdeConnect.thread
                                                            delegate: Item {
                                                                id: kmRow
                                                                required property var modelData
                                                                readonly property bool sent: modelData.type === 2
                                                                width: kdcThreadCol.width
                                                                height: kmBubble.height
                                                                Rectangle {
                                                                    id: kmBubble
                                                                    anchors.right: kmRow.sent ? parent.right : undefined
                                                                    anchors.left: kmRow.sent ? undefined : parent.left
                                                                    width: Math.min(kmTxt.implicitWidth + 20, kmRow.width * 0.8)
                                                                    height: kmTxt.implicitHeight + 14
                                                                    radius: 10
                                                                    color: kmRow.sent ? Theme.accent : Theme.elevated
                                                                    opacity: kmRow.modelData.pending ? 0.6 : 1
                                                                    Text {
                                                                        id: kmTxt
                                                                        anchors.fill: parent; anchors.margins: 7; anchors.leftMargin: 10; anchors.rightMargin: 10
                                                                        text: kmRow.modelData.body !== "" ? kmRow.modelData.body
                                                                            : (kmRow.modelData.hasAttachments ? "📎 Attachment (view on phone)" : "(no text — MMS)")
                                                                        color: kmRow.sent ? Theme.accentText : Theme.fg
                                                                        font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                                                        font.italic: kmRow.modelData.body === ""
                                                                        wrapMode: Text.Wrap
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            // compose
                                            Rectangle {
                                                width: parent.width; height: 32; radius: 7
                                                color: Theme.bg; border.color: kdcCompose.activeFocus ? Theme.accent : Theme.stroke; border.width: 1
                                                TextInput {
                                                    id: kdcCompose
                                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 34; verticalAlignment: TextInput.AlignVCenter
                                                    color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                                    onAccepted: { if (text.trim() !== "") { KdeConnect.sendMessage(text.trim()); text = "" } }
                                                    Text { anchors.verticalCenter: parent.verticalCenter; visible: kdcCompose.text.length === 0; text: "Message…"; color: Theme.fgDim; font: kdcCompose.font }
                                                }
                                                Text {
                                                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                                                    text: Theme.icSend; font.family: Theme.fontIcons; font.pixelSize: 13
                                                    color: kdcCompose.text.trim() !== "" ? Theme.accent : Theme.fgDim
                                                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: { if (kdcCompose.text.trim() !== "") { KdeConnect.sendMessage(kdcCompose.text.trim()); kdcCompose.text = "" } } }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ═══ MAIL (Gmail) ═══
                            Column {
                                width: parent.width; spacing: 6; visible: root.expanded === "mail"
                                Item {
                                    width: parent.width; height: 26
                                    Text {
                                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                        text: Google.signedIn ? ("Inbox" + (Google.mailUnread > 0 ? "  ·  " + Google.mailUnread + " unread" : "")) : "Mail"
                                        color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold
                                    }
                                    Row {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                        // new-mail notifications on/off
                                        Rectangle {
                                            visible: Google.signedIn
                                            width: 22; height: 22; radius: 6
                                            color: mnMa.containsMouse ? Theme.hover : "transparent"
                                            Text { anchors.centerIn: parent; text: Theme.icBellRing; font.family: Theme.fontIcons; font.pixelSize: 12; color: Google.mailNotify ? Theme.accent : Theme.fgDim }
                                            MouseArea { id: mnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Google.setMailNotify(!Google.mailNotify) }
                                        }
                                        Rectangle {
                                            visible: Google.signedIn
                                            width: 22; height: 22; radius: 6
                                            color: mlrMa.containsMouse ? Theme.hover : "transparent"
                                            Text { anchors.centerIn: parent; text: Theme.icRefresh; font.family: Theme.fontIcons; font.pixelSize: 12; color: Theme.fgDim }
                                            MouseArea { id: mlrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Google.fetchMail() }
                                        }
                                        Rectangle {
                                            width: ogTxt.implicitWidth + 18; height: 22; radius: 11
                                            color: ogMa.containsMouse ? Theme.hover : "transparent"; border.color: Theme.hover; border.width: 1
                                            Text { id: ogTxt; anchors.centerIn: parent; text: "Open Gmail"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 11 }
                                            MouseArea { id: ogMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["xdg-open", "https://mail.google.com/mail/u/0/"]) }
                                        }
                                    }
                                }
                                Text {
                                    width: parent.width; visible: !Google.signedIn; wrapMode: Text.Wrap
                                    text: "Connect a Google account (Settings → User) to see mail here."
                                    color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                }
                                Text {
                                    width: parent.width; visible: Google.signedIn && Google.mailError !== ""; wrapMode: Text.Wrap
                                    text: Google.mailError
                                    color: Theme.warning; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                }
                                Row {
                                    visible: Google.signedIn && Google.mailState === "scope"; spacing: 6
                                    Rectangle {
                                        width: rcTxt.implicitWidth + 22; height: 24; radius: 12
                                        color: rcMa.containsMouse ? Qt.lighter(Theme.accent, 1.15) : Theme.accent
                                        Text { id: rcTxt; anchors.centerIn: parent; text: "Reconnect Google"; color: Theme.accentText; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                        MouseArea { id: rcMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Google.signIn() }
                                    }
                                }
                                Text {
                                    width: parent.width
                                    visible: Google.signedIn && Google.mailState === "offline"
                                    text: "Offline — showing the last check."
                                    color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                }
                                Text {
                                    width: parent.width
                                    visible: Google.signedIn && Google.mailState === "" && Google.mailList.length === 0
                                    text: "Inbox is empty."
                                    color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                }
                                // latest 10, compact two-line rows — no inner scrolling
                                Rectangle {
                                    width: parent.width
                                    visible: Google.signedIn && Google.mailList.length > 0
                                    height: visible ? mailCol.implicitHeight + 10 : 0
                                    radius: 7; color: Theme.bg; border.color: Theme.stroke; border.width: 1
                                    Column {
                                        id: mailCol
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 5
                                        Repeater {
                                            model: Google.mailList.slice(0, 10)
                                            delegate: Item {
                                                id: mRow
                                                required property var modelData
                                                width: mailCol.width; height: 34
                                                Rectangle { anchors.fill: parent; radius: 6; color: mmMa.containsMouse ? Theme.hover : "transparent" }
                                                Rectangle {
                                                    visible: mRow.modelData.unread
                                                    anchors.left: parent.left; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter
                                                    width: 6; height: 6; radius: 3; color: Theme.accent
                                                }
                                                Column {
                                                    anchors.left: parent.left; anchors.leftMargin: 14
                                                    anchors.right: parent.right; anchors.rightMargin: 52
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 0
                                                    Text {
                                                        width: parent.width
                                                        text: mRow.modelData.from
                                                        color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                                        font.weight: mRow.modelData.unread ? Font.Bold : Font.DemiBold; elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        width: parent.width
                                                        text: mRow.modelData.subject
                                                        color: mRow.modelData.unread ? Theme.fgSecondary : Theme.fgDim
                                                        font.family: Theme.fontText; font.pixelSize: 11; elide: Text.ElideRight
                                                    }
                                                }
                                                Text {
                                                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                                    text: root.fmtMsgTime(mRow.modelData.date)
                                                    color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10
                                                }
                                                MouseArea { id: mmMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Google.openMail(mRow.modelData.id) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width; spacing: 10
                        Tile {
                            ic: Theme.icDnd; label: "Do Not Disturb"; active: Globals.dnd
                            sub: Globals.dnd ? "On" : "Off"
                            onClicked: Globals.dnd = !Globals.dnd
                        }
                        Tile {
                            // eye open when awake, eye-off when idle-inhibitor is off
                            ic: (Globals.caffeine ? Theme.icEye : Theme.icEyeOff); label: "Insomnia"; active: Globals.caffeine
                            sub: Globals.caffeine ? "Awake" : "Off"
                            onClicked: Globals.caffeine = !Globals.caffeine
                        }
                    }

                    // (the tiling⇄floating toggle lives in the top bar now)

                    // ── sliders + audio output ──
                    Rectangle {
                        width: parent.width; height: sCol.implicitHeight + 24; radius: Theme.radiusInner; color: Theme.elevated
                        Column {
                            id: sCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12; spacing: 12
                            Slider { width: parent.width; icon: Theme.icSun; value: root.brightnessVal; onMoved: function (v) { root.setBrightness(v) } }
                            Slider { width: parent.width; icon: Theme.icVolHigh; value: root.volumeVal; onMoved: function (v) { root.setVolume(v) } }
                            // output device — the shared DropRow (same dropdown as Settings)
                            DropRow {
                                label: "Output"
                                ddId: "qs-audio-out"
                                buttonWidth: 210
                                options: {
                                    var out = [], n = Pipewire.nodes.values
                                    for (var i = 0; i < n.length; i++) { var x = n[i]; if (x.isSink && !x.isStream && x.audio) out.push({ label: x.description || x.nickname || x.name, value: x.id }) }
                                    return out
                                }
                                value: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.id : ""
                                onPicked: function (v) {
                                    var n = Pipewire.nodes.values
                                    for (var i = 0; i < n.length; i++) if (n[i].id === v) { Pipewire.preferredDefaultAudioSink = n[i]; break }
                                }
                            }
                        }
                    }

                    // ── media (MPRIS) — right under the audio controls. Only a live,
                    //    controllable player is shown: stale/dead MPRIS sources (no
                    //    control interface, nothing loaded) hide the card entirely,
                    //    so a play button that would do nothing never appears. ──
                    Rectangle {
                        id: mediaCard
                        property var player: {
                            var ps = Mpris.players.values
                            for (var i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i]
                            for (var j = 0; j < ps.length; j++) {
                                var p = ps[j]
                                if (p.canControl && p.canPlay && ((p.trackTitle && p.trackTitle !== "") || (p.trackArtist && p.trackArtist !== ""))) return p
                            }
                            return null
                        }
                        visible: player !== null
                        width: parent.width; height: visible ? mediaRow.implicitHeight + 24 : 0; radius: Theme.radiusInner; color: Theme.elevated
                        Row {
                            id: mediaRow
                            anchors.fill: parent; anchors.margins: 12; spacing: 12
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 48; height: 48; radius: 8; color: Theme.hover; clip: true
                                Image { id: art; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; source: mediaCard.player && mediaCard.player.trackArtUrl ? mediaCard.player.trackArtUrl : ""; visible: source != "" }
                                Text { anchors.centerIn: parent; visible: art.source == ""; text: Theme.icMusic; font.family: Theme.fontIcons; font.pixelSize: 18; color: Theme.fgDim }
                            }
                            Column {
                                width: parent.width - 48 - 24 - mediaCtl.width; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                // the playing source (player identity: "Spotify", "mpv", …)
                                Text { width: parent.width; text: mediaCard.player ? (mediaCard.player.identity || mediaCard.player.desktopEntry || "Media") : ""; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: 10; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                Text { width: parent.width; text: mediaCard.player ? (mediaCard.player.trackTitle || "—") : ""; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                Text { width: parent.width; visible: text !== ""; text: mediaCard.player ? (mediaCard.player.trackArtist || "") : ""; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; elide: Text.ElideRight }
                            }
                            Row {
                                id: mediaCtl
                                anchors.verticalCenter: parent.verticalCenter; spacing: 16
                                property var pl: mediaCard.player
                                // controls dim + ignore clicks when the player can't do the action
                                Text { anchors.verticalCenter: parent.verticalCenter; text: Theme.icPrev; font.family: Theme.fontIcons; font.pixelSize: 15; color: Theme.fg; opacity: mediaCtl.pl && mediaCtl.pl.canGoPrevious ? 1 : 0.35; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (mediaCtl.pl && mediaCtl.pl.canGoPrevious) mediaCtl.pl.previous() } }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: mediaCtl.pl && mediaCtl.pl.isPlaying ? Theme.icPause : Theme.icPlay; font.family: Theme.fontIcons; font.pixelSize: 18; color: Theme.fg; opacity: mediaCtl.pl && (mediaCtl.pl.isPlaying ? mediaCtl.pl.canPause : mediaCtl.pl.canPlay) ? 1 : 0.35; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (mediaCtl.pl && (mediaCtl.pl.isPlaying ? mediaCtl.pl.canPause : mediaCtl.pl.canPlay)) mediaCtl.pl.togglePlaying() } }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: Theme.icNext; font.family: Theme.fontIcons; font.pixelSize: 15; color: Theme.fg; opacity: mediaCtl.pl && mediaCtl.pl.canGoNext ? 1 : 0.35; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (mediaCtl.pl && mediaCtl.pl.canGoNext) mediaCtl.pl.next() } }
                            }
                        }
                    }

                    // ── system load (CPU + memory; RunCat reads the same CPU value) ──
                    Rectangle {
                        width: parent.width; height: sysCol.implicitHeight + 24; radius: Theme.radiusInner; color: Theme.elevated
                        Column {
                            id: sysCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12; spacing: 10
                            // a labelled meter row
                            component Meter: Column {
                                property string label: ""; property real value: 0; property string glyph: ""
                                width: parent.width; spacing: 4
                                Item {
                                    width: parent.width; height: 16
                                    Row { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 7
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: glyph; font.family: Theme.fontIcons; font.pixelSize: 13; color: Theme.fgDim }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: label; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                    }
                                    Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: Math.round(value * 100) + "%"; color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                }
                                Rectangle { width: parent.width; height: 6; radius: 3; color: Theme.hover
                                    Rectangle { height: parent.height; radius: 3; width: parent.width * Math.max(0, Math.min(1, value)); color: value > 0.85 ? Theme.danger : (value > 0.6 ? Theme.warning : Theme.accent); Behavior on width { NumberAnimation { duration: 400 } } }
                                }
                            }
                            Meter { label: "CPU"; glyph: Theme.icCpu; value: Globals.cpuUsage }
                            Meter { label: "Memory"; glyph: Theme.icMemory; value: Globals.memUsage }
                        }
                    }

                    // ── calendar (compact) ──
                    Rectangle {
                        width: parent.width; height: calCol.implicitHeight + 20; radius: Theme.radiusInner; color: Theme.elevated
                        Column {
                            id: calCol
                            anchors.fill: parent; anchors.margins: 10; spacing: 5
                            Text { text: root.monthNames[root.calMonth] + " " + root.calYear; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                            Grid {
                                width: parent.width; columns: 7
                                Repeater {
                                    model: ["S","M","T","W","T","F","S"]
                                    delegate: Item { required property var modelData; width: calCol.width / 7; height: 22; Text { anchors.centerIn: parent; text: modelData; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11 } }
                                }
                                Repeater {
                                    model: 42
                                    delegate: Item {
                                        required property int index
                                        readonly property int dayNum: index - root.firstW + 1
                                        readonly property bool valid: dayNum >= 1 && dayNum <= root.daysIn
                                        readonly property bool isToday: valid && dayNum === root.calDate
                                        readonly property bool hasEvent: valid && root.eventDays[dayNum] !== undefined
                                        width: calCol.width / 7; height: 32
                                        Rectangle { anchors.centerIn: parent; width: 26; height: 26; radius: 13; visible: parent.isToday; color: Theme.accent }
                                        Text { anchors.centerIn: parent; text: parent.valid ? parent.dayNum : ""; color: parent.isToday ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: 12; font.weight: parent.isToday ? Font.Bold : Font.Normal }
                                        // event dot — tinted to the calendar's own colour. Skipped on
                                        // today: the filled circle already marks it, and a dot would
                                        // half-overlap the circle's bottom edge (32px cell, 26px circle).
                                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 1; width: 4; height: 4; radius: 2; visible: parent.hasEvent && !parent.isToday; color: root.eventDays[parent.dayNum] || Theme.accent }
                                    }
                                }
                            }
                            // agenda — upcoming events grouped by day, GNOME-dropdown style
                            Rectangle { visible: root.agenda.length > 0; width: parent.width; height: 1; color: Theme.stroke; opacity: 0.6 }
                            Text {
                                visible: Google.calState === "offline"
                                width: parent.width; text: "Offline — showing last synced events"
                                color: Theme.warning; font.family: Theme.fontText; font.pixelSize: 10
                            }
                            Text {
                                visible: root.agenda.length === 0
                                width: parent.width
                                text: (Google.signedIn || (Accounts.events || []).length > 0) ? "No upcoming events" : "Connect a Google account (Settings → User) to see events here"
                                color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10; wrapMode: Text.Wrap
                            }
                            Repeater {
                                model: root.agenda
                                delegate: Column {
                                    id: agDay
                                    required property var modelData
                                    width: parent.width; spacing: 2
                                    Text { topPadding: 3; text: agDay.modelData.label; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10; font.weight: Font.DemiBold }
                                    Repeater {
                                        model: agDay.modelData.events
                                        delegate: Item {
                                            required property var modelData
                                            width: agDay.width; height: 30
                                            Rectangle { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: 3; height: 20; radius: 1.5; color: modelData.color !== "" ? modelData.color : Theme.accent }
                                            Column {
                                                anchors.left: parent.left; anchors.leftMargin: 11; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 0
                                                Text { width: parent.width; text: modelData.summary; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; elide: Text.ElideRight }
                                                Text { width: parent.width; text: root.fmtEventTime(modelData) + (modelData.location ? "  ·  " + modelData.location : ""); color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10; elide: Text.ElideRight }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── notifications ──
                    Item {
                        width: parent.width; height: 20
                        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Notifications"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                        Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; visible: Globals.server && Globals.server.trackedNotifications.values.length > 0; text: "Clear All"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.clearAll() } }
                    }
                    Text { width: parent.width; visible: !Globals.server || Globals.server.trackedNotifications.values.length === 0; text: "No Notifications"; horizontalAlignment: Text.AlignHCenter; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; topPadding: 6; bottomPadding: 6 }
                    // One card per APP. A card holding several notifications shows the
                    // latest + a count badge; clicking it expands every notification
                    // of that app (each closable / clickable). A single-notification
                    // card jumps straight to the window that notified.
                    Repeater {
                        model: root.noteGroups
                        delegate: Rectangle {
                            id: nGroup
                            required property var modelData
                            readonly property int count: modelData.items.length
                            readonly property bool open: count > 1 && root.nExpanded === modelData.app
                            width: inner.width; height: gCol.implicitHeight + 20; radius: Theme.radiusInner; color: Theme.elevated

                            // card click — declared FIRST so the inner rows' and the
                            // CloseBtn's MouseAreas (later children) win over it
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (nGroup.count > 1) root.nExpanded = nGroup.open ? "" : nGroup.modelData.app
                                    else root.noteFocus(nGroup.modelData.latest)
                                }
                            }

                            Column {
                                id: gCol
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                                spacing: 6

                                // header: app + count + chevron; latest preview when collapsed
                                Row {
                                    width: parent.width; spacing: 10
                                    Image {
                                        width: 32; height: 32; sourceSize.width: 64; sourceSize.height: 64; visible: source != ""
                                        source: root.noteIcon(nGroup.modelData.latest)
                                    }
                                    Column {
                                        width: parent.width - 42 - 26; spacing: 1
                                        Row {
                                            spacing: 6
                                            Text { text: nGroup.modelData.app; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; elide: Text.ElideRight }
                                            Rectangle {
                                                visible: nGroup.count > 1
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: gCnt.implicitWidth + 10; height: 14; radius: 7; color: Theme.accent
                                                Text { id: gCnt; anchors.centerIn: parent; text: nGroup.count; color: Theme.accentText; font.family: Theme.fontText; font.pixelSize: 9; font.weight: Font.Bold }
                                            }
                                            Text {
                                                visible: nGroup.count > 1
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Theme.icChevronDown; rotation: nGroup.open ? 180 : 0
                                                font.family: Theme.fontIcons; font.pixelSize: 11; color: Theme.fgDim
                                                Behavior on rotation { NumberAnimation { duration: Theme.durFast } }
                                            }
                                        }
                                        Text { visible: !nGroup.open; width: parent.width; text: nGroup.modelData.latest.summary || ""; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                        Text { visible: !nGroup.open && text.length > 0; width: parent.width; text: nGroup.modelData.latest.body || ""; color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; textFormat: Text.PlainText }
                                    }
                                }

                                // expanded: every notification of the app
                                Repeater {
                                    model: nGroup.open ? nGroup.modelData.items : []
                                    delegate: Rectangle {
                                        id: nItem
                                        required property var modelData
                                        width: gCol.width; height: iCol.implicitHeight + 14; radius: 7
                                        color: iMa.containsMouse ? Theme.hover : Theme.bg
                                        MouseArea { id: iMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.noteFocus(nItem.modelData) }
                                        Column {
                                            id: iCol
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 7; anchors.rightMargin: 30
                                            spacing: 1
                                            Text { width: parent.width; text: nItem.modelData.summary || ""; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                            Text { width: parent.width; visible: text.length > 0; text: nItem.modelData.body || ""; color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; textFormat: Text.PlainText }
                                        }
                                        CloseBtn { anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 5; onPressed: nItem.modelData.dismiss() }
                                    }
                                }
                            }
                            // ✕ dismisses the whole group
                            CloseBtn { anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 8; onPressed: root.dismissAllOf(nGroup.modelData.items) }
                        }
                    }
                }
            }

            // ── backdrop: a click anywhere else in the panel dismisses the power menu ──
            MouseArea { anchors.fill: parent; visible: root.powerOpen; onClicked: root.powerOpen = false }

            // ── Power popover: floating, window-like menu (rounded + drop shadow) ──
            Item {
                id: powerPop
                visible: root.powerOpen || ppCloseTimer.running
                width: 232
                height: ppCol.implicitHeight + 16
                anchors.top: parent.top; anchors.topMargin: 56
                anchors.right: parent.right; anchors.rightMargin: 14
                transformOrigin: Item.TopRight
                opacity: root.powerOpen ? 1 : 0
                scale: root.powerOpen ? 1 : 0.9
                Behavior on opacity { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutCubic } }
                Timer { id: ppCloseTimer; interval: Math.max(1, Theme.durBase) }
                Connections { target: root; function onPowerOpenChanged() { if (!root.powerOpen) ppCloseTimer.restart() } }

                // background + real drop shadow (MultiEffect)
                Rectangle {
                    id: ppBg
                    anchors.fill: parent
                    radius: 16
                    color: Theme.elevated
                    border.color: Theme.stroke; border.width: 1
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Theme.shadow
                        shadowOpacity: 0.5
                        shadowBlur: 1.0
                        shadowVerticalOffset: 7
                        blurMax: 40
                    }
                }
                MouseArea { anchors.fill: parent }   // swallow clicks inside the popover

                Column {
                    id: ppCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 6

                    Text { leftPadding: 2; text: "Power Profile"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                    // segmented profile selector (PowerProfiles service ← tuned-ppd D-Bus)
                    // uniform 8px gaps: edge→pill = pill→pill = 8 (mathematically even)
                    Row {
                        width: parent.width; spacing: 8
                        Repeater {
                            model: [{ prof: PowerProfile.PowerSaver, ic: 0xE2DA, label: "Saver" }, { prof: PowerProfile.Balanced, ic: 0xE750, label: "Balanced" }, { prof: PowerProfile.Performance, ic: 0xE628, label: "Turbo" }]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool sel: PowerProfiles.profile === modelData.prof
                                readonly property bool disabled: modelData.prof === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile
                                width: (ppCol.width - 16) / 3
                                height: 46; radius: 9
                                opacity: disabled ? 0.4 : 1
                                color: sel ? Theme.accent : Theme.elevated
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Column {
                                    anchors.centerIn: parent; spacing: 3
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.g(modelData.ic); font.family: Theme.fontIcons; font.pixelSize: 15; color: parent.parent.sel ? Theme.accentText : Theme.fg }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: parent.parent.sel ? Theme.accentText : Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10; font.weight: Font.DemiBold }
                                }
                                MouseArea { anchors.fill: parent; enabled: !parent.disabled; cursorShape: Qt.PointingHandCursor; onClicked: PowerProfiles.profile = modelData.prof }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Theme.stroke; opacity: 0.6 }

                    PowerItem { ic: 0xE2FA; label: "Lock";      onGo: root.runPower("lock") }
                    PowerItem { ic: 0xE58E; label: "Suspend";   onGo: root.runPower("suspend") }
                    PowerItem { ic: 0xE42A; label: "Log Out";   onGo: root.askPower("logout", "Log out?", "Log Out") }
                    PowerItem { ic: 0xE094; label: "Restart";   onGo: root.askPower("reboot", "Restart this computer?", "Restart") }
                    PowerItem { ic: 0xE3DA; label: "Shut Down"; danger: true; onGo: root.askPower("poweroff", "Shut down this computer?", "Shut Down") }
                }
            }

            // ── Confirmation popover: themed "are you sure?" for destructive
            //    actions (Log Out / Restart / Shut Down). Esc or clicking the
            //    dimmed backdrop cancels. ──
            Item {
                id: confirmPop
                anchors.fill: parent
                visible: root.confirmAction !== "" || cfCloseTimer.running
                z: 100
                Timer { id: cfCloseTimer; interval: Math.max(1, Theme.durBase) }
                Connections { target: root; function onConfirmActionChanged() { if (root.confirmAction === "") cfCloseTimer.restart() } }

                readonly property bool danger: root.confirmAction === "poweroff" || root.confirmAction === "reboot"

                // dimmed backdrop — click anywhere outside the card to cancel
                Rectangle {
                    anchors.fill: parent
                    color: "#000000"
                    opacity: root.confirmAction !== "" ? 0.45 : 0
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    MouseArea { anchors.fill: parent; onClicked: root.confirmAction = "" }
                }

                Rectangle {
                    id: cfCard
                    anchors.centerIn: parent
                    width: 252
                    height: cfCol.implicitHeight + 36
                    radius: 18
                    color: Theme.elevated
                    border.color: Theme.stroke; border.width: 1
                    opacity: root.confirmAction !== "" ? 1 : 0
                    scale: root.confirmAction !== "" ? 1 : 0.92
                    Behavior on opacity { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutCubic } }
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Theme.shadow
                        shadowOpacity: 0.55
                        shadowBlur: 1.0
                        shadowVerticalOffset: 9
                        blurMax: 48
                    }
                    MouseArea { anchors.fill: parent }   // swallow clicks on the card

                    Column {
                        id: cfCol
                        anchors.centerIn: parent
                        width: parent.width - 32
                        spacing: 14

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.g(confirmPop.danger ? 0xE3DA : 0xE42A)
                            font.family: Theme.fontIcons; font.pixelSize: 32
                            color: confirmPop.danger ? Theme.danger : Theme.accent
                        }
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                            text: root.confirmTitle
                            color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 10
                            // Cancel
                            Rectangle {
                                width: (cfCol.width - 10) / 2; height: 38; radius: 10
                                color: cancelMa.containsMouse ? Theme.hover : Theme.panel
                                border.color: Theme.stroke; border.width: 1
                                Text { anchors.centerIn: parent; text: "Cancel"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.Medium }
                                MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.confirmAction = "" }
                            }
                            // Confirm
                            Rectangle {
                                width: (cfCol.width - 10) / 2; height: 38; radius: 10
                                color: confirmMa.containsMouse ? (confirmPop.danger ? Theme.danger : Theme.accent)
                                                               : Qt.rgba((confirmPop.danger ? Theme.danger : Theme.accent).r, (confirmPop.danger ? Theme.danger : Theme.accent).g, (confirmPop.danger ? Theme.danger : Theme.accent).b, 0.18)
                                Text { anchors.centerIn: parent; text: root.confirmVerb; color: confirmMa.containsMouse ? Theme.accentText : (confirmPop.danger ? Theme.danger : Theme.accent); font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                MouseArea { id: confirmMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.runPower(root.confirmAction) }
                            }
                        }
                    }
                }
            }
        }
    }
}
