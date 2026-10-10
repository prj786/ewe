import QtQuick
import Quickshell
import Quickshell.Io
import qs

// ewe.media — the now-playing card (design system: Media player, the "full"
// variant). An AnchoredPopup: above the dock when the dock item opens it,
// under the bar when the bar widget does; Esc or a click outside closes.
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
//             spaceS apart; an action the player can't do takes the
//             disabled roles (textDisabled, surfaceHover), never opacity
//
// The seek bar only appears when the player reports both position and length,
// and it only scrubs when canSeek, so a bar that would lie or a drag that
// would no-op never appears.
//
// Entry points: the dock item's action `ewe.media.toggle` (registered here,
// run by the dock or by Widget.qml with the button's anchor) and IPC —
//     qs ipc call ewe.media toggle|show|hide      qs ipc call player toggle|hide   (legacy)
Scope {
    id: root
    property string pluginId: ""
    property string stateDir: ""
    property var settings: ({})

    MprisPick { id: pick }
    readonly property var player: pick.player
    // the popup closes with the player
    onPlayerChanged: if (!root.player) pop.close()

    // The dock item (manifest dockItem, drawn by the dock plugin) follows the
    // same rules the bar button does: never when the `button` setting says
    // bar-only, and — like the built-in dock's music button always did —
    // only while an MPRIS player exists, unless `always_show`. The dock
    // filters on Shell.dockItemShown live.
    readonly property string mode: (root.settings && root.settings.button) ? String(root.settings.button) : "auto"
    readonly property bool dockItemWanted: root.mode !== "bar" && (root.player !== null || (root.settings && root.settings.always_show === true))
    onDockItemWantedChanged: Shell.setDockItemShown("ewe.media", root.dockItemWanted)

    function toggle(anchor) {
        if (pop.open) { pop.close(); return }
        if (!root.player) { Shell.toast("Nothing is playing", "info"); return }
        Shell.closePopups("ewe.media")  // one plugin popup at a time
        pop.openAt(anchor || null)      // null keeps the popup's last anchor
    }
    function show(anchor) { if (!pop.open) root.toggle(anchor) }

    Component.onCompleted: {
        Shell.registerAction("ewe.media.toggle", function (a) { root.toggle(a) })
        Shell.setDockItemShown("ewe.media", root.dockItemWanted)
    }
    Component.onDestruction: { Shell.registerAction("ewe.media.toggle", null); Shell.setDockItemShown("ewe.media", true) }

    IpcHandler {
        target: "ewe.media"
        function toggle(): void { root.toggle(null) }
        function show(): void { root.show(null) }
        function hide(): void { pop.close() }
    }
    // the shell's target before 0.25 (manifest ipcAliases): old keybinds and
    // scripts keep working
    IpcHandler {
        target: "player"
        function toggle(): void { root.toggle(null) }
        function hide(): void { pop.close() }
    }

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

    // MPRIS only pushes position on start/stop/seek; poking the change signal
    // re-reads the interpolated getter so the bar actually moves while open.
    // A poll rate, not a motion duration — twice a second is what a seek bar
    // needs to look continuous.
    Timer {
        running: pop.open && root.player !== null && root.player.isPlaying
        interval: 500; repeat: true
        onTriggered: root.player.positionChanged()
    }

    AnchoredPopup {
        id: pop
        name: "mediaplayer"                 // layer namespace quickshell:mediaplayer, as before (hyprland.lua rules)
        owner: "ewe.media"                  // Shell.closePopups("ewe.media") spares it; any other popup opening closes it
        action: "ewe.media.toggle"
        implicitWidth: Theme.panelSm
        implicitHeight: col.implicitHeight + 2 * (Theme.spaceS + Theme.spaceXs)

        Item {
            id: box
            anchors.fill: parent
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

                // prev · play/pause (accent disc) · next — the disabled roles
                // when the player can't do the action
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spaceS
                    Rectangle {
                        readonly property bool can: box.pl !== null && box.pl.canGoPrevious
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.controlLg; height: Theme.controlLg
                        radius: Theme.radiusPrimary
                        color: can && prevMa.containsMouse ? Theme.surfaceHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        Text {
                            anchors.centerIn: parent
                            text: Theme.icPrev; font.family: Theme.fontIcons; font.pixelSize: Theme.iconLg
                            color: parent.can ? Theme.textPrimary : Theme.textDisabled
                        }
                        MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: if (parent.can) box.pl.previous() }
                    }
                    Rectangle {
                        readonly property bool can: box.pl !== null && (box.pl.isPlaying ? box.pl.canPause : box.pl.canPlay)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.controlXl; height: Theme.controlXl
                        radius: Theme.radiusFull
                        color: !can ? Theme.surfaceHover
                             : playMa.pressed ? Theme.accentPressed
                             : playMa.containsMouse ? Theme.accentHover : Theme.accent
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        Text {
                            anchors.centerIn: parent
                            text: box.pl && box.pl.isPlaying ? Theme.icPause : Theme.icPlay
                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconLg
                            color: parent.can ? Theme.onAccent : Theme.textDisabled
                        }
                        MouseArea { id: playMa; anchors.fill: parent; hoverEnabled: true; cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: if (parent.can) root.playPause(box.pl) }
                    }
                    Rectangle {
                        readonly property bool can: box.pl !== null && box.pl.canGoNext
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.controlLg; height: Theme.controlLg
                        radius: Theme.radiusPrimary
                        color: can && nextMa.containsMouse ? Theme.surfaceHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        Text {
                            anchors.centerIn: parent
                            text: Theme.icNext; font.family: Theme.fontIcons; font.pixelSize: Theme.iconLg
                            color: parent.can ? Theme.textPrimary : Theme.textDisabled
                        }
                        MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: if (parent.can) box.pl.next() }
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
