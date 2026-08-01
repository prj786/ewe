import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
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

    PanelWindow {
        id: win
        screen: { var fm = Hyprland.focusedMonitor; if (!fm) return null; var ss = Quickshell.screens; for (var i = 0; i < ss.length; i++) if (ss[i].name === fm.name) return ss[i]; return null }
        // Always shown while the Overview is open — even if the dock is disabled or
        // set to autohide (the Overview is a launch surface, so the dock belongs there).
        visible: Globals.dockEnabled || Globals.overviewOpen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        // Jump to the Overlay layer while the Overview is open so the dock floats ABOVE
        // the Overview's dim scrim (which is itself on the Overlay layer); otherwise it
        // would be dimmed underneath. Back to Top the rest of the time.
        WlrLayershell.layer: Globals.overviewOpen ? WlrLayer.Overlay : WlrLayer.Top
        WlrLayershell.namespace: "quickshell:dock"
        anchors { bottom: true; left: true; right: true }

        readonly property int dockH: 62
        readonly property int peek: 6
        implicitHeight: dockH + 18

        // Revealed when: autohide off · hovering the fixed bottom edge · hovering the
        // dock itself · a popup is open · within the close grace period · the Overview
        // is open. The bottom edge trigger is FIXED (never moves), so revealing can't
        // slide the dock out from under the cursor → no flicker.
        property bool revealed: !Globals.dockAutohide || edgeHov.hovered || dockHov.hovered
                                 || closeHold.running || Globals.launcherOpen || Globals.storeOpen
                                 || Globals.placesOpen || Globals.overviewOpen
        Timer { id: closeHold; interval: 280 }
        function maybeHide() { if (!edgeHov.hovered && !dockHov.hovered && !Globals.launcherOpen && !Globals.storeOpen && !Globals.placesOpen) closeHold.restart() }
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
            Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutCubic } }
            height: win.dockH
            width: row.implicitWidth + 16
            radius: 18
            color: Theme.panel
            border.color: Theme.stroke; border.width: 1
            HoverHandler { id: dockHov }
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Theme.shadow; shadowOpacity: 0.5; shadowBlur: 1.0; shadowVerticalOffset: 6; blurMax: 40 }

            // a square dock button with custom-drawn glyph
            component DockBtn: Rectangle {
                id: db
                property string kind: "launcher"   // launcher | overview | store | places
                property bool activeState: false
                signal go()
                width: 46; height: 46; radius: 13
                color: (dbMa.containsMouse || activeState) ? Theme.hover : Theme.elevated
                Behavior on color { ColorAnimation { duration: 120 } }
                readonly property color fg: (dbMa.containsMouse || activeState) ? Theme.accent : Theme.fg
                // launcher: 2×2 grid of squares
                Grid {
                    visible: db.kind === "launcher"
                    anchors.centerIn: parent; columns: 2; rowSpacing: 4; columnSpacing: 4
                    Repeater { model: 4; delegate: Rectangle { width: 9; height: 9; radius: 2.5; color: db.fg } }
                }
                // overview: three offset rounded rects (spread windows)
                Item {
                    visible: db.kind === "overview"
                    anchors.centerIn: parent; width: 24; height: 24
                    Rectangle { x: 0;  y: 1;  width: 12; height: 9; radius: 2.5; color: db.fg }
                    Rectangle { x: 13; y: 4;  width: 11; height: 8; radius: 2.5; color: db.fg; opacity: 0.85 }
                    Rectangle { x: 5;  y: 13; width: 14; height: 9; radius: 2.5; color: db.fg; opacity: 0.7 }
                }
                // store: download arrow into a tray
                Item {
                    visible: db.kind === "store"
                    anchors.centerIn: parent; width: 24; height: 24
                    Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 2; width: 4; height: 8; radius: 2; color: db.fg }
                    Shape { anchors.horizontalCenter: parent.horizontalCenter; y: 8; width: 14; height: 7; antialiasing: true
                        ShapePath { strokeWidth: 0; fillColor: db.fg; startX: 0; startY: 0; PathLine { x: 14; y: 0 } PathLine { x: 7; y: 7 } PathLine { x: 0; y: 0 } } }
                    Rectangle { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 2; width: 18; height: 4; radius: 2; color: db.fg }
                }
                // places: a folder (body + tab)
                Item {
                    visible: db.kind === "places"
                    anchors.centerIn: parent; width: 24; height: 24
                    Rectangle { x: 2; y: 5;  width: 9;  height: 5;  radius: 2; color: db.fg }
                    Rectangle { x: 2; y: 8;  width: 20; height: 13; radius: 3; color: db.fg }
                }
                MouseArea { id: dbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: db.go() }
            }

            Row {
                id: row
                anchors.centerIn: parent
                spacing: 8

                DockBtn { id: launchBtn; kind: "launcher"; activeState: Globals.launcherOpen; anchors.verticalCenter: parent.verticalCenter; onGo: { Globals.launcherAnchorX = launchBtn.mapToItem(null, launchBtn.width / 2, 0).x; Globals.storeOpen = false; Globals.placesOpen = false; Globals.launcherOpen = !Globals.launcherOpen } }
                DockBtn { kind: "overview"; anchors.verticalCenter: parent.verticalCenter; onGo: Quickshell.execDetached(["qs", "ipc", "call", "overview", "toggle"]) }
                // store button → Komble (the software manager) when installed;
                // the in-shell quick-installer panel is only the fallback.
                DockBtn { id: storeBtn; kind: "store"; activeState: Globals.storeOpen; anchors.verticalCenter: parent.verticalCenter; onGo: { if (Globals.kombleInstalled) { Quickshell.execDetached(["komble"]) } else { Globals.storeAnchorX = storeBtn.mapToItem(null, storeBtn.width / 2, 0).x; Globals.launcherOpen = false; Globals.placesOpen = false; Globals.storeOpen = !Globals.storeOpen } } }
                DockBtn { id: placesBtn; kind: "places"; activeState: Globals.placesOpen; anchors.verticalCenter: parent.verticalCenter; onGo: { Globals.placesAnchorX = placesBtn.mapToItem(null, placesBtn.width / 2, 0).x; Globals.launcherOpen = false; Globals.storeOpen = false; Globals.placesOpen = !Globals.placesOpen } }

                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 40; color: Theme.stroke }

                // ── workspace boxes ──
                Repeater {
                    model: root.wsList
                    delegate: Rectangle {
                        id: wsBox
                        required property var modelData
                        readonly property bool focused: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData.id
                        anchors.verticalCenter: parent.verticalCenter
                        height: 46; radius: 13
                        width: Math.max(46, wsRow.implicitWidth + 16)
                        color: focused ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : Theme.elevated
                        border.color: focused ? Theme.accent : Theme.stroke; border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }

                        // background click → switch workspace (window tiles sit on top)
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.goWorkspace(wsBox.modelData.id) }

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
                                    width: 34; height: 30; radius: 8
                                    color: modelData.activated ? Theme.accent : Theme.hover
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Image {
                                        anchors.centerIn: parent
                                        width: 20; height: 20; sourceSize.width: 40; sourceSize.height: 40
                                        source: root.iconFor(modelData)
                                    }
                                    MouseArea {
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
