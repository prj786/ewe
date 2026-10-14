pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import "logic.js" as Logic

// SafeState — what the bar glyph, the Quick settings tile and Quick Access
// share (one singleton, registered by the qmldir beside it). It follows Safe
// through `ewe-safe watch`: one JSON line per event, the first one the
// current status (ewe-safe docs/PROTOCOL.md). The bridge restarts with a
// growing pause when it ends; the daemon itself is socket-activated, so
// "down" means Safe's units aren't installed or failed.
//
// The master password never comes here (Safe PLAN.md S4): unlocking runs
// `ewe-safe unlock --ask`, which opens Safe's own prompt. A password never
// comes here either: copies are the daemon's (`ewe-safe copy`), and the
// only secret this file ever reads is a one-time code, for display.
QtObject {
    id: safe

    readonly property string tool: "ewe-safe"
    readonly property string app: "ewe-safe-app"

    property var state: Logic.blank()
    property bool appInstalled: false
    // bumped whenever the items may have changed — Quick Access reloads
    property int generation: 0
    property double now: Date.now()

    readonly property string phase: safe.state.phase
    readonly property bool unlocked: safe.phase === "unlocked"
    readonly property bool locked: safe.phase === "locked"
    readonly property string attention: Logic.attention(safe.state)
    readonly property string syncLine: Logic.syncLine(safe.state, safe.now)
    readonly property string tileSub: Logic.tileSub(safe.state)

    signal unlockFinished(bool ok)

    function _set(s) { safe.state = s }
    function refresh() { if (!safe._status.running) safe._status.running = true }

    // ── actions ──────────────────────────────────────────────────────────
    function unlock() {
        if (safe._unlock.running) return
        Shell.closeQuickSettings()       // the prompt needs the keyboard
        safe._unlock.running = true
    }
    function lock() { if (!safe._lock.running) safe._lock.running = true }
    function toggleLock() {
        if (safe.unlocked) safe.lock()
        else if (safe.locked) safe.unlock()
        else if (safe.phase === "new") safe.openApp("")
        else Shell.toast(safe.phase === "down" ? "Safe isn't running." : "Safe isn't installed.", "warning")
    }
    function copy(id, field) {
        if (!id) return
        safe._copy.field = field
        safe._copy.command = Logic.copyArgv(safe.tool, id, field)
        safe._copy.running = true
    }
    // the Safe window: "" opens it, "show" an item, "new" a login
    function openApp(what, id) {
        if (!safe.appInstalled) {
            Shell.toast("The Safe window isn't installed yet. Use ewe-safe in a terminal for now.", "warning")
            safe._probeApp.running = true      // it may have arrived since
            return
        }
        Shell.closeQuickSettings()
        Quickshell.execDetached(Logic.appArgv(safe.app, what || "", id || ""))
    }
    function statusJson() {
        return JSON.stringify({ phase: safe.phase, items: safe.state.items, attention: safe.attention,
                                sync: safe.syncLine, appInstalled: safe.appInstalled })
    }

    // ── the bridge: `ewe-safe watch` ─────────────────────────────────────
    // A watchdog, not `exited`, brings it back: a binary that isn't there
    // fails to start without any signal (Quickshell only logs it), so
    // whenever the bridge isn't running the timer asks `which` and starts it
    // again — with a growing pause, so a missing Safe costs one `which`
    // every 30 s and an installed one is picked up without a restart.
    property int _lines: 0
    property int _backoff: 1000
    property Process _watch: Process {
        command: [safe.tool, "watch"]
        running: true
        stdout: SplitParser {
            onRead: function (line) {
                safe._lines++
                safe._backoff = 1000
                var r = Logic.applyLine(safe.state, line)
                safe._set(r.state)
                if (r.refresh) { safe.refresh(); safe.generation++ }
            }
        }
        onExited: function (code) {
            if (safe._lines > 0 && safe.phase !== "down")
                safe._set(Logic.applyLine(safe.state, '{"event":"daemon-gone"}').state)
            safe._lines = 0
        }
    }
    property Timer _retry: Timer {
        interval: safe._backoff
        repeat: true
        running: !safe._watch.running
        onTriggered: {
            safe._backoff = Math.min(safe._backoff * 2, 30000)
            if (!safe._probeTool.running) safe._probeTool.running = true
        }
    }
    property Process _probeTool: Process {
        command: ["which", safe.tool]
        stdout: StdioCollector {}
        onExited: function (code) {
            if (code !== 0) { if (safe.phase !== "missing") safe._set(Logic.blank()); return }
            if (!safe._watch.running) safe._watch.running = true
        }
    }
    property Process _probeApp: Process {
        command: ["which", safe.app]
        running: true
        stdout: StdioCollector {}
        onExited: function (code) { safe.appInstalled = code === 0 }
    }

    // ── one-shot calls ───────────────────────────────────────────────────
    property Process _status: Process {
        command: [safe.tool, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d = null
                try { d = JSON.parse(this.text) } catch (e) { return }
                safe._set(Logic.fromStatus(safe.state, d))
            }
        }
    }
    property Process _unlock: Process {
        command: [safe.tool, "unlock", "--ask"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d = null
                try { d = JSON.parse(this.text) } catch (e) { d = null }
                if (d && d.ok) { safe.refresh(); safe.unlockFinished(true); return }
                safe.unlockFinished(false)
                if (d && d.error === "cancelled") return
                if (d) safe._set(Logic.fromStatus(safe.state, d))
                Shell.toast(d && d.message ? d.message : "Safe is still locked.", "warning")
            }
        }
    }
    property Process _lock: Process {
        command: [safe.tool, "lock"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d = null
                try { d = JSON.parse(this.text) } catch (e) { d = null }
                if (!d || !d.ok) Shell.toast("Couldn't lock Safe.", "warning")
            }
        }
    }
    property Process _copy: Process {
        property string field: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var d = null
                try { d = JSON.parse(this.text) } catch (e) { d = null }
                if (d && d.ok) Shell.toast(Logic.copiedText(safe._copy.field, d.cleared_after || 0))
                else Shell.toast(d && d.message ? d.message : "Couldn't copy.", "warning")
            }
        }
    }

    // keeps "In sync · 2 min ago" honest
    property Timer _tick: Timer {
        interval: 30000
        repeat: true
        running: safe.state.sync !== null
        onTriggered: safe.now = Date.now()
    }
}
