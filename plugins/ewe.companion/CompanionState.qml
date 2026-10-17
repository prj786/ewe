pragma Singleton
import QtQuick

// CompanionState — the one truth the notch and the service share.
//
// The service (Service.qml) owns the daemon's socket and writes here; the
// notch (Drop.qml and its parts) reads, and talks back through send(). A
// plugin-local singleton (this directory's qmldir), so nothing of the
// companion lives in the shell's Globals.
QtObject {
    id: st

    property bool connected: false
    // idle · working · waiting · error  (the daemon's word)
    property string presence: "idle"
    property var pending: []          // cards, oldest first
    property var sessions: []         // agent sessions, newest first
    property var glance: ({})         // {disks:[{path, used_pct, free_gb}], updates:{total}}
    property var usage: null          // {five_hour:{pct, resets_at}, seven_day:{…}}
    property var chat: ({})           // {provider, label, ready, needs_key, hint, model}
    property bool gameMode: false
    property var peek: null           // { key, line, level, actions, ttl_ms }
    property bool peekHeld: false     // the pointer is on the notch: hold the line
    property bool dropOpen: false     // opened by hand (click, Super+A)
    property string screenName: ""    // where cards and the home panel open
    property int peekMs: 5000         // the peek_seconds setting, in ms

    // the chat: the last few turns, as the island shows them
    property var messages: []         // [{id, who: "you"|"companion", kind, text, undo}]
    property bool thinking: false

    readonly property int asking: {
        var n = 0
        for (var i = 0; i < st.pending.length; i++)
            if (st.pending[i].kind === "permission" || st.pending[i].kind === "question") n++
        return n
    }
    // the session the indicator talks about: one that needs you, else one
    // that works, else the newest
    readonly property var lead: {
        var ss = st.sessions, w = null
        for (var i = 0; i < ss.length; i++) {
            if (ss[i].state === "waiting") return ss[i]
            if (!w && ss[i].state === "working") w = ss[i]
        }
        return w
    }

    // the service writes these to the socket
    signal outbound(var msg)
    function send(msg) { st.outbound(msg) }
    function shown(id) { st.send({ type: "card.shown", id: id }) }
    function answer(id, action, answers) {
        var m = { type: "card.answer", id: id, action: action }
        if (answers) m.answers = answers
        st.send(m)
    }
    function jump(sessionId) { st.send({ type: "session.jump", id: sessionId }) }
    function run(command, args) { st.send({ type: "command.run", command: command, args: args || {} }) }
    function undo(token) { st.send({ type: "undo", token: token }) }
    function setKey(provider, key) { st.send({ type: "key.set", provider: provider, key: key }) }
    // a proposed command's Run / In terminal: sent once, the buttons go
    function runProposal(messageId, token, mode) {
        st.messages = st.messages.map(function (m) {
            if (m.id !== messageId) return m
            var c = Object.assign({}, m); c.sent = true; return c
        })
        st.send({ type: "confirm.run", token: token, mode: mode })
    }
    function ask(text) {
        var t = String(text).trim()
        if (t === "") return
        st.addMessage({ id: "you-" + Date.now(), who: "you", kind: "you", text: t })
        st.thinking = true
        st.send({ type: "chat.send", text: t })
    }
    function addMessage(m) {
        var ms = st.messages.filter(function (x) { return x.id !== m.id })
        ms.push(m)
        st.messages = ms.slice(-40)   // the notch scrolls them
    }
    // a peek's action: `jump:<session>` jumps, `undo:<token>` undoes;
    // anything else is just dismissed
    function peekAction(id) {
        if (id.indexOf("jump:") === 0) st.jump(id.slice(5))
        else if (id.indexOf("undo:") === 0) st.undo(id.slice(5))
        st.peek = null
    }

    function showPeek(p) {
        st.peek = p
        peekTimer.interval = p.ttl_ms > 0 ? p.ttl_ms : st.peekMs
        peekTimer.restart()
    }
    onPeekHeldChanged: {
        if (st.peekHeld) peekTimer.stop()
        else if (st.peek) peekTimer.restart()
    }
    property Timer peekTimer: Timer {
        onTriggered: if (!st.peekHeld) st.peek = null
    }
}
