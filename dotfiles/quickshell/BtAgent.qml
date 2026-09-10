pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// BtAgent — the desktop's Bluetooth PAIRING agent. Owns the bridge process
// (scripts/bt-agent.py, NDJSON over stdio — the KdeConnect pattern) that
// registers as bluez's default org.bluez.Agent1, and the one `request` the
// BtPairing dialog renders. Device STATE still comes from Quickshell.Bluetooth
// (Bar, Quick Settings); this singleton only answers questions and runs the
// pair/connect calls whose errors Quickshell swallows, so the UI can say WHY
// a pairing failed instead of quietly doing nothing.
QtObject {
    id: bt

    // ── availability ────────────────────────────────────────────────────────
    property bool bridgeUp: false        // helper process alive and spoke
    property bool registered: false      // bluez accepted us as (default) agent
    property bool bridgeFailed: false    // terminal — respawning cannot help
    property string bridgeError: ""      // why the agent is unavailable ("" = fine)
    property int _restarts: 0

    // ── the question on screen ──────────────────────────────────────────────
    // {id, kind: confirm|authorize|service|pin|passkey|display, device:{address,
    //  name, icon, paired, trusted}, passkey?, entered?, what?, uuid?, service?}
    property var request: null

    // ── pair/connect bookkeeping (Quick Settings shows these) ───────────────
    property string pairingAddress: ""   // a pair() we started and are waiting on
    property string busyAddress: ""      // a connect() in flight
    property string lastError: ""        // last failure, human text ("" = none)
    property string lastErrorAddress: ""

    // beside THIS file, not under ~/.config: the shell may run from the repo
    // (the run-ewe driver), the payload, or the package — the script is always
    // in the same scripts/ dir as the QML that owns it
    readonly property string bridgePath: Qt.resolvedUrl("scripts/bt-agent.py").toString().replace(/^file:\/\//, "")

    // ── bridge process ──────────────────────────────────────────────────────
    property Process _bridge: Process {
        command: ["python3", bt.bridgePath]
        stdinEnabled: true
        stdout: SplitParser { onRead: function (data) { bt._onEvent(data) } }
        onExited: {
            bt.bridgeUp = false
            bt.registered = false
            bt.request = null
            if (bt.bridgeFailed) return
            if (bt._restarts >= 5) {
                bt.bridgeError = "Bluetooth pairing agent keeps exiting — run with HS_LOG=info for the reason."
                Log.error("bt-agent", "bridge exited", bt._restarts, "times — giving up")
                return
            }
            bt._restarts++
            bt._restart.interval = 5000 * bt._restarts
            Log.warn("bt-agent", "bridge exited — retry", bt._restarts, "in", bt._restart.interval + "ms")
            bt._restart.restart()
        }
    }
    property Timer _restart: Timer { interval: 5000; onTriggered: { bt._bridge.running = true } }
    function start() { if (!bt._bridge.running) bt._bridge.running = true }
    function send(o) { if (bt._bridge.running) bt._bridge.write(JSON.stringify(o) + "\n") }

    function retryBridge() {
        bt.bridgeFailed = false; bt.bridgeError = ""; bt._restarts = 0
        bt._restart.interval = 5000
        bt._bridge.running = false
        bt._bridge.running = true
    }

    // ── what the UI calls ───────────────────────────────────────────────────
    function pair(address) {
        bt.lastError = ""; bt.lastErrorAddress = ""
        bt.pairingAddress = address
        if (!bt.bridgeUp) {
            bt.pairingAddress = ""
            bt.lastError = bt.bridgeError !== "" ? bt.bridgeError : "Pairing agent not running — try again in a moment"
            bt.lastErrorAddress = address
            return
        }
        bt.send({ cmd: "pair", address: address })
    }
    function connectDevice(address) {
        bt.lastError = ""; bt.lastErrorAddress = ""
        bt.busyAddress = address
        bt.send({ cmd: "connect", address: address })
    }
    function cancelPairing(address) {
        bt.send({ cmd: "cancel", address: address })
        if (bt.pairingAddress === address) bt.pairingAddress = ""
    }
    // the dialog's verdict on the current request
    function reply(ok, value) {
        var r = bt.request
        if (!r) return
        bt.request = null
        if (r.kind === "display") {
            // nothing to answer — a "cancel" means stop the pairing itself
            if (!ok) bt.cancelPairing(r.device.address)
            return
        }
        bt.send({ cmd: "reply", id: r.id, ok: !!ok, value: value === undefined ? "" : String(value) })
        if (!ok && r.device && r.device.address === bt.pairingAddress) bt.cancelPairing(r.device.address)
    }
    function clearError() { bt.lastError = ""; bt.lastErrorAddress = "" }

    // bluez's Icon string → our glyph (Theme's Lucide table)
    function glyph(icon, connected) {
        switch (String(icon || "")) {
        case "audio-headset":               return Theme.icHeadset
        case "audio-headphones":            return Theme.icHeadphones
        case "audio-card":
        case "audio-speakers":              return Theme.icSpeaker
        case "input-keyboard":              return Theme.icKeyboard
        case "input-mouse":                 return Theme.icMouse
        case "input-gaming":                return Theme.icGamepad
        case "input-tablet":                return Theme.icTablet
        case "phone":                       return Theme.icPhone
        case "computer":                    return Theme.icLaptop
        case "video-display":               return Theme.icMonitorOff
        case "printer":                     return Theme.icPrinter
        case "camera-photo":
        case "camera-video":                return Theme.icCamera
        case "multimedia-player":           return Theme.icMusic
        case "network-wireless":            return Theme.icWifi
        default:                            return connected ? Theme.icBluetoothOn : Theme.icBluetooth
        }
    }

    // ── events from the bridge ──────────────────────────────────────────────
    function _onEvent(line) {
        var e
        try { e = JSON.parse(line) } catch (err) { return }
        switch (e.event) {
        case "hello":
            bt.bridgeUp = true
            bt.bridgeError = ""
            bt._restarts = 0
            bt._restart.interval = 5000
            break
        case "agent":
            bt.registered = !!e.registered
            if (!bt.registered) Log.warn("bt-agent", "not registered:", e.why || "?")
            else Log.info("bt-agent", "registered as default pairing agent")
            break
        case "request":
            bt.request = e
            break
        case "cancel":
            if (bt.request && bt.request.id === e.id) bt.request = null
            break
        case "pair":
            if (bt.pairingAddress === e.address) bt.pairingAddress = ""
            if (!e.ok) { bt.lastError = e.error || "Pairing failed"; bt.lastErrorAddress = e.address; Log.warn("bt-agent", "pair", e.address, "failed:", e.raw || e.error) }
            break
        case "connect":
            if (bt.busyAddress === e.address) bt.busyAddress = ""
            if (!e.ok) { bt.lastError = e.error || "Could not connect"; bt.lastErrorAddress = e.address; Log.warn("bt-agent", "connect", e.address, "failed:", e.raw || e.error) }
            break
        case "fatal":
            bt.bridgeFailed = true
            bt.bridgeError = e.error || "Bluetooth pairing agent unavailable"
            Log.error("bt-agent", bt.bridgeError)
            break
        case "error":
            Log.warn("bt-agent", e.error)
            break
        }
    }
}
