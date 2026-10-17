import QtQuick
import Quickshell.Services.Mpris
import qs
import ".."

// NowPlaying — the track that plays (or is paused) with its controls;
// nothing at all when no player has a track. The player pick is the Music
// plugin's: the one playing, else the first one that can be controlled.
Item {
    id: np
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
    visible: np.player !== null
    implicitHeight: visible ? Math.max(Theme.controlMd, meta.implicitHeight) : 0

    Glyph {
        id: note
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.spaceS
        text: Theme.icMusic
        color: np.player && np.player.isPlaying ? Theme.accentText : Theme.textSecondary
        font.pixelSize: Theme.iconMd
    }
    Column {
        id: meta
        anchors.left: note.right
        anchors.leftMargin: Theme.spaceS
        anchors.right: controls.left
        anchors.rightMargin: Theme.spaceS
        anchors.verticalCenter: parent.verticalCenter
        TextStrong { width: parent.width; text: np.player ? (np.player.trackTitle || np.player.identity || "") : "" }
        TextCaption { width: parent.width; visible: text !== ""; text: np.player ? (np.player.trackArtist || "") : "" }
    }
    Row {
        id: controls
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spaceXxs
        QsIconButton { ic: Theme.icPrev; visible: !!np.player && np.player.canGoPrevious; onGo: np.player.previous() }
        QsIconButton { ic: np.player && np.player.isPlaying ? Theme.icPause : Theme.icPlay; onGo: np.player.togglePlaying() }
        QsIconButton { ic: Theme.icNext; visible: !!np.player && np.player.canGoNext; onGo: np.player.next() }
    }
}
