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
//   lid opened                     → if (and only if) the panel is off, bring
//                                    it back with its saved mode/scale/position;
//                                    a panel that is already lit is left alone
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
    //
    // "Still shut" is asked of ACPI, not of the cached flag. After a hibernate
    // the flag is whatever it was when the machine went down — closed — while
    // the person has the lid open in front of them; 4 of 7 hibernate resumes
    // on the 2026-10 machine re-slept within a second on exactly that lie.
    property Connections _wake: Connections {
        target: Logind
        function onResumed() {
            HyprMon.probeLid(function (closed) {
                if (closed && !lid.docked) {
                    Log.info("lid", "woke with the lid still closed and no dock — re-sleeping in 30 s unless it opens")
                    lid._wakeGrace.restart()
                }
            })
        }
        // Going down: nothing that can put the machine BACK to sleep may be
        // left armed. A Timer counts on a clock that keeps running through the
        // hibernate transition (suspend-then-hibernate wakes for ~12 s to write
        // the image), so an 8 s grace armed by DP-1 dropping as we went down
        // fired the instant we came back up — and slept the machine again.
        function onAboutToSleep() { lid._grace.stop(); lid._wakeGrace.stop() }
    }
    property Timer _wakeGrace: Timer {
        interval: 30000
        onTriggered: lid._sleepIfStillClosed("still closed 30 s after an unexplained wake")
    }

    property Timer _grace: Timer {
        interval: 8000
        onTriggered: lid._sleepIfStillClosed("still closed and " + (lid.docked ? "now on battery" : "no external left"))
    }

    // The grace timers' verdict: the lid is REALLY shut (ACPI, right now) and
    // the policy still says sleep. The cached flag is not consulted — see _wake.
    function _sleepIfStillClosed(why) {
        HyprMon.probeLid(function (closed) {
            if (!closed) { Log.info("lid", why + " — but ACPI says it is open now; staying awake"); return }
            if (!lid.shouldSleep) return   // a dock appeared, the charger came back
            lid._sleep(why)
        })
    }

    function _sleep(why) {
        // Every sleep request this shell makes is one line in the journal with
        // its reason — a machine that re-sleeps on its own must never again be
        // a guess ("the request came from ewe.service" was all the journal had).
        Log.warn("lid", "going to sleep:", why || "lid policy")
        // zzz.sh = suspend-then-hibernate with a plain-suspend fallback, so a
        // lid left shut for days ends in zero-drain hibernate, not a dead cell.
        Quickshell.execDetached(["sh", "-c", "exec \"$HOME/.config/hypr/scripts/zzz.sh\""])
    }

    function apply() {
        if (lid.closed) lid._close()
        else { lid._grace.stop(); lid._wakeGrace.stop(); lid._open() }
    }

    function _close() {
        var how = lid.docked ? "docked (" + lid.externals + " external" + (Globals.onBattery ? ", on battery" : ", on AC") + ")" : "laptop alone"
        Log.info("lid", "closed —", how, "→", lid.shouldSleep ? "sleep" : "blank the panel, keep working")
        // Retract transient surfaces either way. Popups latch their output when
        // they open and have no migration path, so one sitting on the panel that
        // is about to go dark would be stranded on a screen that no longer exists.
        lid.retract()
        if (lid.shouldSleep) {
            lid._sleep("lid closed, " + how + (Globals.locked ? ", locked" : ""))
            return
        }
        lid._setInternal(false)
    }

    // Lid opened. On a laptop that slept alone NOTHING was disabled — the
    // panel is up, lit, at its saved scale — and the right thing to do is
    // nothing. The old _open issued `disabled=false, preferred, auto` (knocking
    // the 1.8-scaled eDP to a different layout) and an unconditional dpms-on
    // (a visible cycle of an already-lit xe panel), and HyprMon then repaired
    // the layout 500 ms later: three modesets, each re-laying-out the lock
    // screen — the 3-4 blinks before the password prompt (2026-10-04).
    //
    // So: ask Hyprland what is live, and only an internal panel that is
    // actually DISABLED (clamshell "keep working" blanked it) is re-enabled —
    // with its SAVED profile entry, never preferred/auto. The dpms insurance
    // is HyprMon's guarded one: it lights only an output reporting dpms-off.
    function _open() {
        HyprMon.query(function (ms) {
            var dark = [], stmts = []
            for (var i = 0; i < ms.length; i++)
                if (HyprMon.isInternal(ms[i].name) && ms[i].disabled) dark.push(ms[i])
            if (!dark.length) {
                Log.info("lid", "opened — the built-in panel is already on; nothing to apply")
                HyprMon.wakeIfAsleep()
                return
            }
            for (var k = 0; k < dark.length; k++) {
                var m = dark[k], s = HyprMon.savedSpecFor(m)
                if (s && !s.disabled) stmts.push("hl.monitor(" + HyprMon.luaArgs(s) + ")")
                else {
                    // no profile for this set (or it saved the panel off): the
                    // only honest geometry is Hyprland's own default
                    Log.warn("lid", "no saved layout for", m.name, "— re-enabling at preferred/auto")
                    stmts.push('hl.monitor({ output = "' + lid._outputId(m) + '", disabled = false, mode = "preferred", position = "auto" })')
                }
            }
            Log.info("lid", "opened — re-enabling", dark.map(function (m) { return m.name }).join(", "), "with the saved layout")
            HyprMon.runEvals(stmts, function () { HyprMon.wakeIfAsleep() })
        })
    }

    // match by description where we have one — connector names are not
    // stable across docks, which is why HyprMon keys profiles this way
    function _outputId(m) { return m.description ? "desc:" + HyprMon.luaEsc(m.description) : m.name }

    // Blank ONLY the built-in panel (clamshell keep-working). Re-applying every
    // output would be one modeset per monitor, and on this xe/Lunar Lake
    // hardware a needless modeset is precisely what the display-recovery work
    // went out of its way to avoid (its PSR path answers one with a
    // permanently black panel).
    function _setInternal(on) {
        var ms = HyprMon.monitors || [], stmts = []
        for (var i = 0; i < ms.length; i++) {
            var m = ms[i]
            if (!HyprMon.isInternal(m.name)) continue
            stmts.push(on
                ? 'hl.monitor({ output = "' + lid._outputId(m) + '", disabled = false, mode = "preferred", position = "auto" })'
                : 'hl.monitor({ output = "' + lid._outputId(m) + '", disabled = true })')
        }
        if (!stmts.length) { Log.warn("lid", "no built-in panel found — nothing to do"); return }
        // never black out the whole desk — recovering from that needs a reboot
        if (!on && lid.externals === 0) { Log.warn("lid", "refusing to blank the only display"); return }
        HyprMon.runEvals(stmts, null)
    }

    function retract() {
        Globals.storeOpen = false
        Globals.placesOpen = false
        Quickshell.execDetached(["qs", "ipc", "call", "ewe.clipboard", "hide"])   // the clipboard plugin, if present
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
