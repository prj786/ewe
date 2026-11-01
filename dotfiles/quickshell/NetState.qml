pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// NetState — ONE source of network truth for the bar and Quick settings.
//
// Before it, the bar knew "ethernet connected: yes/no" and "Wi-Fi connected:
// yes/no", Quick settings asked nmcli again on its own, and neither knew
// whether the internet actually worked. On the owner's work desktop
// (2026-10-28) a cable had link at 100 Mb/s but DHCP never answered:
// NetworkManager failed the attempt every 45 s and then blocked the port for
// ~5 minutes, while the shell showed… nothing useful. The owner rebooted
// twice. Now one reading (scripts/net-state.py: devices and their states,
// NetworkManager's connectivity verdict, the device that carries traffic,
// the cable's link and speed, VPNs) feeds every surface, and the words for
// each state live here, once.
//
//   freshness  the one `nmcli monitor` (it moved here from Bar.qml): every
//              NetworkManager event → 400 ms debounce → one net-state.py run,
//              and Globals.netEpoch++ for everyone else (Quick settings' Wi-Fi
//              list, the ewe.vpn plugin). No polling loop. Opening Quick
//              settings asks NetworkManager to re-check connectivity once.
//   Tailscale  `ewe-tailscale status` (bin/): once at login, when Quick
//              settings opens, on the same events and every 30 s while it is
//              open (the only place it is shown) — and after "not installed",
//              only when Quick settings opens (it may have been installed).
//
// Everything here only READS the network, except the actions the user
// presses: Wired on/off and Reconnect (nmcli), the portal sign-in page
// (the browser), and the Tailscale verbs (ewe-tailscale).
QtObject {
    id: ns

    // ── the reading (net-state.py) ───────────────────────────────────────────
    property bool ready: false
    property string connectivity: "unknown"   // full · limited · portal · none · unknown
    property var primary: null                // {dev, type} — where internet traffic leaves
    property var uplink: null                 // {dev, type} — the physical link under it
    property var devices: []
    property var wired: []                    // every ethernet port, with carrier/speed/…
    property var wifi: null
    property var vpns: []

    // ── what it means ────────────────────────────────────────────────────────
    readonly property string uplinkType: ns.uplink ? ns.uplink.type : ""
    function isProblem(c) { return c === "limited" || c === "none" || c === "portal" }
    // "unknown" is not a problem: it is what NetworkManager says before its
    // first check, or with checking switched off — never cry wolf on it
    readonly property bool noInternet: ns.uplink !== null && ns.isProblem(ns.connectivity)
    readonly property bool portal: ns.uplink !== null && ns.connectivity === "portal"
    // the VPN to blame when the internet is gone (Tailscale has its own row)
    readonly property var activeVpn: {
        for (var i = 0; i < ns.vpns.length; i++)
            if (!ns.vpns[i].tailscale && ns.vpns[i].state === "activated") return ns.vpns[i]
        return null
    }
    readonly property string vpnHint: ns.noInternet && ns.activeVpn ? "No internet through " + ns.activeVpn.name : ""

    // the ethernet port to talk about: the one carrying traffic, else one with
    // a cable in, else the first (a dock's port with nothing plugged in)
    readonly property var wiredMain: {
        var w = ns.wired, i
        if (w.length === 0) return null
        for (i = 0; i < w.length; i++) if (ns.uplink && w[i].dev === ns.uplink.dev) return w[i]
        for (i = 0; i < w.length; i++) if (w[i].state === "connected") return w[i]
        for (i = 0; i < w.length; i++) if (w[i].carrier) return w[i]
        return w[0]
    }
    readonly property bool wiredPresent: ns.wiredMain !== null
    //   unplugged  no link (state unavailable, or no carrier)
    //   off        a cable is in, but the user turned the port off here
    //              (`nmcli device disconnect` clears the device's autoconnect)
    //   waiting    a cable is in and NetworkManager is (or keeps) asking for
    //              an address — connecting, or failed/disconnected with
    //              autoconnect still on (the old 45 s fail → 5 min block)
    //   connected  has an address; `internet` says whether it goes anywhere
    readonly property string wiredPhase: {
        var w = ns.wiredMain
        if (!w) return ""
        if (w.state === "unmanaged") return "unmanaged"
        if (w.state === "connected") return "connected"
        if (w.state === "unavailable" || !w.carrier) return "unplugged"
        if (w.state === "connecting") return "waiting"
        return w.autoconnect ? "waiting" : "off"
    }
    readonly property bool wiredUp: ns.wiredPhase === "connected"
    readonly property bool wiredWaiting: ns.wiredPhase === "waiting"
    readonly property bool wiredNoInternet: ns.wiredUp && ns.isProblem(ns.wiredMain.internet)
    readonly property bool wiredPortal: ns.wiredUp && ns.wiredMain.internet === "portal"
    // "Cable runs at 100 Mb/s": only when the NIC can do ≥ 1 Gb/s and the
    // other end does not say it is itself slower — a 100 Mb switch is not a
    // faulty cable. A gigabit link at 100 is the classic two-pairs-dead cable.
    readonly property bool wiredSlow: {
        var w = ns.wiredMain
        if (!w || !w.carrier || !w.speed || !w.maxSpeed) return false
        if (w.speed >= 1000 || w.maxSpeed < 1000) return false
        return !(w.partnerMax && w.partnerMax <= w.speed)
    }

    // how long the port has been waiting for an address (the shell's own
    // clock: NetworkManager does not say when the wait began)
    property string _waitDev: ""
    property real _waitSince: 0
    property real now: Date.now()
    readonly property int waitingSecs: ns.wiredWaiting && ns._waitSince > 0 ? Math.max(0, Math.floor((ns.now - ns._waitSince) / 1000)) : 0
    readonly property bool waitingLong: ns.waitingSecs >= 60
    // a display clock, not a poll: it only re-evaluates the words above, and
    // only while someone is looking at them
    property Timer _tick: Timer {
        interval: 15000; repeat: true
        running: ns.wiredWaiting && Globals.quickSettingsOpen
        onTriggered: ns.now = Date.now()
    }

    function minutes(secs) { return secs < 60 ? "" : Math.floor(secs / 60) + " min" }
    // the wired row's second line — plain words, one per state
    readonly property string wiredText: {
        switch (ns.wiredPhase) {
        case "unplugged": return "No cable detected"
        case "off": return "Off"
        case "unmanaged": return "Not managed here"
        case "waiting": return "Waiting for an address" + (ns.waitingSecs >= 60 ? " · " + ns.minutes(ns.waitingSecs) : "")
        case "connected":
            return ns.wiredPortal ? "Sign in to this network"
                 : ns.wiredNoInternet ? "Connected · no internet"
                 : "Connected"
        }
        return ""
    }
    readonly property string wiredHint: ns.wiredWaiting && ns.waitingLong ? "The network isn’t answering — try another port or cable"
                                      : ns.wiredSlow ? "Cable runs at " + ns.wiredMain.speed + " Mb/s — the cable or port may be faulty"
                                      : ""

    // the Wi-Fi link's own verdict (its row in Quick settings)
    readonly property string wifiInternet: ns.wifi && ns.wifi.state === "connected" ? ns.wifi.internet : ""
    readonly property bool wifiConnecting: ns.wifi !== null && ns.wifi.state === "connecting"

    // ── the bar: the glyph of the link that carries traffic ──────────────────
    // A cable that is the default route shows the cable, even with Wi-Fi up
    // (it used to be Wi-Fi always). No link yet but a cable waiting for an
    // address (or Wi-Fi associating): that glyph, muted. Link but no internet:
    // muted + a warning dot. Nothing at all: nothing, as before.
    readonly property string barGlyph: ns.uplinkType === "ethernet" ? Theme.icEthernet
                                     : ns.uplinkType === "wifi" ? Theme.icWifi
                                     : ns.wiredWaiting ? Theme.icEthernet
                                     : ns.wifiConnecting ? Theme.icWifi
                                     : ""
    readonly property bool barMuted: ns.uplink === null || ns.noInternet
    readonly property bool barWarn: ns.noInternet

    // ── reading it ───────────────────────────────────────────────────────────
    readonly property string _script: Qt.resolvedUrl("scripts/net-state.py").toString().replace(/^file:\/\//, "")
    property bool _again: false
    property Process _read: Process {
        command: ["python3", ns._script]
        stdout: StdioCollector {
            onStreamFinished: {
                var j = null
                try { j = JSON.parse(this.text) } catch (e) { j = null }
                if (!j || !j.ok) {
                    Log.debug("net", "net-state:", j && j.error ? j.error : "unreadable")
                    ns.ready = true
                    return
                }
                ns.connectivity = String(j.connectivity || "unknown")
                ns.primary = j.primary || null
                ns.uplink = j.uplink || null
                ns.devices = j.devices || []
                ns.wired = j.wired || []
                ns.wifi = j.wifi || null
                ns.vpns = j.vpns || []
                ns.ready = true
                ns._trackWait()
            }
        }
        onExited: if (ns._again) { ns._again = false; Qt.callLater(ns.refresh) }
    }
    function refresh() {
        if (_read.running) { ns._again = true; return }
        _read.running = true
    }
    function _trackWait() {
        ns.now = Date.now()
        var w = ns.wiredMain
        if (ns.wiredWaiting && w) {
            if (ns._waitDev !== w.dev || ns._waitSince === 0) { ns._waitDev = w.dev; ns._waitSince = ns.now }
        } else {
            ns._waitDev = ""; ns._waitSince = 0
        }
    }

    // NetworkManager events → one re-read (NM emits a burst per transition)
    property Timer _debounce: Timer {
        interval: 400
        onTriggered: {
            ns.refresh()
            // Tailscale is only on screen inside Quick settings
            if (Globals.quickSettingsOpen) ns.tsRefresh(false)
            Globals.netEpoch++              // Quick settings' lists and the plugins re-read on this
        }
    }
    property int _monTries: 0
    property Process _mon: Process {
        // --pdeathsig: dies with the shell even on an abrupt exit(255) — see
        // Screensaver.qml's pactl; nmcli was the other left-over per restart
        command: ["setpriv", "--pdeathsig", "TERM", "--", "nmcli", "monitor"]
        stdout: SplitParser { onRead: function (line) { ns._monTries = 0; ns._debounce.restart() } }
        // if NetworkManager isn't running, nmcli monitor exits immediately —
        // back off and stop rather than respawning it forever
        onExited: {
            if (ns._monTries >= 5) { Log.warn("net", "nmcli monitor keeps exiting — network indicators are static"); return }
            ns._monTries++
            ns._monRestart.interval = 5000 * ns._monTries
            ns._monRestart.restart()
        }
    }
    property Timer _monRestart: Timer { interval: 5000; onTriggered: ns._mon.running = true }

    // after a wake: nmcli monitor usually dies with the link it was watching
    property Connections _resume: Connections {
        target: Resume
        function onResyncNetwork() {
            ns._monTries = 0
            if (!ns._mon.running) ns._mon.running = true
            ns.refresh()
            if (Globals.quickSettingsOpen) ns.tsRefresh(false)
            Globals.netEpoch++
        }
    }

    // armed from login by shell.qml, like the other always-on singletons
    function start() {
        if (_mon.running) return
        _mon.running = true
        ns.refresh()
        ns.tsRefresh(true)
    }

    // Quick settings opened: ask NetworkManager for a fresh connectivity
    // verdict (it otherwise re-checks every 5 minutes), and re-read Tailscale
    property Process _check: Process {
        command: ["nmcli", "networking", "connectivity", "check"]
        onExited: ns.refresh()
    }
    function panelOpened() {
        if (!_check.running) _check.running = true
        ns.tsRefresh(true)
    }

    // ── actions ──────────────────────────────────────────────────────────────
    property bool wiredBusy: false
    property Process _wiredSet: Process {
        onExited: { ns.wiredBusy = false; ns.refresh(); ns._wiredRescan.restart() }
    }
    property Timer _wiredRescan: Timer { interval: 1500; onTriggered: ns.refresh() }
    // the Wired switch: `device disconnect` drops the link and stops
    // autoconnect until `device connect` (or a re-plug) — the way to be on
    // Wi-Fi with the cable still in
    function setWired(on) {
        var w = ns.wiredMain
        if (!w || ns.wiredPhase === "unplugged" || ns.wiredBusy) return
        ns.wiredBusy = true
        _wiredSet.command = ["nmcli", "device", on ? "connect" : "disconnect", w.dev]
        _wiredSet.running = true
    }
    // Reconnect = `nmcli device connect DEV`, ONE command, not disconnect +
    // connect: activating the port's connection again tears down the attempt
    // in flight (or the live lease) and starts a fresh one — a new DHCP
    // DISCOVER — and it lifts NetworkManager's autoconnect block at once
    // (the 5-minute wait the owner rebooted through). A `disconnect` first
    // would add nothing, and if the `connect` then failed, it would leave the
    // port switched OFF (disconnect clears the device's autoconnect).
    function reconnectWired() {
        var w = ns.wiredMain
        if (!w || ns.wiredPhase === "unplugged" || ns.wiredBusy) return
        ns.wiredBusy = true
        ns._waitSince = 0                 // a fresh attempt starts a fresh clock
        _wiredSet.command = ["nmcli", "device", "connect", w.dev]
        _wiredSet.running = true
    }
    // a captive portal (hotel, café, a guest network): any plain-http page
    // gets redirected to its sign-in page — https pages cannot be
    function openPortal() { Quickshell.execDetached(["xdg-open", "http://neverssl.com"]) }

    // ── Tailscale (bin/ewe-tailscale) ────────────────────────────────────────
    property var ts: ({ installed: false })
    property bool tsChecked: false
    property string tsBusy: ""                // the verb in flight
    property string tsError: ""
    property string tsLoginUrl: ""
    readonly property string tsTool: Quickshell.env("EWE_TAILSCALE_TOOL") || (Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-tailscale")
    readonly property bool tsInstalled: ns.ts.installed === true
    //   setup     the daemon is not running, or it does not take orders from
    //             this user yet — one admin password fixes both
    //   signin    NeedsLogin
    //   off       Stopped (tailscale down)
    //   starting  Starting / NoState
    //   on        Running
    readonly property string tsPhase: !ns.tsInstalled ? ""
        : ns.ts.needs_setup ? "setup"
        : ns.ts.state === "NeedsLogin" ? "signin"
        : ns.ts.state === "Stopped" ? "off"
        : ns.ts.state === "Running" ? "on"
        : "starting"
    readonly property string tsText: ns.tsBusy === "setup" ? "Setting up…"
        : ns.tsBusy === "up" || ns.tsBusy === "reconnect" ? "Connecting…"
        : ns.tsBusy === "down" ? "Turning off…"
        : ns.tsBusy === "logout" ? "Signing out…"
        : ns.tsPhase === "setup" ? "Not set up"
        : ns.tsPhase === "signin" ? "Signed out"
        : ns.tsPhase === "off" ? "Off"
        : ns.tsPhase === "starting" ? "Connecting…"
        : ns.tsPhase === "on" ? (ns.ts.relay_only === true ? "Connected through a relay" : "Connected")
        : ""
    readonly property var tsExit: ns.tsPhase === "on" && ns.ts.exit_node ? ns.ts.exit_node : null
    readonly property var tsHealth: ns.tsInstalled && ns.ts.health ? ns.ts.health : []

    property bool _tsAgain: false
    property real _tsLast: 0
    property Process _tsStatus: Process {
        command: ["python3", ns.tsTool, "status"]
        stdout: StdioCollector { onStreamFinished: ns._tsApply(this.text, "") }
        onExited: if (ns._tsAgain) { ns._tsAgain = false; Qt.callLater(function () { ns.tsRefresh(true) }) }
    }
    // force: also when it said "not installed" last time (Quick settings
    // opening, login) — a plain NetworkManager event does not re-ask then
    function tsRefresh(force) {
        if (ns.tsChecked && !ns.tsInstalled && !force) return
        if (ns.tsBusy !== "") return              // the verb's own answer is coming
        if (_tsStatus.running) { ns._tsAgain = true; return }
        ns._tsLast = Date.now()
        _tsStatus.running = true
    }
    property Timer _tsPoll: Timer {
        interval: 30000; repeat: true
        running: Globals.quickSettingsOpen && ns.tsInstalled
        onTriggered: ns.tsRefresh(false)
    }
    function _tsApply(text, verb) {
        var j = null
        try { j = JSON.parse(text) } catch (e) { j = null }
        ns.tsChecked = true
        if (!j) { if (verb !== "") ns.tsError = "Tailscale did not answer"; return }
        if (j.ok === false) {
            if (verb !== "") ns.tsError = j.code === "cancelled" ? "" : String(j.error || "Tailscale failed")
            if (j.installed === false) ns.ts = { installed: false }
            return
        }
        if (j.installed !== undefined) ns.ts = j
        // the sign-in page WE opened (Sign in → `up`); a stale AuthURL left in
        // tailscaled from an earlier attempt is not a reason to say "finish
        // signing in" — pressing Sign in again fetches a live one
        if ((verb === "up" || verb === "reconnect") && j.login_url) ns.tsLoginUrl = String(j.login_url)
        else if (ns.ts.state !== "NeedsLogin") ns.tsLoginUrl = ""
        if (verb !== "") ns.tsError = ""
        // set up, and nobody is signed in yet: carry straight on to sign-in
        if (verb === "setup" && j.state === "NeedsLogin") Qt.callLater(function () { ns.tsRun("up") })
    }
    property string _tsVerbName: ""
    property Process _tsVerb: Process {
        stdout: StdioCollector { onStreamFinished: ns._tsApply(this.text, ns._tsVerbName) }
        onExited: { ns.tsBusy = ""; ns._tsAfter.restart() }
    }
    // tailscaled settles a moment after the CLI returns — look again
    property Timer _tsAfter: Timer { interval: 2000; onTriggered: ns.tsRefresh(false) }
    function tsRun(verb) {
        if (ns.tsBusy !== "" || !ns.tsInstalled) return
        var args = verb === "exit-node" ? ["exit-node", "off"] : [verb]
        ns.tsBusy = verb
        ns.tsError = ""
        ns._tsVerbName = verb
        _tsVerb.command = ["python3", ns.tsTool].concat(args)
        _tsVerb.running = true
    }
}
