pragma Singleton
import QtQuick
import Quickshell

// Lid — clamshell policy.
//
// The compositor reports the EVENT and the shell decides what it MEANS.
// hyprland.lua binds switch:on/off:Lid Switch → scripts/lid.sh → `qs ipc call
// display lid …` → HyprMon.setLid() → here. Until now the whole policy lived in
// that shell script, which meant a hardcoded eDP-1 (wrong on LVDS/DSI or a
// second panel), a jq dependency whose failure fell through to "suspend", and
// nothing the user could configure.
//
//   lid closed, laptop alone       → suspend
//   lid closed, external connected → Globals.lidDockedSuspend decides: suspend
//                                    (the default — a laptop being closed is
//                                    usually a laptop being carried), or blank
//                                    just the panel and keep working docked
//   lid opened                     → re-enable the panel; HyprMon's re-assert
//                                    lands the saved mode/scale/position on top
//
// Locking is deliberately NOT done here. Suspending raises PrepareForSleep, and
// the logind delay inhibitor (Logind.qml) locks the session before the machine
// goes down. That handshake is why lid.sh's old `sleep 0.5` between locking and
// suspending is gone — it was a guess, and a guess is exactly what raced.
QtObject {
    id: lid

    readonly property bool closed: HyprMon.lidClosed

    // External outputs that are actually LIT. A connected-but-disabled output is
    // not somewhere you can keep working, so it must not count as "docked".
    readonly property int externals: {
        var ms = HyprMon.monitors || [], n = 0
        for (var i = 0; i < ms.length; i++)
            if (!HyprMon.isInternal(ms[i].name) && !ms[i].disabled) n++
        return n
    }
    readonly property bool docked: externals > 0

    property Connections _watch: Connections {
        target: HyprMon
        function onLidClosedChanged() { lid.apply() }
    }

    function apply() {
        if (lid.closed) lid._close()
        else lid._open()
    }

    function _close() {
        var suspend = !lid.docked || Globals.lidDockedSuspend
        Log.info("lid", "closed —", lid.docked ? "docked (" + lid.externals + " external)" : "laptop alone",
                 "→", suspend ? "suspend" : "blank the panel, keep working")
        // Retract transient surfaces either way. Popups latch their output when
        // they open and have no migration path, so one sitting on the panel that
        // is about to go dark would be stranded on a screen that no longer exists.
        lid.retract()
        if (suspend) {
            Quickshell.execDetached(["systemctl", "suspend"])
            return
        }
        lid._setInternal(false)
    }

    function _open() {
        Log.info("lid", "opened — re-enabling the built-in panel")
        lid._setInternal(true)
        // belt-and-braces for the xe/PSR panel: a re-enabled output can come
        // back powered but dark; dpms on is a no-op when it is already lit
        Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.dpms("on")'])
        // HyprMon.setLid(false) has already armed its re-assert, which applies
        // the saved geometry on top of these safe defaults a moment later
    }

    // Touch ONLY the built-in panel. Re-applying every output would be one
    // modeset per monitor, and on this xe/Lunar Lake hardware a needless modeset
    // is precisely what the display-recovery work went out of its way to avoid
    // (its PSR path answers one with a permanently black panel).
    function _setInternal(on) {
        var ms = HyprMon.monitors || [], stmts = []
        for (var i = 0; i < ms.length; i++) {
            var m = ms[i]
            if (!HyprMon.isInternal(m.name)) continue
            // match by description where we have one — connector names are not
            // stable across docks, which is why HyprMon keys profiles this way
            var id = m.description ? "desc:" + HyprMon.luaEsc(m.description) : m.name
            stmts.push(on
                ? 'hl.monitor({ output = "' + id + '", disabled = false, mode = "preferred", position = "auto" })'
                : 'hl.monitor({ output = "' + id + '", disabled = true })')
        }
        if (!stmts.length) { Log.warn("lid", "no built-in panel found — nothing to do"); return }
        // never black out the whole desk — recovering from that needs a reboot
        if (!on && lid.externals === 0) { Log.warn("lid", "refusing to blank the only display"); return }
        HyprMon.runEvals(stmts, null)
    }

    function retract() {
        Globals.storeOpen = false
        Globals.placesOpen = false
        Globals.clipboardOpen = false
        Globals.launcherOpen = false
        Globals.trayMenuOpen = false
        Globals.overviewOpen = false
        Globals.quickSettingsOpen = false
        Globals.openDd = ""
    }

    // shell.qml pokes this so the policy is armed from login — the lid can be
    // shut before anything else would have referenced the singleton
    function start() { Log.debug("lid", "policy armed") }
}
