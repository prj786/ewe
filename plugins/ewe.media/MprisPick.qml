import QtQuick
import Quickshell.Services.Mpris

// ewe.media — which MPRIS player the card shows: the one that is playing,
// else the first controllable one that has a track. The same pick the
// shell's Quick settings card used. One pass, no early return: every
// isPlaying has to be READ for the binding to depend on it. Shared by the
// popup (Panel.qml) and every bar widget (Widget.qml, one per monitor).
QtObject {
    // WebKitGTK publishes its own `org.mpris.MediaPlayer2.org.webkit.*` entry
    // for media playing inside a web view — beside the app's own player (ewe
    // Player is ewe-player AND org.webkit.…): the same playback twice. So a
    // WebKit entry loses to any other player in the SAME state: playing
    // first (another player's, then WebKit's — a web view with no MPRIS of
    // its own still beats a paused Spotify), then paused with a track.
    function _webkit(p) { return String(p.dbusName || "").indexOf("org.webkit.") >= 0 }
    readonly property var player: {
        var ps = Mpris.players.values
        var live = null, ctl = null, wkLive = null, wkCtl = null
        for (var i = 0; i < ps.length; i++) {
            var p = ps[i]
            var wk = _webkit(p)
            var playing = p.isPlaying
            var usable = p.canControl && p.canPlay && ((p.trackTitle && p.trackTitle !== "") || (p.trackArtist && p.trackArtist !== ""))
            if (playing) { if (wk) { if (!wkLive) wkLive = p } else if (!live) live = p }
            if (usable) { if (wk) { if (!wkCtl) wkCtl = p } else if (!ctl) ctl = p }
        }
        return live || wkLive || ctl || wkCtl
    }
}
