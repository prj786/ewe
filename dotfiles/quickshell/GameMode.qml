pragma Singleton
import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// GameMode — the shell's half of game mode (0.42). bin/ewe-game owns the
// rest: Hyprland's effects, GameMode's CPU boost, the power profile, the
// background apps it closes and opens again. Its state file
// ($XDG_RUNTIME_DIR/ewe/game.json) is the one truth, whoever changed it —
// the Quick settings tile, ewe Settings, Shaun, or a game asking Feral
// GameMode — so this watches the file and never keeps a second copy.
//
// What the shell does itself while it is on:
//   both levels  banners stay in the list (Notifications.qml), like Do not
//                disturb but without touching the user's own DND switch
//   ultra        desktop widgets hidden (DesktopWidgets.qml), a video
//                wallpaper frozen (Wallpaper.qml)
//
// Automatic ([desktop.game] auto, Globals.gameAuto): a window opening asks
// `ewe-game scan` whether a game is on screen (a Steam game by its
// SteamAppId, gamescope); a window closing asks again only while the scan
// is what turned game mode on. Debounced, one process per burst.
QtObject {
    id: gm

    readonly property string tool: Quickshell.env("EWE_GAME_TOOL")
        || (Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-game")
    readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ewe/game.json"

    property bool on: false
    property string level: Globals.gameLevel
    property var reasons: []
    property var steps: []
    property bool busy: false
    readonly property bool ultra: gm.on && gm.level === "ultra"
    readonly property string label: !gm.on ? "Off" : gm.level === "ultra" ? "Ultra" : "Balanced"

    function _take(d) {
        if (!d || typeof d !== "object") return
        if (d.ok === false) { Log.warn("game", d.error || "ewe-game failed"); return }
        gm.on = d.on === true
        if (d.level === "ultra" || d.level === "balanced") gm.level = d.level
        gm.reasons = d.reasons || []
        gm.steps = d.steps || []
    }

    function toggle() { gm._run(["toggle"]) }
    function setOn(want) { if (want !== gm.on) gm._run([want ? "on" : "off"]) }

    property var _queued: null
    function _run(args) {
        if (gm._proc.running) { gm._queued = args; return }
        gm.busy = args[0] !== "scan" && args[0] !== "status"
        gm._proc.command = [gm.tool].concat(args)
        gm._proc.running = true
    }
    property Process _proc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var d = null
                try { d = JSON.parse(this.text) } catch (e) { d = null }
                gm._take(d)
            }
        }
        onExited: {
            gm.busy = false
            if (gm._queued) { var a = gm._queued; gm._queued = null; gm._run(a) }
        }
    }

    // the state file: whoever turned game mode on or off, the shell follows
    property FileView _state: FileView {
        path: gm.statePath
        watchChanges: true
        printErrors: false
        onFileChanged: this.reload()
        onLoaded: {
            var d = null
            try { d = JSON.parse(this.text()) } catch (e) { d = null }
            if (d) gm._take({ ok: true, on: d.on, level: d.level, reasons: d.reasons, steps: d.steps })
        }
    }

    // automatic: a window opening may be a game; a window closing matters
    // only while a game window is what turned game mode on
    property Timer _scanSoon: Timer { interval: 1500; onTriggered: gm._run(["scan"]) }
    property Connections _events: Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (!Globals.gameAuto) return
            if (ev.name === "openwindow"
                || (ev.name === "closewindow" && gm.reasons.indexOf("window") >= 0))
                gm._scanSoon.restart()
        }
    }
    // `qs ipc call game toggle|on|off|status` — for a keybind of your own
    // (Settings → Shortcuts) or a script; `status` answers "off" / "ultra" /
    // "balanced"
    property IpcHandler _ipc: IpcHandler {
        target: "game"
        function toggle(): void { gm.toggle() }
        function on(): void { gm.setOn(true) }
        function off(): void { gm.setOn(false) }
        function status(): string { return gm.on ? gm.level : "off" }
    }

    // after a shell restart mid-game: read the state, and look once
    property Timer _boot: Timer {
        interval: 4000; running: true
        onTriggered: gm._run([Globals.gameAuto ? "scan" : "status"])
    }
}
