import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris

// MediaPlayer — the now-playing card that pops up above the dock's music
// button (design system: Media player, the "full" variant; the dock button
// only shows while a player exists).
//
//   card      panelSm wide, surfaceRaised with a borderWidth1 borderSubtle
//             outline, the radiusRounded corner, the shadowFloat elevation
//             and spaceS + spaceXs (12) of padding
//   art       icon4xl (64) on the radiusPrimary corner, or the ewellow
//             gradient with a music glyph when the player publishes none
//   source    the app's name in caption textMuted
//   title     h4 (15, semibold) · artist body in textSecondary, both elided
//   times     the mono caption, tabular, under the seek slider
//   controls  previous · play/pause (accent, round, controlXl) · next,
//             spaceS apart and dimmed when the player can't do the action
//
// The seek bar only appears when the player reports both position and length,
// and it only scrubs when canSeek, so a bar that would lie or a drag that
// would no-op never appears.
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
            x: Math.max(Theme.windowGap, Math.min(parent.width - width - Theme.windowGap,
                                                  Globals.mediaAnchorX - width / 2))
            y: parent.height - height - (Theme.control2xl + Theme.spaceLg + Theme.spaceS)
            width: Theme.panelSm
            height: col.implicitHeight + 2 * (Theme.spaceS + Theme.spaceXs)
            radius: Theme.radiusRounded; color: Theme.surfaceRaised
            border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
            // fade plus a slideOffset lift from the dock edge, in at durBase
            // and out at durFast — no overshoot anywhere
            opacity: Globals.mediaOpen ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: Globals.mediaOpen ? Theme.durBase : Theme.durFast; easing.type: Theme.ease }
            }
            transform: Translate {
                y: (Globals.mediaOpen || Theme.reduceMotion) ? 0 : Theme.slideOffset
                Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            }
            layer.enabled: true
            layer.effect: Elevation {}

            Keys.onEscapePressed: Globals.mediaOpen = false
            MouseArea { anchors.fill: parent }   // swallow clicks so the closer behind never fires

            Column {
                id: col
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: Theme.spaceS + Theme.spaceXs
                spacing: Theme.spaceS + Theme.spaceXs

                Row {
                    width: parent.width
                    spacing: Theme.spaceS + Theme.spaceXs

                    // cover art — the ewellow gradient with a disc glyph when
                    // the player publishes none, so the card keeps its shape
                    Rectangle {
                        id: art
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.icon4xl; height: Theme.icon4xl
                        radius: Theme.radiusPrimary
                        color: Theme.accent
                        clip: true
                        // the ewellow gradient token; the cover art, when
                        // there is one, covers it edge to edge
                        gradient: Gradient {
                            GradientStop { position: Theme.gradientEwellow.stops[0][2] / 100
                                           color: Theme.gradientEwellow.stops[0][0] }
                            GradientStop { position: Theme.gradientEwellow.stops[1][2] / 100
                                           color: Theme.gradientEwellow.stops[1][0] }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !box.hasArt
                            text: Theme.icMusic
                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconXl
                            color: Theme.onAccent
                        }
                        Image {
                            anchors.fill: parent; fillMode: Image.PreserveAspectCrop
                            visible: box.hasArt
                            source: box.hasArt ? box.pl.trackArtUrl : ""
                            sourceSize.width: 2 * Theme.icon4xl; sourceSize.height: 2 * Theme.icon4xl
                            mipmap: true
                        }
                    }

                    Column {
                        width: parent.width - art.width - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spaceXxs
                        // the playing source (player identity: "Spotify", "mpv", …)
                        Text {
                            width: parent.width
                            text: box.pl ? (box.pl.identity || box.pl.desktopEntry || "Media") : ""
                            color: Theme.textMuted
                            font.family: Theme.type.caption.family
                            font.pixelSize: Theme.type.caption.size
                            font.weight: Theme.type.caption.weight
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: box.pl ? (box.pl.trackTitle || "—") : ""
                            color: Theme.textPrimary
                            font.family: Theme.type.h4.family
                            font.pixelSize: Theme.type.h4.size
                            font.weight: Theme.type.h4.weight
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width; visible: text !== ""
                            text: box.pl ? (box.pl.trackArtist || "") : ""
                            color: Theme.textSecondary
                            font.family: Theme.type.body.family
                            font.pixelSize: Theme.type.body.size
                            elide: Text.ElideRight
                        }
                    }
                }

                // prev · play/pause (accent disc) · next — dimmed when unavailable
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spaceS
                    Rectangle {
                        id: prevBtn
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.controlLg; height: Theme.controlLg
                        radius: Theme.radiusPrimary
                        color: prevMa.containsMouse ? Theme.surfaceHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        opacity: box.pl && box.pl.canGoPrevious ? 1 : 0.35
                        Text {
                            anchors.centerIn: parent
                            text: Theme.icPrev; font.family: Theme.fontIcons; font.pixelSize: Theme.iconLg
                            color: Theme.textPrimary
                        }
                        MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: if (box.pl && box.pl.canGoPrevious) box.pl.previous() }
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.controlXl; height: Theme.controlXl
                        radius: Theme.radiusFull
                        color: playMa.pressed ? Theme.accentPressed
                             : playMa.containsMouse ? Theme.accentHover : Theme.accent
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        opacity: box.pl && (box.pl.isPlaying ? box.pl.canPause : box.pl.canPlay) ? 1 : 0.35
                        Text {
                            anchors.centerIn: parent
                            text: box.pl && box.pl.isPlaying ? Theme.icPause : Theme.icPlay
                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconLg; color: Theme.onAccent
                        }
                        MouseArea { id: playMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: if (box.pl && (box.pl.isPlaying ? box.pl.canPause : box.pl.canPlay)) root.playPause(box.pl) }
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.controlLg; height: Theme.controlLg
                        radius: Theme.radiusPrimary
                        color: nextMa.containsMouse ? Theme.surfaceHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        opacity: box.pl && box.pl.canGoNext ? 1 : 0.35
                        Text {
                            anchors.centerIn: parent
                            text: Theme.icNext; font.family: Theme.fontIcons; font.pixelSize: Theme.iconLg
                            color: Theme.textPrimary
                        }
                        MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: if (box.pl && box.pl.canGoNext) box.pl.next() }
                    }
                }

                // ── seek bar + times — only when position AND length are real ──
                Column {
                    visible: box.hasBar
                    width: parent.width
                    spacing: Theme.spaceXxs

                    Item {
                        id: seek
                        width: parent.width; height: Theme.iconSm
                        property bool scrubbing: false
                        property real scrubFrac: 0
                        readonly property real playFrac: box.hasBar ? Math.max(0, Math.min(1, box.pl.position / box.knownLength)) : 0
                        readonly property real frac: scrubbing ? scrubFrac : playFrac

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: Theme.spaceXs
                            radius: Theme.radiusFull; color: Theme.surfaceHover
                            Rectangle { height: parent.height; radius: Theme.radiusFull; width: parent.width * seek.frac; color: Theme.accent }
                        }
                        // scrub handle — appears on hover, like a video timeline
                        Rectangle {
                            visible: (seekMa.containsMouse || seek.scrubbing) && box.pl && box.pl.canSeek
                            x: parent.width * seek.frac - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.iconXs; height: Theme.iconXs
                            radius: Theme.radiusFull; color: Theme.textPrimary
                        }
                        MouseArea {
                            id: seekMa
                            anchors.fill: parent; anchors.margins: -Theme.spaceXs
                            hoverEnabled: true
                            enabled: box.pl !== null && box.pl.canSeek
                            cursorShape: Qt.PointingHandCursor
                            function fracAt(mx) { return Math.max(0, Math.min(1, (mx - Theme.spaceXs) / seek.width)) }
                            onPressed: function (m) { seek.scrubbing = true; seek.scrubFrac = fracAt(m.x) }
                            onPositionChanged: function (m) { if (seek.scrubbing) seek.scrubFrac = fracAt(m.x) }
                            onReleased: {
                                if (box.pl && box.pl.canSeek && box.hasBar) box.pl.position = seek.scrubFrac * box.knownLength
                                seek.scrubbing = false
                            }
                        }
                    }

                    Item {
                        width: parent.width; height: Theme.lineHeightXs
                        Text {
                            anchors.left: parent.left
                            text: box.hasBar ? root.fmt(seek.frac * box.knownLength) : ""
                            color: Theme.textMuted
                            font.family: Theme.fontMono; font.pixelSize: Theme.fontSizeXs
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            anchors.right: parent.right
                            text: box.hasBar ? root.fmt(box.knownLength) : ""
                            color: Theme.textMuted
                            font.family: Theme.fontMono; font.pixelSize: Theme.fontSizeXs
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }
        }
    }
}
