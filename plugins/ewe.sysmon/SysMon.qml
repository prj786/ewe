pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs

// SysMon — the one sampler behind every System monitor surface: the bar
// readout (Widget.qml), the card it opens (Panel.qml → Card.qml) and the
// desktop widget (Desk.qml). Registered by the qmldir beside it, so every
// entry point sees one instance.
//
// It samples ONLY while something shows the numbers: each consumer `hold()`s
// while it is on screen — a bar readout while its bar is up (the host loads
// it only while Show in bar is on), the card while it is open, the desktop
// widget while it is shown (the host loads it only then) — and the timer runs
// while anyone holds. One process per tick (sample.sh, plain sh) reads
// /proc/stat, /proc/meminfo, the default route, its byte counters and the
// clock; the interval follows Shell.lowPower (1.5 s → 3 s on battery).
//
// The last minute of samples is kept for the sparklines. When nobody holds
// any more, the baselines and the history are dropped, so the first tick
// after a reopen does not average across the idle period and no line joins
// across a gap.
QtObject {
    id: sm

    readonly property string pluginId: "ewe.sysmon"

    // ── the reading ──────────────────────────────────────────────────────────
    property real cpuUsage: 0             // 0..1
    property bool cpuKnown: false         // false until two ticks gave a delta
    property int cores: 0
    property real memUsage: 0             // 0..1
    property real memTotalKb: 0
    property real memUsedKb: 0
    property real swapTotalKb: 0
    property real swapUsedKb: 0
    property bool memKnown: false
    readonly property int cpuPct: Math.round(sm.cpuUsage * 100)
    readonly property int memPct: Math.round(sm.memUsage * 100)

    // internet: the default route's interface and its speed
    property bool netKnown: false         // a sample has said online or offline
    property string netIf: ""
    property string netKind: ""           // wifi · ethernet · vpn; "" = offline
    property real down: -1                // bytes/s; -1 = no rate yet
    property real up: -1
    readonly property bool online: sm.netKind !== ""

    // the last minute: [{ t (ms), cpu (0..1 or -1), down, up (B/s or -1) }]
    readonly property int windowMs: 60000
    property var history: []
    // the speed sparkline's scale never drops under this, so a few KB/s of
    // background chatter stays a flat line instead of filling the chart
    readonly property real netFloor: 128 * 1024
    readonly property real netPeak: {
        var m = sm.netFloor
        for (var i = 0; i < sm.history.length; i++)
            m = Math.max(m, sm.history[i].down, sm.history[i].up)
        return m
    }

    // ── who wants samples ────────────────────────────────────────────────────
    // object identities, so a holder that goes away (a bar on an unplugged
    // monitor) can be released by the same handle, and the same holder is
    // never counted twice
    property var _holders: []
    readonly property int wanted: sm._holders.length
    function hold(who, on) {
        var h = sm._holders.filter(function (x) { return x !== who })
        if (on) h.push(who)
        sm._holders = h
    }
    onWantedChanged: if (sm.wanted === 0) {
        sm._prev = null
        sm.history = []
        sm.cpuKnown = false
        sm.down = -1; sm.up = -1
    }

    // ── sampling ─────────────────────────────────────────────────────────────
    readonly property string script: Qt.resolvedUrl("sample.sh").toString().replace(/^file:\/\//, "")
    // the last tick's raw counters, handed back to sample.sh:
    // { total, idle, net: { if, rx, tx, t } | null }
    property var _prev: null
    function _args() {
        var a = ["sh", sm.script]
        var p = sm._prev
        if (!p) return a
        a.push(String(p.total), String(p.idle))
        if (p.net) a.push(p.net.if, String(p.net.rx), String(p.net.tx), String(p.net.t))
        return a
    }
    function _take(j) {
        if (typeof j.cpu === "number") { sm.cpuUsage = Math.max(0, Math.min(1, j.cpu)); sm.cpuKnown = true }
        if (typeof j.cores === "number") sm.cores = j.cores
        if (typeof j.mem === "number") {
            sm.memUsage = Math.max(0, Math.min(1, j.mem))
            sm.memTotalKb = j.memTotal || 0
            sm.memUsedKb = j.memUsed || 0
            sm.memKnown = sm.memTotalKb > 0
        }
        sm.swapTotalKb = j.swapTotal || 0
        sm.swapUsedKb = j.swapUsed || 0
        var n = j.net
        sm.netKnown = true
        sm.netIf = n ? String(n.if) : ""
        sm.netKind = n ? String(n.kind) : ""
        sm.down = n && typeof n.down === "number" ? n.down : -1
        sm.up = n && typeof n.up === "number" ? n.up : -1
        sm._prev = { total: j.total, idle: j.idle, net: n ? { if: n.if, rx: n.rx, tx: n.tx, t: n.t } : null }

        var now = Date.now()
        var h = sm.history.filter(function (s) { return now - s.t <= sm.windowMs })
        h.push({ t: now, cpu: (typeof j.cpu === "number") ? sm.cpuUsage : -1, down: sm.down, up: sm.up })
        sm.history = h
    }
    property Process _proc: Process {
        command: sm._args()
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (!j || !j.ok) { Log.warn("ewe.sysmon", "sample failed:", j && j.error); return }
                    if (sm.wanted > 0) sm._take(j)
                } catch (e) { Log.warn("ewe.sysmon", "unreadable sample:", String(e)) }
            }
        }
    }
    // a poll rate, not a motion duration
    property Timer _timer: Timer {
        interval: Shell.lowPower ? 3000 : 1500
        running: sm.wanted > 0
        repeat: true; triggeredOnStart: true
        onTriggered: if (!sm._proc.running) sm._proc.running = true
    }

    // ── words and numbers ────────────────────────────────────────────────────
    // Lucide glyphs Theme has no name for (yet): the vendored face carries
    // every Lucide icon and its codepoints are stable (Theme.qml, Icons).
    // A Theme name wins as soon as the shell has one.
    readonly property string icActivity: Theme["icActivity"] || Theme.ic(0xE038)    // activity
    readonly property string icDown: Theme["icArrowDown"] || Theme.ic(0xE042)       // arrow-down
    readonly property string icUp: Theme["icArrowUp"] || Theme.ic(0xE04A)           // arrow-up

    // the setting's unit: "MB/s" like downloads (1024-based, as browsers
    // count) or "Mbit/s" like speed tests (1000-based bits)
    function bits(settings) { return !!settings && settings.speed_unit === "Mbit/s" }
    // a speed as [number, unit] — "1.2" "MB/s", "86" "KB/s", "—" "" before
    // there is a rate. Three figures at most, so the bar barely moves.
    function speedParts(bps, inBits) {
        if (!(bps >= 0)) return ["—", ""]
        var v = inBits ? bps * 8 / 1000 : bps / 1024
        var k = inBits ? 1000 : 1024
        var names = inBits ? ["kbit/s", "Mbit/s", "Gbit/s"] : ["KB/s", "MB/s", "GB/s"]
        var i = 0
        while (i < names.length - 1 && v >= 999.5) { v /= k; i++ }
        return [v < 0.05 ? "0" : v < 9.95 ? v.toFixed(1) : String(Math.round(v)), names[i]]
    }
    function speedText(bps, inBits) {
        var p = sm.speedParts(bps, inBits)
        return p[1] === "" ? p[0] : p[0] + " " + p[1]
    }
    // kB → "6.1" (GB, 1024-based like every memory figure on the desktop)
    function gb(kb) { return (kb / 1048576).toFixed(1) }
    readonly property string memUsedText: sm.memKnown ? sm.gb(sm.memUsedKb) + " GB" : "—"
    readonly property string memTotalText: sm.memKnown ? "of " + sm.gb(sm.memTotalKb) + " GB" : ""
    readonly property string swapText: sm.swapTotalKb <= 0 ? ""
                                     : sm.swapUsedKb < 1024 ? "swap empty"
                                     : sm.swapUsedKb < 1048576 ? Math.round(sm.swapUsedKb / 1024) + " MB in swap"
                                     : sm.gb(sm.swapUsedKb) + " GB in swap"
    readonly property string memCaption: !sm.memKnown ? "" : sm.memPct + "% in use" + (sm.swapText !== "" ? " · " + sm.swapText : "")
    readonly property string cpuText: sm.cpuKnown ? sm.cpuPct + "%" : "—"
    readonly property string memText: sm.memKnown ? sm.memPct + "%" : "—"
    readonly property string cpuCaption: (sm.cores > 0 ? sm.cores + (sm.cores === 1 ? " core" : " cores") + " · " : "") + "last 60 seconds"

    // the Wi-Fi network's name, from the shell's own network reading when a
    // plugin can see it (NetState, `import qs`): its connection is the
    // profile NetworkManager joined — what Quick settings shows too
    readonly property string ssid: {
        if (sm.netKind !== "wifi") return ""
        try {
            var w = NetState.wifi
            if (w && w.state === "connected" && (!w.dev || w.dev === sm.netIf))
                return String(w.connection || "").trim()
        } catch (e) {}
        return ""
    }
    readonly property string kindText: sm.netKind === "wifi" ? "Wi-Fi"
                                      : sm.netKind === "ethernet" ? "Ethernet"
                                      : sm.netKind === "vpn" ? "VPN" : "Offline"
    // the card: "Wi-Fi · home-5G"; the widget leaves the name out
    readonly property string linkText: !sm.netKnown ? "" : sm.ssid !== "" ? "Wi-Fi · " + sm.ssid : sm.kindText

    // ── the desktop widget: shown or not is the HOST's (ewe-plugin place
    //    --visible), not a setting of ours — the card's switch and Komble's
    //    Show on the desktop are the same switch ──────────────────────────
    readonly property string _tool: {
        try { if (PluginHost.tool) return PluginHost.tool } catch (e) {}
        return Quickshell.env("EWE_PLUGIN_TOOL") || (Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-plugin")
    }
    readonly property bool widgetShown: {
        try {
            var p = PluginHost.placement[sm.pluginId]
            return !!p && p.visible !== false
        } catch (e) { return false }
    }
    property bool _userSet: false
    function setWidgetShown(on) {
        sm._userSet = true
        try {
            if (typeof PluginHost.setWidgetVisible === "function") { PluginHost.setWidgetVisible(sm.pluginId, !!on); return }
        } catch (e) {}
        // no host call: the tool itself, which pokes `plugins reload` back
        Quickshell.execDetached([sm._tool, "place", sm.pluginId, "--visible", on ? "on" : "off"])
    }
    // Off until the user turns it on. The manifest says so
    // (desktopWidget.visible: false); a host that does not read that yet
    // shows every widget nobody placed, so the first time the widget loads
    // in a session it asks ewe.conf whether anyone ever chose — and hides
    // itself when not. A stored choice (the card, Komble, the arrange-mode
    // Hide chip, another machine's) always stands.
    property bool _settled: false
    function settleDefault() {
        if (sm._settled || sm._userSet) return
        sm._settled = true
        sm._confRead.running = true
    }
    property Process _confRead: Process {
        command: [sm._tool.replace(/ewe-plugin$/, "ewe-conf"), "get", "plugins.widgets"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (sm._userSet) return
                var t = null
                try { t = JSON.parse(this.text) } catch (e) { t = null }
                var mine = t && t[sm.pluginId]
                if (mine && typeof mine.visible === "boolean") return
                Log.info("ewe.sysmon", "desktop widget: nobody chose to show it yet — hiding it (Show on desktop turns it on)")
                sm.setWidgetShown(false)
            }
        }
    }

    // ── where the card opens from IPC (no click to anchor it): the readout
    //    on the focused output, else the first bar that has one ────────────
    property var _bars: []
    function addBar(owner, item, win) {
        sm._bars = sm._bars.filter(function (b) { return b.owner !== owner }).concat([{ owner: owner, item: item, win: win }])
    }
    function removeBar(owner) { sm._bars = sm._bars.filter(function (b) { return b.owner !== owner }) }
    function barAnchor() {
        var fm = ""
        try { fm = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "" } catch (e) {}
        var pick = null
        for (var i = 0; i < sm._bars.length; i++) {
            var b = sm._bars[i]
            if (!b.item || !b.win || b.win.visible === false) continue
            if (!pick) pick = b
            if (fm !== "" && b.win.screen && b.win.screen.name === fm) { pick = b; break }
        }
        return pick ? Shell.anchorFor(pick.item, pick.win) : null
    }
}
