pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// SysMon — the CPU / memory sampler the tile and the bar widgets share
// (registered by the qmldir beside it, so every entry point sees one
// instance). It samples ONLY while something shows the numbers: each
// consumer `hold()`s while it is on screen (the tile while Quick settings
// is open on home, a bar widget while `show_in_bar` is on) and the timer runs
// while anyone holds. Nothing is spawned for meters nobody can see — the
// shell's sampler used to cost ~170k fork/exec a day behind a closed panel.
//
// One process per tick (sample.sh, plain sh) reading /proc/stat and
// /proc/meminfo; the interval follows Shell.lowPower (1.5 s → 3 s on battery).
QtObject {
    id: sm

    property real cpuUsage: 0      // 0..1
    property real memUsage: 0      // 0..1
    readonly property int cpuPct: Math.round(sm.cpuUsage * 100)
    readonly property int memPct: Math.round(sm.memUsage * 100)

    // who wants samples right now — object identities, so a holder that
    // goes away (a bar on an unplugged monitor) can be released by the
    // same handle, and the same holder is never counted twice
    property var _holders: []
    readonly property int wanted: sm._holders.length
    function hold(who, on) {
        var h = sm._holders.filter(function (x) { return x !== who })
        if (on) h.push(who)
        sm._holders = h
    }
    // drop the baseline when sampling stops, so the first tick after a
    // reopen does not average across the whole idle period
    onWantedChanged: if (sm.wanted === 0) sm._prev = null

    readonly property string script: Qt.resolvedUrl("sample.sh").toString().replace(/^file:\/\//, "")
    property var _prev: null                 // { total, idle } jiffies of the last tick

    property Process _proc: Process {
        command: sm._prev ? ["sh", sm.script, String(sm._prev.total), String(sm._prev.idle)] : ["sh", sm.script]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (!j || !j.ok) { Log.warn("ewe.sysmon", "sample failed:", j && j.error); return }
                    if (typeof j.cpu === "number") sm.cpuUsage = Math.max(0, Math.min(1, j.cpu))
                    if (typeof j.mem === "number") sm.memUsage = Math.max(0, Math.min(1, j.mem))
                    sm._prev = { total: j.total, idle: j.idle }
                } catch (e) { Log.warn("ewe.sysmon", "unreadable sample:", String(e)) }
            }
        }
    }
    property Timer _timer: Timer {
        interval: Shell.lowPower ? 3000 : 1500
        running: sm.wanted > 0
        repeat: true; triggeredOnStart: true
        onTriggered: if (!sm._proc.running) sm._proc.running = true
    }
}
