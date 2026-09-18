import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Notifications
import Quickshell.Bluetooth

// QuickSettings — Quick settings (design system: Quick settings, Quick
// settings tile, Switch, Slider, List row, Section header, Agenda,
// Notification center, Power menu, Dialog, Empty state).
//
//   panel    panelMd wide (the icon rail plus the card's panelSm of content),
//            surfaceRaised with a borderWidth1 borderSubtle outline, the
//            radiusRounded corner and the shadowFloat elevation, spaceXs
//            below the bar at the right edge, spaceS + spaceXs of padding and
//            between sections. Its height follows the open page, up to 80%
//            of the screen. Solid, never Glass.
//   motion   in: fade plus a slideOffset drop at durBase; out at durFast;
//            OutCubic, and nothing moves under Reduce motion
//   rail     the collapsed Side navigation: the sheep mark, then one
//            controlLg × controlMd item per page (home, Wi-Fi, Bluetooth,
//            sound, VPN, SSH, Cast, Mobile, Mail, Calendar, Notifications) on
//            surfaceBase; the selected page is accentSubtle with an
//            accentText glyph; Settings and Power sit at its foot
//   home     the tile grid (Tile.qml), spaceS apart, and the CPU / memory
//            meters
//   pages    a detail page per tile: the feature's name and Switch, then its
//            list (ListWell + ListRow), notes and actions
//   foot     volume and brightness Sliders under a divider, always shown
//
// Every page, tab, shortcut and IPC command of the 2026-09 panel stays:
// `quicksettings toggle|show|hide|powerdialog|tab <name>`.
Scope {
    id: root

    // all colours come from Theme.qml (single source of truth)
    // ── Audio device lists ────────────────────────────────────────────────
    // THE LIST IS PORTS, NOT CARDS. A sound card publishes one PipeWire node
    // per ALSA UCM device, not per usable output. This laptop has five sinks
    // — Speaker, Headphones, HDMI1, HDMI2, HDMI3 — and their descriptions are
    // all "Core Ultra 200V Series Processors HD Audio <something>", so in a
    // sidebar-width row every one of them elides to the same
    // "Core Ultra 200V Series Processors HD Aud…". They were never duplicates;
    // they were five rows whose only distinguishing word was off-screen.
    //
    // Three things, then:
    //
    //  1. LABEL WITH THE NICK. node.nick is already the short, human name —
    //     "Speaker", "Headphones", "LS27D60xU" (the monitor's own model), "HDMI
    //     2". description is the CARD talking, and the card is the same for
    //     every row, so it belongs last. Dedupe follows the label that is
    //     actually rendered, which now distinguishes.
    //  2. DROP DEAD PORTS. Nothing is plugged into HDMI 2, so offering it is
    //     offering silence. Availability lives on the card's PORT and PipeWire
    //     does not copy it onto the node, so it is not reachable from here at
    //     all — scripts/audio-ports.py asks pactl and names the nodes to hide.
    //     An unreadable answer hides nothing, so the list can never go empty.
    //  3. DROP MONITORS. PipeWire publishes a monitor SOURCE for every sink —
    //     a loopback of what is playing. Nobody picks one as their microphone.
    property var deadNodes: ({})

    Process {
        id: portScan
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/audio-ports.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = {}, lines = this.text.split("\n")
                for (var i = 0; i < lines.length; i++)
                    if (lines[i].trim() !== "") m[lines[i].trim()] = true
                root.deadNodes = m
            }
        }
    }
    // Re-ask when the node set changes — plugging headphones in adds a node
    // AND flips a port's availability, and only the first is observable here.
    Connections {
        target: Pipewire.nodes
        function onValuesChanged() { portScan.running = false; portScan.running = true }
    }
    Component.onCompleted: portScan.running = true

    function audioNodes(wantSink) {
        var n = Pipewire.nodes.values, seen = {}, out = []
        var def = wantSink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
        for (var pass = 0; pass < 2; pass++)
            for (var i = 0; i < n.length; i++) {
                var d = n[i]
                if (!d.audio || d.isStream || d.isSink !== wantSink) continue
                var nm = String(d.name || "")
                if (!wantSink && nm.indexOf(".monitor") >= 0) continue
                if (root.deadNodes[nm]) continue
                var isDef = def && def.id === d.id
                if (pass === 0 ? !isDef : isDef) continue   // defaults claim their label first
                var label = root.audioLabel(d)
                if (seen[label]) continue
                seen[label] = true
                out.push(d)
            }
        return out
    }

    // The one place a device's name is decided, so the row, the dedupe and
    // anything else that names a device cannot disagree.
    function audioLabel(d) {
        return d.nickname || d.description || d.name
    }


    function g(c) { return String.fromCodePoint(c) }   // handles MDI glyphs > U+FFFF

    // calendar
    property var today: new Date()
    property int calYear:  today.getFullYear()
    property int calMonth: today.getMonth()
    property int calDate:  today.getDate()
    // the week starts where the locale says (Sunday = 0, as in JS Date)
    readonly property int firstDow: Qt.locale().firstDayOfWeek
    readonly property int firstW: (new Date(calYear, calMonth, 1).getDay() - firstDow + 7) % 7
    readonly property int daysIn: new Date(calYear, calMonth + 1, 0).getDate()
    readonly property var monthNames: ["January","February","March","April","May","June","July","August","September","October","November","December"]
    // calendar events — Agenda picks the source: the Nextcloud account
    // (CalDAV), the optional Google client, or the GOA/EDS pipeline;
    // empty → no dots, no agenda, a gentle hint.
    readonly property var calEvents: Agenda.events
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
                label: keys[k] === t0 ? "Today" : (keys[k] === t0 + 86400000 ? "Tomorrow" : Qt.formatDateTime(dd, "dddd, d MMMM")),
                events: groups[keys[k]].slice(0, 4)
            })
        }
        return out
    }
    // the agenda row: its start in the time column ("All day" for all-day
    // events), and a meta line of "Now", the duration and the place
    function fmtEventStart(e) {
        if (e.allDay) return "All day"
        var d = new Date(e.start)
        return isNaN(d.getTime()) ? "" : Qt.formatTime(d, "hh:mm AP")
    }
    function eventNow(e) {
        if (e.allDay) return false
        var s = new Date(e.start).getTime(), en = new Date(e.end).getTime(), now = Date.now()
        return !isNaN(s) && !isNaN(en) && s <= now && now < en
    }
    function fmtDuration(mins) {
        if (mins < 60) return mins + " min"
        var h = Math.floor(mins / 60), m = mins % 60
        return h + " h" + (m > 0 ? " " + m + " min" : "")
    }
    function eventMeta(e) {
        var parts = []
        if (root.eventNow(e)) parts.push("Now")
        if (!e.allDay) {
            var s = new Date(e.start).getTime(), en = new Date(e.end).getTime()
            if (!isNaN(s) && !isNaN(en) && en > s) parts.push(root.fmtDuration(Math.round((en - s) / 60000)))
        }
        if (e.location) parts.push(e.location)
        return parts.join(" · ")
    }

    // which section is expanded: "" | "audio" | "wifi" | "bt" | "vpn" | "ssh" | "mobile" | "mail"
    // ── tabs (the 2026-09 revamp): home is the toggle grid, every list
    //    lives on its own tab; `expanded` survives as a read-only alias so
    //    the section visibles below keep working unchanged ──
    property string tab: "home"
    readonly property string expanded: tab === "home" ? "" : tab
    function setTab(t) {
        if (t !== "bt" && Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = false
        root.tab = t
        if (t === "wifi") { wifiScan.running = true; wifiSavedScan.running = true }
        if (t === "bt" && Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = true
        if (t === "vpn") vpnScan.running = true
        if (t === "ssh") sshScan.running = true
        if (t === "mobile") { root.mobileView = "notifs"; KdeConnect.refresh() }
        if (t === "mail" && Mail.available) Mail.fetch()
        if (t === "cast") Globals.castCommand("scan", "")
    }

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
    property bool pwShow: false        // reveal the Wi-Fi password while typing
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
        wifiState.running = true; wiredState.running = true; brightnessProc.running = true; volumeProc.running = true; wifiSavedScan.running = true
        sshScan.running = true   // always: the SSH tile's sub-label needs the host count
        vpnScan.running = true   // always: the VPN card only exists when profiles do
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
        Globals.focusAppWindow([n.desktopEntry, n.appName])
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
    // Bluetooth: pair → trust → connect. A device that "connected for a second
    // and dropped" was paired but never TRUSTED — bluez accepts one connection
    // from an untrusted device and refuses the reconnect that follows — so
    // trust is set on every tap, and an unpaired device is paired first (the
    // Connections below then connects it once pairing lands). Pairing goes
    // through BtAgent (the bluez agent bridge), not device.pair(): that is
    // what answers "confirm 123456?" / "type the PIN" for phones, keyboards
    // and modern headsets, and it reports WHY a pairing failed — Quickshell's
    // own pair() swallows the error and the tap looked like it did nothing.
    // the first connected device, for the Bluetooth tile's status
    function btConnectedName() {
        var d = Bluetooth.devices ? Bluetooth.devices.values : []
        for (var i = 0; i < d.length; i++) if (d[i].connected) return d[i].name || d[i].deviceName || ""
        return ""
    }
    function btTap(d) {
        BtAgent.clearError()
        if (d.connected) { d.disconnect(); return }
        if (BtAgent.pairingAddress === d.address) { BtAgent.cancelPairing(d.address); return }
        d.trusted = true
        if (!d.paired) { BtAgent.pair(d.address); return }
        if (!BtAgent.connectDevice(d.address)) d.connect()   // no bridge: Quickshell connects, silently
    }

    function connectWifi(ssid, sec) {
        // already on this network → nothing to do (clicking the active row
        // used to pop a password box, which read as "why is it asking AGAIN")
        if (root.curSsid() === ssid && root.pwTarget !== ssid) return
        // a saved profile joins without a prompt — NetworkManager has the key.
        // Only a network with NO profile, or a profile whose key lives in a
        // secret agent ewe does not have, needs the password box.
        var saved = root.wifiSaved[ssid] || null
        var needsKey = sec && sec !== "" && (!saved || saved.psk === "agent")
        if (needsKey && root.pwText === "") {
            root.pwTarget = (root.pwTarget === ssid) ? "" : ssid   // toggle the password field
            return
        }
        var cmd
        if (saved && root.pwText === "")
            cmd = ["nmcli", "connection", "up", "id", saved.name]
        else if (saved)
            // a fresh key for an existing profile goes INTO that profile — the
            // old `device wifi connect` path minted a duplicate "SSID 1" each time
            cmd = ["sh", "-c", 'nmcli connection modify "$1" 802-11-wireless-security.psk "$2" 802-11-wireless-security.psk-flags 0 && exec nmcli connection up id "$1"', "_", saved.name, root.pwText]
        else {
            cmd = ["nmcli", "device", "wifi", "connect", ssid]
            if (root.pwText !== "") cmd = cmd.concat(["password", root.pwText])
        }
        // through a tracked Process, not execDetached: joining can take seconds
        // and used to look like nothing was happening until the list refreshed
        root.wifiPending = ssid
        root.wifiConfirm = ""
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
        root.vpnPending = (up ? "connect to " : "disconnect from ") + name
        root.vpnBusyName = name
        vpnUpProc.name = name
        Globals.netBusy = "vpn"
        vpnUpProc.command = ["nmcli", "connection", up ? "up" : "down", name]
        vpnUpProc.running = true
    }
    // ── VPN credentials, inline ──
    // Nothing in ewe is a NetworkManager secret agent, so a profile without
    // stored secrets can only fail with "secrets were required … --ask". The
    // row then opens a credentials form; the secrets are written INTO the
    // profile (password-flags=0 — GNOME's "store for all users", root-only
    // file under /etc/NetworkManager) and the toggle just works from then on.
    // L2TP/IPsec (the corporate kind: server + user + password + PSK) is the
    // case that surfaced this (metal, 2026-09-02); OpenVPN gets the same form.
    property string vpnCredTarget: ""    // profile whose form is open
    property string vpnCredService: ""   // …l2tp | …openvpn | …
    property bool vpnCredNeedsPsk: false
    property string vpnCredUser: ""
    property string vpnCredPass: ""
    property string vpnCredPsk: ""
    property string vpnCredError: ""
    property bool vpnCredShow: false
    function vpnAskCredentials(name) {
        root.vpnCredTarget = name; root.vpnCredError = ""; root.vpnCredPass = ""; root.vpnCredPsk = ""
        root.vpnCredService = ""; root.vpnCredNeedsPsk = false
        vpnInfoProc.command = ["nmcli", "-t", "-g", "vpn.service-type,vpn.data", "connection", "show", name]
        vpnInfoProc.running = true
    }
    function vpnCloseCredentials() { root.vpnCredTarget = ""; root.vpnCredPass = ""; root.vpnCredPsk = ""; root.vpnCredError = "" }
    function nmEsc(v) { return String(v).replace(/,/g, "\\,") }   // nmcli splits dict values on ','
    function vpnSaveCredentials() {
        var name = root.vpnCredTarget
        if (name === "" || root.vpnCredUser === "" || root.vpnCredPass === "") { root.vpnCredError = "Enter a username and a password."; return }
        var l2tp = /l2tp$/.test(root.vpnCredService), ovpn = /openvpn$/.test(root.vpnCredService)
        var args = ["nmcli", "connection", "modify", name, "vpn.user-name", root.vpnCredUser, "+vpn.data", "password-flags=0"]
        if (l2tp) args.push("+vpn.data", "user=" + root.nmEsc(root.vpnCredUser))
        if (ovpn) args.push("+vpn.data", "username=" + root.nmEsc(root.vpnCredUser))
        args.push("+vpn.secrets", "password=" + root.nmEsc(root.vpnCredPass))
        if (l2tp && root.vpnCredPsk !== "") {
            args.push("+vpn.data", "ipsec-enabled=yes", "+vpn.data", "ipsec-psk-flags=0")
            args.push("+vpn.secrets", "ipsec-psk=" + root.nmEsc(root.vpnCredPsk))
        }
        root.vpnCredError = ""
        root.vpnBusyName = name; Globals.netBusy = "vpn"
        vpnCredProc.name = name
        vpnCredProc.command = args
        vpnCredProc.running = true
    }
    // logind writes the backlight for us (no udev rule, no setuid helper); fall
    // back to brightnessctl when the bridge is down or the machine has no
    // backlight device logind will accept
    function setBrightness(v) {
        root.brightnessVal = v
        if (Logind.setBrightness(v)) return
        Quickshell.execDetached(["brightnessctl", "set", Math.round(v * 100) + "%"])
    }
    function setVolume(v) { root.volumeVal = v; Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", Math.round(v * 100) + "%"]); volSndTimer.restart() }
    // GNOME-style feedback blip once the slider settles (not per pixel)
    property Timer volSndTimer: Timer { interval: 180; onTriggered: Globals.playSound("audio-volume-change") }
    // persist the event-sounds switch through the one file (debounced)
    property Timer writePrefsPoke: Timer {
        interval: 400
        onTriggered: Quickshell.execDetached(["sh", "-c",
            '"$HOME/.config/quickshell/../../bin/ewe-conf" set --no-hooks desktop.sound.event_sounds ' + (Globals.eventSounds ? "true" : "false")])
    }
    // ── power actions ──
    // All session/power actions go through ~/.config/hypr/scripts/power.sh: one
    // tested, distro-agnostic path per action (logout via loginctl, not the
    // unreliable Lua `hyprctl dispatch exit`). The ones that close apps (Sign
    // out, Restart, Shut down) ask first in a Dialog; reversible ones (Lock,
    // Suspend) run immediately.
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

    Connections { target: Globals; function onQuickSettingsOpenChanged() { if (Globals.quickSettingsOpen) { root.tab = "home"; root.refresh() } } }
    IpcHandler {
        target: "quicksettings"
        function toggle(): void { Globals.quickSettingsOpen = !Globals.quickSettingsOpen }
        function show(): void { Globals.quickSettingsOpen = true }
        function hide(): void { Globals.quickSettingsOpen = false }
        // Power-button press (XF86PowerOff bind in hyprland.lua; logind ignores
        // the key so a stray tap can't hard-poweroff): open the panel with the
        // shutdown confirmation already up.
        function powerdialog(): void { Globals.quickSettingsOpen = true; root.askPower("poweroff", "Shut down this computer?", "Shut down") }
        // jump straight to a tab (also how the test driver screenshots them)
        function tab(name: string): void { Globals.quickSettingsOpen = true; root.setTab(name) }
    }

    // saved Wi-Fi profiles — joining one of these never needs a password.
    // Keyed by the profile's SSID, not its name (scripts/wifi-profiles.sh):
    // a profile need not be named after its network, and names with spaces
    // or colons were easy to mangle. {ssid: {name, psk}} where psk is
    // "stored" (the key is in the profile), "agent" (NetworkManager would
    // ask a secret agent ewe does not have — so we ask the user once and
    // store it) or "none" (open).
    property var wifiSaved: ({})
    readonly property string wifiProfilesScript: Qt.resolvedUrl("scripts/wifi-profiles.sh").toString().replace(/^file:\/\//, "")
    Process {
        id: wifiSavedScan
        command: ["bash", root.wifiProfilesScript]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = {}, ls = this.text.split("\n")
                for (var i = 0; i < ls.length; i++) {
                    var f = ls[i].split("\t")
                    if (f.length >= 3 && f[0] !== "") m[f[0]] = { name: f[1], psk: f[2] }
                }
                root.wifiSaved = m
            }
        }
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
                if (root.wifiConfirm !== "" && root.curSsid() === root.wifiConfirm) {
                    root.wifiConfirm = ""; root.wifiPending = ""; wifiConfirmTimer.stop()
                }
            }
        }
    }
    Process { id: wifiState; command: ["nmcli", "-t", "-f", "WIFI", "radio"]; stdout: StdioCollector { onStreamFinished: root.wifiOn = this.text.trim() === "enabled" } }
    // the (first) ethernet port: its device name and NetworkManager state —
    // connected / connecting / disconnected (cable in, link turned off here) /
    // unavailable (no cable). wiredUp is the old boolean, kept for the tile.
    property string wiredDev: ""
    property string wiredStateStr: ""
    readonly property bool wiredPresent: wiredDev !== ""
    property bool wiredBusy: false
    Process { id: wiredState; command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | awk -F: '$2==\"ethernet\"{print $1\":\"$3; exit}'"]; stdout: StdioCollector { onStreamFinished: { var p = this.text.trim().split(":"); root.wiredDev = p[0] || ""; root.wiredStateStr = p[1] || ""; root.wiredUp = root.wiredStateStr === "connected"; if (!wiredSetProc.running) root.wiredBusy = false } } }
    // the wired switch: `device disconnect` drops the link and stops
    // autoconnect until `device connect` (or a re-plug) — the way to be on
    // Wi-Fi with the cable still in
    Process { id: wiredSetProc; onExited: { wiredState.running = true; wiredRescan.restart() } }
    Timer { id: wiredRescan; interval: 1500; onTriggered: wiredState.running = true }
    function setWired(on) {
        if (!root.wiredPresent || root.wiredStateStr === "unavailable") return
        root.wiredBusy = true
        wiredSetProc.command = ["nmcli", "device", on ? "connect" : "disconnect", root.wiredDev]
        wiredSetProc.running = true
    }
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
    // the network we just joined, until a list read shows it IN-USE
    property string wifiConfirm: ""
    Timer { id: wifiConfirmTimer; interval: 4000; onTriggered: { root.wifiConfirm = ""; root.wifiPending = "" } }
    // NetworkManager events (the bar's `nmcli monitor`) — re-read while the
    // panel is open instead of waiting for the 6 s poll; this is what makes a
    // cable plug, a Wi-Fi join or a VPN coming up show at once
    Connections {
        target: Globals
        function onNetEpochChanged() {
            if (!Globals.quickSettingsOpen) return
            wifiState.running = true; wiredState.running = true
            if (root.expanded === "wifi") wifiScan.running = true
        }
    }
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
        property string name: ""
        stderr: StdioCollector { id: vpnErr }
        onExited: function (exitCode, exitStatus) {
            root.vpnBusyName = ""
            Globals.netBusy = ""
            vpnRescan.restart()
            if (exitCode !== 0) {
                var msg = (vpnErr.text || "").trim()
                // no stored secrets (and no secret agent to ask): open the
                // credentials form on that row instead of only shouting
                if (/secrets|--ask|no agents|agent/i.test(msg)) { root.setTab("vpn"); root.vpnAskCredentials(vpnUpProc.name); return }
                if (root.vpnCredTarget === vpnUpProc.name) { root.vpnCredError = msg !== "" ? msg.split("\n")[0] : ("nmcli exited with code " + exitCode); return }
                var title = "Couldn’t " + root.vpnPending, body = msg !== "" ? msg : ("nmcli exited with code " + exitCode)
                // "The VPN service failed to start" says nothing — the reason
                // is a journal line back; fetch it before shouting
                if (/VPN service failed to start|activation failed/i.test(msg)) {
                    vpnWhyProc.name = vpnUpProc.name; vpnWhyProc.title = title; vpnWhyProc.fallback = body
                    vpnWhyProc.running = false; vpnWhyProc.running = true
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
    Process {
        id: vpnWhyProc
        property string name: ""
        property string title: ""
        property string fallback: ""
        command: ["journalctl", "-u", "NetworkManager", "-n", "150", "-o", "cat", "--since", "-3min", "--no-pager"]
        stdout: StdioCollector {
            onStreamFinished: {
                var why = "", lines = (this.text || "").split("\n")
                for (var i = lines.length - 1; i >= 0; i--) {
                    if (lines[i].indexOf('"' + vpnWhyProc.name + '"') < 0) continue
                    var m = /failed to connect: '([^']+)'/.exec(lines[i])
                    if (m) { why = m[1]; break }
                }
                var body = vpnWhyProc.fallback
                if (why !== "") body = why + (/ipsec/i.test(why) ? " — L2TP/IPsec needs IKEv1: libreswan with ikev1-policy=accept (install.sh sets it up; see the manual's VPN section)" : "")
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "VPN", vpnWhyProc.title, body])
            }
        }
    }
    // what kind of profile is asking: service type decides the fields (L2TP
    // gets a pre-shared key), vpn.data prefills the username
    Process {
        id: vpnInfoProc
        stdout: StdioCollector {
            onStreamFinished: {
                var rows = this.text.split("\n")
                root.vpnCredService = (rows[0] || "").trim()
                var data = rows[1] || "", user = ""
                var m = /(?:^|,)\s*user(?:name)?\s*=\s*([^,]*)/.exec(data)
                if (m) user = m[1].trim()
                root.vpnCredUser = user
                root.vpnCredNeedsPsk = /l2tp$/.test(root.vpnCredService)
            }
        }
    }
    // writes the credentials into the profile, then brings it up
    Process {
        id: vpnCredProc
        property string name: ""
        stderr: StdioCollector { id: vpnCredErr }
        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0) {
                root.vpnBusyName = ""; Globals.netBusy = ""
                var msg = (vpnCredErr.text || "").trim()
                root.vpnCredError = msg !== "" ? msg.split("\n")[0] : ("nmcli exited with code " + exitCode)
                return
            }
            root.vpnCloseCredentials()
            root.toggleVpn(vpnCredProc.name, true)
        }
    }
    // joins a Wi-Fi network; same deal — spinner while running, notify on failure
    Process {
        id: wifiConnProc
        stderr: StdioCollector { id: wifiConnErr }
        onExited: function (exitCode, exitStatus) {
            var failed = root.wifiPending
            Globals.netBusy = ""
            if (exitCode === 0) {
                // nmcli has returned, but the row must not flip from spinner
                // to check until the list SAYS we are on the network — read it
                // now (the old 2.5 s one-shot left a dead gap), and stop
                // waiting after 4 s whatever it says
                root.wifiConfirm = failed
                wifiScan.running = true; wifiSavedScan.running = true; wiredState.running = true
                wifiConfirmTimer.restart()
                rescanTimer.restart()
                return
            }
            root.wifiPending = ""
            rescanTimer.restart()
            if (exitCode !== 0) {
                var msg = (wifiConnErr.text || "").trim()
                // stale/keyless saved profile: offer the password box instead
                // of only shouting — the retry then carries a fresh secret
                if (/secrets|no key|password|802-1x|auth/i.test(msg)) root.pwTarget = failed
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Wi-Fi", "Couldn’t join " + failed, msg !== "" ? msg : ("nmcli exited with code " + exitCode)])
            }
        }
    }
    // gated on the panel, not just no-op'd inside it: this used to wake every 6 s
    // for the whole session only to hit the early return on the first line
    Timer { interval: 6000; running: Globals.quickSettingsOpen; repeat: true; onTriggered: { wifiState.running = true; wiredState.running = true; if (root.expanded === "wifi") wifiScan.running = true; if (root.expanded === "ssh") sshScan.running = true } }

    PanelWindow {
        id: win
        visible: Globals.quickSettingsOpen || win.held
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:control"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        anchors { top: true; bottom: true; left: true; right: true }

        // `held` keeps the window mapped through the close animation; it is set
        // on OPEN so no signal-order race can unmap it early (the close blink —
        // see Overview.qml for the full story)
        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durBase); onTriggered: win.held = false }
        Connections { target: Globals; function onQuickSettingsOpenChanged() {
            if (Globals.quickSettingsOpen) { closeTimer.stop(); win.held = true }
            else { closeTimer.restart(); root.powerOpen = false }
        } }
        MouseArea { anchors.fill: parent; onClicked: Globals.quickSettingsOpen = false }

        Rectangle {
            id: panel
            readonly property int pad: Theme.spaceS + Theme.spaceXs
            readonly property int railW: Theme.controlLg + 2 * Theme.spaceS
            width: Theme.panelMd
            // the layer already sits below the bar's exclusive zone: spaceXs
            // below it, windowGap in from the right edge
            y: Theme.spaceXs
            x: parent.width - width - Theme.windowGap
            // Wrap the content instead of spanning the desktop: the panel is as
            // tall as the open page needs (the rail sets the floor), capped at
            // the card's 80% of the screen, and a page switch animates it.
            readonly property real railNeed: railTop.implicitHeight + railBottom.implicitHeight + 3 * pad
            readonly property real wantH: pad + hdrItem.height + pad + inner.implicitHeight + pad + foot.height + pad
            readonly property real maxH: Math.min((win.screen ? win.screen.height : parent.height) * 0.8,
                                                  parent.height - Theme.spaceXs - Theme.windowGap)
            height: Math.min(maxH, Math.max(wantH, railNeed))
            Behavior on height { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            radius: Theme.radiusRounded
            color: Theme.surfaceRaised
            border.color: Theme.borderSubtle
            border.width: Theme.borderWidth1
            clip: true
            layer.enabled: true
            layer.effect: Elevation {}
            // fade plus a slideOffset drop from the bar — in at durBase, out
            // at durFast, no overshoot
            opacity: Globals.quickSettingsOpen ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: Globals.quickSettingsOpen ? Theme.durBase : Theme.durFast; easing.type: Theme.ease }
            }
            transform: Translate {
                y: (Globals.quickSettingsOpen || Theme.reduceMotion) ? 0 : -Theme.slideOffset
                Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            }
            MouseArea { anchors.fill: parent }

            // catches Esc: the power menu first, then a confirmation, then the
            // panel (Quick settings is otherwise mouse-driven)
            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: {
                    if (root.confirmAction !== "") root.confirmAction = ""
                    else if (root.powerOpen) root.powerOpen = false
                    else Globals.quickSettingsOpen = false
                }
            }
            Connections {
                target: Globals
                function onQuickSettingsOpenChanged() { if (Globals.quickSettingsOpen) keyCatcher.forceActiveFocus() }
            }

            // ══ shared pieces ═══════════════════════════════════════════════

            // text in the system's type styles
            component TBody: Text {
                color: Theme.textPrimary
                font.family: Theme.type.body.family
                font.pixelSize: Theme.type.body.size
                font.weight: Theme.type.body.weight
                elide: Text.ElideRight
            }
            component TStrong: Text {
                color: Theme.textPrimary
                font.family: Theme.type.bodyStrong.family
                font.pixelSize: Theme.type.bodyStrong.size
                font.weight: Theme.type.bodyStrong.weight
                elide: Text.ElideRight
            }
            component TCaption: Text {
                color: Theme.textMuted
                font.family: Theme.type.caption.family
                font.pixelSize: Theme.type.caption.size
                font.weight: Theme.type.caption.weight
                elide: Text.ElideRight
            }
            component TMono: Text {
                color: Theme.textSecondary
                font.family: Theme.type.monoNumeric.family
                font.pixelSize: Theme.type.monoNumeric.size
                font.weight: Theme.type.monoNumeric.weight
                font.features: ({ "tnum": 1 })
            }
            component Glyph: Text {
                font.family: Theme.fontIcons
                font.pixelSize: Theme.iconMd
                color: Theme.textSecondary
            }
            // a hint, a note or an error under a list: caption, wrapping
            component Note: Text {
                property string tone: ""            // "" (muted) · danger · warning
                width: parent ? parent.width : Theme.panelSm
                wrapMode: Text.Wrap
                color: tone === "danger" ? Theme.danger : tone === "warning" ? Theme.warning : Theme.textMuted
                font.family: Theme.type.caption.family
                font.pixelSize: Theme.type.caption.size
            }

            // Button (design system: Button) — sm in the panel's dense rows,
            // md in dialogs; primary · secondary · ghost · danger
            component QsBtn: Rectangle {
                id: qb
                property string label: ""
                property string ic: ""
                property string variant: "secondary"
                property string size: "sm"
                property bool disabled: false
                property bool busy: false
                signal go()
                readonly property bool _sm: qb.size === "sm"
                readonly property color _ink: qb.disabled ? Theme.textDisabled
                                            : qb.variant === "primary" ? Theme.onAccent
                                            : qb.variant === "danger" ? Theme.onStatus : Theme.textPrimary
                width: qbRow.implicitWidth + 2 * (qb._sm ? Theme.spaceS : Theme.spaceS + Theme.spaceXs)
                height: qb._sm ? Theme.controlSm : Theme.controlMd
                radius: Theme.radiusPrimary
                color: qb.disabled ? (qb.variant === "ghost" ? "transparent" : Theme.surfaceRaised)
                     : qb.variant === "primary" ? (qbMa.pressed ? Theme.accentPressed : qbMa.containsMouse ? Theme.accentHover : Theme.accent)
                     : qb.variant === "danger" ? (qbMa.pressed ? Qt.tint(Theme.danger, Theme.withAlpha(Theme.textPrimary, 0.24))
                                                : qbMa.containsMouse ? Qt.tint(Theme.danger, Theme.withAlpha(Theme.textPrimary, 0.12)) : Theme.danger)
                     : qb.variant === "secondary" ? (qbMa.pressed ? Theme.surfacePressed : qbMa.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised)
                     : (qbMa.pressed ? Theme.surfacePressed : qbMa.containsMouse ? Theme.surfaceHover : "transparent")
                border.color: qb.disabled ? (qb.variant === "ghost" ? "transparent" : Theme.borderSubtle)
                            : qb.variant === "secondary" ? Theme.borderStrong : "transparent"
                border.width: Theme.borderWidth1
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                Row {
                    id: qbRow
                    anchors.centerIn: parent
                    spacing: Theme.spaceXs
                    Spinner {
                        visible: qb.busy; anchors.verticalCenter: parent.verticalCenter
                        size: qb._sm ? Theme.iconSm : Theme.iconMd
                        tone: qb.variant === "primary" ? "on-accent" : "neutral"
                    }
                    Glyph {
                        visible: qb.ic !== "" && !qb.busy; anchors.verticalCenter: parent.verticalCenter
                        text: qb.ic; color: qb._ink
                        font.pixelSize: qb._sm ? Theme.iconSm : Theme.iconMd
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qb.label; color: qb._ink
                        font.family: Theme.type.label.family
                        font.pixelSize: qb._sm ? Theme.type.label.size : Theme.type.body.size
                        font.weight: Theme.fontWeightMedium
                    }
                }
                MouseArea { id: qbMa; anchors.fill: parent; hoverEnabled: true; enabled: !qb.disabled && !qb.busy; cursorShape: Qt.PointingHandCursor; onClicked: qb.go() }
            }

            // Icon button (design system: Icon button), ghost: textSecondary,
            // hover surfaceHover with a textPrimary glyph, selected accentSubtle
            // with an accentText glyph. `square` draws the stop mark.
            component IconBtn: Rectangle {
                id: ib
                property string ic: ""
                property bool selected: false
                property bool danger: false          // the glyph turns danger on hover
                property bool square: false
                property string size: "sm"           // sm · md
                property color glyph: Theme.textSecondary
                readonly property alias hovered: ibMa.containsMouse
                signal go()
                width: ib.size === "sm" ? Theme.controlSm : Theme.controlMd
                height: width
                radius: Theme.radiusPrimary
                color: ib.selected ? Theme.accentSubtle
                     : ibMa.pressed ? Theme.surfacePressed
                     : ibMa.containsMouse ? Theme.surfaceHover : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                readonly property color _ink: ib.selected ? Theme.accentText
                                            : ibMa.containsMouse ? (ib.danger ? Theme.danger : Theme.textPrimary) : ib.glyph
                Glyph {
                    visible: !ib.square
                    anchors.centerIn: parent; text: ib.ic; color: ib._ink
                    font.pixelSize: ib.size === "sm" ? Theme.iconSm : Theme.iconMd
                }
                Rectangle {
                    visible: ib.square
                    anchors.centerIn: parent
                    width: Theme.spaceS; height: Theme.spaceS
                    radius: Theme.radiusSlight / 2
                    color: ib._ink
                }
                MouseArea { id: ibMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.go() }
            }

            // Text field box (design system: Text field, md): surfaceSunken
            // behind a borderStrong outline that turns textMuted on hover,
            // focusRing with focus and danger on an error. The TextInput is
            // the child, so its id stays reachable from the page.
            component Field: Rectangle {
                id: fd
                property bool focused: false
                property bool error: false
                width: parent ? parent.width : Theme.panelSm
                height: Theme.controlMd
                radius: Theme.radiusPrimary
                color: Theme.surfaceSunken
                border.color: fd.error ? Theme.danger : fd.focused ? Theme.focusRing
                            : fdHover.hovered ? Theme.textMuted : Theme.borderStrong
                border.width: Theme.fieldBorderWidth
                HoverHandler { id: fdHover }
            }
            component FieldInput: TextInput {
                id: fi
                property string placeholder: ""
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.textPrimary
                selectionColor: Theme.accentSubtle
                selectedTextColor: Theme.textPrimary
                font.family: Theme.type.body.family
                font.pixelSize: Theme.type.body.size
                clip: true
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: fi.text.length === 0
                    text: fi.placeholder
                    color: Theme.textMuted
                    font: fi.font
                }
            }

            // Segmented control (md, full width): a surfaceSunken well, the
            // chosen segment surfaceSelected
            component Segmented: Rectangle {
                id: seg
                property var options: []            // [{ label, value, disabled }]
                property var value
                signal picked(var v)
                width: parent ? parent.width : Theme.panelSm
                height: Theme.controlMd
                radius: Theme.radiusPrimary
                color: Theme.surfaceSunken
                border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                Row {
                    id: segRow
                    anchors.fill: parent
                    anchors.margins: Theme.spaceXxs + seg.border.width
                    spacing: Theme.spaceXxs
                    Repeater {
                        model: seg.options
                        delegate: Rectangle {
                            id: sgItem
                            required property var modelData
                            readonly property bool sel: String(modelData.value) === String(seg.value)
                            readonly property bool dis: !!modelData.disabled
                            width: (segRow.width - (seg.options.length - 1) * segRow.spacing) / Math.max(1, seg.options.length)
                            height: segRow.height
                            radius: Theme.radiusSecondary
                            color: sgItem.sel ? Theme.surfaceSelected : "transparent"
                            border.color: sgItem.sel ? Theme.borderSubtle : "transparent"
                            border.width: Theme.borderWidth1
                            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                            Text {
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, parent.width - 2 * Theme.spaceXs)
                                text: sgItem.modelData.label
                                elide: Text.ElideRight
                                color: sgItem.dis ? Theme.textDisabled : (sgItem.sel || sgMa.containsMouse) ? Theme.textPrimary : Theme.textSecondary
                                font.family: Theme.type.label.family
                                font.pixelSize: Theme.type.label.size
                                font.weight: Theme.type.label.weight
                            }
                            MouseArea { id: sgMa; anchors.fill: parent; hoverEnabled: true; enabled: !sgItem.dis; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(sgItem.modelData.value) }
                        }
                    }
                }
            }

            // a settings row: glyph, label and description on the left, the
            // Switch on the right; clicking anywhere on the row toggles
            component SwitchRow: Item {
                id: sr
                property string ic: ""
                property string label: ""
                property string desc: ""
                property bool on: false
                property bool disabled: false
                property bool busy: false
                signal toggled()
                width: parent ? parent.width : Theme.panelSm
                height: Math.max(Theme.controlLg, srText.implicitHeight + 2 * Theme.spaceXs)
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSecondary
                    color: (srMa.containsMouse && !sr.disabled) ? Theme.surfaceHover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                }
                MouseArea { id: srMa; anchors.fill: parent; hoverEnabled: true; enabled: !sr.disabled; cursorShape: Qt.PointingHandCursor; onClicked: sr.toggled() }
                Glyph {
                    id: srIc
                    visible: sr.ic !== ""
                    width: visible ? Theme.iconMd : 0
                    anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                    anchors.verticalCenter: parent.verticalCenter
                    text: sr.ic
                    color: sr.disabled ? Theme.textDisabled : sr.on ? Theme.accentText : Theme.textSecondary
                }
                Column {
                    id: srText
                    anchors.left: srIc.right; anchors.leftMargin: sr.ic !== "" ? Theme.spaceS + Theme.spaceXs : Theme.spaceS
                    anchors.right: srSw.left; anchors.rightMargin: Theme.spaceS
                    anchors.verticalCenter: parent.verticalCenter
                    TBody { width: parent.width; text: sr.label; color: sr.disabled ? Theme.textDisabled : Theme.textPrimary }
                    Row {
                        visible: sr.desc !== "" || sr.busy
                        spacing: Theme.spaceXs
                        Spinner { visible: sr.busy; anchors.verticalCenter: parent.verticalCenter; size: Theme.iconSm }
                        TCaption { width: Math.min(implicitWidth, srText.width - (sr.busy ? Theme.iconSm + Theme.spaceXs : 0)); text: sr.desc }
                    }
                }
                Toggle {
                    id: srSw
                    anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                    anchors.verticalCenter: parent.verticalCenter
                    on: sr.on; disabled: sr.disabled
                    onToggled: sr.toggled()
                }
            }

            // a detail page's head: back, the feature's name (and a quiet
            // status), extra actions, and the feature's Switch
            component PageHead: Item {
                id: ph
                property string title: ""
                property string note: ""
                property bool busy: false
                property bool hasSwitch: false
                property bool on: false
                property bool switchDisabled: false
                default property alias actions: phAct.data
                signal toggled()
                width: parent ? parent.width : Theme.panelSm
                height: Theme.controlLg
                IconBtn {
                    id: phBack
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    size: "md"; ic: Theme.icBack
                    onGo: root.setTab("home")
                }
                Row {
                    anchors.left: phBack.right; anchors.leftMargin: Theme.spaceS
                    anchors.right: phAct.left; anchors.rightMargin: Theme.spaceS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spaceS
                    TStrong { id: phTitle; anchors.verticalCenter: parent.verticalCenter; text: ph.title; width: Math.min(implicitWidth, parent.width) }
                    Spinner { visible: ph.busy; anchors.verticalCenter: parent.verticalCenter; size: Theme.iconSm }
                    TCaption {
                        visible: ph.note !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - phTitle.width - (ph.busy ? Theme.iconSm + Theme.spaceS : 0) - Theme.spaceS)
                        text: ph.note
                    }
                }
                Row {
                    id: phAct
                    anchors.right: phSw.visible ? phSw.left : parent.right
                    anchors.rightMargin: phSw.visible ? Theme.spaceS : 0
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spaceXxs
                }
                Toggle {
                    id: phSw
                    visible: ph.hasSwitch
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    on: ph.on; disabled: ph.switchDisabled
                    onToggled: ph.toggled()
                }
            }

            // Empty state, compact: a controlLg circle, a body-strong title,
            // a description, an optional action
            component Empty: Column {
                id: em
                property string ic: ""
                property string title: ""
                property string desc: ""
                default property alias actions: emAct.data
                width: parent ? parent.width : Theme.panelSm
                spacing: Theme.spaceXs
                topPadding: Theme.spaceMd; bottomPadding: Theme.spaceMd
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.controlLg; height: Theme.controlLg
                    radius: Theme.radiusFull
                    color: Theme.surfaceHover
                    Glyph { anchors.centerIn: parent; text: em.ic }
                }
                TStrong {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: em.title
                    font.weight: Theme.fontWeightSemibold
                }
                Text {
                    visible: em.desc !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, Theme.panelSm - Theme.spaceXl - Theme.spaceMd)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: em.desc
                    color: Theme.textSecondary
                    font.family: Theme.type.body.family
                    font.pixelSize: Theme.type.body.size
                }
                Row {
                    id: emAct
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: children.length > 0 ? Theme.spaceXs : 0
                    spacing: Theme.spaceS
                }
            }

            // a two-line message row (a phone conversation, a mail): an unread
            // dot, the sender, a line of preview and the time
            component MsgRow: Item {
                id: mr
                property string title: ""
                property string line: ""
                property string time: ""
                property bool unread: false
                signal clicked()
                width: parent ? parent.width : Theme.panelSm
                height: Math.max(Theme.controlXl, mrCol.implicitHeight + 2 * Theme.spaceXs)
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSecondary
                    color: mrMa.pressed ? Theme.surfacePressed : mrMa.containsMouse ? Theme.surfaceHover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                }
                MouseArea { id: mrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mr.clicked() }
                Badge {
                    visible: mr.unread; dot: true
                    anchors.left: parent.left; anchors.leftMargin: Theme.spaceXs
                    anchors.verticalCenter: parent.verticalCenter
                }
                Column {
                    id: mrCol
                    anchors.left: parent.left; anchors.leftMargin: Theme.spaceMd
                    anchors.right: mrTime.left; anchors.rightMargin: Theme.spaceS
                    anchors.verticalCenter: parent.verticalCenter
                    TBody { width: parent.width; text: mr.title; font.weight: mr.unread ? Theme.fontWeightSemibold : Theme.fontWeightMedium }
                    TCaption { width: parent.width; text: mr.line; color: mr.unread ? Theme.textSecondary : Theme.textMuted }
                }
                TCaption {
                    id: mrTime
                    anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                    anchors.top: parent.top; anchors.topMargin: Theme.spaceXs + Theme.spaceXxs
                    text: mr.time
                }
            }

            // ── one rail item (Side navigation, collapsed) ──
            component RailBtn: Rectangle {
                id: rb
                property string ic: ""
                property bool current: false
                property bool danger: false            // the glyph is the warning, never a slab
                property bool dot: false               // pending notifications
                signal go()
                width: Theme.controlLg; height: Theme.controlMd
                radius: Theme.radiusSecondary
                color: rb.current ? Theme.accentSubtle
                     : rbMa.pressed ? Theme.surfacePressed
                     : rbMa.containsMouse ? Theme.surfaceHover : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                Glyph {
                    anchors.centerIn: parent; text: rb.ic
                    color: rb.danger ? Theme.danger
                         : rb.current ? Theme.accentText
                         : rbMa.containsMouse ? Theme.textPrimary : Theme.textSecondary
                }
                Badge {
                    visible: rb.dot && !rb.current; dot: true
                    anchors.top: parent.top; anchors.right: parent.right
                    anchors.topMargin: Theme.spaceXxs; anchors.rightMargin: Theme.spaceXs
                }
                MouseArea { id: rbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.go() }
            }

            // ══ the icon rail: pages down the left edge, Settings and Power
            //    pinned at its foot. VPN, SSH and Mail obey the same "only what
            //    exists" rule as their home tiles. ══
            Rectangle {
                id: rail
                // inset by the panel's own outline, so the rail never paints
                // over it, with the concentric corner
                readonly property int inset: panel.border.width
                width: panel.railW - inset
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                anchors.leftMargin: inset; anchors.topMargin: inset; anchors.bottomMargin: inset
                topLeftRadius: Theme.rIn(Theme.radiusRounded, inset)
                bottomLeftRadius: Theme.rIn(Theme.radiusRounded, inset)
                color: Theme.surfaceBase
                Rectangle { anchors.right: parent.right; width: Theme.borderWidth1; height: parent.height; color: Theme.borderSubtle }

                Column {
                    id: railTop
                    anchors.top: parent.top; anchors.topMargin: panel.pad
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spaceXxs
                    // the flock mark — the ewe, tinted to the accent
                    Item {
                        width: Theme.iconXl; height: Theme.iconXl
                        anchors.horizontalCenter: parent.horizontalCenter
                        Image {
                            id: sheepMark
                            anchors.fill: parent
                            source: Qt.resolvedUrl("assets/sheep.svg")
                            sourceSize.width: 2 * Theme.iconXl; sourceSize.height: 2 * Theme.iconXl
                            visible: false
                        }
                        MultiEffect {
                            anchors.fill: sheepMark
                            source: sheepMark
                            colorization: 1
                            colorizationColor: Theme.accent
                        }
                    }
                    Item { width: Theme.spaceS; height: Theme.spaceS }
                    Repeater {
                        model: [
                            { key: "home",   icon: Theme.icApps },
                            { key: "wifi",   icon: Theme.icWifi },
                            { key: "bt",     icon: Theme.icBluetooth },
                            { key: "audio",  icon: Theme.icVolHigh },
                            { key: "vpn",    icon: Theme.icVpn },
                            { key: "ssh",    icon: Theme.icSsh },
                            { key: "cast",   icon: Theme.icCast },
                            { key: "mobile", icon: Theme.icPhone },
                            { key: "mail",   icon: Theme.icMail },
                            { key: "cal",    icon: Theme.icCalendar },
                            { key: "notifs", icon: Theme.icBell }
                        ]
                        delegate: RailBtn {
                            required property var modelData
                            visible: modelData.key === "mail" ? Mail.available
                                   : modelData.key === "vpn"  ? (root.vpnList.length > 0 || Globals.vpnActive)
                                   : modelData.key === "ssh"  ? (root.sshList.length > 0 || Globals.sshTunnelUp)
                                   : true
                            ic: modelData.icon
                            current: root.tab === modelData.key
                            dot: modelData.key === "notifs" && Globals.server && Globals.server.trackedNotifications.values.length > 0
                            onGo: root.setTab(modelData.key)
                        }
                    }
                }
                Column {
                    id: railBottom
                    anchors.bottom: parent.bottom; anchors.bottomMargin: panel.pad
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spaceXxs
                    RailBtn { ic: Theme.icCog; onGo: { Globals.quickSettingsOpen = false; Globals.openSettings() } }
                    RailBtn { ic: Theme.icPower; danger: true; current: root.powerOpen; onGo: root.powerOpen = !root.powerOpen }
                }
            }

            // ══ header: the date, and the battery on the right ══
            Item {
                id: hdrItem
                anchors.top: parent.top; anchors.left: rail.right; anchors.right: parent.right
                anchors.topMargin: panel.pad; anchors.leftMargin: panel.pad; anchors.rightMargin: panel.pad
                height: Theme.controlMd
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    anchors.right: batt.left; anchors.rightMargin: Theme.spaceS
                    // the Writing guide's heading date: "Thursday, 17 September"
                    text: Qt.formatDateTime(root.today, "dddd, d MMMM")
                    elide: Text.ElideRight
                    color: Theme.textPrimary
                    font.family: Theme.type.h4.family
                    font.pixelSize: Theme.type.h4.size
                    font.weight: Theme.type.h4.weight
                }
                Row {
                    id: batt
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spaceXs
                    visible: UPower.displayDevice && UPower.displayDevice.isLaptopBattery
                    property var dev: UPower.displayDevice
                    property real pct: dev ? (dev.percentage <= 1 ? dev.percentage * 100 : dev.percentage) : 0
                    property bool charging: dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged)
                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.charging ? Theme.icBolt : (parent.pct >= 60 ? Theme.icBattFull : parent.pct >= 30 ? Theme.icBatt50 : Theme.icBattEmpty)
                        color: parent.charging ? Theme.success : (parent.pct <= 15 ? Theme.danger : Theme.textSecondary)
                    }
                    TMono { anchors.verticalCenter: parent.verticalCenter; text: Math.round(parent.pct) + "%" }
                }
            }

            // ══ foot: volume and brightness, always under a divider ══
            Column {
                id: foot
                anchors.left: rail.right; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.leftMargin: panel.pad; anchors.rightMargin: panel.pad; anchors.bottomMargin: panel.pad
                spacing: Theme.spaceS
                Rectangle { width: parent.width; height: Theme.borderWidth1; color: Theme.borderSubtle }
                Slider {
                    width: parent.width
                    live: true
                    icon: root.volumeVal <= 0 ? Theme.icVolMute : root.volumeVal < 0.5 ? Theme.icVolLow : Theme.icVolHigh
                    showValue: true
                    valueText: Math.round(root.volumeVal * 100) + "%"
                    value: root.volumeVal
                    onMoved: function (v) { root.setVolume(v) }
                }
                Slider {
                    width: parent.width
                    live: true
                    icon: Theme.icSun
                    showValue: true
                    valueText: Math.round(root.brightnessVal * 100) + "%"
                    value: root.brightnessVal
                    onMoved: function (v) { root.setBrightness(v) }
                }
            }

            Flickable {
                id: flick
                anchors.top: hdrItem.bottom; anchors.topMargin: panel.pad
                anchors.left: rail.right; anchors.leftMargin: panel.pad
                anchors.right: parent.right; anchors.rightMargin: panel.pad
                anchors.bottom: foot.top; anchors.bottomMargin: panel.pad
                contentHeight: inner.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: inner
                    width: flick.width
                    spacing: panel.pad

                    // ═══ HOME: the tile grid — a tile's body toggles, its
                    //     details zone opens the matching page ═══
                    Row {
                        visible: root.tab === "home"
                        width: parent.width; spacing: Theme.spaceS
                        Tile {
                            // adapts to the live link: the wired glyph and "Wired"
                            // when a cable is the active connection and Wi-Fi isn't (e.g. VMs)
                            readonly property bool onWired: root.wiredUp && root.curSsid() === ""
                            ic: onWired ? Theme.icEthernet : Theme.icWifi
                            label: root.wiredUp ? "Network" : "Wi-Fi"
                            active: root.wifiOn || onWired               // on = the radio or the link is up
                            opened: root.expanded === "wifi"
                            hasMenu: true
                            busy: (root.expanded === "wifi" && wifiScan.running) || root.wifiPending !== ""
                            // joining: say so, and where to. Both links up: say both —
                            // the cable used to vanish behind the SSID
                            sub: root.wifiPending !== "" ? "Joining " + root.wifiPending + "…"
                               : root.curSsid() !== "" ? (root.wiredUp ? root.curSsid() + " · Wired" : root.curSsid())
                               : (onWired ? "Wired" : (root.wifiOn ? "On" : "Off"))
                            // body = the switch (no list needed to turn Wi-Fi off);
                            // details = the network list
                            onClicked: { Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiOn ? "off" : "on"]); rescanTimer.restart() }
                            onMenu: root.setTab("wifi")
                        }
                        Tile {
                            ic: Theme.icBluetooth; label: "Bluetooth"
                            active: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false
                            disabled: !Bluetooth.defaultAdapter
                            opened: root.expanded === "bt"
                            hasMenu: true
                            busy: root.expanded === "bt" && Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering
                            sub: !Bluetooth.defaultAdapter ? "No adapter"
                               : !Bluetooth.defaultAdapter.enabled ? "Off"
                               : (root.btConnectedName() !== "" ? root.btConnectedName() : "On")
                            onClicked: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                            onMenu: root.setTab("bt")
                        }
                    }
                    Row {
                        // (the tiles' own conditions — a child's `visible` reads false while
                        // this row is hidden, so it cannot decide the row)
                        visible: root.tab === "home" && (root.vpnList.length > 0 || Globals.vpnActive || root.sshList.length > 0 || Globals.sshTunnelUp)
                        width: parent.width; spacing: Theme.spaceS
                        Tile {
                            id: vpnTile
                            // home shows only what exists: no VPN profiles and
                            // nothing active → no tile
                            visible: root.vpnList.length > 0 || Globals.vpnActive
                            ic: Theme.icVpn; label: "VPN"
                            active: Globals.vpnActive
                            opened: root.expanded === "vpn"
                            hasMenu: true
                            busy: root.vpnBusyName !== ""
                            sub: root.vpnBusyName !== "" ? "Connecting…" : (Globals.vpnActive ? "On" : "Off")
                            function openList() { root.setTab("vpn") }
                            // body: GNOME semantics — disconnect the active VPN /
                            // reconnect the single configured one; only when the
                            // choice is ambiguous does the body open the list
                            onClicked: {
                                var act = null
                                for (var i = 0; i < root.vpnList.length; i++) if (root.vpnList[i].active) { act = root.vpnList[i]; break }
                                if (act) root.toggleVpn(act.name, false)
                                else if (root.vpnList.length === 1) root.toggleVpn(root.vpnList[0].name, true)
                                else vpnTile.openList()
                            }
                            onMenu: vpnTile.openList()
                        }
                        Tile {
                            id: sshTile
                            visible: root.sshList.length > 0 || Globals.sshTunnelUp
                            ic: Theme.icSsh; label: "SSH"
                            active: Globals.sshTunnelUp
                            opened: root.expanded === "ssh"
                            hasMenu: true
                            sub: Globals.sshTunnelUp ? "Tunnel on"
                               : root.sshList.length > 0 ? root.sshList.length + (root.sshList.length === 1 ? " host" : " hosts")
                               : "Not set up"
                            // hosts are a list, not a switch — body and details both open
                            onClicked: root.setTab("ssh")
                            onMenu: root.setTab("ssh")
                        }
                    }
                    Row {
                        visible: root.tab === "home"
                        width: parent.width; spacing: Theme.spaceS
                        Tile {
                            ic: Theme.icDnd; label: "Do not disturb"; active: Globals.dnd
                            sub: Globals.dnd ? "On" : "Off"
                            onClicked: Globals.dnd = !Globals.dnd
                        }
                        Tile {
                            // eye open while awake, eye-off while the idle inhibitor is off
                            ic: (Globals.caffeine ? Theme.icEye : Theme.icEyeOff); label: "Keep awake"; active: Globals.caffeine
                            sub: Globals.caffeine ? "On" : "Off"
                            onClicked: Globals.caffeine = !Globals.caffeine
                        }
                    }
                    // an active cast earns a home tile; clicking it hangs up and
                    // the tile leaves with the session
                    Row {
                        visible: root.tab === "home" && Globals.casting
                        width: parent.width; spacing: Theme.spaceS
                        Tile {
                            ic: Theme.icCast; label: "Cast"; active: true
                            busy: Globals.castState !== "streaming"
                            sub: Globals.castState === "streaming" ? Globals.castSinkName : "Connecting…"
                            onClicked: Globals.castCommand("stop", "")
                        }
                    }
                    // system load (CPU + memory; RunCat reads the same CPU value),
                    // on the tiles' surfaceOverlay
                    Rectangle {
                        visible: root.tab === "home"
                        width: parent.width; height: sysCol.implicitHeight + 2 * panel.pad
                        radius: Theme.radiusRounded
                        color: Theme.surfaceOverlay
                        border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                        Column {
                            id: sysCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: panel.pad
                            spacing: Theme.spaceS + Theme.spaceXs
                            Meter { label: "CPU"; glyph: Theme.icCpu; value: Globals.cpuUsage }
                            Meter { label: "Memory"; glyph: Theme.icMemory; value: Globals.memUsage }
                        }
                    }

                    // ═══ SOUND: output and input devices ═══
                    Column {
                        visible: root.tab === "audio"
                        width: parent.width; spacing: Theme.spaceS
                        PageHead {
                            title: "Sound"
                            note: Pipewire.defaultAudioSink ? root.audioLabel(Pipewire.defaultAudioSink) : ""
                        }
                        // GNOME-style: one switch for every event chime
                        SwitchRow {
                            ic: Theme.icBellRing; label: "Event sounds"
                            on: Globals.eventSounds
                            onToggled: { Globals.eventSounds = !Globals.eventSounds; root.writePrefsPoke.restart(); if (Globals.eventSounds) Globals.playSound("audio-volume-change") }
                        }
                        SectionTitle { text: "Output" }
                        ListWell {
                            flush: true
                            Repeater {
                                model: root.audioNodes(true)
                                delegate: ListRow {
                                    required property var modelData
                                    readonly property bool isDefault: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.id === modelData.id
                                    glyph: Theme.icSpeaker
                                    glyphColor: isDefault ? Theme.accentText : Theme.textSecondary
                                    label: root.audioLabel(modelData)
                                    active: isDefault; check: isDefault
                                    onClicked: { Pipewire.preferredDefaultAudioSink = modelData; volumeProc.running = true }
                                }
                            }
                        }
                        SectionTitle { text: "Input" }
                        ListWell {
                            flush: true
                            Repeater {
                                model: root.audioNodes(false)
                                delegate: ListRow {
                                    required property var modelData
                                    readonly property bool isDefault: Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.id === modelData.id
                                    glyph: Theme.icMic
                                    glyphColor: isDefault ? Theme.accentText : Theme.textSecondary
                                    label: root.audioLabel(modelData)
                                    active: isDefault; check: isDefault
                                    onClicked: Pipewire.preferredDefaultAudioSource = modelData
                                }
                            }
                        }
                    }

                    // ═══ WI-FI (and the wired port) ═══
                    Column {
                        visible: root.expanded === "wifi"
                        width: parent.width; spacing: Theme.spaceS
                        PageHead {
                            title: "Wi-Fi"
                            busy: wifiScan.running
                            hasSwitch: true; on: root.wifiOn
                            onToggled: { Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiOn ? "off" : "on"]); rescanTimer.restart() }
                        }
                        // WIRED — only when the machine has a port. The switch is
                        // the "I'm on Wi-Fi, ignore the cable" control; unplugged,
                        // it just says so.
                        SwitchRow {
                            visible: root.wiredPresent
                            ic: Theme.icEthernet; label: "Wired"
                            desc: root.wiredStateStr === "unavailable" ? "No cable"
                                : root.wiredStateStr === "connecting" || root.wiredBusy ? "Connecting…"
                                : root.wiredUp ? "Connected" : "Off"
                            busy: root.wiredBusy || root.wiredStateStr === "connecting"
                            on: root.wiredUp || root.wiredStateStr === "connecting"
                            disabled: root.wiredStateStr === "unavailable"
                            onToggled: root.setWired(!on)
                        }
                        // a scan with nothing to show yet — say so instead of
                        // sitting there as an empty box that looks broken
                        Row {
                            visible: root.wifiOn && root.wifiList.length === 0
                            spacing: Theme.spaceS
                            leftPadding: Theme.spaceS
                            Spinner { visible: wifiScan.running; anchors.verticalCenter: parent.verticalCenter; size: Theme.iconSm }
                            TCaption { anchors.verticalCenter: parent.verticalCenter; text: wifiScan.running ? "Looking for networks…" : "No networks found" }
                        }
                        Empty {
                            visible: !root.wifiOn
                            ic: Theme.icWifiOff; title: "Wi-Fi is off"
                            desc: "Turn it on to see networks nearby."
                        }
                        ListWell {
                            flush: true
                            visible: root.wifiOn && root.wifiList.length > 0
                            Repeater {
                                model: root.wifiOn ? root.wifiList : []
                                delegate: Column {
                                    id: wRow
                                    required property var modelData
                                    width: parent.width
                                    spacing: Theme.spaceXs
                                    ListRow {
                                        readonly property var saved: root.wifiSaved[wRow.modelData.ssid] || null
                                        glyph: wRow.modelData.signal >= 66 ? Theme.icWifi : (wRow.modelData.signal >= 33 ? Theme.icWifiMed : Theme.icWifiLow)
                                        glyphColor: wRow.modelData.active ? Theme.accentText : Theme.textSecondary
                                        label: wRow.modelData.ssid
                                        desc: root.wifiPending === wRow.modelData.ssid ? "Connecting…"
                                            : wRow.modelData.active ? "Connected"
                                            : saved ? "Saved"
                                            : wRow.modelData.sec === "" ? "Open" : ""
                                        active: wRow.modelData.active
                                        check: wRow.modelData.active && root.wifiPending !== wRow.modelData.ssid
                                        busy: root.wifiPending === wRow.modelData.ssid
                                        onClicked: root.connectWifi(wRow.modelData.ssid, wRow.modelData.sec)
                                        Glyph {
                                            visible: wRow.modelData.sec !== "" && !wRow.modelData.active && root.wifiPending !== wRow.modelData.ssid
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Theme.icLock; font.pixelSize: Theme.iconSm; color: Theme.textMuted
                                        }
                                    }
                                    // the password, right under the network being joined
                                    Row {
                                        visible: root.pwTarget === wRow.modelData.ssid
                                        width: parent.width
                                        spacing: Theme.spaceS
                                        bottomPadding: Theme.spaceXs
                                        Field {
                                            width: parent.width - pwJoin.width - parent.spacing
                                            focused: pwInput.activeFocus
                                            FieldInput {
                                                id: pwInput
                                                anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.controlSm + Theme.spaceXs
                                                placeholder: "Password"
                                                echoMode: root.pwShow ? TextInput.Normal : TextInput.Password
                                                onTextChanged: root.pwText = text
                                                Component.onCompleted: if (root.pwTarget === wRow.modelData.ssid) forceActiveFocus()
                                                onAccepted: root.connectWifi(wRow.modelData.ssid, wRow.modelData.sec)
                                                Keys.onEscapePressed: Globals.quickSettingsOpen = false
                                            }
                                            // show or hide the password while typing
                                            IconBtn {
                                                anchors.right: parent.right; anchors.rightMargin: Theme.spaceXxs
                                                anchors.verticalCenter: parent.verticalCenter
                                                ic: root.pwShow ? Theme.icEyeOff : Theme.icEye
                                                selected: root.pwShow
                                                onGo: root.pwShow = !root.pwShow
                                            }
                                        }
                                        QsBtn {
                                            id: pwJoin
                                            anchors.verticalCenter: parent.verticalCenter
                                            size: "md"; variant: "primary"; label: "Join"
                                            onGo: root.connectWifi(wRow.modelData.ssid, wRow.modelData.sec)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ═══ BLUETOOTH ═══
                    Column {
                        visible: root.expanded === "bt"
                        width: parent.width; spacing: Theme.spaceS
                        PageHead {
                            title: "Bluetooth"
                            busy: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering
                            note: (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering) ? "Searching…" : ""
                            hasSwitch: true
                            on: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false
                            switchDisabled: !Bluetooth.defaultAdapter
                            onToggled: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                        }
                        Empty {
                            visible: !Bluetooth.defaultAdapter
                            ic: Theme.icBluetooth; title: "No Bluetooth adapter"
                            desc: "This computer has no Bluetooth, or it is turned off in the firmware."
                        }
                        ListWell {
                            flush: true
                            visible: btList.shown > 0
                            Repeater {
                                id: btList
                                property int shown: { var c = 0, d = Bluetooth.devices ? Bluetooth.devices.values : []; for (var i = 0; i < d.length; i++) if (d[i].paired || d[i].connected || (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering)) c++; return c }
                                model: Bluetooth.devices ? Bluetooth.devices.values : []
                                delegate: ListRow {
                                    id: bRow
                                    required property var modelData
                                    visible: modelData.paired || modelData.connected || (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering)
                                    readonly property bool working: modelData.pairing || BtAgent.pairingAddress === modelData.address || BtAgent.busyAddress === modelData.address
                                    readonly property string battery: modelData.connected && modelData.batteryAvailable
                                                                      ? Math.round(modelData.battery <= 1 ? modelData.battery * 100 : modelData.battery) + "%" : ""
                                    // the device's kind (bluez's Icon → headphones / keyboard / phone / …)
                                    glyph: BtAgent.glyph(modelData.icon, modelData.connected)
                                    glyphColor: modelData.connected ? Theme.accentText : Theme.textSecondary
                                    label: modelData.name || modelData.deviceName || modelData.address
                                    desc: working ? (modelData.paired ? "Connecting…" : "Pairing…")
                                        : modelData.connected ? (battery !== "" ? "Connected · " + battery : "Connected")
                                        : modelData.paired ? "" : "New device"
                                    active: modelData.connected
                                    check: modelData.connected && !working && !bForget.visible
                                    busy: working
                                    onClicked: root.btTap(modelData)
                                    // forget: a trash button on hover, for anything paired
                                    IconBtn {
                                        id: bForget
                                        visible: (bRow.hovered || bForget.hovered) && bRow.modelData.paired && !bRow.working
                                        anchors.verticalCenter: parent.verticalCenter
                                        ic: Theme.icTrash; danger: true
                                        onGo: { BtAgent.clearError(); bRow.modelData.forget() }
                                    }
                                    // a pairing that just completed connects by itself — the tap that
                                    // started it was the intent, and bluez does not connect on pair
                                    Connections { target: bRow.modelData; function onPairedChanged() { if (bRow.modelData.paired && !bRow.modelData.connected) { bRow.modelData.trusted = true; bRow.modelData.connect() } } }
                                }
                            }
                        }
                        // why the last tap failed ("codes did not match", "not in
                        // pairing mode", …) — from BtAgent; cleared by the next tap
                        Note { visible: BtAgent.lastError !== ""; tone: "danger"; text: BtAgent.lastError }
                        Note {
                            visible: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled && !BtAgent.registered
                            tone: "warning"
                            text: BtAgent.bridgeError !== "" ? BtAgent.bridgeError : "The pairing agent isn’t running yet. Devices that ask for a code can’t pair."
                        }
                    }

                    // ═══ VPN ═══
                    Column {
                        visible: root.expanded === "vpn"
                        width: parent.width; spacing: Theme.spaceS
                        PageHead { title: "VPN"; busy: root.vpnBusyName !== "" }
                        Empty {
                            visible: root.vpnList.length === 0
                            ic: Theme.icVpn; title: "No VPN connections"
                            desc: "Add a VPN connection, and it shows up here."
                        }
                        ListWell {
                            flush: true
                            visible: root.vpnList.length > 0
                            Repeater {
                                model: root.vpnList
                                delegate: Column {
                                    id: vRow
                                    required property var modelData
                                    width: parent.width
                                    spacing: Theme.spaceS
                                    ListRow {
                                        glyph: Theme.icVpn
                                        glyphColor: vRow.modelData.active ? Theme.accentText : Theme.textSecondary
                                        label: vRow.modelData.name
                                        desc: root.vpnBusyName === vRow.modelData.name ? "Connecting…" : vRow.modelData.active ? "Connected" : ""
                                        active: vRow.modelData.active
                                        check: vRow.modelData.active && root.vpnBusyName !== vRow.modelData.name
                                        busy: root.vpnBusyName === vRow.modelData.name
                                        onClicked: (root.vpnCredTarget === vRow.modelData.name) ? root.vpnCloseCredentials() : root.toggleVpn(vRow.modelData.name, !vRow.modelData.active)
                                    }
                                    // the sign-in form: username · password · (L2TP) pre-shared
                                    // key, stored in the profile on Connect, so the toggle works
                                    // from then on
                                    Column {
                                        visible: root.vpnCredTarget === vRow.modelData.name
                                        width: parent.width
                                        spacing: Theme.spaceS
                                        leftPadding: Theme.spaceS; rightPadding: Theme.spaceS; bottomPadding: Theme.spaceS
                                        readonly property real w: width - leftPadding - rightPadding
                                        Note { width: parent.w; text: "Enter your sign-in details once. They’re kept in the connection." }
                                        Field {
                                            width: parent.w
                                            focused: vUser.activeFocus
                                            FieldInput {
                                                id: vUser
                                                anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                                                placeholder: "Username"
                                                text: root.vpnCredUser
                                                onTextChanged: root.vpnCredUser = text
                                                Component.onCompleted: if (root.vpnCredTarget === vRow.modelData.name && text === "") forceActiveFocus()
                                                Keys.onEscapePressed: root.vpnCloseCredentials()
                                            }
                                        }
                                        Field {
                                            width: parent.w
                                            focused: vPass.activeFocus
                                            error: root.vpnCredError !== ""
                                            FieldInput {
                                                id: vPass
                                                anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.controlSm + Theme.spaceXs
                                                placeholder: "Password"
                                                echoMode: root.vpnCredShow ? TextInput.Normal : TextInput.Password
                                                text: root.vpnCredPass
                                                onTextChanged: root.vpnCredPass = text
                                                Component.onCompleted: if (root.vpnCredTarget === vRow.modelData.name && root.vpnCredUser !== "") forceActiveFocus()
                                                onAccepted: root.vpnCredNeedsPsk ? vPsk.forceActiveFocus() : root.vpnSaveCredentials()
                                                Keys.onEscapePressed: root.vpnCloseCredentials()
                                            }
                                            IconBtn {
                                                anchors.right: parent.right; anchors.rightMargin: Theme.spaceXxs
                                                anchors.verticalCenter: parent.verticalCenter
                                                ic: root.vpnCredShow ? Theme.icEyeOff : Theme.icEye
                                                selected: root.vpnCredShow
                                                onGo: root.vpnCredShow = !root.vpnCredShow
                                            }
                                        }
                                        Field {
                                            visible: root.vpnCredNeedsPsk
                                            width: parent.w
                                            focused: vPsk.activeFocus
                                            FieldInput {
                                                id: vPsk
                                                anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                                                placeholder: "Pre-shared key (IPsec), if there is one"
                                                echoMode: root.vpnCredShow ? TextInput.Normal : TextInput.Password
                                                text: root.vpnCredPsk
                                                onTextChanged: root.vpnCredPsk = text
                                                onAccepted: root.vpnSaveCredentials()
                                                Keys.onEscapePressed: root.vpnCloseCredentials()
                                            }
                                        }
                                        Note { visible: root.vpnCredError !== ""; width: parent.w; tone: "danger"; text: root.vpnCredError }
                                        Row {
                                            anchors.right: parent.right; anchors.rightMargin: parent.rightPadding
                                            spacing: Theme.spaceS
                                            QsBtn { size: "md"; variant: "ghost"; label: "Cancel"; onGo: root.vpnCloseCredentials() }
                                            QsBtn {
                                                size: "md"; variant: "primary"
                                                busy: root.vpnBusyName === vRow.modelData.name
                                                disabled: root.vpnBusyName !== "" && root.vpnBusyName !== vRow.modelData.name
                                                label: root.vpnBusyName === vRow.modelData.name ? "Connecting…" : "Connect"
                                                onGo: root.vpnSaveCredentials()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ═══ SSH — hosts from ~/.ssh/config. Row click → a terminal
                    //     ssh'd in; globe → SOCKS tunnel + the host's saved browse
                    //     script (first click opens a paste-once editor); pencil
                    //     edits the script; the stop mark stops a running tunnel. ═══
                    Column {
                        visible: root.expanded === "ssh"
                        width: parent.width; spacing: Theme.spaceS
                        PageHead { title: "SSH"; note: "~/.ssh/config" }
                        Column {
                            visible: root.sshList.length === 0
                            width: parent.width; spacing: Theme.spaceS
                            Empty { ic: Theme.icSsh; title: "No SSH hosts"; desc: "Add a host to ~/.ssh/config, like this:" }
                            Rectangle {
                                width: parent.width; height: sshSample.implicitHeight + 2 * Theme.spaceS
                                radius: Theme.radiusPrimary
                                color: Theme.surfaceSunken
                                border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                                Text {
                                    id: sshSample
                                    anchors.fill: parent; anchors.margins: Theme.spaceS
                                    text: "Host mypc\n    HostName 192.168.1.20\n    User you"
                                    color: Theme.textSecondary
                                    font.family: Theme.type.mono.family
                                    font.pixelSize: Theme.type.mono.size
                                }
                            }
                        }
                        ListWell {
                            flush: true
                            visible: root.sshList.length > 0
                            Repeater {
                                model: root.sshList
                                delegate: Column {
                                    id: sshRow
                                    required property var modelData
                                    width: parent.width
                                    spacing: Theme.spaceXs
                                    ListRow {
                                        glyph: Theme.icSsh
                                        glyphColor: sshRow.modelData.tunnel ? Theme.accentText : Theme.textSecondary
                                        label: sshRow.modelData.host
                                        desc: sshRow.modelData.tunnel ? "Tunnel on" : ""
                                        active: sshRow.modelData.tunnel
                                        // the whole row (under the buttons) → a terminal
                                        onClicked: root.sshTerm(sshRow.modelData.host)
                                        IconBtn {
                                            visible: sshRow.modelData.tunnel
                                            anchors.verticalCenter: parent.verticalCenter
                                            square: true; danger: true
                                            onGo: root.sshStopTunnel(sshRow.modelData.host)
                                        }
                                        IconBtn {
                                            visible: sshRow.modelData.script
                                            anchors.verticalCenter: parent.verticalCenter
                                            ic: Theme.icPencil
                                            selected: root.scriptTarget === sshRow.modelData.host
                                            onGo: root.sshEditScript(sshRow.modelData.host)
                                        }
                                        // globe: run the host's browse script (or open the
                                        // editor if none is saved yet)
                                        IconBtn {
                                            anchors.verticalCenter: parent.verticalCenter
                                            ic: Theme.icWeb
                                            onGo: root.sshBrowse(sshRow.modelData.host, sshRow.modelData.script)
                                        }
                                    }
                                    // the browse-script editor — paste once, kept in
                                    // ~/.config/quickshell/ssh-browse/<host>.sh
                                    Column {
                                        width: parent.width; spacing: Theme.spaceS
                                        bottomPadding: Theme.spaceS
                                        visible: root.scriptTarget === sshRow.modelData.host
                                        onVisibleChanged: if (visible) { seEdit.text = root.scriptText; seEdit.forceActiveFocus() }
                                        Rectangle {
                                            width: parent.width; height: 3 * Theme.control2xl
                                            radius: Theme.radiusPrimary
                                            color: Theme.surfaceSunken
                                            border.color: seEdit.activeFocus ? Theme.focusRing : Theme.borderStrong
                                            border.width: Theme.fieldBorderWidth
                                            Flickable {
                                                id: seFlick
                                                anchors.fill: parent; anchors.margins: Theme.spaceS; clip: true
                                                contentWidth: width; contentHeight: seEdit.implicitHeight
                                                TextEdit {
                                                    id: seEdit
                                                    width: seFlick.width
                                                    textFormat: TextEdit.PlainText; wrapMode: TextEdit.WrapAnywhere
                                                    selectByMouse: true
                                                    color: Theme.textPrimary
                                                    selectionColor: Theme.accentSubtle
                                                    selectedTextColor: Theme.textPrimary
                                                    font.family: Theme.type.mono.family
                                                    font.pixelSize: Theme.type.mono.size
                                                    Keys.onEscapePressed: root.scriptTarget = ""
                                                    // keep the cursor in view while typing or pasting
                                                    onCursorRectangleChanged: {
                                                        if (cursorRectangle.y < seFlick.contentY) seFlick.contentY = cursorRectangle.y
                                                        else if (cursorRectangle.y + cursorRectangle.height > seFlick.contentY + seFlick.height)
                                                            seFlick.contentY = cursorRectangle.y + cursorRectangle.height - seFlick.height
                                                    }
                                                }
                                            }
                                            Note {
                                                visible: seEdit.text.length === 0
                                                anchors.fill: parent; anchors.margins: Theme.spaceS
                                                text: "Paste the shell script to run for “" + sshRow.modelData.host + "”, such as a browser that goes through the tunnel.\n\nIt runs with SSH_HOST and SOCKS_PORT set, once a SOCKS5 tunnel to the host is up on 127.0.0.1:$SOCKS_PORT (1080 by default; needs key or agent sign-in). Saved to ~/.config/quickshell/ssh-browse/."
                                            }
                                        }
                                        Row {
                                            anchors.right: parent.right
                                            spacing: Theme.spaceS
                                            QsBtn {
                                                visible: sshRow.modelData.script
                                                variant: "danger"; label: "Delete script"
                                                onGo: root.sshDeleteScript(sshRow.modelData.host)
                                            }
                                            QsBtn { variant: "ghost"; label: "Cancel"; onGo: root.scriptTarget = "" }
                                            QsBtn {
                                                variant: "primary"; label: "Save and run"
                                                disabled: seEdit.text.trim().length === 0
                                                onGo: root.sshSaveScript(sshRow.modelData.host, seEdit.text)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ═══ MOBILE (KDE Connect) ═══
                    Column {
                        visible: root.expanded === "mobile"
                        width: parent.width; spacing: Theme.spaceS

                        // mark everything seen while the list is on screen
                        Connections {
                            target: KdeConnect
                            function onNotifsChanged() {
                                if (Globals.quickSettingsOpen && root.expanded === "mobile" && root.mobileView === "notifs")
                                    KdeConnect.markAllSeen()
                            }
                        }
                        onVisibleChanged: if (visible) KdeConnect.markAllSeen()

                        PageHead {
                            title: KdeConnect.connected ? KdeConnect.device.name : "Mobile"
                            note: KdeConnect.connected ? "" : "KDE Connect"
                            // the connected phone's battery
                            Row {
                                visible: KdeConnect.connected && KdeConnect.device.batteryCharge >= 0
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spaceXs
                                rightPadding: Theme.spaceXs
                                Glyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: KdeConnect.connected && KdeConnect.device.isCharging ? Theme.icBolt : Theme.icBattFull
                                    font.pixelSize: Theme.iconSm
                                    color: KdeConnect.connected && KdeConnect.device.isCharging ? Theme.success : Theme.textSecondary
                                }
                                TMono { anchors.verticalCenter: parent.verticalCenter; text: KdeConnect.connected ? KdeConnect.device.batteryCharge + "%" : "" }
                            }
                            IconBtn { anchors.verticalCenter: parent.verticalCenter; ic: Theme.icRefresh; onGo: KdeConnect.refresh() }
                        }

                        // — not installed —
                        Empty {
                            visible: KdeConnect.bridgeUp && !KdeConnect.installed
                            ic: Theme.icPhone; title: "KDE Connect isn’t installed"
                            desc: "Install it with sudo pacman -S kdeconnect, then install the app on your phone. Both need the same Wi-Fi network."
                        }
                        // — installed, daemon down —
                        Row {
                            visible: KdeConnect.installed && !KdeConnect.daemonRunning
                            width: parent.width; spacing: Theme.spaceS
                            TBody { anchors.verticalCenter: parent.verticalCenter; width: parent.width - kdStart.width - parent.spacing; text: "KDE Connect isn’t running."; color: Theme.textSecondary }
                            QsBtn { id: kdStart; anchors.verticalCenter: parent.verticalCenter; variant: "primary"; label: "Start"; onGo: KdeConnect.refresh() }
                        }

                        // — incoming pair request —
                        Column {
                            width: parent.width; spacing: Theme.spaceS
                            visible: KdeConnect.device !== null && KdeConnect.device.pairRequestedByPeer
                            TBody {
                                width: parent.width; wrapMode: Text.Wrap; elide: Text.ElideNone
                                text: "“" + (KdeConnect.device ? KdeConnect.device.name : "") + "” wants to pair with this computer."
                            }
                            Row {
                                anchors.right: parent.right
                                spacing: Theme.spaceS
                                QsBtn { variant: "ghost"; label: "Reject"; onGo: KdeConnect.cancelPair(KdeConnect.device.id) }
                                QsBtn { variant: "primary"; label: "Accept"; onGo: KdeConnect.acceptPair(KdeConnect.device.id) }
                            }
                        }

                        // — pairing in progress (we asked) —
                        Row {
                            visible: KdeConnect.pairingId !== ""
                            width: parent.width; spacing: Theme.spaceS
                            Spinner { anchors.verticalCenter: parent.verticalCenter; size: Theme.iconSm }
                            TBody { anchors.verticalCenter: parent.verticalCenter; width: parent.width - Theme.iconSm - kpCancel.width - 2 * parent.spacing; text: "Pairing… Accept the request on your phone."; color: Theme.textSecondary }
                            QsBtn { id: kpCancel; anchors.verticalCenter: parent.verticalCenter; variant: "ghost"; label: "Cancel"; onGo: KdeConnect.cancelPair(KdeConnect.pairingId) }
                        }
                        Note { visible: KdeConnect.pairError !== ""; tone: "danger"; text: KdeConnect.pairError }

                        // — no paired device: the phones in reach —
                        Column {
                            width: parent.width; spacing: Theme.spaceS
                            visible: KdeConnect.installed && KdeConnect.daemonRunning
                                     && (KdeConnect.device === null || (!KdeConnect.device.isPaired && !KdeConnect.device.pairRequestedByPeer))
                                     && KdeConnect.pairingId === ""
                            Empty {
                                visible: KdeConnect.devices.length === 0
                                ic: Theme.icPhone; title: "No phones found"
                                desc: "Open KDE Connect on your phone. Both devices need the same network."
                            }
                            ListWell {
                                flush: true
                                visible: KdeConnect.devices.length > 0
                                Repeater {
                                    model: KdeConnect.devices
                                    delegate: ListRow {
                                        id: kpRow
                                        required property var modelData
                                        glyph: Theme.icPhone
                                        label: modelData.name
                                        desc: modelData.isReachable ? "" : "Offline"
                                        disabled: !modelData.isReachable
                                        onClicked: if (kpRow.modelData.isReachable) KdeConnect.requestPair(kpRow.modelData.id)
                                        QsBtn {
                                            visible: kpRow.modelData.isReachable
                                            anchors.verticalCenter: parent.verticalCenter
                                            variant: "secondary"; label: "Pair"
                                            onGo: KdeConnect.requestPair(kpRow.modelData.id)
                                        }
                                    }
                                }
                            }
                        }

                        // — paired but out of reach —
                        Note {
                            visible: KdeConnect.device !== null && KdeConnect.device.isPaired && !KdeConnect.device.isReachable
                            text: "“" + (KdeConnect.device ? KdeConnect.device.name : "") + "” is offline. Put it on the same network with KDE Connect open, then refresh."
                        }

                        // — connected: notifications ⇄ messages, and ring —
                        Column {
                            width: parent.width; spacing: Theme.spaceS
                            visible: KdeConnect.connected

                            Row {
                                width: parent.width; spacing: Theme.spaceS
                                Segmented {
                                    width: parent.width - ringBtn.width - parent.spacing
                                    options: [{ label: "Notifications" + (KdeConnect.unreadCount > 0 ? " · " + KdeConnect.unreadCount : ""), value: "notifs" },
                                              { label: "Messages", value: "msgs" }]
                                    value: root.mobileView
                                    onPicked: function (v) {
                                        root.mobileView = v
                                        if (v === "notifs") KdeConnect.markAllSeen()
                                        else KdeConnect.loadConversations()
                                    }
                                }
                                // ring (find my phone)
                                IconBtn { id: ringBtn; anchors.verticalCenter: parent.verticalCenter; size: "md"; ic: Theme.icBellRing; onGo: KdeConnect.ring() }
                            }

                            // ── the phone's notifications ──
                            Column {
                                width: parent.width; spacing: Theme.spaceS; visible: root.mobileView === "notifs"
                                Empty { visible: KdeConnect.notifs.length === 0; ic: Theme.icBell; title: "No notifications on the phone" }
                                Flickable {
                                    width: parent.width
                                    visible: KdeConnect.notifs.length > 0
                                    height: Math.min(kdcNotifCol.implicitHeight, Theme.panelSm - Theme.spaceXl - Theme.spaceLg)
                                    clip: true
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
                                                    height: knBody.implicitHeight + 2 * Theme.spaceS
                                                    Rectangle {
                                                        anchors.fill: parent; radius: Theme.radiusSecondary
                                                        color: knMa.containsMouse ? Theme.surfaceHover : "transparent"
                                                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                                    }
                                                    MouseArea { id: knMa; anchors.fill: parent; hoverEnabled: true }
                                                    Image {
                                                        anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                                                        anchors.top: parent.top; anchors.topMargin: Theme.spaceS
                                                        width: Theme.iconMd; height: Theme.iconMd
                                                        visible: knRow.modelData.iconPath !== ""
                                                        source: knRow.modelData.iconPath !== "" ? "file://" + knRow.modelData.iconPath : ""
                                                        sourceSize.width: 2 * Theme.iconMd; sourceSize.height: 2 * Theme.iconMd; mipmap: true
                                                    }
                                                    Glyph {
                                                        visible: knRow.modelData.iconPath === ""
                                                        anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                                                        anchors.top: parent.top; anchors.topMargin: Theme.spaceS
                                                        text: Theme.icPhone
                                                    }
                                                    Column {
                                                        id: knBody
                                                        anchors.left: parent.left; anchors.leftMargin: Theme.spaceS + Theme.iconMd + Theme.spaceS + Theme.spaceXs
                                                        anchors.right: knBtns.left; anchors.rightMargin: Theme.spaceXs
                                                        anchors.top: parent.top; anchors.topMargin: Theme.spaceS
                                                        spacing: Theme.spaceXxs
                                                        TStrong { width: parent.width; text: knRow.modelData.title || knRow.modelData.appName }
                                                        Text {
                                                            width: parent.width
                                                            visible: text !== ""
                                                            text: knRow.modelData.text || knRow.modelData.ticker
                                                            color: Theme.textSecondary
                                                            font.family: Theme.type.body.family
                                                            font.pixelSize: Theme.type.body.size
                                                            wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                                                        }
                                                        TCaption { text: knRow.modelData.appName }
                                                    }
                                                    Row {
                                                        id: knBtns
                                                        anchors.right: parent.right; anchors.rightMargin: Theme.spaceXs
                                                        anchors.top: parent.top; anchors.topMargin: Theme.spaceXs
                                                        spacing: Theme.spaceXxs
                                                        // reply (only when the app allows it)
                                                        IconBtn {
                                                            visible: knRow.modelData.replyId !== ""
                                                            ic: Theme.icSend
                                                            selected: root.replyTarget === knRow.modelData.id
                                                            onGo: root.replyTarget = root.replyTarget === knRow.modelData.id ? "" : knRow.modelData.id
                                                        }
                                                        IconBtn {
                                                            visible: knRow.modelData.dismissable
                                                            ic: Theme.icClose
                                                            onGo: KdeConnect.dismissNotif(knRow.modelData.id)
                                                        }
                                                    }
                                                }
                                                // the inline reply
                                                Row {
                                                    visible: root.replyTarget === knRow.modelData.id
                                                    width: parent.width; spacing: Theme.spaceS
                                                    leftPadding: Theme.spaceS; rightPadding: Theme.spaceS; bottomPadding: Theme.spaceS
                                                    Field {
                                                        width: parent.width - parent.leftPadding - parent.rightPadding - knSend.width - parent.spacing
                                                        focused: knReply.activeFocus
                                                        FieldInput {
                                                            id: knReply
                                                            anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                                                            placeholder: "Reply…"
                                                            Component.onCompleted: if (root.replyTarget === knRow.modelData.id) forceActiveFocus()
                                                            onAccepted: { if (text.trim() !== "") { KdeConnect.replyNotif(knRow.modelData.replyId, text.trim()); root.replyTarget = "" } }
                                                        }
                                                    }
                                                    QsBtn {
                                                        id: knSend
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        size: "md"; variant: "primary"; label: "Send"
                                                        disabled: knReply.text.trim() === ""
                                                        onGo: { KdeConnect.replyNotif(knRow.modelData.replyId, knReply.text.trim()); root.replyTarget = "" }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── messages: the conversation list ⇄ a thread ──
                            Column {
                                width: parent.width; spacing: Theme.spaceS; visible: root.mobileView === "msgs"

                                // conversation list
                                Column {
                                    width: parent.width; spacing: Theme.spaceS; visible: KdeConnect.openThread < 0
                                    Row {
                                        visible: KdeConnect.conversations.length === 0
                                        spacing: Theme.spaceS
                                        leftPadding: Theme.spaceS
                                        Spinner { visible: KdeConnect.convsRequested; anchors.verticalCenter: parent.verticalCenter; size: Theme.iconSm }
                                        TCaption { anchors.verticalCenter: parent.verticalCenter; text: KdeConnect.convsRequested ? "Loading conversations from the phone…" : "No conversations yet" }
                                    }
                                    Flickable {
                                        width: parent.width
                                        visible: KdeConnect.conversations.length > 0
                                        height: Math.min(kdcConvCol.implicitHeight, Theme.panelSm - Theme.spaceXl - Theme.spaceMd)
                                        clip: true
                                        contentHeight: kdcConvCol.implicitHeight
                                        boundsBehavior: Flickable.StopAtBounds
                                        Column {
                                            id: kdcConvCol
                                            width: parent.width
                                            Repeater {
                                                model: KdeConnect.conversations
                                                delegate: MsgRow {
                                                    required property var modelData
                                                    title: modelData.display
                                                    line: modelData.body
                                                    time: root.fmtMsgTime(modelData.date)
                                                    unread: modelData.unread
                                                    onClicked: KdeConnect.openConversation(modelData.threadId)
                                                }
                                            }
                                        }
                                    }
                                }

                                // thread view
                                Column {
                                    width: parent.width; spacing: Theme.spaceS; visible: KdeConnect.openThread >= 0
                                    Row {
                                        width: parent.width; spacing: Theme.spaceS
                                        IconBtn { anchors.verticalCenter: parent.verticalCenter; size: "md"; ic: Theme.icBack; onGo: KdeConnect.openThread = -1 }
                                        TStrong {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - Theme.controlMd - parent.spacing
                                            text: {
                                                for (var i = 0; i < KdeConnect.conversations.length; i++)
                                                    if (KdeConnect.conversations[i].threadId === KdeConnect.openThread) return KdeConnect.conversations[i].display
                                                return "Conversation"
                                            }
                                        }
                                    }
                                    Rectangle {
                                        width: parent.width; height: Theme.panelSm - Theme.spaceXl - Theme.spaceLg
                                        radius: Theme.radiusRounded
                                        color: Theme.surfaceSunken
                                        border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                                        Flickable {
                                            id: kdcThreadFlick
                                            anchors.fill: parent; anchors.margins: Theme.spaceS; clip: true
                                            contentHeight: kdcThreadCol.implicitHeight
                                            boundsBehavior: Flickable.StopAtBounds
                                            // stick to the newest message
                                            onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                                            // pull past the top → page older messages in
                                            onAtYBeginningChanged: if (atYBeginning && contentHeight > height) KdeConnect.loadOlder()
                                            Column {
                                                id: kdcThreadCol
                                                width: parent.width; spacing: Theme.spaceXs
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
                                                            width: Math.min(kmTxt.implicitWidth + 2 * (Theme.spaceS + Theme.spaceXs), kmRow.width * 0.8)
                                                            height: kmTxt.implicitHeight + 2 * Theme.spaceS
                                                            radius: Theme.radiusRounded
                                                            color: kmRow.sent ? Theme.accent : Theme.surfaceOverlay
                                                            border.color: kmRow.sent ? "transparent" : Theme.borderSubtle
                                                            border.width: Theme.borderWidth1
                                                            opacity: kmRow.modelData.pending ? Theme.opacityApp : 1
                                                            Text {
                                                                id: kmTxt
                                                                anchors.fill: parent
                                                                anchors.topMargin: Theme.spaceS; anchors.bottomMargin: Theme.spaceS
                                                                anchors.leftMargin: Theme.spaceS + Theme.spaceXs; anchors.rightMargin: Theme.spaceS + Theme.spaceXs
                                                                text: kmRow.modelData.body !== "" ? kmRow.modelData.body
                                                                    : (kmRow.modelData.hasAttachments ? "Attachment. Open it on the phone." : "No text (MMS)")
                                                                color: kmRow.sent ? Theme.onAccent : Theme.textPrimary
                                                                font.family: Theme.type.body.family
                                                                font.pixelSize: Theme.type.body.size
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
                                    Row {
                                        width: parent.width; spacing: Theme.spaceS
                                        Field {
                                            width: parent.width - kdcSend.width - parent.spacing
                                            focused: kdcCompose.activeFocus
                                            FieldInput {
                                                id: kdcCompose
                                                anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                                                placeholder: "Message…"
                                                onAccepted: { if (text.trim() !== "") { KdeConnect.sendMessage(text.trim()); text = "" } }
                                            }
                                        }
                                        QsBtn {
                                            id: kdcSend
                                            anchors.verticalCenter: parent.verticalCenter
                                            size: "md"; variant: "primary"; ic: Theme.icSend; label: "Send"
                                            disabled: kdcCompose.text.trim() === ""
                                            onGo: { KdeConnect.sendMessage(kdcCompose.text.trim()); kdcCompose.text = "" }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ═══ MAIL (Gmail) ═══
                    Column {
                        visible: root.expanded === "mail"
                        width: parent.width; spacing: Theme.spaceS
                        PageHead {
                            title: Mail.available ? "Inbox" : "Mail"
                            note: Mail.available && Mail.unread > 0 ? Mail.unread + " unread" : ""
                            // new-mail notifications on or off
                            IconBtn { visible: Mail.available; anchors.verticalCenter: parent.verticalCenter; ic: Theme.icBellRing; selected: Mail.notify; onGo: Mail.setNotify(!Mail.notify) }
                            IconBtn { visible: Mail.available; anchors.verticalCenter: parent.verticalCenter; ic: Theme.icRefresh; onGo: Mail.fetch() }
                            QsBtn { anchors.verticalCenter: parent.verticalCenter; label: Mail.inboxLabel; onGo: Mail.openInbox() }
                        }
                        Note { visible: !Mail.available; text: Mail.hint }
                        Note { visible: Mail.available && Mail.error !== ""; tone: "warning"; text: Mail.error }
                        QsBtn { visible: Mail.needsReconnect; variant: "primary"; label: "Reconnect Google"; onGo: Mail.reconnect() }
                        Note { visible: Mail.available && Mail.state === "offline"; text: "Offline. Showing the last check." }
                        Empty {
                            visible: Mail.available && Mail.state === "" && Mail.list.length === 0
                            ic: Theme.icMail; title: "No mail"; desc: "Your inbox is empty."
                        }
                        // the latest 10, compact two-line rows — no inner scrolling
                        ListWell {
                            flush: true
                            visible: Mail.available && Mail.list.length > 0
                            Repeater {
                                model: Mail.list.slice(0, 10)
                                delegate: MsgRow {
                                    required property var modelData
                                    title: modelData.from
                                    line: modelData.subject
                                    time: root.fmtMsgTime(modelData.date)
                                    unread: modelData.unread
                                    onClicked: Mail.open(modelData.id)
                                }
                            }
                        }
                    }

                    // ═══ CAST to a TV — the whole flow lives here (RFC-004):
                    //     the sink list from ewe-castd (Miracast + Chromecast),
                    //     pick a TV → SharePicker → streaming. No foreign window. ═══
                    Column {
                        id: castCard
                        visible: root.tab === "cast"
                        width: parent.width; spacing: Theme.spaceS
                        property bool castOpen: root.tab === "cast"
                        // the switch is on while a session runs; turning it off hangs up
                        PageHead {
                            title: "Cast"
                            busy: Globals.casting && Globals.castState !== "streaming"
                            note: Globals.castState === "streaming" ? "Casting to " + Globals.castSinkName
                                : Globals.casting ? "Connecting…" : ""
                            hasSwitch: Globals.casting
                            on: Globals.casting
                            onToggled: Globals.castCommand("stop", "")
                        }
                        // while a session is being built, narrate the daemon's state
                        // where the person is looking — the same line the toasts carry
                        Note { visible: Globals.casting && Globals.castState !== "streaming" && Globals.castDetail !== ""; text: Globals.castDetail }
                        // nothing yet — an honest empty state instead of a broken-looking box
                        Row {
                            visible: castCard.castOpen && !Globals.casting && Globals.castSinks.length === 0
                            spacing: Theme.spaceS
                            leftPadding: Theme.spaceS
                            Spinner { visible: Globals.castDetail.indexOf("not installed") === -1; anchors.verticalCenter: parent.verticalCenter; size: Theme.iconSm }
                            TCaption {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Globals.castDetail.indexOf("not installed") !== -1 ? Globals.castDetail : "Looking for displays…"
                            }
                        }
                        ListWell {
                            flush: true
                            visible: castCard.castOpen && !Globals.casting && Globals.castSinks.length > 0
                            Repeater {
                                model: castCard.castOpen ? Globals.castSinks : []
                                delegate: ListRow {
                                    required property var modelData
                                    glyph: Theme.icCast
                                    label: modelData.name
                                    kind: modelData.kind === "chromecast" ? "Chromecast" : modelData.kind === "miracast" ? "Miracast" : ""
                                    onClicked: Globals.castCommand("start", modelData.id)
                                }
                            }
                        }
                    }

                    // ═══ CALENDAR (Agenda): the month, then the week's events ═══
                    Column {
                        id: calCol
                        visible: root.tab === "cal"
                        width: parent.width; spacing: Theme.spaceS
                        // header: month and year
                        Item {
                            width: parent.width; height: Theme.controlLg
                            IconBtn { id: calBack; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; size: "md"; ic: Theme.icBack; onGo: root.setTab("home") }
                            TStrong {
                                anchors.left: calBack.right; anchors.leftMargin: Theme.spaceS
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.monthNames[root.calMonth] + " " + root.calYear
                                font.weight: Theme.fontWeightSemibold
                            }
                        }
                        Grid {
                            id: calGrid
                            width: parent.width; columns: 7
                            readonly property real cellW: width / 7
                            Repeater {
                                model: 7
                                delegate: Item {
                                    required property int index
                                    width: calGrid.cellW; height: Theme.controlSm
                                    TCaption {
                                        anchors.centerIn: parent
                                        text: Qt.locale().dayName((root.firstDow + index) % 7, Locale.ShortFormat).slice(0, 2)
                                    }
                                }
                            }
                            Repeater {
                                model: 42
                                delegate: Item {
                                    id: calDay
                                    required property int index
                                    readonly property int dayNum: index - root.firstW + 1
                                    readonly property bool valid: dayNum >= 1 && dayNum <= root.daysIn
                                    readonly property bool isToday: valid && dayNum === root.calDate
                                    readonly property bool hasEvent: valid && root.eventDays[dayNum] !== undefined
                                    readonly property bool weekend: { var d = (root.firstDow + index) % 7; return d === 0 || d === 6 }
                                    // the sixth week only when the month reaches it
                                    visible: index < 35 || root.firstW + root.daysIn > 35
                                    width: calGrid.cellW; height: Theme.controlMd + Theme.spaceXxs
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: Theme.controlMd; height: Theme.controlMd
                                        radius: Theme.radiusSecondary
                                        visible: calDay.isToday
                                        color: Theme.accent
                                    }
                                    TMono {
                                        anchors.centerIn: parent
                                        text: calDay.valid ? calDay.dayNum : ""
                                        color: calDay.isToday ? Theme.onAccent : calDay.weekend ? Theme.textSecondary : Theme.textPrimary
                                        font.weight: calDay.isToday ? Theme.fontWeightSemibold : Theme.type.mono.weight
                                    }
                                    // the event dot, spaceXxs above the cell's bottom edge
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: Theme.spaceXxs + Theme.spaceXxs / 2
                                        width: Theme.spaceXs; height: Theme.spaceXs; radius: Theme.radiusFull
                                        visible: calDay.hasEvent
                                        color: calDay.isToday ? Theme.onAccent : Theme.accentText
                                    }
                                }
                            }
                        }
                        Rectangle { width: parent.width; height: Theme.borderWidth1; color: Theme.borderSubtle }
                        // offline: the warning Inline alert
                        Rectangle {
                            visible: Agenda.state === "offline"
                            width: parent.width; height: offCol.implicitHeight + 2 * Theme.spaceS
                            radius: Theme.radiusPrimary
                            color: Theme.warningSubtle
                            Glyph { id: offIc; anchors.left: parent.left; anchors.leftMargin: Theme.spaceS + Theme.spaceXs; anchors.top: parent.top; anchors.topMargin: Theme.spaceS + Theme.spaceXxs / 2; text: Theme.icCloudOff; color: Theme.warning }
                            Column {
                                id: offCol
                                anchors.left: offIc.right; anchors.leftMargin: Theme.spaceS
                                anchors.right: parent.right; anchors.rightMargin: Theme.spaceS + Theme.spaceXs
                                anchors.top: parent.top; anchors.topMargin: Theme.spaceS
                                TStrong { text: "Offline"; color: Theme.warning }
                                TBody { width: parent.width; text: "Showing events from the last sync."; wrapMode: Text.Wrap }
                            }
                        }
                        Empty {
                            visible: root.agenda.length === 0
                            ic: Theme.icCalendar
                            title: Agenda.hintTitle
                            desc: Agenda.hintBody
                            QsBtn {
                                visible: !Agenda.connected
                                size: "md"; label: "Open Settings"
                                onGo: { Globals.quickSettingsOpen = false; Globals.openSettings() }
                            }
                        }
                        // the agenda: upcoming events grouped by day
                        Repeater {
                            model: root.agenda
                            delegate: Column {
                                id: agDay
                                required property var modelData
                                width: calCol.width; spacing: Theme.spaceXxs
                                topPadding: Theme.spaceS
                                SectionTitle { text: agDay.modelData.label }
                                Repeater {
                                    model: agDay.modelData.events
                                    delegate: Rectangle {
                                        id: evRow
                                        required property var modelData
                                        readonly property bool now: root.eventNow(modelData)
                                        width: agDay.width
                                        height: Math.max(Theme.controlXl, evText.implicitHeight + 2 * Theme.spaceXs)
                                        radius: Theme.radiusSecondary
                                        color: evRow.now ? Theme.accentSubtle : "transparent"
                                        TMono {
                                            id: evTime
                                            anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                                            anchors.top: evText.top
                                            width: Theme.spaceXl
                                            text: root.fmtEventStart(evRow.modelData)
                                            color: Theme.textMuted
                                        }
                                        // the calendar's own colour
                                        Rectangle {
                                            id: evBar
                                            anchors.left: evTime.right; anchors.leftMargin: Theme.spaceS
                                            anchors.top: evText.top; anchors.bottom: evText.bottom
                                            width: Theme.borderWidth2
                                            radius: Theme.borderWidth2 / 2
                                            color: evRow.modelData.color !== "" ? evRow.modelData.color : Theme.accent
                                        }
                                        Column {
                                            id: evText
                                            anchors.left: evBar.right; anchors.leftMargin: Theme.spaceS
                                            anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                                            anchors.verticalCenter: parent.verticalCenter
                                            TBody { width: parent.width; text: evRow.modelData.summary }
                                            TCaption { visible: text !== ""; width: parent.width; text: root.eventMeta(evRow.modelData) }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ═══ NOTIFICATIONS (Notification center): Do not disturb,
                    //     then one card per app ═══
                    Column {
                        visible: root.tab === "notifs"
                        width: parent.width; spacing: Theme.spaceS
                        readonly property bool any: Globals.server && Globals.server.trackedNotifications.values.length > 0
                        Item {
                            width: parent.width; height: Theme.controlLg
                            IconBtn { id: ntBack; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; size: "md"; ic: Theme.icBack; onGo: root.setTab("home") }
                            Text {
                                anchors.left: ntBack.right; anchors.leftMargin: Theme.spaceS
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Notifications"
                                color: Theme.textPrimary
                                font.family: Theme.type.h4.family
                                font.pixelSize: Theme.type.h4.size
                                font.weight: Theme.type.h4.weight
                            }
                            QsBtn {
                                visible: parent.parent.any
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                size: "md"; variant: "ghost"; label: "Clear all"
                                onGo: root.clearAll()
                            }
                        }
                        SwitchRow {
                            ic: Theme.icDnd; label: "Do not disturb"
                            on: Globals.dnd
                            onToggled: Globals.dnd = !Globals.dnd
                        }
                        Rectangle { width: parent.width; height: Theme.borderWidth1; color: Theme.borderSubtle }
                        Empty {
                            visible: !parent.any
                            ic: Globals.dnd ? Theme.icDnd : Theme.icBell
                            title: "No notifications"
                            desc: Globals.dnd ? "Banners are hidden while Do not disturb is on." : "You’re all caught up."
                        }
                        // One card per APP. Several from one app stack, with "N more
                        // from App" below; clicking the stack opens every one of
                        // them (each closable and clickable). A single
                        // notification jumps straight to the window that sent it.
                        Repeater {
                            model: root.tab === "notifs" ? root.noteGroups : []
                            delegate: Item {
                                id: nGroup
                                required property var modelData
                                readonly property int count: modelData.items.length
                                readonly property bool open: count > 1 && root.nExpanded === modelData.app
                                readonly property bool stacked: count > 1 && !open
                                readonly property var latest: modelData.latest
                                readonly property bool critical: latest.urgency === NotificationUrgency.Critical
                                width: parent.width
                                height: nCard.height + (stacked ? Theme.spaceS + Theme.spaceXs + nMore.height + Theme.spaceXs : 0)

                                // the stack: two spaceXs layers peeking out below the newest card
                                Rectangle {
                                    visible: nGroup.stacked
                                    anchors.top: nCard.bottom; anchors.topMargin: -(Theme.spaceMd - Theme.spaceXs)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width - 2 * Theme.spaceS; height: Theme.spaceMd
                                    radius: Theme.radiusRounded
                                    color: Theme.surfaceOverlay
                                    border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                                    z: -1
                                }
                                Rectangle {
                                    visible: nGroup.stacked && nGroup.count > 2
                                    anchors.top: nCard.bottom; anchors.topMargin: -(Theme.spaceMd - 2 * Theme.spaceXs)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width - 2 * Theme.spaceMd; height: Theme.spaceMd
                                    radius: Theme.radiusRounded
                                    color: Theme.surfaceOverlay
                                    border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                                    z: -2
                                }

                                // a flat card: surfaceOverlay, no shadow
                                Rectangle {
                                    id: nCard
                                    width: parent.width
                                    height: gCol.implicitHeight + Theme.spaceS + Theme.spaceS + Theme.spaceXs
                                    radius: Theme.radiusRounded
                                    color: Theme.surfaceOverlay
                                    border.color: nGroup.critical ? Theme.danger : Theme.borderSubtle
                                    border.width: Theme.borderWidth1
                                    // card click — declared FIRST so the inner rows' and the
                                    // close buttons' MouseAreas (later children) win over it
                                    MouseArea {
                                        id: nCardMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (nGroup.count > 1) root.nExpanded = nGroup.open ? "" : nGroup.modelData.app
                                            else root.noteFocus(nGroup.latest)
                                        }
                                    }
                                    Column {
                                        id: gCol
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                        anchors.leftMargin: Theme.spaceS + Theme.spaceXs; anchors.rightMargin: Theme.spaceS + Theme.spaceXs
                                        anchors.topMargin: Theme.spaceS
                                        spacing: Theme.spaceS

                                        // header: the app, its count, and close (on hover)
                                        Item {
                                            width: parent.width; height: Theme.controlSm
                                            Row {
                                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                                anchors.right: nClose.left; anchors.rightMargin: Theme.spaceXs
                                                spacing: Theme.spaceXs
                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: Theme.iconMd; height: Theme.iconMd
                                                    radius: Theme.radiusSlight
                                                    color: Theme.surfaceHover
                                                    clip: true
                                                    Image {
                                                        anchors.fill: parent
                                                        sourceSize.width: 2 * Theme.iconMd; sourceSize.height: 2 * Theme.iconMd
                                                        mipmap: true
                                                        source: (nGroup.latest.appIcon && nGroup.latest.appIcon != "")
                                                                ? Quickshell.iconPath(nGroup.latest.appIcon, "dialog-information")
                                                                : Quickshell.iconPath("dialog-information")
                                                    }
                                                }
                                                TCaption {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: nGroup.modelData.app
                                                    color: Theme.textSecondary
                                                    font.weight: Theme.fontWeightMedium
                                                }
                                                Badge { visible: nGroup.count > 1; anchors.verticalCenter: parent.verticalCenter; count: nGroup.count }
                                                Glyph {
                                                    visible: nGroup.count > 1
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: Theme.icChevronDown; rotation: nGroup.open ? 180 : 0
                                                    font.pixelSize: Theme.iconSm; color: Theme.textMuted
                                                    Behavior on rotation { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                                }
                                            }
                                            // close dismisses the whole group
                                            IconBtn {
                                                id: nClose
                                                anchors.right: parent.right; anchors.rightMargin: -Theme.spaceXs
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: nCardMa.containsMouse || nClose.hovered || nGroup.open
                                                ic: Theme.icClose
                                                onGo: root.dismissAllOf(nGroup.modelData.items)
                                            }
                                        }

                                        // collapsed: the newest one
                                        Row {
                                            visible: !nGroup.open
                                            width: parent.width
                                            spacing: Theme.spaceS + Theme.spaceXs
                                            Column {
                                                width: parent.width - (nMedia.visible ? nMedia.width + parent.spacing : 0)
                                                spacing: Theme.spaceXxs
                                                Row {
                                                    width: parent.width; spacing: Theme.spaceXs
                                                    Glyph { visible: nGroup.critical; anchors.verticalCenter: parent.verticalCenter; text: Theme.icWarning; color: Theme.danger }
                                                    TStrong {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: parent.width - (nGroup.critical ? Theme.iconMd + parent.spacing : 0)
                                                        text: nGroup.latest.summary || ""
                                                        color: nGroup.critical ? Theme.danger : Theme.textPrimary
                                                    }
                                                }
                                                Text {
                                                    visible: text.length > 0
                                                    width: parent.width
                                                    text: nGroup.latest.body || ""
                                                    color: Theme.textSecondary
                                                    font.family: Theme.type.body.family
                                                    font.pixelSize: Theme.type.body.size
                                                    wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                                                    textFormat: Text.PlainText
                                                }
                                            }
                                            Rectangle {
                                                id: nMedia
                                                visible: nGroup.latest.image && nGroup.latest.image != ""
                                                width: Theme.icon3xl; height: Theme.icon3xl
                                                radius: Theme.radiusPrimary
                                                color: Theme.surfaceHover
                                                clip: true
                                                Image {
                                                    anchors.fill: parent; fillMode: Image.PreserveAspectCrop
                                                    sourceSize.width: 2 * Theme.icon3xl; sourceSize.height: 2 * Theme.icon3xl
                                                    mipmap: true
                                                    source: nMedia.visible ? nGroup.latest.image : ""
                                                }
                                            }
                                        }

                                        // open: every notification of the app, divided
                                        Repeater {
                                            model: nGroup.open ? nGroup.modelData.items : []
                                            delegate: Item {
                                                id: nItem
                                                required property var modelData
                                                required property int index
                                                width: gCol.width
                                                height: iCol.implicitHeight + (nItem.index > 0 ? Theme.spaceS : 0)
                                                Rectangle {
                                                    visible: nItem.index > 0
                                                    width: parent.width; height: Theme.borderWidth1
                                                    color: Theme.borderSubtle
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.noteFocus(nItem.modelData) }
                                                Column {
                                                    id: iCol
                                                    anchors.left: parent.left; anchors.right: iClose.left; anchors.rightMargin: Theme.spaceXs
                                                    anchors.bottom: parent.bottom
                                                    spacing: Theme.spaceXxs
                                                    TStrong { width: parent.width; text: nItem.modelData.summary || "" }
                                                    Text {
                                                        visible: text.length > 0
                                                        width: parent.width
                                                        text: nItem.modelData.body || ""
                                                        color: Theme.textSecondary
                                                        font.family: Theme.type.body.family
                                                        font.pixelSize: Theme.type.body.size
                                                        wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                                                        textFormat: Text.PlainText
                                                    }
                                                }
                                                IconBtn {
                                                    id: iClose
                                                    anchors.right: parent.right; anchors.rightMargin: -Theme.spaceXs
                                                    anchors.top: iCol.top
                                                    ic: Theme.icClose
                                                    onGo: nItem.modelData.dismiss()
                                                }
                                            }
                                        }
                                    }
                                }

                                // "N more from App", below the stack
                                TCaption {
                                    id: nMore
                                    visible: nGroup.stacked
                                    anchors.top: nCard.bottom; anchors.topMargin: Theme.spaceS + Theme.spaceXs
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: (nGroup.count - 1) + " more from " + nGroup.modelData.app
                                }
                            }
                        }
                    }
                }
            }

            // ══ the power menu: a Menu rising from the rail's power item ══
            // a click anywhere else in the panel closes it
            MouseArea { anchors.fill: parent; visible: root.powerOpen; onClicked: root.powerOpen = false }

            component PowerItem: Rectangle {
                id: pit
                property string ic: ""
                property string label: ""
                property bool danger: false
                signal go()
                width: parent ? parent.width : Theme.panelSm
                height: Theme.controlMd
                radius: Theme.radiusSecondary
                // a quiet hover for every row — the danger lives in the glyph,
                // never in a red slab behind it
                color: pitMa.pressed ? Theme.surfacePressed : pitMa.containsMouse ? Theme.surfaceHover : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                Row {
                    anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spaceS
                    Glyph { anchors.verticalCenter: parent.verticalCenter; text: pit.ic; color: pit.danger ? Theme.danger : Theme.textSecondary }
                    TBody { anchors.verticalCenter: parent.verticalCenter; text: pit.label; color: (pit.danger && pitMa.containsMouse) ? Theme.danger : Theme.textPrimary }
                }
                MouseArea { id: pitMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pit.go() }
            }

            Item {
                id: powerPop
                visible: root.powerOpen || ppCloseTimer.running
                width: Theme.panelSm - Theme.spaceXl
                height: ppCol.implicitHeight + 2 * (Theme.spaceXs + Theme.borderWidth1)
                // rises from the rail's power item (the bottom-left corner)
                anchors.bottom: parent.bottom; anchors.bottomMargin: panel.pad
                anchors.left: parent.left; anchors.leftMargin: panel.railW + Theme.spaceXs
                opacity: root.powerOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: root.powerOpen ? Theme.durBase : Theme.durFast; easing.type: Theme.ease } }
                transform: Translate {
                    y: (root.powerOpen || Theme.reduceMotion) ? 0 : Theme.slideOffset
                    Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
                }
                Timer { id: ppCloseTimer; interval: Math.max(1, Theme.durBase) }
                Connections { target: root; function onPowerOpenChanged() { if (!root.powerOpen) ppCloseTimer.restart() } }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusRounded
                    color: Theme.surfaceOverlay
                    border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                    layer.enabled: true
                    layer.effect: Elevation {}
                }
                MouseArea { anchors.fill: parent }   // swallow clicks inside the menu

                Column {
                    id: ppCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: Theme.spaceXs + Theme.borderWidth1

                    // the power mode (PowerProfiles service ← tuned-ppd D-Bus)
                    Column {
                        width: parent.width
                        spacing: Theme.spaceS
                        padding: Theme.spaceS
                        SectionTitle { text: "Power mode"; first: true }
                        Segmented {
                            width: parent.width - 2 * parent.padding
                            value: PowerProfiles.profile
                            options: [{ label: "Power saver", value: PowerProfile.PowerSaver },
                                      { label: "Balanced", value: PowerProfile.Balanced },
                                      { label: "Performance", value: PowerProfile.Performance, disabled: !PowerProfiles.hasPerformanceProfile }]
                            onPicked: function (v) { PowerProfiles.profile = v }
                        }
                    }
                    // an inset divider, spaceXs above and below
                    Item {
                        width: parent.width; height: Theme.spaceS + Theme.borderWidth1
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: Theme.spaceS; width: parent.width - 2 * Theme.spaceS; height: Theme.borderWidth1
                            color: Theme.borderSubtle
                        }
                    }
                    PowerItem { ic: Theme.icLock;    label: "Lock";      onGo: root.runPower("lock") }
                    PowerItem { ic: root.g(0xE410);  label: "Suspend";   onGo: root.runPower("suspend") }
                    PowerItem { ic: root.g(0xE10E);  label: "Sign out";  onGo: root.askPower("logout", "Sign out?", "Sign out") }
                    PowerItem { ic: root.g(0xE145);  label: "Restart";   danger: true; onGo: root.askPower("reboot", "Restart this computer?", "Restart") }
                    PowerItem { ic: root.g(0xE140);  label: "Shut down"; danger: true; onGo: root.askPower("poweroff", "Shut down this computer?", "Shut down") }
                }
            }

            // ══ the confirmation: a Dialog on the `scrim` for the actions that
            //    close apps (Sign out · Restart · Shut down). Esc, Cancel or a
            //    click on the scrim cancels. ══
            Item {
                id: confirmPop
                anchors.fill: parent
                visible: root.confirmAction !== "" || cfCloseTimer.running
                z: 100
                Timer { id: cfCloseTimer; interval: Math.max(1, Theme.durBase) }
                Connections { target: root; function onConfirmActionChanged() { if (root.confirmAction === "") cfCloseTimer.restart() } }

                readonly property bool shown: root.confirmAction !== ""
                readonly property bool danger: root.confirmAction === "poweroff" || root.confirmAction === "reboot"

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusRounded
                    color: Theme.scrim
                    opacity: confirmPop.shown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: confirmPop.shown ? Theme.durBase : Theme.durFast; easing.type: Theme.ease } }
                    MouseArea { anchors.fill: parent; onClicked: root.confirmAction = "" }
                }

                Rectangle {
                    id: cfCard
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.spaceMd
                    height: cfCol.implicitHeight + 2 * Theme.spaceMd
                    radius: Theme.radiusRounded
                    color: Theme.surfaceRaised
                    border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                    layer.enabled: true
                    layer.effect: Elevation {}
                    opacity: confirmPop.shown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: confirmPop.shown ? Theme.durBase : Theme.durFast; easing.type: Theme.ease } }
                    transform: Translate {
                        y: (confirmPop.shown || Theme.reduceMotion) ? 0 : Theme.slideOffset
                        Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
                    }
                    MouseArea { anchors.fill: parent }   // swallow clicks on the dialog

                    Column {
                        id: cfCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: Theme.spaceMd
                        spacing: Theme.spaceMd

                        Row {
                            width: parent.width
                            spacing: Theme.spaceS + Theme.spaceXs
                            Rectangle {
                                width: Theme.icon2xl; height: Theme.icon2xl
                                radius: Theme.radiusFull
                                color: confirmPop.danger ? Theme.dangerSubtle : Theme.accentSubtle
                                Glyph {
                                    anchors.centerIn: parent
                                    text: root.g(confirmPop.danger ? 0xE140 : 0xE10E)
                                    color: confirmPop.danger ? Theme.danger : Theme.accentText
                                }
                            }
                            Column {
                                width: parent.width - Theme.icon2xl - parent.spacing
                                spacing: Theme.spaceXs
                                Text {
                                    width: parent.width; wrapMode: Text.WordWrap
                                    text: root.confirmTitle
                                    color: Theme.textPrimary
                                    font.family: Theme.type.h3.family
                                    font.pixelSize: Theme.type.h3.size
                                    font.weight: Theme.type.h3.weight
                                    font.letterSpacing: Theme.type.h3.letterSpacing
                                }
                                Text {
                                    width: parent.width; wrapMode: Text.WordWrap
                                    text: "Open apps will close. Save your work first."
                                    color: Theme.textSecondary
                                    font.family: Theme.type.body.family
                                    font.pixelSize: Theme.type.body.size
                                }
                            }
                        }
                        Row {
                            anchors.right: parent.right
                            spacing: Theme.spaceS
                            QsBtn { size: "md"; variant: "ghost"; label: "Cancel"; onGo: root.confirmAction = "" }
                            QsBtn {
                                size: "md"
                                variant: confirmPop.danger ? "danger" : "primary"
                                label: root.confirmVerb
                                onGo: root.runPower(root.confirmAction)
                            }
                        }
                    }
                }
            }
        }
    }
}
