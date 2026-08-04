pragma Singleton
import QtQuick
import Quickshell

// Resume — the ordered wake-up routine.
//
// This is where shells usually break. After a suspend essentially every cached
// value in the shell is a lie: the battery moved, the charger may have come or
// gone, the dock may have been plugged or unplugged, OAuth tokens minted hours
// ago are expired, timers that were counting down were frozen mid-tick, and any
// D-Bus subscription whose bus connection died is now a silent zombie that will
// never report anything again.
//
// The temptation is to scatter a listener per concern. That gives you no order,
// no way to know whether a step ran, and no way to debug "the calendar was empty
// after I opened the lid". So there is exactly ONE routine, it runs in a fixed
// order, and every step logs. Run `HS_LOG=info qs` and a wake reads as a
// transcript.
//
// Ordering rationale: local state first (it cannot fail and the UI shows it
// immediately), then displays (the user is staring at them), then the network
// steps LAST and deferred — on wake the Wi-Fi link has usually not
// reassociated yet, so firing token refreshes immediately just burns a helper
// process to discover the obvious.
QtObject {
    id: rs

    property bool busy: false
    property int runs: 0
    property double lastRun: 0

    // Non-singleton components (Battery, the clocks, the bar's network probes)
    // cannot be called directly, so the routine drives them through these. They
    // are emitted from run() in order — this is a sequence, not a broadcast.
    signal resyncTime()
    signal resyncPower()
    signal resyncNetwork()

    // how long to let the link come back before touching the network
    readonly property int networkDelayMs: 3000

    property Connections _hook: Connections {
        target: Logind
        function onResumed() { rs.run("resume") }
        // Going back down inside the deferred network window: drop the pending
        // step and clear busy, or the NEXT wake would be ignored as "already
        // running" and never refresh its tokens.
        function onAboutToSleep() {
            if (!rs.busy) return
            rs._netStep.stop()
            rs.busy = false
            Log.debug("resume", "suspended again mid-sequence — cancelled the deferred step")
        }
    }

    function run(reason) {
        if (rs.busy) { Log.debug("resume", "already running — ignoring", reason); return }
        rs.busy = true
        rs.runs++
        rs.lastRun = Date.now()
        Log.info("resume", "=== wake sequence start (" + reason + ") ===")

        // 1. time — a Timer frozen mid-tick fires late, so clocks can show a
        //    stale minute until their next boundary. Re-tick them now.
        //    Note: this does NOT re-read the timezone. Qt caches the system zone
        //    for the process lifetime, so a machine that crossed a timezone while
        //    asleep still needs a shell reload — worth knowing, not worth faking.
        Log.info("resume", "1/6 clocks")
        rs.resyncTime()

        // 2. power — percentage, charging state and the AC line all moved while
        //    we were down, and brightness may have been changed by firmware.
        Log.info("resume", "2/6 power + brightness")
        Logind.refreshBrightness()
        Power.refresh()
        rs.resyncPower()

        // 3. displays — the dock state can have changed while asleep, which no
        //    hotplug event will tell us about because we were not running to
        //    hear it. reassert(false) re-queries first and only corrects real
        //    drift, so this is cheap when nothing moved. Wake is GUARDED
        //    (wakeIfAsleep: dpms-on only for outputs reporting dpms-off) — the
        //    old unconditional dpms("on") here cycled already-lit panels and
        //    produced a visible blink on every keyboard wake. The lid-open
        //    "powered but dark" xe failure keeps its unconditional insurance in
        //    Lid.qml, which is the path where that failure actually occurs.
        Log.info("resume", "3/6 displays")
        HyprMon.wakeIfAsleep()
        HyprMon.reassert(false)

        // 4. bridges — a helper whose bus connection died does not necessarily
        //    exit; it can sit there looking alive and reporting nothing.
        Log.info("resume", "4/6 bridge liveness")
        KdeConnect.probeLiveness()

        // 5+6 need the network, which is very unlikely to be up yet.
        rs._netStep.restart()
    }

    property Timer _netStep: Timer {
        interval: rs.networkDelayMs
        onTriggered: {
            Log.info("resume", "5/6 network probes")
            rs.resyncNetwork()

            // 6. accounts — every access token minted before the suspend is
            //    expired. Refresh proactively instead of letting the next poll
            //    find out by failing a request. If the link still is not up this
            //    fails safely: Google keeps its cached events, goes "offline" and
            //    arms its own retry.
            Log.info("resume", "6/6 accounts")
            Google.refreshAfterResume()

            rs.busy = false
            Log.info("resume", "=== wake sequence done ===")
        }
    }

    // shell.qml pokes this so the routine is armed from login rather than from
    // whenever something first happens to reference the singleton
    function start() { Log.debug("resume", "service armed") }
}
