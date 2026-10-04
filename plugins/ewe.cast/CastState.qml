pragma Singleton
import QtQuick

// CastState — the one truth the four entry points of ewe.cast render.
//
// The service (Service.qml) owns the ewe-castd control socket and writes
// here; the tile, the page and the bar glyph only read, and send commands
// back through `send()`. A plugin-local singleton (listed in this
// directory's qmldir) so nothing of this lives in the shell's Globals.
QtObject {
    // idle · picking · connecting · waiting · negotiating · starting · streaming · error
    property string state: "idle"
    property string detail: ""          // one narrated line for the current state
    property string sinkName: ""        // who we're casting to, while active
    property var sinks: []              // [{id, name, kind}] — displays in range
    property bool legacy: false         // the gnome-network-displays fallback is up
    // anything that lights the bar glyph and the tile
    readonly property bool casting: legacy || (state !== "idle" && state !== "error")
    readonly property bool streaming: state === "streaming" || legacy

    // tile / page → service → daemon socket
    signal command(string cmd, string arg)
    function send(cmd, arg) { command(cmd, arg || "") }
}
