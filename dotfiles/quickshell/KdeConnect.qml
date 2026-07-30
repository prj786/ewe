pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// KdeConnect — THE phone service. Owns the D-Bus bridge process
// (scripts/kdeconnect-bridge.py, NDJSON over stdio) and every model the UI
// binds to: devices/pairing, battery, phone notifications (with a persisted
// seen-set driving the unread badge) and SMS conversations. The Quick Settings
// card, the bar indicator and the messaging panel are pure consumers — nothing
// else in the shell knows a D-Bus path.
QtObject {
    id: kc

    // ── availability ────────────────────────────────────────────────────────
    property bool bridgeUp: false        // helper process alive and spoke
    property bool installed: false       // kdeconnectd binary present
    property bool daemonRunning: false
    property bool bridgeFailed: false    // terminal — respawning cannot help
    property string bridgeError: ""      // why the bridge is unavailable ("" = fine)
    property int _restarts: 0

    // ── devices ─────────────────────────────────────────────────────────────
    property var devices: []             // [{id,name,type,isReachable,isPaired,pairState,pairRequestedByPeer,batteryCharge,isCharging}]
    property string activeId: ""         // user-chosen device (persisted); "" → auto
    // the device the shell talks to: the chosen one when valid, else the first
    // paired device (reachable preferred), else an incoming pair request
    readonly property var device: {
        var best = null
        for (var i = 0; i < devices.length; i++) {
            var d = devices[i]
            if (d.id === activeId) return d
            if (d.isPaired && d.isReachable) { if (!best || !best.isPaired || !best.isReachable) best = d }
            else if (d.isPaired) { if (!best) best = d }
            else if (d.pairRequestedByPeer && !best) best = d
        }
        return best
    }
    readonly property bool connected: device !== null && device.isPaired && device.isReachable

    // ── pairing UX ──────────────────────────────────────────────────────────
    property string pairingId: ""        // device we asked to pair (waiting for the phone)
    property string pairError: ""

    // ── phone notifications (of `device`) ───────────────────────────────────
    property var notifs: []              // [{id,appName,title,text,iconPath,dismissable,replyId}]
    property int seenRev: 0              // bumped when the seen-set changes (recomputes unread)
    property var _seen: ({})             // "<devId>/<notifId>" -> epoch-ms last seen
    readonly property int unreadCount: {
        seenRev
        if (!device) return 0
        var n = 0
        for (var i = 0; i < notifs.length; i++)
            if (!_seen[device.id + "/" + notifs[i].id]) n++
        return n
    }

    // ── SMS conversations (of `device`) ─────────────────────────────────────
    // messages arrive as single events (that's the D-Bus API shape) — the
    // service aggregates: latest message per thread = the conversation list
    property var _msgs: ({})             // threadId -> { key -> msg }
    property var conversations: []       // [{threadId,display,body,date,unread,multitarget}] date-desc
    property int openThread: -1
    property var thread: []              // messages of openThread, date-asc
    property bool convsRequested: false

    readonly property string bridgePath: Quickshell.env("HOME") + "/.config/quickshell/scripts/kdeconnect-bridge.py"
    readonly property string statePath: Quickshell.env("HOME") + "/.config/quickshell/kdeconnect-state.json"

    // ── bridge process ──────────────────────────────────────────────────────
    property Process _bridge: Process {
        running: true
        command: ["python3", kc.bridgePath]
        stdinEnabled: true
        stdout: SplitParser { onRead: function (data) { kc._onEvent(data) } }
        // A bridge that cannot start (no python-dbus/python-gobject) used to be
        // relaunched every 5 s for the whole session — 720 doomed interpreter
        // starts an hour on any box missing those packages. Back off, then stop.
        onExited: {
            kc.bridgeUp = false
            kc.daemonRunning = false
            if (kc.bridgeFailed) return                  // told us why; retrying is pointless
            if (kc._restarts >= 5) {
                kc.bridgeError = "KDE Connect bridge keeps exiting — run with HS_LOG=info for the reason."
                Log.error("kdeconnect", "bridge exited", kc._restarts, "times — giving up")
                return
            }
            kc._restarts++
            kc._restart.interval = 5000 * kc._restarts   // 5s, 10s, 15s, …
            Log.warn("kdeconnect", "bridge exited — retry", kc._restarts, "in", kc._restart.interval + "ms")
            kc._restart.restart()
        }
    }
    property Timer _restart: Timer { interval: 5000; onTriggered: { kc._bridge.running = true } }
    function send(o) { if (kc._bridge.running) kc._bridge.write(JSON.stringify(o) + "\n") }

    // A bridge whose bus connection died does NOT exit: every D-Bus call raises,
    // the handlers swallow it, and it sits there with bridgeUp still true,
    // serving a frozen device list, while onExited never fires so nothing
    // respawns it. A suspend is exactly when that happens. So ask it to speak,
    // and recycle it if it doesn't — `refresh` always answers with a devices
    // event, even when kdeconnectd itself is gone.
    property bool _probePending: false
    property Timer _probeT: Timer {
        interval: 4000
        onTriggered: {
            if (!kc._probePending) return
            kc._probePending = false
            Log.warn("kdeconnect", "bridge did not answer a probe — recycling it")
            kc._bridge.running = false      // onExited schedules the respawn
        }
    }
    function probeLiveness() {
        if (!kc.bridgeUp || kc.bridgeFailed) return
        kc._probePending = true
        kc._probeT.restart()
        kc.send({ cmd: "refresh" })
    }

    // manual recovery after a terminal failure (install the deps, then retry)
    function retryBridge() {
        kc.bridgeFailed = false; kc.bridgeError = ""; kc._restarts = 0
        kc._restart.interval = 5000
        kc._bridge.running = false
        kc._bridge.running = true
    }

    function _onEvent(line) {
        var e
        try { e = JSON.parse(line) } catch (err) { return }
        // anything at all arriving proves the bridge is still alive
        kc._probePending = false
        kc._probeT.stop()
        switch (e.event) {
        case "hello":
            kc.bridgeUp = true
            kc.installed = !!e.installed
            kc.bridgeError = ""
            kc._restarts = 0                 // it spoke — a later exit starts fresh
            kc._restart.interval = 5000
            break
        // the bridge reports its own fatals and per-command failures; both used to
        // fall through this switch and vanish, so the python side's careful error
        // reporting reached nobody
        case "fatal":
            kc.bridgeFailed = true
            kc.bridgeError = e.error || "KDE Connect bridge unavailable"
            Log.error("kdeconnect", "bridge fatal:", kc.bridgeError)
            break
        case "error":
            Log.warn("kdeconnect", "command", e.cmd || "?", "failed:", e.error || "?")
            break
        case "daemon":
            kc.daemonRunning = !!e.running
            break
        case "devices":
            kc.devices = e.list || []
            // pairing resolved (either way) → stop waiting
            if (kc.pairingId !== "") {
                for (var i = 0; i < kc.devices.length; i++)
                    if (kc.devices[i].id === kc.pairingId && kc.devices[i].pairState !== 1)
                        kc.pairingId = ""
            }
            break
        case "battery": {
            var ds = kc.devices.slice()
            for (var b = 0; b < ds.length; b++)
                if (ds[b].id === e.deviceId) {
                    ds[b].batteryCharge = e.charge; ds[b].isCharging = e.isCharging
                    kc.devices = ds
                    break
                }
            break
        }
        case "pairError":
            kc.pairError = e.error || "Pairing failed"
            kc.pairingId = ""
            break
        case "notifications":
            if (kc.device && e.deviceId === kc.device.id) kc.notifs = e.list || []
            break
        case "message":
            if (kc.device && e.deviceId === kc.device.id) kc._addMessage(e.msg)
            break
        case "conversationRemoved":
            if (kc.device && e.deviceId === kc.device.id) {
                delete kc._msgs[e.threadId]
                kc._rebuildConvs()
            }
            break
        }
    }

    // ── device / pairing commands ───────────────────────────────────────────
    function refresh() { kc.pairError = ""; kc.send({ cmd: "refresh" }) }
    function requestPair(id) { kc.pairError = ""; kc.pairingId = id; kc.send({ cmd: "pair", deviceId: id }) }
    function cancelPair(id) { kc.pairingId = ""; kc.send({ cmd: "cancelPair", deviceId: id }) }
    function acceptPair(id) { kc.send({ cmd: "acceptPair", deviceId: id }) }
    function unpair(id) { kc.send({ cmd: "unpair", deviceId: id }) }
    function selectDevice(id) { kc.activeId = id; kc._saveState(); kc._onDeviceSwitch() }
    function ring() { if (kc.device) kc.send({ cmd: "ring", deviceId: kc.device.id }) }
    function shareText(t) { if (kc.device) kc.send({ cmd: "shareText", deviceId: kc.device.id, text: t }) }
    function shareUrl(u) { if (kc.device) kc.send({ cmd: "shareUrl", deviceId: kc.device.id, url: u }) }

    // notifications arrive per-device — refetch when the active device flips
    property string _lastDevId: ""
    property Connections _devWatch: Connections {
        target: kc
        function onDeviceChanged() {
            var id = kc.device ? kc.device.id : ""
            if (id !== kc._lastDevId) { kc._lastDevId = id; kc._onDeviceSwitch() }
        }
    }
    function _onDeviceSwitch() {
        kc.notifs = []
        kc._msgs = {}; kc.conversations = []; kc.thread = []; kc.openThread = -1; kc.convsRequested = false
        if (kc.device && kc.device.isReachable && kc.device.isPaired)
            kc.send({ cmd: "notifications", deviceId: kc.device.id })
    }

    // ── notifications API ───────────────────────────────────────────────────
    function dismissNotif(id) { if (kc.device) kc.send({ cmd: "dismiss", deviceId: kc.device.id, id: id }) }
    function replyNotif(replyId, text) { if (kc.device) kc.send({ cmd: "replyNotif", deviceId: kc.device.id, replyId: replyId, text: text }) }
    // the panel was viewed — everything currently listed counts as seen
    function markAllSeen() {
        if (!kc.device || kc.notifs.length === 0) return
        var now = Date.now(), dirty = false
        for (var i = 0; i < kc.notifs.length; i++) {
            var k = kc.device.id + "/" + kc.notifs[i].id
            if (!kc._seen[k]) { kc._seen[k] = now; dirty = true }
        }
        if (dirty) { kc.seenRev++; kc._saveState() }
    }

    // ── messaging API ───────────────────────────────────────────────────────
    function loadConversations() {
        if (!kc.device || !kc.connected) return
        kc.convsRequested = true
        kc.send({ cmd: "requestConversations", deviceId: kc.device.id })
    }
    function openConversation(threadId) {
        kc.openThread = threadId
        kc._rebuildThread()
        kc.send({ cmd: "requestConversation", deviceId: kc.device.id, threadId: threadId, start: 0, end: 30 })
    }
    function loadOlder() {
        if (kc.openThread < 0) return
        kc.send({ cmd: "requestConversation", deviceId: kc.device.id, threadId: kc.openThread,
                  start: kc.thread.length, end: kc.thread.length + 30 })
    }
    function sendMessage(text) {
        if (kc.openThread < 0 || !kc.device) return
        kc.send({ cmd: "sendMessage", deviceId: kc.device.id, threadId: kc.openThread, text: text })
        // optimistic echo — reconciled when the phone echoes the real message
        kc._addMessage({ threadId: kc.openThread, body: text, date: Date.now(), type: 2,
                         read: 1, addresses: [], uid: 0, multitarget: false, hasAttachments: false, event: 1, pending: true })
    }

    function _msgKey(m) { return m.uid > 0 ? "u" + m.uid : "t" + m.date + ":" + m.type }
    function _addMessage(m) {
        if (m.threadId === undefined || m.threadId < 0) return
        var t = kc._msgs[m.threadId] || {}
        if (m.type === 2 && !m.pending) {
            // a real sent message arrived — drop any optimistic copy with the same body
            for (var k in t) if (t[k].pending && t[k].body === m.body) delete t[k]
        }
        t[kc._msgKey(m)] = m
        kc._msgs[m.threadId] = t
        kc._rebuildConvs()
        if (m.threadId === kc.openThread) kc._rebuildThread()
    }
    function _rebuildConvs() {
        var out = []
        for (var tid in kc._msgs) {
            var latest = null
            for (var k in kc._msgs[tid]) {
                var m = kc._msgs[tid][k]
                if (!latest || m.date > latest.date) latest = m
            }
            if (!latest) continue
            out.push({
                threadId: Number(tid),
                display: latest.addresses.length > 0 ? latest.addresses.join(", ") : "Conversation " + tid,
                body: latest.body || (latest.hasAttachments ? "📎 Attachment" : ""),
                date: latest.date,
                unread: latest.type === 1 && latest.read === 0,
                multitarget: latest.multitarget
            })
        }
        out.sort(function (a, b) { return b.date - a.date })
        kc.conversations = out
    }
    function _rebuildThread() {
        var t = kc._msgs[kc.openThread] || {}
        var out = []
        for (var k in t) out.push(t[k])
        out.sort(function (a, b) { return a.date - b.date })
        kc.thread = out
    }

    // ── persisted UI state (seen notification ids + chosen device) ──────────
    property Process _stateWriter: Process {}
    function _saveState() {
        // prune seen entries older than 14 days — phone notification ids recycle
        var cut = Date.now() - 14 * 86400000
        for (var k in kc._seen) if (kc._seen[k] < cut) delete kc._seen[k]
        HyprMon.atomicWrite(kc._stateWriter, kc.statePath,
            JSON.stringify({ seen: kc._seen, activeId: kc.activeId }))
    }
    property Process _stateLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/kdeconnect-state.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (j.seen && typeof j.seen === "object") kc._seen = j.seen
                    if (j.activeId) kc.activeId = j.activeId
                    kc.seenRev++
                } catch (e) {}
            }
        }
    }
}
