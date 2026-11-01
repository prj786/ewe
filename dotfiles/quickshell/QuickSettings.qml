import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Notifications
import Quickshell.Bluetooth

// QuickSettings — the control centre (design system: Quick settings, Quick
// settings tile, Switch, Slider, Segmented control, List row, Section
// header, Agenda, Notification, Dialog, Empty state, Tooltip). The UI
// revamp of 2026-11 (owner-approved mockups Main / QsDetail / QsLight).
//
//   panel    panelSm wide (wider in step with Text size, Theme.grow),
//            surfaceRaised with a borderWidth1 borderSubtle outline, the
//            radiusRounded corner and the shadowFloat elevation, spaceXs
//            below the bar at the right edge, spaceS + spaceXs of padding and
//            between sections. Its HEIGHT FOLLOWS THE PAGE (up to 80% of the
//            screen; a longer page scrolls) — no empty band. Solid, never Glass.
//   motion   in: fade plus a slide from the right edge at durBase; out at
//            durFast; a page change resizes at durFast; OutCubic, and nothing
//            moves under Reduce motion
//   home     the head: you (avatar, name, today's date — opens ewe Sync),
//            then Screenshot · Settings · Lock · Power. The tiles (Tile.qml,
//            every one with its icon circle, on or off), two to a row; the
//            shortcut row of small tiles (Calendar, then every plugin page
//            no tile already opens); volume (its chevron opens the output
//            list) and brightness; the latest notifications inline (Show all
//            opens the full list); the foot: battery and power mode, each
//            only when the machine has it
//   pages    open IN PLACE of home — from a tile's chevron, a shortcut, the
//            volume chevron, Show all or the Power button: QsPageHead (back,
//            name over status, switch), sections under overline headers, a
//            foot with the page's actions. Esc goes back one page, then
//            closes the panel.
//
// Every page, shortcut and IPC command stays: `quicksettings toggle|show|
// hide|powerdialog|tab <name>`, where <name> is a built-in page (home wifi bt
// audio cal notifs remote power) or a plugin's quickPage.key — the same keys
// Shell.openQuickSettings(key) takes. There is no icon rail any more (it
// went in 0.39): a plugin page is a shortcut tile, unless the plugin's own
// tile is on home and opens it from its chevron.
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

    // ── pages ──────────────────────────────────────────────────────────────
    // home is the control centre itself; every list lives on its own page,
    // which opens in place of home. `expanded` survives as a read-only alias
    // so the page `visible`s below read the same as before the revamp.
    property string tab: "home"
    readonly property string expanded: tab === "home" ? "" : tab
    Connections { target: Globals; function onQuickSettingsTabRequested(name) { root.setTab(name) } }
    // the pages the shell itself has; anything else is an add-on's quickPage.key
    readonly property var builtinTabs: ["home", "wifi", "bt", "audio", "cal", "notifs", "remote", "power"]
    function hasTab(t) {
        if (root.builtinTabs.indexOf(t) >= 0) return true
        var ps = PluginHost.quickPages
        for (var i = 0; i < ps.length; i++) if (ps[i].key === t) return true
        return false
    }
    function setTab(t) {
        // Rule 4: `quicksettings tab vpn` (an old keybind, a script) with the
        // VPN add-on not installed must not open an empty panel — fall back
        // to home, and say which add-on would have answered.
        if (!root.hasTab(t)) {
            Log.info("quicksettings", "tab", t, "— no such page (a plugin that is not installed?); showing home")
            t = "home"
        }
        if (t !== "bt" && Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = false
        if (t !== "wifi") root.hiddenOpen = false
        root.tab = t
        if (t === "wifi") { wifiScan.running = true; wifiSavedScan.running = true }
        if (t === "bt" && Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = true
        root.pageShown()
    }
    // every page starts at its top, with the keyboard on the panel (Esc)
    signal pageShown()

    // ── you: the account row of the head ──────────────────────────────────
    // the passwd entry's full name (what Settings → Account edits), else the
    // login name
    property string userName: Quickshell.env("USER") || ""
    Process {
        running: true
        command: ["sh", "-c", 'getent passwd "$USER" | cut -d: -f5 | cut -d, -f1']
        stdout: StdioCollector { onStreamFinished: { var t = this.text.trim(); if (t !== "") root.userName = t } }
    }
    // the account entry: ewe Sync (your machines, folders, conflicts) — the
    // same door as the bar's sync glyph; Settings when ewe Sync is missing
    function openAccount() {
        Globals.quickSettingsOpen = false
        if (Globals.syncAppInstalled) Globals.openSync()
        else Globals.openSettings()
    }
    // Screenshot: the screenshot plugin's region capture, once the panel is
    // out of the way. No plugin → no button (it is what owns the Print keys).
    readonly property var shotPlugin: {
        var o = PluginHost.instances["ewe.screenshot"]
        return (o && o.panel && typeof o.panel.shoot === "function") ? o.panel : null
    }
    function screenshot() {
        Globals.quickSettingsOpen = false
        shotTimer.restart()
    }
    Timer { id: shotTimer; interval: Math.max(1, Theme.durBase + Theme.durSlow); onTriggered: if (root.shotPlugin) root.shotPlugin.shoot("region") }

    // ── the shortcut row ──────────────────────────────────────────────────
    // Calendar, then every plugin page (quickPage) in manifest order — minus
    // the pages a plugin's own tile already opens from its chevron (VPN, Cast,
    // SSH with hosts): a page is never offered twice, and never not at all.
    // `tileOpens` is read off the home grid (readTiles): a tile's slot is
    // hidden by the plugin when it has nothing to say (SSH with no hosts), and
    // then its page comes back here.
    property var tileOpens: ({})
    readonly property var shortcuts: {
        var out = [{ key: "cal", label: "Calendar", icon: Theme.icCalendar }]
        var ps = PluginHost.quickPages
        for (var i = 0; i < ps.length; i++)
            if (!root.tileOpens[ps[i].id] && root.builtinTabs.indexOf(ps[i].key) < 0)
                out.push({ key: ps[i].key, label: ps[i].label, icon: Theme[ps[i].icon] || Theme.icApps })
        return out
    }

    // ── the foot: battery and power mode ──────────────────────────────────
    readonly property var batt: UPower.displayDevice
    readonly property bool hasBattery: !!(root.batt && root.batt.isLaptopBattery)
    readonly property real battPct: root.batt ? (root.batt.percentage <= 1 ? root.batt.percentage * 100 : root.batt.percentage) : 0
    readonly property bool battCharging: !!root.batt && (root.batt.state === UPowerDeviceState.Charging || root.batt.state === UPowerDeviceState.FullyCharged)
    // "100% · Fully charged", "64% · 3 h 5 min left", "80% · 40 min to full"
    readonly property string battText: {
        if (!root.hasBattery) return ""
        var d = root.batt, s = d.state, tail = ""
        if (s === UPowerDeviceState.FullyCharged) tail = "Fully charged"
        else if (s === UPowerDeviceState.Charging) tail = d.timeToFull > 0 ? root.fmtDuration(Math.round(d.timeToFull / 60)) + " to full" : "Charging"
        else if (s === UPowerDeviceState.Discharging) tail = d.timeToEmpty > 0 ? root.fmtDuration(Math.round(d.timeToEmpty / 60)) + " left" : "On battery"
        else if (s === UPowerDeviceState.PendingCharge) tail = "Not charging"
        return Math.round(root.battPct) + "%" + (tail !== "" ? " · " + tail : "")
    }
    // power-profiles-daemon (or tuned-ppd) answering on the system bus —
    // Power.qml's one-shot probe, re-run each time the panel opens
    readonly property bool hasModes: Power.ppdRunning
    Component.onCompleted: { portScan.running = true; Power.refresh() }

    // wifi
    property var wifiList: []
    property bool wifiOn: true
    property string pwTarget: ""
    property bool pwShow: false        // reveal the Wi-Fi password while typing
    property string pwText: ""
    property bool hiddenOpen: false    // the "Hidden network…" form
    function curSsid() { for (var i = 0; i < wifiList.length; i++) if (wifiList[i].active) return wifiList[i].ssid; return "" }
    // the network we are on: the scanned list knows the SSID; before the
    // first scan the profile's name is the best there is
    function wifiName() {
        var ssid = root.curSsid()
        if (ssid === "" && NetState.wifi && NetState.wifi.state === "connected") ssid = NetState.wifi.connection.trim()
        return ssid
    }

    // sliders (0..1), read on open, updated optimistically on drag
    property real brightnessVal: 0.5
    property real volumeVal: 0.5
    // a backlight to drive: logind names one, or brightnessctl found one
    property bool brightnessFound: false
    readonly property bool hasBrightness: Logind.hasBacklight || root.brightnessFound

    function refresh() {
        var d = new Date()
        Globals.openDd = ""   // never reopen with a stale dropdown expanded
        root.today = d; root.calYear = d.getFullYear(); root.calMonth = d.getMonth(); root.calDate = d.getDate()
        root.nowMs = Date.now()
        wifiState.running = true; brightnessProc.running = true; volumeProc.running = true; wifiSavedScan.running = true
        if (root.expanded === "wifi") wifiScan.running = true
        NetState.panelOpened()     // a fresh connectivity verdict + Tailscale
        Power.refresh()
    }
    function clearAll() {
        if (!Globals.server) return
        var v = Globals.server.trackedNotifications.values.slice()
        for (var i = 0; i < v.length; i++) v[i].dismiss()
    }

    // ── notifications, grouped by app ─────────────────────────────────────
    // One card per app, the app that spoke last first; a card holding several
    // notifications expands/collapses on click (nExpanded holds the app whose
    // card is open on the full list). Home shows the newest two cards.
    property string nExpanded: ""
    readonly property int noteCount: Globals.server ? Globals.server.trackedNotifications.values.length : 0
    readonly property var noteGroups: {
        var vals = (Globals.server ? Globals.server.trackedNotifications.values : []) || []
        var by = {}, order = [], last = {}, out = []
        for (var i = 0; i < vals.length; i++) {
            var k = String(vals[i].appName || "Notification")
            if (!by[k]) { by[k] = []; order.push(k) }
            by[k].push(vals[i])
            last[k] = i
        }
        order.sort(function (a, b) { return last[b] - last[a] })
        for (var j = 0; j < order.length; j++) {
            var items = by[order[j]]
            out.push({ app: order[j], items: items, latest: items[items.length - 1] })
        }
        return out
    }
    // arrival times, keyed by notification id — the protocol carries none,
    // and a card's head says how long ago ("now", "2 min", "14:05")
    property var arrived: ({})
    property double nowMs: Date.now()
    Connections {
        target: Globals.server
        function onNotification(n) { root.arrived[n.id] = Date.now() }
    }
    Timer { interval: 30000; repeat: true; running: Globals.quickSettingsOpen && root.noteCount > 0; onTriggered: root.nowMs = Date.now() }
    function noteTime(n) {
        var t = root.arrived[n.id]
        if (t === undefined) return "now"
        var mins = Math.floor((root.nowMs - t) / 60000)
        if (mins < 1) return "now"
        if (mins < 60) return mins + " min"
        var d = new Date(t), today = new Date(root.nowMs)
        return d.toDateString() === today.toDateString() ? Qt.formatTime(d, "hh:mm") : Qt.formatDateTime(d, "d MMM")
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
    // a network that does not broadcast its name: NetworkManager makes a
    // profile with `hidden yes`, so it rejoins by itself from then on
    function joinHidden(ssid, pw) {
        ssid = String(ssid).trim()
        if (ssid === "") return
        var cmd = ["nmcli", "device", "wifi", "connect", ssid]
        if (pw !== "") cmd = cmd.concat(["password", pw])
        cmd = cmd.concat(["hidden", "yes"])
        root.wifiPending = ssid
        root.wifiConfirm = ""
        Globals.netBusy = "wifi"
        wifiConnProc.command = cmd
        wifiConnProc.running = true
        root.hiddenOpen = false
    }
    // logind writes the backlight for us (no udev rule, no setuid helper); fall
    // back to brightnessctl when the bridge is down or the machine has no
    // backlight device logind will accept
    function setBrightness(v) {
        root.brightnessVal = v
        if (Logind.setBrightness(v)) return
        Quickshell.execDetached(["brightnessctl", "-c", "backlight", "set", Math.round(v * 100) + "%"])
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
    // Suspend) run immediately. Lock is the head's own button; the rest are
    // the Power page (the head's power button).
    property string confirmAction: ""   // "" = no confirmation showing
    property string confirmTitle: ""
    property string confirmVerb: ""
    function runPower(action) {
        Quickshell.execDetached(["sh", "-c", "exec \"$HOME/.config/hypr/scripts/power.sh\" " + action])
        root.confirmAction = ""; Globals.quickSettingsOpen = false
    }
    function askPower(action, title, verb) {
        root.confirmTitle = title; root.confirmVerb = verb; root.confirmAction = action
    }

    Connections { target: Globals; function onQuickSettingsOpenChanged() { if (Globals.quickSettingsOpen) { root.tab = "home"; root.nExpanded = ""; root.refresh(); root.pageShown() } } }
    // Super+N and the power button — `hl.dsp.global("ewe:quicksettings")` /
    // `("ewe:power")` in hyprland.lua: delivered over the global-shortcuts
    // protocol, no process per press (Launcher.qml). The IPC verbs below stay
    // for scripts.
    GlobalShortcut {
        appid: "ewe"; name: "quicksettings"
        description: "Toggle Quick settings"
        onPressed: Globals.quickSettingsOpen = !Globals.quickSettingsOpen
    }
    GlobalShortcut {
        appid: "ewe"; name: "power"
        description: "Shut down (confirmation)"
        onPressed: { Globals.quickSettingsOpen = true; root.askPower("poweroff", "Shut down this computer?", "Shut down") }
    }
    IpcHandler {
        target: "quicksettings"
        function toggle(): void { Globals.quickSettingsOpen = !Globals.quickSettingsOpen }
        function show(): void { Globals.quickSettingsOpen = true }
        function hide(): void { Globals.quickSettingsOpen = false }
        // Power-button press (XF86PowerOff bind in hyprland.lua; logind ignores
        // the key so a stray tap can't hard-poweroff): open the panel with the
        // shutdown confirmation already up.
        function powerdialog(): void { Globals.quickSettingsOpen = true; root.askPower("poweroff", "Shut down this computer?", "Shut down") }
        // jump straight to a page (also how the test driver screenshots them)
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
    // the wired port, the connectivity verdict, VPNs and Tailscale: NetState
    // (one reading for the bar and this panel — see NetState.qml)
    // `-c backlight`: a desktop has no backlight, and brightnessctl's
    // fallback device would be a keyboard LED — no slider for that
    Process {
        id: brightnessProc
        command: ["sh", "-c", "brightnessctl -m -c backlight 2>/dev/null | head -n 1 | cut -d, -f4 | tr -d '%'"]
        stdout: StdioCollector { onStreamFinished: { var n = parseInt(this.text.trim()); root.brightnessFound = !isNaN(n); if (!isNaN(n)) root.brightnessVal = n / 100 } }
    }
    Process { id: volumeProc; command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oE '[0-9]+\\.[0-9]+'"]; stdout: StdioCollector { onStreamFinished: { var f = parseFloat(this.text.trim()); if (!isNaN(f)) root.volumeVal = Math.min(1, f) } } }
    Timer { id: rescanTimer; interval: 2500; onTriggered: { wifiState.running = true; wifiScan.running = true } }
    // the network we just joined, until a list read shows it IN-USE
    property string wifiConfirm: ""
    Timer { id: wifiConfirmTimer; interval: 4000; onTriggered: { root.wifiConfirm = ""; root.wifiPending = "" } }
    // NetworkManager events (NetState's `nmcli monitor`) — re-read while the
    // panel is open instead of waiting for the 6 s poll; this is what makes a
    // cable plug or a Wi-Fi join show at once
    Connections {
        target: Globals
        function onNetEpochChanged() {
            if (!Globals.quickSettingsOpen) return
            wifiState.running = true
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
                wifiScan.running = true; wifiSavedScan.running = true
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
    Timer { interval: 6000; running: Globals.quickSettingsOpen; repeat: true; onTriggered: { wifiState.running = true; if (root.expanded === "wifi") wifiScan.running = true } }

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
            else closeTimer.restart()
        } }
        MouseArea { anchors.fill: parent; onClicked: Globals.quickSettingsOpen = false }

        Rectangle {
            id: panel
            readonly property int pad: Theme.spaceS + Theme.spaceXs
            readonly property bool onHome: root.tab === "home"
            // grows with Text size, so two tiles still fit side by side
            width: Theme.grow(Theme.panelSm)
            // the layer already sits below the bar's exclusive zone: spaceXs
            // below it, windowGap in from the right edge
            y: Theme.spaceXs
            x: parent.width - width - Theme.windowGap
            // the page's own height, up to 80% of the screen (a longer page
            // scrolls inside); never shorter than a confirmation on top of it
            readonly property real maxH: Math.min((win.screen ? win.screen.height : parent.height) * 0.8,
                                                  parent.height - Theme.spaceXs - Theme.windowGap)
            height: Math.min(maxH, Math.max(body.implicitHeight + 2 * pad,
                                            root.confirmAction !== "" ? cfCard.height + 2 * Theme.spaceMd : 0))
            // a page change resizes at durFast — not while the panel fades in,
            // so it opens at its size
            Behavior on height {
                enabled: !Theme.reduceMotion && panel.opacity === 1
                NumberAnimation { duration: Theme.durFast; easing.type: Theme.ease }
            }
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

            // catches Esc: the confirmation first, then back one page, then
            // the panel (Quick settings is otherwise mouse-driven)
            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: {
                    if (root.confirmAction !== "") root.confirmAction = ""
                    else if (root.tab !== "home") root.setTab("home")
                    else Globals.quickSettingsOpen = false
                }
            }
            Connections {
                target: root
                function onPageShown() { flick.contentY = 0; panel.hint(null, false, ""); keyCatcher.forceActiveFocus() }
                // the password row going away hands the keyboard back
                function onPwTargetChanged() { if (root.pwTarget === "") keyCatcher.forceActiveFocus() }
            }

            // ══ shared pieces: TextBody/TextStrong/TextCaption/TextMono, Glyph,
            //    QsNote, QsButton, QsIconButton, QsField(+Input), QsSegmented,
            //    QsSwitchRow, QsPageHead, QsEmpty, QsMsgRow — promoted to their own
            //    files in API 3 (public to plugins, docs/PLUGINS.md) ══

            // ── Tooltip: names an icon-only control (the head's buttons, the
            //    shortcut tiles, the power modes) after 500 ms of hover —
            //    at once when a neighbour's was just showing ──
            property Item tipItem: null
            property string tipText: ""
            function hint(item, on, text) {
                if (on && item) {
                    panel.tipItem = item; panel.tipText = text
                    if (tipWarm.running || tipBox.shown) tipBox.place()
                    else tipDelay.restart()
                } else if (!item || panel.tipItem === item) {
                    if (tipBox.shown) tipWarm.restart()
                    tipDelay.stop(); tipBox.shown = false; panel.tipItem = null
                }
            }
            Timer { id: tipDelay; interval: 500; onTriggered: tipBox.place() }   // the Tooltip spec's hover delay
            Timer { id: tipWarm; interval: 500 }

            // ── a page's foot: a borderWidth1 rule, spaceXs, then its actions
            //    (`start` on the left, the rest on the right) ──
            component PageFoot: Item {
                id: pf
                default property alias end: pfEnd.data
                property alias start: pfStart.data
                width: parent ? parent.width : Theme.panelSm
                height: Theme.borderWidth1 + Theme.spaceXs + Theme.controlSm
                Rectangle { width: parent.width; height: Theme.borderWidth1; color: Theme.borderSubtle }
                Row { id: pfStart; anchors.left: parent.left; anchors.bottom: parent.bottom; spacing: Theme.spaceS }
                Row { id: pfEnd; anchors.right: parent.right; anchors.bottom: parent.bottom; spacing: Theme.spaceS }
            }

            // ── one app's notifications (Notification, grouped): a flat card
            //    (surfaceOverlay, no shadow) with the newest on top and two
            //    spaceXs layers peeking out below it for the rest, "N more from
            //    App" under them. On the full list a stack opens in place; on
            //    home it opens the full list with that app open. ──
            component NoteGroup: Item {
                id: nGroup
                property var group: ({ app: "", items: [], latest: null })
                property bool inline: false
                readonly property int count: nGroup.group.items.length
                readonly property bool open: !nGroup.inline && nGroup.count > 1 && root.nExpanded === nGroup.group.app
                readonly property bool stacked: nGroup.count > 1 && !nGroup.open
                readonly property var latest: nGroup.group.latest
                readonly property bool critical: !!nGroup.latest && nGroup.latest.urgency === NotificationUrgency.Critical
                // the open card lists the newest first
                readonly property var newestFirst: nGroup.group.items.slice().reverse()
                width: parent ? parent.width : Theme.panelSm
                height: nCard.height + (nGroup.stacked ? 2 * Theme.spaceXs + Theme.spaceS + nMore.height : 0)

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

                Rectangle {
                    id: nCard
                    width: parent.width
                    height: gCol.implicitHeight + Theme.spaceS + Theme.spaceS + Theme.spaceXs
                    radius: Theme.radiusRounded
                    color: nCardMa.containsMouse ? Theme.surfaceHover : Theme.surfaceOverlay
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
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
                            if (nGroup.count > 1 && nGroup.inline) { root.nExpanded = nGroup.group.app; root.setTab("notifs") }
                            else if (nGroup.count > 1) root.nExpanded = nGroup.open ? "" : nGroup.group.app
                            else root.noteFocus(nGroup.latest)
                        }
                    }
                    Column {
                        id: gCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.leftMargin: Theme.spaceS + Theme.spaceXs; anchors.rightMargin: Theme.spaceS + Theme.spaceXs
                        anchors.topMargin: Theme.spaceS
                        spacing: Theme.spaceXs

                        // head: the app's icon and name · how long ago, a chevron
                        // on a stack of the full list, close on hover
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
                                        source: (nGroup.latest && nGroup.latest.appIcon && nGroup.latest.appIcon != "")
                                                ? Quickshell.iconPath(nGroup.latest.appIcon, "dialog-information")
                                                : Quickshell.iconPath("dialog-information")
                                    }
                                }
                                TextCaption {
                                    id: nApp
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, parent.width - Theme.iconMd - nWhen.width - 2 * parent.spacing - (nChev.visible ? nChev.width + parent.spacing : 0))
                                    text: nGroup.group.app
                                    color: Theme.textSecondary
                                    font.weight: Theme.fontWeightMedium
                                }
                                TextCaption {
                                    id: nWhen
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: nGroup.latest ? "· " + root.noteTime(nGroup.latest) : ""
                                }
                                Glyph {
                                    id: nChev
                                    visible: nGroup.count > 1 && !nGroup.inline
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
                                onGo: root.dismissAllOf(nGroup.group.items)
                            }
                        }

                        // collapsed: the newest one
                        Row {
                            visible: !nGroup.open && !!nGroup.latest
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
                                        text: nGroup.latest ? (nGroup.latest.summary || "") : ""
                                        color: nGroup.critical ? Theme.danger : Theme.textPrimary
                                    }
                                }
                                Text {
                                    visible: text.length > 0
                                    width: parent.width
                                    text: nGroup.latest ? (nGroup.latest.body || "") : ""
                                    color: Theme.textSecondary
                                    font.family: Theme.type.body.family
                                    font.pixelSize: Theme.type.body.size
                                    wrapMode: Text.Wrap; maximumLineCount: nGroup.inline ? 2 : 3; elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                }
                            }
                            Rectangle {
                                id: nMedia
                                visible: !!nGroup.latest && !!nGroup.latest.image && nGroup.latest.image != ""
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

                        // open: every notification of the app, newest first, divided
                        Repeater {
                            model: nGroup.open ? nGroup.newestFirst : []
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
                    anchors.top: nCard.bottom; anchors.topMargin: 2 * Theme.spaceXs + Theme.spaceS
                    anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                    text: (nGroup.count - 1) + " more from " + nGroup.group.app
                }
            }

            Column {
                id: body
                x: panel.pad; y: panel.pad
                width: panel.width - 2 * panel.pad
                spacing: panel.pad

                // ══ the head (home): you — the avatar, your name and today's
                //    date, a door to ewe Sync — then Screenshot · Settings ·
                //    Lock · Power ══
                Item {
                    id: head
                    visible: panel.onHome
                    width: parent.width
                    height: Math.max(Theme.controlLg, whoCol.implicitHeight)
                    Rectangle {
                        id: you
                        // the hover plate reaches spaceXs past the avatar and
                        // the text; every width here comes from the text's own
                        // and the buttons' place, never from this plate (a
                        // cycle through a Row's implicit width spins the shell)
                        readonly property real textW: Math.max(0, Math.min(Math.max(whoName.implicitWidth, whoDate.implicitWidth),
                                                                           headActs.x - 3 * Theme.spaceXs - Theme.controlLg - Theme.spaceS))
                        x: -Theme.spaceXs
                        width: Theme.controlLg + Theme.spaceS + you.textW + 3 * Theme.spaceXs
                        height: parent.height + 2 * Theme.spaceXxs
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Theme.radiusPrimary
                        color: youMa.pressed ? Theme.surfacePressed : youMa.containsMouse ? Theme.surfaceHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        Row {
                            id: youRow
                            x: Theme.spaceXs
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spaceS
                            Avatar {
                                anchors.verticalCenter: parent.verticalCenter
                                size: Theme.controlLg
                                initial: root.userName.length > 0 ? root.userName.charAt(0).toUpperCase() : ""
                                ringColor: Theme.surfaceRaised
                            }
                            Column {
                                id: whoCol
                                anchors.verticalCenter: parent.verticalCenter
                                width: you.textW
                                TextStrong { id: whoName; width: parent.width; text: root.userName }
                                // the Writing guide's heading date: "Sunday, 1 November"
                                TextCaption { id: whoDate; width: parent.width; text: Qt.formatDateTime(root.today, "dddd, d MMMM") }
                            }
                        }
                        MouseArea {
                            id: youMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openAccount()
                            onContainsMouseChanged: panel.hint(you, containsMouse, Globals.syncAppInstalled ? "Open ewe Sync" : "Open ewe Settings")
                        }
                    }
                    Row {
                        id: headActs
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spaceXs
                        QsIconButton {
                            id: shotBtn
                            visible: root.shotPlugin !== null
                            size: "md"; ic: Theme.icCamera
                            onGo: root.screenshot()
                            onHoveredChanged: panel.hint(shotBtn, hovered, "Take a screenshot")
                        }
                        QsIconButton {
                            id: setBtn
                            size: "md"; ic: Theme.icCog
                            onGo: { Globals.quickSettingsOpen = false; Globals.openSettings() }
                            onHoveredChanged: panel.hint(setBtn, hovered, "Open ewe Settings")
                        }
                        QsIconButton {
                            id: lockBtn
                            size: "md"; ic: Theme.icLock
                            onGo: root.runPower("lock")
                            onHoveredChanged: panel.hint(lockBtn, hovered, "Lock")
                        }
                        QsIconButton {
                            id: powBtn
                            size: "md"; ic: Theme.icPower
                            onGo: root.setTab("power")
                            onHoveredChanged: panel.hint(powBtn, hovered, "Power")
                        }
                    }
                }

                Flickable {
                    id: flick
                    width: parent.width
                    // the page's height while it fits; the rest of 80% of the
                    // screen, scrolling, when it does not
                    height: Math.min(inner.implicitHeight,
                                     panel.maxH - 2 * panel.pad
                                     - (head.visible ? head.height + body.spacing : 0)
                                     - (foot.visible ? foot.height + body.spacing : 0))
                    contentHeight: inner.implicitHeight
                    interactive: contentHeight > height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: inner
                        width: flick.width
                        spacing: panel.pad

                        // ═══ HOME ═══
                        Column {
                            id: homePage
                            visible: root.tab === "home"
                            width: parent.width
                            spacing: panel.pad
                            onVisibleChanged: if (visible) Qt.callLater(root.readTiles)

                            // the tiles: a tile's body toggles, its chevron opens
                            // the matching page. The built-ins (Wi-Fi, Bluetooth,
                            // Do not disturb, Sharing) come first, then the
                            // plugins' quick-tiles (API 3) in manifest order,
                            // flowing two per row (span 1) or a whole row (span 2).
                            Flow {
                                id: homeGrid
                                width: parent.width; spacing: Theme.spaceS
                                Tile {
                                    // follows the link that CARRIES traffic (NetState):
                                    // the cable's glyph when a cable is the default route
                                    // — even with Wi-Fi up — or is still waiting for an
                                    // address; Wi-Fi's otherwise. Its second line says
                                    // what is wrong first, then where you are.
                                    readonly property bool onWired: NetState.uplinkType === "ethernet"
                                                                 || (NetState.uplink === null && NetState.wiredWaiting)
                                    ic: onWired ? Theme.icEthernet : Theme.icWifi
                                    label: NetState.wiredUp || NetState.wiredWaiting ? "Network" : "Wi-Fi"
                                    active: root.wifiOn || NetState.wiredUp       // on = the radio or the link is up
                                    hasMenu: true
                                    busy: root.wifiPending !== "" || (NetState.uplink === null && NetState.wiredWaiting)
                                    // joining: say so, and where to. Both links up: say both —
                                    // the one carrying traffic first
                                    sub: {
                                        if (root.wifiPending !== "") return "Joining " + root.wifiPending + "…"
                                        var ssid = root.wifiName()
                                        var name = NetState.uplinkType === "ethernet" ? "Wired"
                                                 : NetState.uplinkType === "wifi" ? (ssid !== "" ? ssid : "Wi-Fi") : ""
                                        if (NetState.portal) return "Sign in to this network"
                                        // the VPN in the way is named on the page ("No internet through …")
                                        if (NetState.noInternet) return (NetState.activeVpn ? NetState.activeVpn.name : name) + " · no internet"
                                        if (name === "Wired" && ssid !== "") return "Wired · " + ssid
                                        if (name !== "" && NetState.uplinkType === "wifi" && NetState.wiredUp) return name + " · Wired"
                                        if (name !== "") return name
                                        if (NetState.wiredWaiting) return "Waiting for an address"
                                        return root.wifiOn ? "On" : "Off"
                                    }
                                    // body = the switch (no list needed to turn Wi-Fi off);
                                    // details = the network list
                                    onClicked: { Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiOn ? "off" : "on"]); rescanTimer.restart() }
                                    onMenu: root.setTab("wifi")
                                }
                                Tile {
                                    ic: Theme.icBluetooth; label: "Bluetooth"
                                    active: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false
                                    disabled: !Bluetooth.defaultAdapter
                                    hasMenu: true
                                    sub: !Bluetooth.defaultAdapter ? "No adapter"
                                       : !Bluetooth.defaultAdapter.enabled ? "Off"
                                       : (root.btConnectedName() !== "" ? root.btConnectedName() : "On")
                                    onClicked: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                                    onMenu: root.setTab("bt")
                                }
                                Tile {
                                    ic: Theme.icDnd; label: "Do not disturb"; active: Globals.dnd
                                    sub: Globals.dnd ? "On" : "Off"
                                    onClicked: Globals.dnd = !Globals.dnd
                                }
                                // Remote (RFC-009). Turning sharing ON is never one
                                // stray click: off → the page (switch + what it means);
                                // on → off in one click (the safe direction)
                                Tile {
                                    ic: Theme.icShare; label: "Sharing"
                                    active: RemoteState.sharing
                                    hasMenu: true
                                    busy: RemoteState.busy === "share"
                                    sub: !RemoteState.sharing ? "Off"
                                       : RemoteState.connectedCount > 0 ? RemoteState.connectedNames + " connected"
                                       : "On · " + RemoteState.codeDisplay
                                    onClicked: RemoteState.sharing ? RemoteState.setSharing(false) : root.setTab("remote")
                                    onMenu: root.setTab("remote")
                                }
                                // the plugins' tiles: the host sizes the Loader (half
                                // the row, or all of it for span 2); the plugin fills
                                // a Tile, and hides its slot when it has nothing to say
                                Repeater {
                                    id: tileRep
                                    model: PluginHost.quickTiles
                                    delegate: Loader {
                                        id: tileSlot
                                        required property var modelData
                                        width: modelData.span >= 2 ? parent.width : Math.floor((parent.width - Theme.spaceS) / 2)
                                        source: "file://" + modelData.entry
                                        readonly property bool shown: Globals.quickSettingsOpen && root.tab === "home"
                                        onShownChanged: if (status === Loader.Ready && item && ("panelOpen" in item)) item.panelOpen = tileSlot.shown
                                        onVisibleChanged: Qt.callLater(root.readTiles)
                                        onStatusChanged: {
                                            if (status === Loader.Error) Log.warn("plugins", modelData.id + "/quick-tile failed to load (see the qml error above)")
                                            else if (status === Loader.Ready) { PluginHost.inject(item, modelData.id, { panelOpen: tileSlot.shown }); Qt.callLater(root.readTiles) }
                                        }
                                        Connections { target: PluginHost; function onSettingsChanged() { if (tileSlot.status === Loader.Ready) PluginHost._giveSettings(tileSlot.item, tileSlot.modelData.id) } }
                                    }
                                }
                            }

                            // the shortcut row: small tiles for the pages no tile
                            // opens — Calendar, then the plugins' (SSH, Mobile,
                            // Mail…). Four to six to a row, wrapping after six.
                            Flow {
                                id: shortRow
                                width: parent.width; spacing: Theme.spaceS
                                readonly property int cols: Math.max(4, Math.min(6, root.shortcuts.length))
                                readonly property real cell: Math.floor((width - (cols - 1) * spacing) / cols)
                                Repeater {
                                    model: root.shortcuts
                                    delegate: Tile {
                                        id: shortTile
                                        required property var modelData
                                        small: true
                                        width: shortRow.cell
                                        ic: modelData.icon
                                        label: modelData.label
                                        onClicked: root.setTab(modelData.key)
                                        HoverHandler { onHoveredChanged: panel.hint(shortTile, hovered, shortTile.modelData.label) }
                                    }
                                }
                            }

                            // volume (its chevron: the output list) and brightness
                            Column {
                                width: parent.width
                                spacing: Theme.spaceS
                                Row {
                                    width: parent.width
                                    spacing: Theme.spaceXs
                                    Slider {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - volMore.width - parent.spacing
                                        live: true
                                        icon: root.volumeVal <= 0 ? Theme.icVolMute : root.volumeVal < 0.5 ? Theme.icVolLow : Theme.icVolHigh
                                        showValue: true
                                        valueText: Math.round(root.volumeVal * 100) + "%"
                                        value: root.volumeVal
                                        onMoved: function (v) { root.setVolume(v) }
                                    }
                                    QsIconButton {
                                        id: volMore
                                        anchors.verticalCenter: parent.verticalCenter
                                        ic: Theme.icChevronRight
                                        onGo: root.setTab("audio")
                                        onHoveredChanged: panel.hint(volMore, hovered, Pipewire.defaultAudioSink ? "Sound output: " + root.audioLabel(Pipewire.defaultAudioSink) : "Sound output")
                                    }
                                }
                                Row {
                                    visible: root.hasBrightness
                                    width: parent.width
                                    spacing: Theme.spaceXs
                                    Slider {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - Theme.controlSm - parent.spacing
                                        live: true
                                        icon: Theme.icSun
                                        showValue: true
                                        valueText: Math.round(root.brightnessVal * 100) + "%"
                                        value: root.brightnessVal
                                        onMoved: function (v) { root.setBrightness(v) }
                                    }
                                }
                            }

                            // the latest notifications, inline: the newest two
                            // apps' cards; Show all opens the full list
                            Column {
                                width: parent.width
                                spacing: Theme.spaceS
                                Item {
                                    width: parent.width; height: Theme.controlSm
                                    SectionTitle {
                                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                        topPadding: 0; bottomPadding: 0
                                        text: "Notifications"
                                    }
                                    Row {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spaceXs
                                        QsButton { visible: root.noteCount > 0; variant: "ghost"; label: "Show all"; onGo: root.setTab("notifs") }
                                        QsButton { visible: root.noteCount > 0; variant: "ghost"; label: "Clear all"; onGo: root.clearAll() }
                                    }
                                }
                                TextCaption {
                                    visible: root.noteCount === 0
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: Globals.dnd ? "No notifications. Banners are hidden while Do not disturb is on." : "No notifications"
                                }
                                Repeater {
                                    model: root.tab === "home" ? root.noteGroups.slice(0, 2) : []
                                    delegate: NoteGroup {
                                        required property var modelData
                                        group: modelData
                                        inline: true
                                    }
                                }
                            }
                        }

                        // ═══ REMOTE: share this computer, your computers (RFC-009) ═══
                        RemotePage {
                            visible: root.tab === "remote"
                            width: parent.width
                        }

                        // ═══ SOUND: output and input devices ═══
                        Column {
                            visible: root.tab === "audio"
                            width: parent.width; spacing: panel.pad
                            QsPageHead {
                                title: "Sound"
                                note: Pipewire.defaultAudioSink ? root.audioLabel(Pipewire.defaultAudioSink) : ""
                            }
                            Slider {
                                width: parent.width
                                live: true
                                icon: root.volumeVal <= 0 ? Theme.icVolMute : root.volumeVal < 0.5 ? Theme.icVolLow : Theme.icVolHigh
                                showValue: true
                                valueText: Math.round(root.volumeVal * 100) + "%"
                                value: root.volumeVal
                                onMoved: function (v) { root.setVolume(v) }
                            }
                            Column {
                                width: parent.width; spacing: Theme.spaceXs
                                SectionTitle { text: "Output"; leftPadding: Theme.spaceS }
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
                            }
                            Column {
                                width: parent.width; spacing: Theme.spaceXs
                                SectionTitle { text: "Input"; leftPadding: Theme.spaceS }
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
                            // GNOME-style: one switch for every event chime
                            QsSwitchRow {
                                ic: Theme.icBellRing; label: "Event sounds"
                                on: Globals.eventSounds
                                onToggled: { Globals.eventSounds = !Globals.eventSounds; root.writePrefsPoke.restart(); if (Globals.eventSounds) Globals.playSound("audio-volume-change") }
                            }
                            PageFoot {
                                QsButton { label: "Sound settings"; onGo: { Globals.quickSettingsOpen = false; Shell.openSettings("sound") } }
                            }
                        }

                        // ═══ WI-FI (and the wired port, Tailscale) ═══
                        Column {
                            visible: root.expanded === "wifi"
                            width: parent.width; spacing: panel.pad
                            QsPageHead {
                                title: "Wi-Fi"
                                note: !root.wifiOn ? "Off"
                                    : root.wifiPending !== "" ? "Joining " + root.wifiPending + "…"
                                    : root.wifiName() !== "" ? "Connected to " + root.wifiName()
                                    : "Not connected"
                                busy: wifiScan.running
                                hasSwitch: true; on: root.wifiOn
                                onToggled: { Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiOn ? "off" : "on"]); rescanTimer.restart() }
                            }
                            // WHAT IS WRONG, whatever the link: a sign-in page in the
                            // way (hotel, café, guest network) or a VPN with no
                            // internet behind it. The VPN itself is the ewe.vpn
                            // plugin's page — here it is only named.
                            Row {
                                visible: NetState.portal
                                width: parent.width
                                spacing: Theme.spaceS
                                leftPadding: Theme.spaceS
                                QsNote {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - parent.leftPadding - portalBtn.width - parent.spacing
                                    tone: "warning"
                                    text: "Sign in to this network"
                                }
                                QsButton {
                                    id: portalBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    variant: "primary"; label: "Open sign-in page"
                                    onGo: NetState.openPortal()
                                }
                            }
                            QsNote {
                                visible: NetState.vpnHint !== ""
                                leftPadding: Theme.spaceS; rightPadding: Theme.spaceS
                                tone: "warning"
                                text: NetState.vpnHint
                            }
                            // NETWORKS
                            Column {
                                width: parent.width; spacing: Theme.spaceXs
                                SectionTitle { text: "Networks"; leftPadding: Theme.spaceS }
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
                                                    : wRow.modelData.active ? (NetState.wifiInternet === "portal" ? "Sign in to this network"
                                                                             : NetState.isProblem(NetState.wifiInternet) ? "Connected · no internet"
                                                                             : "Connected")
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
                                                        // Esc gives up on this network, not the panel
                                                        Keys.onEscapePressed: { root.pwTarget = ""; root.pwText = "" }
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
                            // WIRED — only when the machine has a port. The switch is
                            // the "I'm on Wi-Fi, ignore the cable" control; the line
                            // under it says what the port is really doing (no cable ·
                            // waiting for an address, and for how long · connected,
                            // with or without internet), then a hint when there is
                            // something to try, and Reconnect while it is stuck.
                            Column {
                                visible: NetState.wiredPresent
                                width: parent.width
                                spacing: Theme.spaceXs
                                SectionTitle { text: "Wired"; leftPadding: Theme.spaceS }
                                QsSwitchRow {
                                    ic: Theme.icEthernet; label: "Ethernet"
                                    desc: NetState.wiredBusy ? "Connecting…" : NetState.wiredText
                                    busy: NetState.wiredBusy || NetState.wiredWaiting
                                    on: NetState.wiredUp || NetState.wiredWaiting
                                    disabled: NetState.wiredPhase === "unplugged" || NetState.wiredPhase === "unmanaged"
                                    onToggled: NetState.setWired(!on)
                                }
                                QsNote {
                                    visible: NetState.wiredHint !== ""
                                    leftPadding: Theme.spaceS; rightPadding: Theme.spaceS
                                    tone: NetState.wiredWaiting ? "warning" : ""
                                    text: NetState.wiredHint
                                }
                                QsButton {
                                    visible: NetState.wiredWaiting || NetState.wiredNoInternet
                                    x: Theme.spaceS
                                    ic: Theme.icRefresh; label: "Reconnect"
                                    busy: NetState.wiredBusy
                                    onGo: NetState.reconnectWired()
                                }
                            }
                            // TAILSCALE — only when it is installed (every ewe install
                            // has it; the daemon runs only once set up here). The
                            // switch turns it on and off; the buttons are the one
                            // next step (Set up · Sign in) or Reconnect; an exit node
                            // in use is named, and Tailscale's own health messages
                            // are shown as they are.
                            Column {
                                visible: NetState.tsInstalled
                                width: parent.width
                                spacing: Theme.spaceXs
                                SectionTitle { text: "Tailscale"; leftPadding: Theme.spaceS }
                                QsSwitchRow {
                                    ic: Theme.icNetwork; label: "Tailscale"
                                    desc: NetState.tsText
                                    busy: NetState.tsBusy !== "" || NetState.tsPhase === "starting"
                                    on: NetState.tsPhase === "on" || NetState.tsPhase === "starting"
                                    disabled: NetState.tsBusy !== ""
                                    onToggled: NetState.tsRun(NetState.tsPhase === "setup" ? "setup"
                                                            : on ? "down" : "up")
                                }
                                Row {
                                    visible: NetState.tsExit !== null
                                    width: parent.width
                                    spacing: Theme.spaceS
                                    leftPadding: Theme.spaceS
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - parent.leftPadding - tsExitBtn.width - parent.spacing
                                        spacing: Theme.spaceXs
                                        TextCaption {
                                            id: tsExitName
                                            width: Math.min(implicitWidth, parent.width - (NetState.tsExit && !NetState.tsExit.online ? tsExitOff.implicitWidth + parent.spacing : 0))
                                            text: NetState.tsExit ? "Using exit node " + NetState.tsExit.name : ""
                                            color: Theme.textSecondary
                                        }
                                        TextCaption {
                                            id: tsExitOff
                                            visible: NetState.tsExit !== null && !NetState.tsExit.online
                                            text: "· offline"
                                            color: Theme.danger
                                        }
                                    }
                                    QsButton {
                                        id: tsExitBtn
                                        anchors.verticalCenter: parent.verticalCenter
                                        label: "Stop using"
                                        busy: NetState.tsBusy === "exit-node"
                                        onGo: NetState.tsRun("exit-node")
                                    }
                                }
                                Repeater {
                                    model: NetState.tsHealth.slice(0, 2)
                                    delegate: QsNote {
                                        required property var modelData
                                        leftPadding: Theme.spaceS; rightPadding: Theme.spaceS
                                        tone: "warning"
                                        text: modelData
                                    }
                                }
                                QsNote {
                                    visible: NetState.tsPhase === "signin" && NetState.tsLoginUrl !== "" && NetState.tsBusy === ""
                                    leftPadding: Theme.spaceS; rightPadding: Theme.spaceS
                                    text: "Finish signing in in your browser."
                                }
                                QsNote {
                                    visible: NetState.tsError !== ""
                                    leftPadding: Theme.spaceS; rightPadding: Theme.spaceS
                                    tone: "danger"
                                    text: NetState.tsError
                                }
                                Row {
                                    x: Theme.spaceS
                                    spacing: Theme.spaceS
                                    // from the phase, never from the buttons' `visible`: that
                                    // reads back EFFECTIVE visibility, false while this Row
                                    // is hidden — the Row would never show
                                    visible: NetState.tsPhase === "setup" || NetState.tsPhase === "signin"
                                             || NetState.tsPhase === "on" || NetState.tsPhase === "starting"
                                    QsButton {
                                        id: tsSetupBtn
                                        visible: NetState.tsPhase === "setup"
                                        variant: "primary"; label: "Set up Tailscale"
                                        busy: NetState.tsBusy === "setup"
                                        onGo: NetState.tsRun("setup")
                                    }
                                    QsButton {
                                        id: tsSignInBtn
                                        visible: NetState.tsPhase === "signin"
                                        variant: "primary"; label: "Sign in"
                                        busy: NetState.tsBusy === "up"
                                        onGo: NetState.tsRun("up")
                                    }
                                    QsButton {
                                        id: tsReconnectBtn
                                        visible: NetState.tsPhase === "on" || NetState.tsPhase === "starting"
                                        ic: Theme.icRefresh; label: "Reconnect"
                                        busy: NetState.tsBusy === "reconnect"
                                        onGo: NetState.tsRun("reconnect")
                                    }
                                }
                            }
                            // HIDDEN NETWORK — its name and (if it has one) its
                            // password; NetworkManager remembers it from then on
                            Column {
                                visible: root.hiddenOpen
                                width: parent.width
                                spacing: Theme.spaceS
                                SectionTitle { text: "Hidden network"; leftPadding: Theme.spaceS }
                                QsField {
                                    focused: hidSsid.activeFocus
                                    QsFieldInput {
                                        id: hidSsid
                                        anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                                        placeholder: "Network name"
                                        onAccepted: hidPw.forceActiveFocus()
                                        Keys.onEscapePressed: root.hiddenOpen = false
                                    }
                                }
                                QsField {
                                    focused: hidPw.activeFocus
                                    QsFieldInput {
                                        id: hidPw
                                        anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                                        placeholder: "Password (leave empty for an open network)"
                                        echoMode: TextInput.Password
                                        onAccepted: root.joinHidden(hidSsid.text, hidPw.text)
                                        Keys.onEscapePressed: root.hiddenOpen = false
                                    }
                                }
                                Row {
                                    anchors.right: parent.right
                                    spacing: Theme.spaceS
                                    QsButton { variant: "ghost"; label: "Cancel"; onGo: root.hiddenOpen = false }
                                    QsButton { variant: "primary"; label: "Join"; disabled: hidSsid.text.trim() === ""; onGo: root.joinHidden(hidSsid.text, hidPw.text) }
                                }
                                onVisibleChanged: {
                                    if (visible) { hidSsid.text = ""; hidPw.text = ""; hidSsid.forceActiveFocus() }
                                    else keyCatcher.forceActiveFocus()
                                }
                            }
                            PageFoot {
                                start: QsButton { visible: root.wifiOn && !root.hiddenOpen; variant: "ghost"; label: "Hidden network…"; onGo: root.hiddenOpen = true }
                                QsButton { label: "Network settings"; onGo: { Globals.quickSettingsOpen = false; Shell.openSettings("network") } }
                            }
                        }

                        // ═══ BLUETOOTH ═══
                        Column {
                            visible: root.expanded === "bt"
                            width: parent.width; spacing: panel.pad
                            QsPageHead {
                                title: "Bluetooth"
                                busy: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering
                                note: !Bluetooth.defaultAdapter ? "No adapter"
                                    : !Bluetooth.defaultAdapter.enabled ? "Off"
                                    : root.btConnectedName() !== "" ? "Connected to " + root.btConnectedName()
                                    : Bluetooth.defaultAdapter.discovering ? "Searching…" : "On"
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
                            Column {
                                visible: btList.shown > 0
                                width: parent.width; spacing: Theme.spaceXs
                                SectionTitle { text: "Devices"; leftPadding: Theme.spaceS }
                                ListWell {
                                    flush: true
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
                            }
                            // searching, nothing found yet
                            Row {
                                visible: btList.shown === 0 && !!Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled
                                spacing: Theme.spaceS
                                leftPadding: Theme.spaceS
                                Spinner { visible: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering; anchors.verticalCenter: parent.verticalCenter; size: Theme.iconSm }
                                TextCaption { anchors.verticalCenter: parent.verticalCenter; text: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering ? "Looking for devices…" : "No devices" }
                            }
                            // why the last tap failed ("codes did not match", "not in
                            // pairing mode", …) — from BtAgent; cleared by the next tap
                            QsNote { visible: BtAgent.lastError !== ""; tone: "danger"; text: BtAgent.lastError }
                            QsNote {
                                visible: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled && !BtAgent.registered
                                tone: "warning"
                                text: BtAgent.bridgeError !== "" ? BtAgent.bridgeError : "The pairing agent isn’t running yet. Devices that ask for a code can’t pair."
                            }
                            PageFoot {
                                QsButton { label: "Bluetooth settings"; onGo: { Globals.quickSettingsOpen = false; Shell.openSettings("bluetooth") } }
                            }
                        }

                        // ═══ CALENDAR (Agenda): the month, then the week's events ═══
                        Column {
                            id: calCol
                            visible: root.tab === "cal"
                            width: parent.width; spacing: panel.pad
                            QsPageHead {
                                title: "Calendar"
                                note: root.monthNames[root.calMonth] + " " + root.calYear
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
                                topPadding: Theme.spaceS; bottomPadding: Theme.spaceS
                                ic: Theme.icCalendar
                                title: Agenda.hintTitle
                                desc: Agenda.hintBody
                                QsButton {
                                    visible: !Agenda.connected
                                    size: "md"; label: "Open ewe Settings"
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
                                    SectionTitle { text: agDay.modelData.label; leftPadding: Theme.spaceS }
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

                        // ═══ NOTIFICATIONS (the full list): Do not disturb, then
                        //     one card per app, the latest app first ═══
                        Column {
                            visible: root.tab === "notifs"
                            width: parent.width; spacing: panel.pad
                            QsPageHead {
                                title: "Notifications"
                                note: root.noteCount === 0 ? "" : root.noteCount === 1 ? "1 notification" : root.noteCount + " notifications"
                                QsButton {
                                    visible: root.noteCount > 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    variant: "ghost"; label: "Clear all"
                                    onGo: root.clearAll()
                                }
                            }
                            QsSwitchRow {
                                ic: Theme.icDnd; label: "Do not disturb"
                                desc: Globals.dnd ? "Banners are hidden; notifications still land here" : ""
                                on: Globals.dnd
                                onToggled: Globals.dnd = !Globals.dnd
                            }
                            Rectangle { width: parent.width; height: Theme.borderWidth1; color: Theme.borderSubtle }
                            QsEmpty {
                                visible: root.noteCount === 0
                                topPadding: Theme.spaceS
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
                                delegate: NoteGroup {
                                    required property var modelData
                                    group: modelData
                                }
                            }
                        }

                        // ═══ POWER (the head's power button): suspend, sign out,
                        //     restart, shut down — the last three ask first ═══
                        Column {
                            visible: root.tab === "power"
                            width: parent.width; spacing: panel.pad
                            QsPageHead { title: "Power" }
                            ListWell {
                                flush: true
                                ListRow { glyph: root.g(0xE410); label: "Suspend"; onClicked: root.runPower("suspend") }
                                ListRow { glyph: root.g(0xE10E); label: "Sign out"; onClicked: root.askPower("logout", "Sign out?", "Sign out") }
                                ListRow { glyph: root.g(0xE145); glyphColor: Theme.danger; label: "Restart"; onClicked: root.askPower("reboot", "Restart this computer?", "Restart") }
                                ListRow { glyph: root.g(0xE140); glyphColor: Theme.danger; label: "Shut down"; onClicked: root.askPower("poweroff", "Shut down this computer?", "Shut down") }
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
                                // a key the shell keeps for itself (remote, power…)
                                // is the built-in page, never also this one
                                visible: root.tab === modelData.key && root.builtinTabs.indexOf(modelData.key) < 0
                                width: parent.width; spacing: Theme.spaceS
                                readonly property bool shown: Globals.quickSettingsOpen && pageSlot.visible
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

                // ══ the foot (home): the battery and the power mode, each only
                //    when the machine has it; no foot at all on a desktop
                //    without power-profiles-daemon ══
                Item {
                    id: foot
                    visible: panel.onHome && (root.hasBattery || root.hasModes)
                    width: parent.width
                    height: Theme.borderWidth1 + Theme.spaceXs + Theme.controlSm
                    Rectangle { width: parent.width; height: Theme.borderWidth1; color: Theme.borderSubtle }
                    Row {
                        visible: root.hasBattery
                        anchors.left: parent.left; anchors.leftMargin: Theme.spaceXs
                        anchors.right: modes.visible ? modes.left : parent.right; anchors.rightMargin: Theme.spaceS
                        anchors.bottom: parent.bottom
                        height: Theme.controlSm
                        spacing: Theme.spaceS
                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.battCharging ? Theme.icBolt
                                : root.battPct >= 60 ? Theme.icBattFull : root.battPct >= 30 ? Theme.icBatt50 : Theme.icBattEmpty
                            color: root.battCharging ? Theme.success : root.battPct <= 15 ? Theme.danger : Theme.textSecondary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.iconMd - parent.spacing
                            text: root.battText
                            elide: Text.ElideRight
                            color: Theme.textSecondary
                            font.family: Theme.type.label.family
                            font.pixelSize: Theme.type.label.size
                        }
                    }
                    // the power mode (PowerProfiles service ← power-profiles-daemon
                    // or tuned-ppd); Performance only where the machine offers it
                    QsSegmented {
                        id: modes
                        visible: root.hasModes
                        anchors.right: parent.right; anchors.bottom: parent.bottom
                        size: "sm"
                        value: PowerProfiles.profile
                        options: PowerProfiles.hasPerformanceProfile
                                 ? [{ icon: Theme.icLeaf, tip: "Power saver", value: PowerProfile.PowerSaver },
                                    { icon: Theme.icBalance, tip: "Balanced", value: PowerProfile.Balanced },
                                    { icon: Theme.icSpeed, tip: "Performance", value: PowerProfile.Performance }]
                                 : [{ icon: Theme.icLeaf, tip: "Power saver", value: PowerProfile.PowerSaver },
                                    { icon: Theme.icBalance, tip: "Balanced", value: PowerProfile.Balanced }]
                        onPicked: function (v) { PowerProfiles.profile = v }
                        onHoverItemChanged: panel.hint(modes.hoverItem, modes.hoverItem !== null, modes.hoverTip)
                    }
                }
            }

            // ══ the tooltip box (Tooltip): surfaceOverlay, borderSubtle, the
            //    radiusSlight corner, label type; spaceXs under its target,
            //    centred on it, above it when the panel's edge is in the way ══
            Rectangle {
                id: tipBox
                property bool shown: false
                function place() {
                    var t = panel.tipItem
                    if (!t || !t.visible) { tipBox.shown = false; return }
                    var p = t.mapToItem(panel, t.width / 2, 0)
                    tipBox.x = Math.max(panel.pad, Math.min(panel.width - tipBox.width - panel.pad, p.x - tipBox.width / 2))
                    var below = p.y + t.height + Theme.spaceXs
                    tipBox.y = (below + tipBox.height <= panel.height - Theme.spaceXs) ? below : p.y - Theme.spaceXs - tipBox.height
                    tipBox.shown = true
                }
                visible: shown && panel.tipText !== ""
                z: 60
                width: tipText.implicitWidth + 2 * Theme.spaceS
                height: tipText.implicitHeight + 2 * Theme.spaceXxs
                radius: Theme.radiusSlight
                color: Theme.surfaceOverlay
                border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                Text {
                    id: tipText
                    anchors.centerIn: parent
                    text: panel.tipText
                    color: Theme.textPrimary
                    font.family: Theme.type.label.family
                    font.pixelSize: Theme.type.label.size
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

    // which plugin tiles open their own page (read off the home grid while it
    // shows — a slot's `visible` is the effective one, so a hidden home says
    // nothing about the tiles on it)
    function readTiles() {
        if (!homePage.visible) return
        var m = {}
        for (var i = 0; i < tileRep.count; i++) {
            var s = tileRep.itemAt(i)
            if (!s) continue
            m[s.modelData.id] = s.visible && !!s.item && s.item.hasMenu === true
        }
        if (JSON.stringify(m) !== JSON.stringify(root.tileOpens)) root.tileOpens = m
    }
}
