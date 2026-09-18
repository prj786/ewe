import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Dock — a small, centered bottom dock (our own take). Layout:
//   [ launcher ] [ overview ] | [ workspace boxes … ]
// The launcher opens the Launcher; overview opens the window overview; each workspace
// box shows its windows as little app tiles (click a tile to focus that window,
// click the box to switch to that workspace). Replaces the top-bar workspace row.
//
// Toggle + intelligent-hide live in Globals (Settings → Dock). Themed from Theme.qml.
Scope {
    id: root

    function g(c) { return String.fromCodePoint(c) }

    // ── roles inside Glass (Glass card): once bar opacity drops below 100
    //    the dock is a glass surface, so hover/pressed tint the glass, accent
    //    text deepens to glassAccent and muted text rises to textSecondary ──
    readonly property color hoverFill:   Theme.glass ? Theme.glassHover : Theme.surfaceHover
    readonly property color pressedFill: Theme.glass ? Theme.glassPressed : Theme.surfacePressed
    readonly property color inkAccent:   Theme.glass ? Theme.glassAccent : Theme.accentText
    readonly property color inkMuted:    Theme.glass ? Theme.textSecondary : Theme.textMuted
    function clsOf(t) { return (t && t.lastIpcObject && t.lastIpcObject.class) ? t.lastIpcObject.class : (t && t.wayland ? (t.wayland.appId || "") : "") }
    function iconFor(t) { var e = DesktopEntries.heuristicLookup(root.clsOf(t)); return Quickshell.iconPath(e && e.icon ? e.icon : root.clsOf(t), "application-x-executable") }
    function goWorkspace(id) { Hyprland.dispatch("hl.dsp.focus({workspace=" + id + "})") }

    // the Pen: windows stashed on the special workspace (id < 0) — Super+Z
    readonly property var penWins: {
        var rev = root.claimRev
        var out = []
        var tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (var i = 0; i < tls.length; i++) { var t = tls[i]; if (t.workspace && t.workspace.id < 0) out.push(t) }
        return out
    }

    // workspaces (id>0) that have windows, plus the focused one — sorted, each with its toplevels
    readonly property var wsList: {
        var byws = {}
        var tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (var i = 0; i < tls.length; i++) { var t = tls[i]; var w = t.workspace ? t.workspace.id : -1; if (w > 0) { (byws[w] = byws[w] || []).push(t) } }
        var fid = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
        if (fid > 0 && !byws[fid]) byws[fid] = []
        var ids = Object.keys(byws).map(Number).sort(function (a, b) { return a - b })
        var out = []
        for (var k = 0; k < ids.length; k++) out.push({ id: ids[k], wins: byws[ids[k]] })
        return out
    }

    // Intelligent hide needs to know when floating/fullscreen state changes —
    // those live only in lastIpcObject, which Quickshell doesn't refetch on
    // its own for these events. Bump a revision so wsClaimed re-evaluates.
    property int claimRev: 0
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            var n = ev.name
            if (n === "openwindow" || n === "closewindow" || n === "movewindow"
             || n === "changefloatingmode" || n === "fullscreen") {
                Hyprland.refreshToplevels()
                root.claimRev++
            }
            // entering/leaving the Pen — the monitor's specialWorkspace field
            // only lives in lastIpcObject, so refetch it on the raw event
            if (n === "activespecial") {
                Hyprland.refreshMonitors()
                root.claimRev++
            }
        }
    }

    // One window per screen, visible only on the primary — NOT a single window
    // with a screen: binding. Rebinding screen mid-hotplug (the primary name
    // going stale while the output detaches) could resolve to null and destroy
    // the window for good; per-screen windows are created/destroyed by the
    // screen model itself, so the dock always lands on whatever remains.
    Variants {
        model: Quickshell.screens

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData
        // primary = HyprMon's primary flag; if no connected screen carries that
        // name (mid-hotplug, stale profile), fall back to the first screen
        readonly property bool isPrimary: {
            var ss = Quickshell.screens
            for (var i = 0; i < ss.length; i++)
                if (ss[i].name === HyprMon.primaryName) return win.modelData.name === HyprMon.primaryName
            return ss.length > 0 && win.modelData === ss[0]
        }
        // Always shown while the Overview is open — even if the dock is disabled or
        // set to autohide (the Overview is a launch surface, so the dock belongs there).
        visible: win.isPrimary && (Globals.dockEnabled || Globals.overviewOpen)
        color: "transparent"
        // Always-visible dock reserves its strip so windows tile/maximize ABOVE it
        // instead of sliding underneath; intelligent-hide keeps zero reserve so
        // windows get the full height and the dock overlays only when revealed.
        // The reserve is expressed through the NUMERIC zone, never by flipping
        // exclusionMode at runtime — a live Normal→Ignore switch was not always
        // recommitted to the compositor, leaving a ghost strip that windows
        // refused to use until the dock was toggled off and on.
        exclusiveZone: (Globals.dockEnabled && !Globals.dockAutohide) ? dockH + Theme.windowGap : 0
        // Jump to the Overlay layer while the Overview is open so the dock floats ABOVE
        // the Overview's dim scrim (which is itself on the Overlay layer); otherwise it
        // would be dimmed underneath. Back to Top the rest of the time.
        WlrLayershell.layer: Globals.overviewOpen ? WlrLayer.Overlay : WlrLayer.Top
        WlrLayershell.namespace: "quickshell:dock"
        anchors { bottom: true; left: true; right: true }

        // Settings → Dock → Icon size (Dock card, "Sizes"): the cell is the
        // button/box edge, and every other figure is its own token per size
        // rather than a multiplier — 40/20/32x28/16, 48/24/36x32/20,
        // 64/32/48x40/24.
        readonly property bool small: Globals.dockIconSize === "small"
        readonly property bool large: Globals.dockIconSize === "large"
        readonly property int cell:      win.small ? Theme.controlXl : win.large ? Theme.barHeightLg : Theme.control2xl
        readonly property int glyphPx:   win.small ? Theme.iconLg : win.large ? Theme.icon2xl : Theme.iconXl
        readonly property int tileW:     win.small ? Theme.controlLg : win.large ? Theme.control2xl : Theme.controlLg + Theme.spaceXs
        readonly property int tileH:     win.small ? Theme.controlMd : win.large ? Theme.controlXl : Theme.controlLg
        readonly property int appPx:     win.small ? Theme.iconMd : win.large ? Theme.iconXl : Theme.iconLg
        // the container: spaceS of padding all round, and a radius that stays
        // concentric with the radiusPrimary items inside it
        readonly property int dockH: cell + 2 * Theme.spaceS
        readonly property int dockR: Theme.r(Theme.radiusPrimary + Theme.spaceS)
        // the sliver left on screen while hidden (Dock card: auto-hide)
        readonly property int peek: Theme.spaceXs + Theme.spaceXxs
        implicitHeight: dockH + 2 * Theme.windowGap + Theme.spaceXxs

        // Intelligent hide, made intelligent: the dock ducks only when this
        // screen's active workspace has a window that actually claims the
        // screen (tiled, or fullscreened in any mode). An empty or
        // floating-only workspace keeps the dock out even with autohide on.
        // A toplevel whose IPC object hasn't arrived yet counts as claiming —
        // better a dock that ducks a beat early than one sitting over a tile.
        readonly property var hyMon: Hyprland.monitorFor(win.screen)
        // the second flow: the Pen is OPEN on this screen — the dock then
        // shows only the Pen box, no numbered desktops (you are elsewhere)
        readonly property bool penOpen: {
            var rev = root.claimRev
            var o = win.hyMon ? win.hyMon.lastIpcObject : null
            return !!(o && o.specialWorkspace && String(o.specialWorkspace.name).indexOf("special") === 0)
        }
        readonly property bool wsClaimed: {
            var rev = root.claimRev
            var wid = win.hyMon && win.hyMon.activeWorkspace ? win.hyMon.activeWorkspace.id : -1
            var tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
            for (var i = 0; i < tls.length; i++) {
                var t = tls[i]
                if (!t.workspace || t.workspace.id !== wid) continue
                var o = t.lastIpcObject
                if (!o || !o.floating || o.fullscreen) return true
            }
            return false
        }

        // Revealed when: autohide off · nothing on the workspace claims the screen ·
        // hovering the fixed bottom edge · hovering the dock itself · a popup is open ·
        // within the close grace period · the Overview is open. The bottom edge trigger
        // is FIXED (never moves), so revealing can't slide the dock out from under the
        // cursor → no flicker.
        property bool revealed: !Globals.dockAutohide || !win.wsClaimed || edgeHov.hovered
                                 || dockHov.hovered
                                 || closeHold.running || Globals.launcherOpen || Globals.storeOpen
                                 || Globals.placesOpen || Globals.mediaOpen || Globals.overviewOpen
        Timer { id: closeHold; interval: 280 }
        function maybeHide() { if (!edgeHov.hovered && !dockHov.hovered && !Globals.launcherOpen && !Globals.storeOpen && !Globals.placesOpen && !Globals.mediaOpen) closeHold.restart() }
        Connections { target: edgeHov; function onHoveredChanged() { win.maybeHide() } }
        Connections { target: dockHov; function onHoveredChanged() { win.maybeHide() } }

        // input region: a fixed bottom-edge trigger strip (always) ∪ the dock pill
        mask: Region {
            Region { x: edge.x; y: win.height - win.peek; width: edge.width; height: win.peek }
            Region { x: Math.max(0, dock.x - Theme.spaceS); y: dock.y; width: dock.width + 2 * Theme.spaceS; height: win.height - dock.y }
        }

        // fixed bottom-edge hover trigger (does not move when the dock slides)
        Item { id: edge; x: dock.x; width: dock.width; anchors.bottom: parent.bottom; height: win.peek; HoverHandler { id: edgeHov } }

        // ── the dock pill ──
        Rectangle {
            id: dock
            anchors.horizontalCenter: parent.horizontalCenter
            // windowGap above the bottom edge (Dock card, "Placement")
            y: win.revealed ? (parent.height - height - Theme.windowGap) : (parent.height - win.peek)
            Behavior on y { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            // Entrance: slide up from below the screen edge once the shell is
            // up (mirrors the bar's slide-down; also plays on hotplug). Runs
            // on a Translate so it never fights the revealed/peek y binding.
            // Reduce motion drops the slide; the pill just fades in.
            transform: Translate {
                NumberAnimation on y {
                    running: !Theme.reduceMotion
                    from: win.implicitHeight; to: 0
                    duration: Theme.durSlow; easing.type: Theme.easeSlow
                }
            }
            // Reduce motion: no slides. The pill fades in at start, and
            // auto-hide jumps to the peek and back while the pill fades out
            // and in at durFast, so it still says where it went.
            property bool entered: false
            Component.onCompleted: dock.entered = true
            opacity: !dock.entered ? 0
                   : (Theme.reduceMotion && !win.revealed) ? 0 : 1
            Behavior on opacity { enabled: Theme.reduceMotion; NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
            height: win.dockH
            width: row.implicitWidth + 2 * Theme.spaceS
            radius: win.dockR
            // surfaceRaised, or glassRaised once bar opacity drops below 100
            color: Theme.dockFill
            border.color: Theme.dockStroke
            border.width: Theme.borderWidth1
            HoverHandler { id: dockHov }
            layer.enabled: true
            layer.effect: Elevation {}

            // a square dock launcher (Dock card, "States"): radiusPrimary, no
            // fill by default, surfaceHover on hover, surfacePressed while
            // pressed, and accentSubtle with an accentText glyph while its
            // panel is open. Inside Glass those become the glass tints.
            component DockBtn: Rectangle {
                id: db
                property string glyph: ""
                property string image: ""          // an SVG instead of a glyph (the ewe sheep), tinted like one
                property bool activeState: false
                // a toolbar button named by what it opens (Dock card, Accessibility)
                property string a11yName: ""
                Accessible.role: Accessible.Button
                Accessible.name: db.a11yName
                signal go()
                width: win.cell; height: win.cell; radius: Theme.radiusPrimary
                color: db.activeState ? (Theme.glass ? Theme.glassPressed : Theme.accentSubtle)
                     : dbMa.pressed ? root.pressedFill
                     : dbMa.containsMouse ? root.hoverFill : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                readonly property color tint: db.activeState ? root.inkAccent
                                            : dbMa.containsMouse ? Theme.textPrimary : Theme.textSecondary
                Text {
                    visible: db.image === ""
                    anchors.centerIn: parent
                    text: db.glyph
                    font.family: Theme.fontIcons; font.pixelSize: win.glyphPx
                    color: db.tint
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                }
                Image {
                    id: dbImg
                    visible: false
                    source: db.image
                    width: win.glyphPx; height: width
                    sourceSize: Qt.size(width * 2, height * 2)
                    fillMode: Image.PreserveAspectFit
                }
                MultiEffect {
                    visible: db.image !== ""
                    anchors.centerIn: parent
                    width: dbImg.width; height: dbImg.height
                    source: dbImg
                    colorization: 1.0
                    colorizationColor: db.tint
                    Behavior on colorizationColor { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                }
                MouseArea { id: dbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: db.go() }
            }

            Row {
                id: row
                anchors.centerIn: parent
                spacing: Theme.spaceS

                DockBtn { id: launchBtn; a11yName: "Apps"; image: Qt.resolvedUrl("assets/sheep.svg"); activeState: Globals.launcherOpen; anchors.verticalCenter: parent.verticalCenter; onGo: { Globals.launcherAnchorX = launchBtn.mapToItem(null, launchBtn.width / 2, 0).x; Globals.storeOpen = false; Globals.placesOpen = false; Globals.mediaOpen = false; Globals.launcherOpen = !Globals.launcherOpen } }
                DockBtn { a11yName: "Overview"; glyph: Theme.icStack; anchors.verticalCenter: parent.verticalCenter; onGo: Quickshell.execDetached(["qs", "ipc", "call", "overview", "toggle"]) }
                // store button → Komble (the software manager) when installed;
                // the in-shell quick-installer panel is only the fallback.
                DockBtn { id: storeBtn; a11yName: "Komble"; glyph: Theme.icStore; activeState: Globals.storeOpen; anchors.verticalCenter: parent.verticalCenter; onGo: { if (Globals.kombleInstalled) { if (!Globals.focusAppWindow(["komble"])) Quickshell.execDetached(["komble"]) } else { Globals.storeAnchorX = storeBtn.mapToItem(null, storeBtn.width / 2, 0).x; Globals.launcherOpen = false; Globals.placesOpen = false; Globals.mediaOpen = false; Globals.storeOpen = !Globals.storeOpen } } }
                DockBtn { id: placesBtn; a11yName: "Places"; glyph: Theme.icFolder; activeState: Globals.placesOpen; anchors.verticalCenter: parent.verticalCenter; onGo: { Globals.placesAnchorX = placesBtn.mapToItem(null, placesBtn.width / 2, 0).x; Globals.launcherOpen = false; Globals.storeOpen = false; Globals.mediaOpen = false; Globals.placesOpen = !Globals.placesOpen } }
                // now-playing — only exists while an MPRIS player does (MediaPlayer.qml resolves it)
                DockBtn { id: mediaBtn; a11yName: "Media player"; visible: Globals.mediaPlayer !== null; glyph: Theme.icMusic; activeState: Globals.mediaOpen; anchors.verticalCenter: parent.verticalCenter; onGo: { Globals.mediaAnchorX = mediaBtn.mapToItem(null, mediaBtn.width / 2, 0).x; Globals.launcherOpen = false; Globals.storeOpen = false; Globals.placesOpen = false; Globals.mediaOpen = !Globals.mediaOpen } }

                // spaceS shorter than the items beside it (Dock card #3)
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Theme.borderWidth1; height: win.cell - Theme.spaceS; color: Theme.dockStroke }

                // ── the Pen — ewe's hidden workspace (special:pen). Appears
                //    only while something is stashed: package glyph + a tile
                //    per window. Tile → fetch that window; box → show/hide
                //    the Pen; Super+Z stashes/toggles from the keyboard. ──
                Rectangle {
                    id: penBox
                    visible: root.penWins.length > 0 || win.penOpen
                    anchors.verticalCenter: parent.verticalCenter
                    height: win.cell; radius: Theme.radiusPrimary
                    width: Math.max(win.cell, penRow.implicitWidth + 2 * Theme.spaceS)
                    // open = accentSubtle with an accent border (Dock card)
                    color: win.penOpen ? (Theme.glass ? Theme.glassHover : Theme.accentSubtle)
                         : penMa.hovered ? root.hoverFill : "transparent"
                    border.color: win.penOpen ? Theme.accent : Theme.dockStroke
                    border.width: Theme.borderWidth1
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                    MouseArea { id: penMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        readonly property bool hovered: containsMouse
                        onClicked: Hyprland.dispatch('hl.dsp.workspace.toggle_special("pen")') }
                    Row {
                        id: penRow
                        anchors.centerIn: parent
                        spacing: Theme.spaceXs
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.icPen
                            color: win.penOpen ? root.inkAccent : root.inkMuted
                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
                        }
                        Repeater {
                            model: root.penWins
                            delegate: Rectangle {
                                required property var modelData
                                anchors.verticalCenter: parent.verticalCenter
                                width: win.tileW; height: win.tileH; radius: Theme.radiusSecondary
                                color: modelData.activated && win.penOpen ? Theme.accent
                                     : penTileMa.containsMouse ? root.hoverFill : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                Image {
                                    anchors.centerIn: parent
                                    width: win.appPx; height: win.appPx
                                    sourceSize.width: 2 * win.appPx; sourceSize.height: 2 * win.appPx; mipmap: true
                                    source: root.iconFor(modelData)
                                }
                                MouseArea {
                                    id: penTileMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                    // left: go to that window (inside the Pen);
                                    // middle: send it home to the normal flow
                                    onClicked: function (m) {
                                        if (m.button === Qt.MiddleButton) {
                                            // move THAT window (by address, not "the
                                            // active one"), then focus it where it lands
                                            var ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
                                            var a = String(modelData.address || "")
                                            if (a !== "" && a.indexOf("0x") !== 0) a = "0x" + a
                                            if (a !== "") Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + ws + ', window = "address:' + a + '", follow = false })')
                                            Globals.focusToplevel(modelData)
                                        } else Globals.focusToplevel(modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── workspace boxes (hidden while the Pen flow is open —
                //    one flow at a time, exactly what you see) ──
                Repeater {
                    model: win.penOpen ? [] : root.wsList
                    delegate: Rectangle {
                        id: wsBox
                        required property var modelData
                        readonly property bool focused: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData.id
                        anchors.verticalCenter: parent.verticalCenter
                        height: win.cell; radius: Theme.radiusPrimary
                        width: Math.max(win.cell, wsRow.implicitWidth + 2 * Theme.spaceS)
                        color: focused ? (Theme.glass ? Theme.glassHover : Theme.accentSubtle)
                             : wsMa.containsMouse ? root.hoverFill : "transparent"
                        border.color: focused ? Theme.accent : Theme.dockStroke
                        border.width: Theme.borderWidth1
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }

                        // background click → switch workspace (window tiles sit on top)
                        MouseArea { id: wsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.goWorkspace(wsBox.modelData.id) }

                        Row {
                            id: wsRow
                            anchors.centerIn: parent
                            spacing: Theme.spaceXs
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: wsBox.modelData.id + ":"
                                color: wsBox.focused ? root.inkAccent : root.inkMuted
                                font.family: Theme.type.label.family
                                font.pixelSize: Theme.type.label.size
                                font.weight: Theme.fontWeightSemibold
                                font.features: ({ "tnum": 1 })
                            }
                            // empty-workspace hint
                            Text {
                                visible: wsBox.modelData.wins.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "empty"; color: Theme.textSecondary
                                font.family: Theme.type.label.family
                                font.pixelSize: Theme.type.label.size
                            }
                            // window tiles
                            Repeater {
                                model: wsBox.modelData.wins
                                delegate: Rectangle {
                                    required property var modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: win.tileW; height: win.tileH; radius: Theme.radiusSecondary
                                    color: modelData.activated ? Theme.accent
                                         : tileMa.containsMouse ? root.hoverFill : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                    Image {
                                        anchors.centerIn: parent
                                        width: win.appPx; height: win.appPx
                                        sourceSize.width: 2 * win.appPx; sourceSize.height: 2 * win.appPx; mipmap: true
                                        source: root.iconFor(modelData)
                                    }
                                    MouseArea {
                                        id: tileMa
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: Globals.focusToplevel(modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    }
}
