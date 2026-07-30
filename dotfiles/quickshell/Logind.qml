pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Logind — THE systemd-logind service. Owns the D-Bus bridge process
// (scripts/logind-bridge.py, NDJSON over stdio) and everything the shell needs
// from org.freedesktop.login1:
//
//   * PrepareForSleep / PrepareForShutdown, with a DELAY INHIBITOR held by the
//     bridge so we lock BEFORE the machine suspends instead of racing it. The
//     contract: on aboutToSleep() a consumer does its work and then calls
//     sleepReady(). Miss it and the bridge lets go on its own timer — a held
//     delay stalls every suspend on the machine, so it is never left to chance.
//   * the session's Lock / Unlock signals, which is what `loginctl lock-session`
//     actually emits (Lock.qml documented this recovery path for years while
//     nothing implemented it, because hypridle owned the signal instead).
//   * LockedHint / IdleHint mirrored into shell state, so lock state has ONE
//     source of truth that the rest of the system can see too.
//   * SetBrightness for the panel and keyboard backlights — logind writes sysfs
//     on our behalf, so there is no udev rule and no setuid helper to ship.
//     Callers fall back to brightnessctl when the bridge is unavailable.
QtObject {
    id: ld

    // ── availability ────────────────────────────────────────────────────────
    property bool bridgeUp: false
    property bool bridgeFailed: false    // terminal — respawning cannot help
    property string bridgeError: ""
    property int _restarts: 0

    // ── session state ───────────────────────────────────────────────────────
    property string sessionPath: ""
    property bool inhibited: false       // we hold the sleep delay
    property int delayMs: 4000           // how long the bridge will hold it
    property bool lockedHint: false      // logind's view of "screen is locked"
    property bool idleHint: false
    property bool preparingForSleep: false

    // { name, max, value, percent } — null when the machine has no such device
    property var backlight: null
    property var kbdBacklight: null
    readonly property bool hasBacklight: backlight !== null
    readonly property bool hasKbdBacklight: kbdBacklight !== null

    // ── signals consumers hang off ──────────────────────────────────────────
    signal aboutToSleep()        // delay held: do pre-sleep work, then sleepReady()
    signal resumed()             // woke up — everything cached is now suspect
    signal aboutToShutdown()
    signal lockRequested()       // loginctl lock-session
    signal unlockRequested()     // loginctl unlock-session

    readonly property string bridgePath: Quickshell.env("HOME") + "/.config/quickshell/scripts/logind-bridge.py"

    // ── bridge process ──────────────────────────────────────────────────────
    property Process _bridge: Process {
        running: true
        command: ["python3", ld.bridgePath]
        stdinEnabled: true
        stdout: SplitParser { onRead: function (data) { ld._onEvent(data) } }
        onExited: {
            ld.bridgeUp = false
            ld.inhibited = false
            if (ld.bridgeFailed) return              // it told us why; retrying is pointless
            if (ld._restarts >= 5) {
                ld.bridgeError = "logind bridge keeps exiting — run with HS_LOG=info for the reason."
                Log.error("logind", "bridge exited", ld._restarts, "times — giving up")
                return
            }
            ld._restarts++
            ld._restart.interval = 5000 * ld._restarts
            Log.warn("logind", "bridge exited — retry", ld._restarts, "in", ld._restart.interval + "ms")
            ld._restart.restart()
        }
    }
    property Timer _restart: Timer { interval: 5000; onTriggered: { ld._bridge.running = true } }
    function send(o) { if (ld._bridge.running) ld._bridge.write(JSON.stringify(o) + "\n") }

    function retryBridge() {
        ld.bridgeFailed = false; ld.bridgeError = ""; ld._restarts = 0
        ld._restart.interval = 5000
        ld._bridge.running = false
        ld._bridge.running = true
    }

    function _onEvent(line) {
        var e
        try { e = JSON.parse(line) } catch (err) { return }
        switch (e.event) {
        case "hello":
            ld.bridgeUp = true
            ld.bridgeError = ""
            ld._restarts = 0
            ld._restart.interval = 5000
            ld.sessionPath = e.session || ""
            ld.inhibited = !!e.inhibited
            if (e.delayMs) ld.delayMs = e.delayMs
            ld.lockedHint = !!e.lockedHint
            ld.idleHint = !!e.idleHint
            ld.backlight = e.backlight || null
            ld.kbdBacklight = e.kbd || null
            Log.info("logind", "session", ld.sessionPath, "· delay", ld.delayMs + "ms",
                     "· backlight", ld.backlight ? ld.backlight.name : "none",
                     "· kbd", ld.kbdBacklight ? ld.kbdBacklight.name : "none")
            break
        case "sleep":
            if (e.starting) {
                ld.preparingForSleep = true
                if (e.delayMs) ld.delayMs = e.delayMs
                Log.info("logind", "PrepareForSleep(true) — holding the delay for up to", ld.delayMs + "ms")
                ld.aboutToSleep()
            } else {
                ld.preparingForSleep = false
                ld.inhibited = true          // the bridge re-takes it on resume
                Log.info("logind", "PrepareForSleep(false) — resumed")
                ld.resumed()
            }
            break
        case "shutdown":
            if (e.starting) { ld.preparingForSleep = true; ld.aboutToShutdown() }
            else ld.preparingForSleep = false
            break
        case "sleepTimeout":
            // nobody called sleepReady() in time; the bridge let go so the
            // machine could actually suspend. Worth knowing about — it means a
            // pre-sleep step is hanging.
            Log.warn("logind", "no sleepReady() within", e.ms + "ms — released the delay anyway")
            ld.inhibited = false
            break
        case "lock":
            Log.info("logind", "session Lock")
            ld.lockRequested()
            break
        case "unlock":
            Log.info("logind", "session Unlock")
            ld.unlockRequested()
            break
        case "session":
            if (e.lockedHint !== undefined) ld.lockedHint = !!e.lockedHint
            if (e.idleHint !== undefined) ld.idleHint = !!e.idleHint
            break
        case "brightness":
            ld.backlight = e.backlight || null
            ld.kbdBacklight = e.kbd || null
            break
        case "fatal":
            ld.bridgeFailed = true
            ld.bridgeError = e.error || "logind bridge unavailable"
            Log.error("logind", "bridge fatal:", ld.bridgeError)
            break
        case "error":
            Log.warn("logind", "command", e.cmd || "?", "failed:", e.error || "?")
            break
        }
    }

    // ── API ─────────────────────────────────────────────────────────────────
    // Tell logind we are done preparing and it may suspend now. Call this from
    // every aboutToSleep() consumer — the bridge's timer is a backstop, not a
    // plan (waiting it out delays the suspend by the full window every time).
    function sleepReady() {
        if (!ld.preparingForSleep) return
        ld.inhibited = false
        ld.send({ cmd: "sleepReady" })
    }

    // Brightness via logind, 0..1. Returns false when unavailable so the caller
    // can fall back to brightnessctl.
    function setBrightness(pct) {
        if (!ld.bridgeUp || !ld.hasBacklight) return false
        ld.send({ cmd: "setBrightness", device: "backlight", percent: pct })
        return true
    }
    function setKbdBrightness(pct) {
        if (!ld.bridgeUp || !ld.hasKbdBacklight) return false
        ld.send({ cmd: "setBrightness", device: "kbd", percent: pct })
        return true
    }
    function refreshBrightness() { if (ld.bridgeUp) ld.send({ cmd: "getBrightness" }) }

    // Mirror the shell's lock state onto the session so `loginctl` and anything
    // else on the system agrees with us about whether the screen is locked.
    function setLockedHint(v) { if (ld.bridgeUp) ld.send({ cmd: "setLockedHint", value: !!v }) }
    function setIdleHint(v) { if (ld.bridgeUp) ld.send({ cmd: "setIdleHint", value: !!v }) }
    function refresh() { if (ld.bridgeUp) ld.send({ cmd: "refresh" }) }

    // Constructing this singleton is what launches the bridge. shell.qml calls
    // start() so the logind wiring — and the sleep delay inhibitor — is armed
    // from login, not from whenever the lock screen or a brightness slider first
    // happens to touch it.
    function start() { Log.debug("logind", "service armed") }
}
