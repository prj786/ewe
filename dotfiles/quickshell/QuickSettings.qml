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
//   panel    panelMd wide (the icon rail plus the card's panelSm of content;
//            wider in step with Text size, Theme.grow),
//            surfaceRaised with a borderWidth1 borderSubtle outline, the
//            radiusRounded corner and the shadowFloat elevation, spaceXs
//            below the bar at the right edge, spaceS + spaceXs of padding and
//            between sections. One height for every page: half the screen
//            (at most 80%); a longer page scrolls. Solid, never Glass.
//   motion   in: fade plus a slide from the right edge at durBase; out at durFast;
//            OutCubic, and nothing moves under Reduce motion
//   rail     the collapsed Side navigation: the sheep mark, then one
//            controlLg × controlMd item per page (home, Wi-Fi, Bluetooth,
//            sound, Calendar, Notifications; the add-ons' pages follow) on
//            surfaceBase; the selected page is accentSubtle with an
//            accentText glyph; Settings and Power sit at its foot
//   home     the tile grid (Tile.qml), spaceS apart
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

    // which section is expanded: "" | "audio" | "wifi" | "bt" | an add-on page key
    // ── tabs (the 2026-09 revamp): home is the toggle grid, every list
    //    lives on its own tab; `expanded` survives as a read-only alias so
    //    the section visibles below keep working unchanged ──
    property string tab: "home"
    readonly property string expanded: tab === "home" ? "" : tab
    Connections { target: Globals; function onQuickSettingsTabRequested(name) { root.setTab(name) } }
    function setTab(t) {
        if (t !== "bt" && Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = false
        root.tab = t
        if (t === "wifi") { wifiScan.running = true; wifiSavedScan.running = true }
        if (t === "bt" && Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = true
    }

    // wifi
    property var wifiList: []
    property bool wifiOn: true
    property bool wiredUp: false   // a wired (ethernet) link is the active connection
    property string pwTarget: ""
    property bool pwShow: false        // reveal the Wi-Fi password while typing
    property string pwText: ""
    function curSsid() { for (var i = 0; i < wifiList.length; i++) if (wifiList[i].active) return wifiList[i].ssid; return "" }

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
        if (root.expanded === "wifi") wifiScan.running = true
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
                    // nmcli -t escapes ':' and '\' inside values ("My\:Net"); undo it
                    var ssid = p.slice(3).join(":").replace(/\\:/g, ":").replace(/\\\\/g, "\\")
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
    // nmcli's device states carry a parenthetical — "connecting (getting IP
    // configuration)", "connected (externally)" — so match the word, not the string
    readonly property bool wiredConnecting: wiredStateStr.indexOf("connecting") === 0
    property bool wiredBusy: false
    Process { id: wiredState; command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | awk -F: '$2==\"ethernet\"{print $1\":\"$3; exit}'"]; stdout: StdioCollector { onStreamFinished: { var p = this.text.trim().split(":"); root.wiredDev = p[0] || ""; root.wiredStateStr = p[1] || ""; root.wiredUp = root.wiredStateStr.indexOf("connected") === 0; if (!wiredSetProc.running) root.wiredBusy = false } } }
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
    Process { id: brightnessProc; command: ["sh", "-c", "brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%'"]; stdout: StdioCollector { onStreamFinished: { var n = parseInt(this.text.trim()); if (!isNaN(n)) root.brightnessVal = n / 100 } } }
    Process { id: volumeProc; command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oE '[0-9]+\\.[0-9]+'"]; stdout: StdioCollector { onStreamFinished: { var f = parseFloat(this.text.trim()); if (!isNaN(f)) root.volumeVal = Math.min(1, f) } } }
    Timer { id: rescanTimer; interval: 2500; onTriggered: { wifiState.running = true; wifiScan.running = true } }
    // the network we just joined, until a list read shows it IN-USE
    property string wifiConfirm: ""
    Timer { id: wifiConfirmTimer; interval: 4000; onTriggered: { root.wifiConfirm = ""; root.wifiPending = "" } }
    // NetworkManager events (the bar's `nmcli monitor`) — re-read while the
    // panel is open instead of waiting for the 6 s poll; this is what makes a
    // cable plug or a Wi-Fi join show at once
    Connections {
        target: Globals
        function onNetEpochChanged() {
            if (!Globals.quickSettingsOpen) return
            wifiState.running = true; wiredState.running = true
            if (root.expanded === "wifi") wifiScan.running = true
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
    Timer { interval: 6000; running: Globals.quickSettingsOpen; repeat: true; onTriggered: { wifiState.running = true; wiredState.running = true; if (root.expanded === "wifi") wifiScan.running = true } }

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
            // grows with Text size, so two tiles still fit side by side
            width: Theme.grow(Theme.panelMd)
            // the layer already sits below the bar's exclusive zone: spaceXs
            // below it, windowGap in from the right edge
            y: Theme.spaceXs
            x: parent.width - width - Theme.windowGap
            // ONE height for every page — half the screen (the rail sets the
            // floor, the card's 80% the ceiling) — so switching pages never
            // moves the panel's bottom edge; a longer page scrolls inside.
            readonly property real railNeed: railTop.implicitHeight + railBottom.implicitHeight + 3 * pad
            readonly property real maxH: Math.min((win.screen ? win.screen.height : parent.height) * 0.8,
                                                  parent.height - Theme.spaceXs - Theme.windowGap)
            height: Math.min(maxH, Math.max((win.screen ? win.screen.height : parent.height) * 0.5, railNeed))
            radius: Theme.radiusRounded
            color: Theme.surfaceRaised
            border.color: Theme.borderSubtle
            border.width: Theme.borderWidth1
            clip: true
            layer.enabled: true
            layer.effect: Elevation {}
            // fade plus a slide in from the right edge, where the panel lives
            // — in at durBase, out at durFast, no overshoot; Reduce motion
            // keeps the fade only
            opacity: Globals.quickSettingsOpen ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: Globals.quickSettingsOpen ? Theme.durBase : Theme.durFast; easing.type: Theme.ease }
            }
            transform: Translate {
                x: (Globals.quickSettingsOpen || Theme.reduceMotion) ? 0 : panel.width + Theme.windowGap
                Behavior on x { NumberAnimation { duration: Globals.quickSettingsOpen ? Theme.durBase : Theme.durFast; easing.type: Theme.ease } }
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

            // ══ shared pieces: TextBody/TextStrong/TextCaption/TextMono, Glyph,
            //    QsNote, QsButton, QsIconButton, QsField(+Input), QsSegmented,
            //    QsSwitchRow, QsPageHead, QsEmpty, QsMsgRow — promoted to their own
            //    files in API 3 (public to plugins, docs/PLUGINS.md) ══

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
            //    pinned at its foot. The add-ons' pages follow the built-ins. ══
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
                            source: Qt.resolvedUrl("assets/ewe-mark.svg")
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
                            { key: "cal",    icon: Theme.icCalendar },
                            { key: "notifs", icon: Theme.icBell }
                        ]
                        delegate: RailBtn {
                            required property var modelData
                            ic: modelData.icon
                            current: root.tab === modelData.key
                            dot: modelData.key === "notifs" && Globals.server && Globals.server.trackedNotifications.values.length > 0
                            onGo: root.setTab(modelData.key)
                        }
                    }
                    // plugin pages (API 3 quick-page): after the built-ins, in
                    // manifest order; the icon is a Theme glyph NAME
                    Repeater {
                        model: PluginHost.quickPages
                        delegate: RailBtn {
                            required property var modelData
                            ic: Theme[modelData.icon] || Theme.icApps
                            current: root.tab === modelData.key
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
                    TextMono { anchors.verticalCenter: parent.verticalCenter; text: Math.round(parent.pct) + "%" }
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
                    // (VPN and SSH are the ewe.vpn / ewe.ssh add-ons' quick-tiles and pages)
                    Row {
                        visible: root.tab === "home"
                        width: parent.width; spacing: Theme.spaceS
                        Tile {
                            ic: Theme.icDnd; label: "Do not disturb"; active: Globals.dnd
                            sub: Globals.dnd ? "On" : "Off"
                            onClicked: Globals.dnd = !Globals.dnd
                        }
                        // (Insomnia — keep awake — is the ewe.insomnia add-on's quick-tile)
                    }
                    // (the CPU / memory meters are the ewe.sysmon add-on's span-2 quick-tile)
                    // ═══ plugin tiles (API 3 quick-tile): after the built-ins,
                    //     two per row (span 1) or the whole row (span 2), in
                    //     manifest order. The host sizes the Loader; the
                    //     plugin fills a Tile. ═══
                    Flow {
                        visible: root.tab === "home" && PluginHost.quickTiles.length > 0
                        width: parent.width; spacing: Theme.spaceS
                        Repeater {
                            model: PluginHost.quickTiles
                            delegate: Loader {
                                id: tileSlot
                                required property var modelData
                                width: modelData.span >= 2 ? parent.width : Math.floor((parent.width - Theme.spaceS) / 2)
                                source: "file://" + modelData.entry
                                readonly property bool shown: Globals.quickSettingsOpen && root.tab === "home"
                                onShownChanged: if (status === Loader.Ready && item && ("panelOpen" in item)) item.panelOpen = tileSlot.shown
                                onStatusChanged: {
                                    if (status === Loader.Error) Log.warn("plugins", modelData.id + "/quick-tile failed to load (see the qml error above)")
                                    else if (status === Loader.Ready) PluginHost.inject(item, modelData.id, { panelOpen: tileSlot.shown })
                                }
                                Connections { target: PluginHost; function onSettingsChanged() { if (tileSlot.status === Loader.Ready) PluginHost._giveSettings(tileSlot.item, tileSlot.modelData.id) } }
                            }
                        }
                    }

                    // ═══ SOUND: output and input devices ═══
                    Column {
                        visible: root.tab === "audio"
                        width: parent.width; spacing: Theme.spaceS
                        QsPageHead {
                            title: "Sound"
                            note: Pipewire.defaultAudioSink ? root.audioLabel(Pipewire.defaultAudioSink) : ""
                        }
                        // GNOME-style: one switch for every event chime
                        QsSwitchRow {
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
                        QsPageHead {
                            title: "Wi-Fi"
                            busy: wifiScan.running
                            hasSwitch: true; on: root.wifiOn
                            onToggled: { Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiOn ? "off" : "on"]); rescanTimer.restart() }
                        }
                        // WIRED — only when the machine has a port. The switch is
                        // the "I'm on Wi-Fi, ignore the cable" control; unplugged,
                        // it just says so.
                        QsSwitchRow {
                            visible: root.wiredPresent
                            ic: Theme.icEthernet; label: "Wired"
                            desc: root.wiredStateStr === "unavailable" ? "No cable"
                                : root.wiredConnecting || root.wiredBusy ? "Connecting…"
                                : root.wiredUp ? "Connected" : "Off"
                            busy: root.wiredBusy || root.wiredConnecting
                            on: root.wiredUp || root.wiredConnecting
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
                            TextCaption { anchors.verticalCenter: parent.verticalCenter; text: wifiScan.running ? "Looking for networks…" : "No networks found" }
                        }
                        QsEmpty {
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
                                        QsField {
                                            width: parent.width - pwJoin.width - parent.spacing
                                            focused: pwInput.activeFocus
                                            QsFieldInput {
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
                                            QsIconButton {
                                                anchors.right: parent.right; anchors.rightMargin: Theme.spaceXxs
                                                anchors.verticalCenter: parent.verticalCenter
                                                ic: root.pwShow ? Theme.icEyeOff : Theme.icEye
                                                selected: root.pwShow
                                                onGo: root.pwShow = !root.pwShow
                                            }
                                        }
                                        QsButton {
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
                        QsPageHead {
                            title: "Bluetooth"
                            busy: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering
                            note: (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering) ? "Searching…" : ""
                            hasSwitch: true
                            on: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false
                            switchDisabled: !Bluetooth.defaultAdapter
                            onToggled: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                        }
                        QsEmpty {
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
                                    QsIconButton {
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
                        QsNote { visible: BtAgent.lastError !== ""; tone: "danger"; text: BtAgent.lastError }
                        QsNote {
                            visible: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled && !BtAgent.registered
                            tone: "warning"
                            text: BtAgent.bridgeError !== "" ? BtAgent.bridgeError : "The pairing agent isn’t running yet. Devices that ask for a code can’t pair."
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
                            QsIconButton { id: calBack; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; size: "md"; ic: Theme.icBack; onGo: root.setTab("home") }
                            TextStrong {
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
                                    TextCaption {
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
                                    TextMono {
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
                                TextStrong { text: "Offline"; color: Theme.warning }
                                TextBody { width: parent.width; text: "Showing events from the last sync."; wrapMode: Text.Wrap }
                            }
                        }
                        QsEmpty {
                            visible: root.agenda.length === 0
                            ic: Theme.icCalendar
                            title: Agenda.hintTitle
                            desc: Agenda.hintBody
                            QsButton {
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
                                        TextMono {
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
                                            TextBody { width: parent.width; text: evRow.modelData.summary }
                                            TextCaption { visible: text !== ""; width: parent.width; text: root.eventMeta(evRow.modelData) }
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
                            QsIconButton { id: ntBack; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; size: "md"; ic: Theme.icBack; onGo: root.setTab("home") }
                            Text {
                                anchors.left: ntBack.right; anchors.leftMargin: Theme.spaceS
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Notifications"
                                color: Theme.textPrimary
                                font.family: Theme.type.h4.family
                                font.pixelSize: Theme.type.h4.size
                                font.weight: Theme.type.h4.weight
                            }
                            QsButton {
                                visible: parent.parent.any
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                size: "md"; variant: "ghost"; label: "Clear all"
                                onGo: root.clearAll()
                            }
                        }
                        QsSwitchRow {
                            ic: Theme.icDnd; label: "Do not disturb"
                            on: Globals.dnd
                            onToggled: Globals.dnd = !Globals.dnd
                        }
                        Rectangle { width: parent.width; height: Theme.borderWidth1; color: Theme.borderSubtle }
                        QsEmpty {
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
                                                TextCaption {
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
                                            QsIconButton {
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
                                                    TextStrong {
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
                                                    TextStrong { width: parent.width; text: nItem.modelData.summary || "" }
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
                                                QsIconButton {
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
                                TextCaption {
                                    id: nMore
                                    visible: nGroup.stacked
                                    anchors.top: nCard.bottom; anchors.topMargin: Theme.spaceS + Theme.spaceXs
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: (nGroup.count - 1) + " more from " + nGroup.modelData.app
                                }
                            }
                        }
                    }

                    // ═══ plugin pages (API 3 quick-page): one Column per
                    //     registered page, shown while its key is the tab —
                    //     the same way the built-in pages above are ═══
                    Repeater {
                        model: PluginHost.quickPages
                        delegate: Column {
                            id: pageSlot
                            required property var modelData
                            visible: root.tab === modelData.key
                            width: parent.width; spacing: Theme.spaceS
                            readonly property bool shown: Globals.quickSettingsOpen && root.tab === modelData.key
                            onShownChanged: if (pageLoader.status === Loader.Ready && pageLoader.item && ("panelOpen" in pageLoader.item)) pageLoader.item.panelOpen = pageSlot.shown
                            Loader {
                                id: pageLoader
                                width: parent.width
                                source: "file://" + pageSlot.modelData.entry
                                onStatusChanged: {
                                    if (status === Loader.Error) Log.warn("plugins", pageSlot.modelData.id + "/quick-page failed to load (see the qml error above)")
                                    else if (status === Loader.Ready) PluginHost.inject(item, pageSlot.modelData.id, { panelOpen: pageSlot.shown })
                                }
                                Connections { target: PluginHost; function onSettingsChanged() { if (pageLoader.status === Loader.Ready) PluginHost._giveSettings(pageLoader.item, pageSlot.modelData.id) } }
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
                    TextBody { anchors.verticalCenter: parent.verticalCenter; text: pit.label; color: (pit.danger && pitMa.containsMouse) ? Theme.danger : Theme.textPrimary }
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
                        QsSegmented {
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
                            QsButton { size: "md"; variant: "ghost"; label: "Cancel"; onGo: root.confirmAction = "" }
                            QsButton {
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
