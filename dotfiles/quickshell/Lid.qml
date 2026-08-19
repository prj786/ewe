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
//   lid closed, laptop alone       → sleep (zzz.sh: suspend-then-hibernate)
//   lid closed, docked, ON AC      → Globals.lidDockedSuspend decides: blank
//                                    just the panel and keep working (the
//                                    default — that's what a dock is for), or
//                                    sleep anyway
//   lid closed, docked, ON BATTERY → sleep, always. A hub that lights a monitor
//                                    but doesn't feed the laptop kept machines
//                                    awake in a bag all night (2026-08-08:
//                                    23:33 close → 10:09 open, zero suspends,
//                                    battery gone by morning). No display setup
//                                    is worth a cooked battery.
//   lid opened                     → re-enable the panel; HyprMon's re-assert
//                                    lands the saved mode/scale/position on top
//
// The keep-working choice is also NOT final: while the lid stays closed, losing
// AC or losing the last lit external re-runs the policy (with a short grace so
// a dock re-enumeration blip doesn't sleep the machine mid-flap).
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

    // The one sleep decision, asked at close time AND re-asked while closed.
    // A LOCKED session always sleeps: nobody is working through that lid, and
    // "locked + shut + awake" is exactly the shape of the bag-drain incidents.
    readonly property bool shouldSleep: Globals.locked || !docked || Globals.lidDockedSuspend || Globals.onBattery

    property Connections _watch: Connections {
        target: HyprMon
        function onLidClosedChanged() { lid.apply() }
    }

    // While closed and kept awake, the world can change under us: the charger
    // gets pulled (docked → carried), or the dock/monitor goes away and the
    // machine is running blind with no display at all. Either way re-run the
    // policy — after a grace period, because USB-C docks re-enumerate on their
    // own and a two-second monitor flap must not sleep the machine.
    onExternalsChanged: _recheck()
    property Connections _power: Connections {
        target: Globals
        function onOnBatteryChanged() { lid._recheck() }
    }

    function _recheck() {
        if (lid.closed && lid.shouldSleep) lid._grace.restart()
    }

    // A wake that arrives with the lid still SHUT and no dock was not a person
    // opening the laptop — it is the Logitech receiver seeing a mouse jiggle,
    // or any other stray wake source, reaching a machine in a bag. The lid
    // switch never changes state across that wake, so no close event will ever
    // re-fire; without this the machine sits awake in the dark until the cell
    // is gone. 30 s of grace: a deliberate wake shows itself by the lid opening
    // (or a dock appearing), either of which disarms the timer's condition.
    property Connections _wake: Connections {
        target: Logind
        function onResumed() {
            if (lid.closed && !lid.docked) {
                Log.info("lid", "woke with the lid still closed and no dock — re-sleeping in 30 s unless it opens")
                lid._wakeGrace.restart()
            }
        }
    }
    property Timer _wakeGrace: Timer {
        interval: 30000
        onTriggered: {
            if (!lid.closed || !lid.shouldSleep) return
            Log.info("lid", "still closed 30 s after an unexplained wake — going back to sleep")
            lid._sleep()
        }
    }

    property Timer _grace: Timer {
        interval: 8000
        onTriggered: {
            if (!lid.closed || !lid.shouldSleep) return   // recovered or reopened
            Log.info("lid", "still closed and", lid.docked ? "now on battery" : "no external left", "— going to sleep")
            lid._sleep()
        }
    }

    function _sleep() {
        // zzz.sh = suspend-then-hibernate with a plain-suspend fallback, so a
        // lid left shut for days ends in zero-drain hibernate, not a dead cell.
        Quickshell.execDetached(["sh", "-c", "exec \"$HOME/.config/hypr/scripts/zzz.sh\""])
    }

    function apply() {
        if (lid.closed) lid._close()
        else { lid._grace.stop(); lid._wakeGrace.stop(); lid._open() }
    }

    function _close() {
        Log.info("lid", "closed —", lid.docked ? "docked (" + lid.externals + " external" + (Globals.onBattery ? ", on battery" : ", on AC") + ")" : "laptop alone",
                 "→", lid.shouldSleep ? "sleep" : "blank the panel, keep working")
        // Retract transient surfaces either way. Popups latch their output when
        // they open and have no migration path, so one sitting on the panel that
        // is about to go dark would be stranded on a screen that no longer exists.
        lid.retract()
        if (lid.shouldSleep) {
            lid._sleep()
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
