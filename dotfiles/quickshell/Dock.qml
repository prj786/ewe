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
    function clsOf(t) { return (t && t.lastIpcObject && t.lastIpcObject.class) ? t.lastIpcObject.class : (t && t.wayland ? (t.wayland.appId || "") : "") }
    function iconFor(t) { var e = DesktopEntries.heuristicLookup(root.clsOf(t)); return Quickshell.iconPath(e && e.icon ? e.icon : root.clsOf(t), "application-x-executable") }
    function goWorkspace(id) { Hyprland.dispatch("hl.dsp.focus({workspace=" + id + "})") }

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
        exclusiveZone: (Globals.dockEnabled && !Globals.dockAutohide) ? dockH + 8 : 0
        // Jump to the Overlay layer while the Overview is open so the dock floats ABOVE
        // the Overview's dim scrim (which is itself on the Overlay layer); otherwise it
        // would be dimmed underneath. Back to Top the rest of the time.
        WlrLayershell.layer: Globals.overviewOpen ? WlrLayer.Overlay : WlrLayer.Top
        WlrLayershell.namespace: "quickshell:dock"
        anchors { bottom: true; left: true; right: true }

        // Settings → Dock → Icon size. `cell` is the button/box edge; everything
        // else scales off `k` so the three sizes keep the same proportions.
        readonly property int cell: Globals.dockIconSize === "small" ? 38
                                  : Globals.dockIconSize === "large" ? 54 : 46
        readonly property real k: cell / 46
        readonly property int dockH: cell + 16
        readonly property int peek: 6
        implicitHeight: dockH + 18

        // Intelligent hide, made intelligent: the dock ducks only when this
        // screen's active workspace has a window that actually claims the
        // screen (tiled, or fullscreened in any mode). An empty or
        // floating-only workspace keeps the dock out even with autohide on.
        // A toplevel whose IPC object hasn't arrived yet counts as claiming —
        // better a dock that ducks a beat early than one sitting over a tile.
        readonly property var hyMon: Hyprland.monitorFor(win.screen)
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
            Region { x: Math.max(0, dock.x - 8); y: dock.y; width: dock.width + 16; height: win.height - dock.y }
        }

        // fixed bottom-edge hover trigger (does not move when the dock slides)
        Item { id: edge; x: dock.x; width: dock.width; anchors.bottom: parent.bottom; height: win.peek; HoverHandler { id: edgeHov } }

        // ── the dock pill ──
        Rectangle {
            id: dock
            anchors.horizontalCenter: parent.horizontalCenter
            y: win.revealed ? (parent.height - height - 8) : (parent.height - win.peek)
            Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            // Entrance: slide up from below the screen edge once the shell is
            // up (mirrors the bar's slide-down; also plays on hotplug). Runs
            // on a Translate so it never fights the revealed/peek y binding.
            transform: Translate {
                NumberAnimation on y {
                    from: win.implicitHeight; to: 0
                    duration: Theme.durSlow; easing.type: Theme.ease
                }
            }
            height: win.dockH
            width: row.implicitWidth + 16
            radius: Theme.radius
            color: Theme.panel
            border.color: Theme.stroke; border.width: 1
            HoverHandler { id: dockHov }
            layer.enabled: true
            layer.effect: Elevation {}
            Sheen { radius: parent.radius }

            // a square dock button — Phosphor glyph, same quiet-hover treatment
            // as the bar's StatusItems so bar and dock read as one system
            component DockBtn: Rectangle {
                id: db
                property string glyph: ""
                property bool activeState: false
                signal go()
                width: win.cell; height: win.cell; radius: Math.round(13 * win.k)
                color: activeState ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                     : dbMa.containsMouse ? Theme.hover : "transparent"
                border.color: activeState ? Theme.accent : "transparent"
                border.width: activeState ? 1 : 0
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
                scale: dbMa.pressed ? 0.9 : (dbMa.containsMouse ? 1.08 : 1.0)
                Behavior on scale { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                Text {
                    anchors.centerIn: parent
                    text: db.glyph
                    font.family: Theme.fontIcons; font.pixelSize: Math.round(22 * win.k)
                    color: db.activeState ? Theme.accent : (dbMa.containsMouse ? Theme.fg : Theme.fgSecondary)
                    Behavior on color { ColorAnimation { duration: Theme.durFast } }
                }
                MouseArea { id: dbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: db.go() }
            }

            Row {
                id: row
                anchors.centerIn: parent
                spacing: 8

                DockBtn { id: launchBtn; glyph: Theme.icApps; activeState: Globals.launcherOpen; anchors.verticalCenter: parent.verticalCenter; onGo: { Globals.launcherAnchorX = launchBtn.mapToItem(null, launchBtn.width / 2, 0).x; Globals.storeOpen = false; Globals.placesOpen = false; Globals.mediaOpen = false; Globals.launcherOpen = !Globals.launcherOpen } }
                DockBtn { glyph: Theme.icStack; anchors.verticalCenter: parent.verticalCenter; onGo: Quickshell.execDetached(["qs", "ipc", "call", "overview", "toggle"]) }
                // store button → Komble (the software manager) when installed;
                // the in-shell quick-installer panel is only the fallback.
                DockBtn { id: storeBtn; glyph: Theme.icDownload; activeState: Globals.storeOpen; anchors.verticalCenter: parent.verticalCenter; onGo: { if (Globals.kombleInstalled) { Quickshell.execDetached(["komble"]) } else { Globals.storeAnchorX = storeBtn.mapToItem(null, storeBtn.width / 2, 0).x; Globals.launcherOpen = false; Globals.placesOpen = false; Globals.mediaOpen = false; Globals.storeOpen = !Globals.storeOpen } } }
                DockBtn { id: placesBtn; glyph: Theme.icFolder; activeState: Globals.placesOpen; anchors.verticalCenter: parent.verticalCenter; onGo: { Globals.placesAnchorX = placesBtn.mapToItem(null, placesBtn.width / 2, 0).x; Globals.launcherOpen = false; Globals.storeOpen = false; Globals.mediaOpen = false; Globals.placesOpen = !Globals.placesOpen } }
                // now-playing — only exists while an MPRIS player does (MediaPlayer.qml resolves it)
                DockBtn { id: mediaBtn; visible: Globals.mediaPlayer !== null; glyph: Theme.icMusic; activeState: Globals.mediaOpen; anchors.verticalCenter: parent.verticalCenter; onGo: { Globals.mediaAnchorX = mediaBtn.mapToItem(null, mediaBtn.width / 2, 0).x; Globals.launcherOpen = false; Globals.storeOpen = false; Globals.placesOpen = false; Globals.mediaOpen = !Globals.mediaOpen } }

                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: Math.round(40 * win.k); color: Theme.stroke }

                // ── workspace boxes ──
                Repeater {
                    model: root.wsList
                    delegate: Rectangle {
                        id: wsBox
                        required property var modelData
                        readonly property bool focused: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData.id
                        anchors.verticalCenter: parent.verticalCenter
                        height: win.cell; radius: Math.round(13 * win.k)
                        width: Math.max(win.cell, wsRow.implicitWidth + 16)
                        color: focused ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                             : wsMa.containsMouse ? Theme.hover : Theme.elevated
                        border.color: focused ? Theme.accent : Theme.stroke; border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }

                        // background click → switch workspace (window tiles sit on top)
                        MouseArea { id: wsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.goWorkspace(wsBox.modelData.id) }

                        Row {
                            id: wsRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: wsBox.modelData.id + ":"
                                color: wsBox.focused ? Theme.accent : Theme.fgDim
                                font.family: Theme.fontText; font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            // empty-workspace hint
                            Text {
                                visible: wsBox.modelData.wins.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "empty"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11
                            }
                            // window tiles
                            Repeater {
                                model: wsBox.modelData.wins
                                delegate: Rectangle {
                                    required property var modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.round(34 * win.k); height: Math.round(30 * win.k); radius: 8
                                    color: modelData.activated ? Theme.accent : Theme.hover
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    scale: tileMa.containsMouse ? 1.1 : 1.0
                                    Behavior on scale { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                    Image {
                                        anchors.centerIn: parent
                                        width: Math.round(20 * win.k); height: Math.round(20 * win.k); sourceSize.width: 40; sourceSize.height: 40; mipmap: true
                                        source: root.iconFor(modelData)
                                    }
                                    MouseArea {
                                        id: tileMa
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { if (modelData.wayland) modelData.wayland.activate() }
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
