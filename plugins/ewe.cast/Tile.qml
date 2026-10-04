import QtQuick
import qs

// ewe.cast — the Quick settings home tile. Lit while a session exists (busy
// until the picture is on the TV); a click then hangs up, the way the
// built-in tile did. Idle, a click opens the sink list (the page) — the
// same thing Super+Shift+C does — and the details zone always does.
Tile {
    id: root
    property string pluginId: ""
    property var settings: ({})
    property bool panelOpen: false
    ic: Theme.icCast
    label: "Cast"
    active: CastState.casting
    busy: CastState.casting && !CastState.streaming
    sub: CastState.streaming ? (CastState.sinkName || "Casting")
         : CastState.casting ? "Connecting…" : "Off"
    hasMenu: true
    onClicked: {
        if (CastState.casting) CastState.send("stop")
        else Shell.openQuickSettings("cast")
    }
    onMenu: Shell.openQuickSettings("cast")
}
