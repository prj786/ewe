import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris

// MediaPlayer — a small now-playing card that pops up above the dock's music
// button (the QuickSettings media card moved here; the dock button only shows
// while a player exists). Cover art on the left — when the player publishes no
// art the block collapses and the text takes the full width. Controls:
// previous / play-pause / next, dimmed when the player can't do the action.
// A seek bar with elapsed/total times sits underneath — only when the player
// reports both position and length, and it only scrubs when canSeek, so a bar
// that would lie or a drag that would no-op never appears.
Scope {
    id: root

    // The same "playing first, else controllable with a track" pick the QS
    // card used. One pass, no early return: every isPlaying has to be READ for
    // the binding to depend on it (see the same note in Screensaver.qml).
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
    // the dock button binds its visibility to this; popup closes with the player
    Binding { target: Globals; property: "mediaPlayer"; value: root.player }
    onPlayerChanged: if (!root.player) Globals.mediaOpen = false

    function fmt(s) {
        s = Math.max(0, Math.round(s))
        var m = Math.floor(s / 60), r = s % 60
        return m + ":" + (r < 10 ? "0" : "") + r
    }

    // Quickshell's togglePlaying() sends the INDIVIDUAL Play/Pause methods on
    // the bus; some players (Stremio) ignore those and only answer the spec's
    // combined PlayPause verb (verified with dbus-monitor). When the player
    // allows both directions, call PlayPause directly — the one verb everyone
    // answers; otherwise fall back to togglePlaying() for the odd player where
    // only one direction is possible (PlayPause errors when CanPause=false).
    function playPause(pl) {
        if (!pl) return
        if (pl.canPlay && pl.canPause && pl.dbusName)
            Quickshell.execDetached(["busctl", "--user", "call", pl.dbusName,
                "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "PlayPause"])
        else pl.togglePlaying()
    }

    IpcHandler {
        target: "player"
        function toggle(): void { if (!Globals.mediaOpen && root.player === null) return; Globals.launcherOpen = false; Globals.storeOpen = false; Globals.placesOpen = false; Globals.mediaOpen = !Globals.mediaOpen }
        function hide(): void { Globals.mediaOpen = false }
    }

    property var openScreen: null
    function focusedScreen() {
        var fm = Hyprland.focusedMonitor, ss = Quickshell.screens
        if (fm) for (var i = 0; i < ss.length; i++) if (ss[i].name === fm.name) return ss[i]
        return ss.length > 0 ? ss[0] : null
    }

    // MPRIS only pushes position on start/stop/seek; poking the change signal
    // re-reads the interpolated getter so the bar actually moves while open
    Timer {
        running: Globals.mediaOpen && root.player !== null && root.player.isPlaying
        interval: 500; repeat: true
        onTriggered: root.player.positionChanged()
    }

    PanelWindow {
        id: win
        visible: Globals.mediaOpen || win.held
        screen: root.openScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell:mediaplayer"
        anchors { top: true; bottom: true; left: true; right: true }

        // `held` keeps the window mapped through the close animation; set on
        // OPEN so no signal-order race can unmap it early (see Overview.qml)
        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durSlow + 60); onTriggered: win.held = false }
        Connections { target: Globals; function onMediaOpenChanged() {
            if (Globals.mediaOpen) { closeTimer.stop(); win.held = true; root.openScreen = root.focusedScreen(); box.forceActiveFocus() }
            else closeTimer.restart()
        } }

        // click anywhere outside the card → close (LauncherPanel idiom)
        MouseArea { anchors.fill: parent; onClicked: Globals.mediaOpen = false }

        Rectangle {
            id: box
            focus: true
            readonly property var pl: root.player
            readonly property bool hasArt: pl !== null && pl.trackArtUrl !== undefined && String(pl.trackArtUrl) !== ""
            // Browser MPRIS drops length/positionSupported for a moment right
            // after a SetPosition, and nothing re-publishes them until the next
            // play/pause — binding the bar to the LIVE flags made it vanish
            // after every scrub. Latch the last good length + eligibility and
            // only reset when the player itself changes.
            property real knownLength: 0
            property bool knownBar: false
            readonly property real liveLength: (pl !== null && pl.lengthSupported && pl.length > 0 && isFinite(pl.length)) ? pl.length : 0
            onLiveLengthChanged: if (liveLength > 0) knownLength = liveLength
            readonly property bool liveBar: pl !== null && pl.positionSupported && liveLength > 0
            onLiveBarChanged: if (liveBar) knownBar = true
            onPlChanged: { knownLength = liveLength; knownBar = liveBar }
            readonly property bool hasBar: pl !== null && knownBar && knownLength > 0
            x: Math.max(12, Math.min(parent.width - width - 12, Globals.mediaAnchorX - width / 2))
            y: parent.height - height - 90
            width: 340
            height: col.implicitHeight + 28
            radius: Theme.radius; color: Theme.panel
            border.color: Theme.stroke; border.width: 1
            Sheen { radius: parent.radius }
            opacity: Globals.mediaOpen ? 1 : 0
            scale: Globals.mediaOpen ? 1 : 0.96
            transformOrigin: Item.Bottom
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            layer.enabled: true
            layer.effect: Elevation {}

            Keys.onEscapePressed: Globals.mediaOpen = false
            MouseArea { anchors.fill: parent }   // swallow clicks so the closer behind never fires

            Column {
                id: col
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 14
                spacing: 12

                Row {
                    width: parent.width
                    spacing: 12

                    // cover art — collapses entirely when the player has none
                    Rectangle {
                        visible: box.hasArt
                        anchors.verticalCenter: parent.verticalCenter
                        width: 84; height: 84; radius: 10; color: Theme.hover; clip: true
                        Image {
                            anchors.fill: parent; fillMode: Image.PreserveAspectCrop
                            source: box.hasArt ? box.pl.trackArtUrl : ""
                            sourceSize.width: 168; sourceSize.height: 168; mipmap: true
                        }
                    }

                    Column {
                        width: parent.width - (box.hasArt ? 84 + 12 : 0)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        // the playing source (player identity: "Spotify", "mpv", …)
                        Text { width: parent.width; text: box.pl ? (box.pl.identity || box.pl.desktopEntry || "Media") : ""; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: 10; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Text { width: parent.width; text: box.pl ? (box.pl.trackTitle || "—") : ""; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Text { width: parent.width; visible: text !== ""; text: box.pl ? (box.pl.trackArtist || "") : ""; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; elide: Text.ElideRight }

                        Item { width: 1; height: 6 }

                        // prev · play/pause (accent disc) · next — dimmed when unavailable
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 20
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icPrev; font.family: Theme.fontIcons; font.pixelSize: 17; color: Theme.fg
                                opacity: box.pl && box.pl.canGoPrevious ? 1 : 0.35
                                MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (box.pl && box.pl.canGoPrevious) box.pl.previous() }
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 38; height: 38; radius: 19
                                color: Theme.accent
                                opacity: box.pl && (box.pl.isPlaying ? box.pl.canPause : box.pl.canPlay) ? 1 : 0.35
                                scale: playMa.pressed ? 0.92 : 1
                                Behavior on scale { NumberAnimation { duration: Theme.durFast; easing.type: Theme.ease } }
                                Text {
                                    anchors.centerIn: parent
                                    text: box.pl && box.pl.isPlaying ? Theme.icPause : Theme.icPlay
                                    font.family: Theme.fontIcons; font.pixelSize: 18; color: Theme.accentText
                                }
                                MouseArea { id: playMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (box.pl && (box.pl.isPlaying ? box.pl.canPause : box.pl.canPlay)) root.playPause(box.pl) }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.icNext; font.family: Theme.fontIcons; font.pixelSize: 17; color: Theme.fg
                                opacity: box.pl && box.pl.canGoNext ? 1 : 0.35
                                MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (box.pl && box.pl.canGoNext) box.pl.next() }
                            }
                        }
                    }
                }

                // ── seek bar + times — only when position AND length are real ──
                Column {
                    visible: box.hasBar
                    width: parent.width
                    spacing: 4

                    Item {
                        id: seek
                        width: parent.width; height: 14
                        property bool scrubbing: false
                        property real scrubFrac: 0
                        readonly property real playFrac: box.hasBar ? Math.max(0, Math.min(1, box.pl.position / box.knownLength)) : 0
                        readonly property real frac: scrubbing ? scrubFrac : playFrac

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: seekMa.containsMouse || seek.scrubbing ? 6 : 4
                            radius: height / 2; color: Theme.hover
                            Behavior on height { NumberAnimation { duration: Theme.durFast } }
                            Rectangle { height: parent.height; radius: parent.radius; width: parent.width * seek.frac; color: Theme.accent }
                        }
                        // scrub handle — appears on hover, like a video timeline
                        Rectangle {
                            visible: (seekMa.containsMouse || seek.scrubbing) && box.pl && box.pl.canSeek
                            x: parent.width * seek.frac - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12; height: 12; radius: 6; color: Theme.accent
                        }
                        MouseArea {
                            id: seekMa
                            anchors.fill: parent; anchors.margins: -4
                            hoverEnabled: true
                            enabled: box.pl !== null && box.pl.canSeek
                            cursorShape: Qt.PointingHandCursor
                            function fracAt(mx) { return Math.max(0, Math.min(1, (mx - 4) / seek.width)) }
                            onPressed: function (m) { seek.scrubbing = true; seek.scrubFrac = fracAt(m.x) }
                            onPositionChanged: function (m) { if (seek.scrubbing) seek.scrubFrac = fracAt(m.x) }
                            onReleased: {
                                if (box.pl && box.pl.canSeek && box.hasBar) box.pl.position = seek.scrubFrac * box.knownLength
                                seek.scrubbing = false
                            }
                        }
                    }

                    Item {
                        width: parent.width; height: 14
                        Text { anchors.left: parent.left; text: box.hasBar ? root.fmt(seek.frac * box.knownLength) : ""; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11 }
                        Text { anchors.right: parent.right; text: box.hasBar ? root.fmt(box.knownLength) : ""; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11 }
                    }
                }
            }
        }
    }
}
