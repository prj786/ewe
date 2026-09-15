pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// GlobalShortcuts — makes apps' PORTAL global shortcuts fire. 1Password's
// Quick Access, Discord push-to-talk, Slack, OBS… register a shortcut through
// xdg-desktop-portal's GlobalShortcuts; under Hyprland nothing is bound until
// the config says `hl.bind(key, hl.dsp.global(name))`, so out of the box every
// one of them is dead. bin/ewe-globalshortcuts turns Electron-style names
// (they carry their trigger: `…-Ctrl+Shift+Space`) into binds, writes
// generated/globalshortcuts.lua for the next reload and applies the new ones
// live. This singleton just decides WHEN: at startup, whenever a window opens
// (an app that just launched registers its shortcuts moments later), and on a
// slow heartbeat for tray-only apps that never open a window (1Password at
// login). One IPC read per tick — cheap.
QtObject {
    id: gs

    property int bound: 0
    property var skipped: []          // [{name, reason}] — Settings may show these
    property string lastError: ""
    property bool _dirty: true

    function start() { _boot.start(); _beat.start() }
    function sync() { if (!_proc.running) _proc.running = true; else gs._dirty = true }

    property Timer _boot: Timer { interval: 4000; onTriggered: gs.sync() }
    property Timer _beat: Timer { interval: 30000; repeat: true; onTriggered: gs.sync() }
    // a new window: its app may have just registered shortcuts — look shortly after
    property Timer _debounce: Timer { interval: 1500; onTriggered: gs.sync() }
    property Connections _events: Connections {
        target: Hyprland
        function onRawEvent(ev) { if (ev.name === "openwindow") gs._debounce.restart() }
    }

    property Process _proc: Process {
        command: ["ewe-globalshortcuts", "sync"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d = null
                try { d = JSON.parse(this.text) } catch (e) { d = null }
                if (!d) { gs.lastError = "ewe-globalshortcuts: no answer"; return }
                gs.bound = d.bound || 0
                gs.skipped = d.skipped || []
                gs.lastError = d.ok ? "" : (d.error || (d.failed && d.failed.length ? d.failed[0].error : "failed"))
                if (d.added && d.added.length)
                    for (var i = 0; i < d.added.length; i++) Log.info("globalshortcuts", "bound", d.added[i].combo, "→", d.added[i].name)
                if (gs.lastError) Log.warn("globalshortcuts", gs.lastError)
            }
        }
        onExited: { if (gs._dirty) { gs._dirty = false; gs._proc.running = true } }
    }
}
