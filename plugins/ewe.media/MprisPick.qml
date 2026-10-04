import QtQuick
import Quickshell.Services.Mpris

// ewe.media — which MPRIS player the card shows: the one that is playing,
// else the first controllable one that has a track. The same pick the
// shell's Quick settings card used. One pass, no early return: every
// isPlaying has to be READ for the binding to depend on it. Shared by the
// popup (Panel.qml) and every bar widget (Widget.qml, one per monitor).
QtObject {
    readonly property var player: {
        var ps = Mpris.players.values
        var live = null, ctl = null
        for (var i = 0; i < ps.length; i++) {
            var p = ps[i]
            if (p.isPlaying && !live) live = p
            if (!ctl && p.canControl && p.canPlay && ((p.trackTitle && p.trackTitle !== "") || (p.trackArtist && p.trackArtist !== ""))) ctl = p
        }
        return live || ctl
    }
}
