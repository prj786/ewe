import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

// LauncherPanel — the pinned-apps / launcher box that pops up above the dock's
// launcher button. Empty search → your pinned apps; type → filter all installed
// apps. Click a tile to launch; click its pin badge to pin/unpin (persisted via
// Globals.pinnedApps). Themed from Theme.qml.
Scope {
    id: root
    function g(c) { return String.fromCodePoint(c) }
    property string query: ""

    function entryForId(id) {
        var want = String(id || "").replace(/\.desktop$/, "")
        var a = DesktopEntries.applications ? DesktopEntries.applications.values : []
        for (var i = 0; i < a.length; i++) if (a[i] && a[i].id === want) return a[i]
        return null
    }
    readonly property var allApps: {
        var a = DesktopEntries.applications ? DesktopEntries.applications.values.slice() : []
        a = a.filter(function (x) { return x && !x.noDisplay })
        a.sort(function (x, y) { return (x.name || "").localeCompare(y.name || "") })
        return a
    }
    function shownApps() {
        var q = root.query.trim().toLowerCase()
        if (q === "") {
            var out = []
            var p = Globals.pinnedApps || []
            for (var i = 0; i < p.length; i++) { var e = root.entryForId(p[i]); if (e) out.push(e) }
            return out
        }
        return root.allApps.filter(function (e) { return (e.name || "").toLowerCase().indexOf(q) >= 0 }).slice(0, 24)
    }
    // focus-or-launch: a running app's window is jumped to; `fresh` (middle
    // click) forces a new instance anyway
    function launch(e, fresh) { Globals.launchEntry(e, fresh); Globals.launcherOpen = false }

    // Latch the monitor when opening — binding `screen` to focusedMonitor makes it
    // churn under focus-follows-mouse (surface remaps → visible blink).
    property var openScreen: null
    function focusedScreen() {
        var fm = Hyprland.focusedMonitor, ss = Quickshell.screens
        if (fm) for (var i = 0; i < ss.length; i++) if (ss[i].name === fm.name) return ss[i]
        return ss.length > 0 ? ss[0] : null
    }
    Component.onCompleted: root.openScreen = root.focusedScreen()

    IpcHandler {
        target: "launcher"
        function toggle(): void { Globals.storeOpen = false; Globals.placesOpen = false; Globals.launcherOpen = !Globals.launcherOpen }
        function show(): void { Globals.launcherOpen = true }
        function hide(): void { Globals.launcherOpen = false }
    }

    PanelWindow {
        id: win
        visible: Globals.launcherOpen || win.held
        screen: root.openScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell:launcher"
        anchors { top: true; bottom: true; left: true; right: true }

        // `held` keeps the window mapped through the close animation; set on
        // OPEN so no signal-order race can unmap it early (see Overview.qml)
        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durSlow + 60); onTriggered: win.held = false }
        Connections { target: Globals; function onLauncherOpenChanged() {
            if (Globals.launcherOpen) { closeTimer.stop(); win.held = true; root.openScreen = root.focusedScreen(); root.query = ""; searchIn.text = ""; searchIn.forceActiveFocus() }
            else closeTimer.restart()
        } }

        MouseArea { anchors.fill: parent; onClicked: Globals.launcherOpen = false }

        Rectangle {
            id: box
            // kept spaceS + spaceXs from the screen edges, centred over the
            // dock's sheep button (Launcher panel card, "Placement")
            readonly property int edgeGap: Theme.spaceS + Theme.spaceXs
            x: Math.max(edgeGap, Math.min(parent.width - width - edgeGap, Globals.launcherAnchorX - width / 2))
            // the dock's own strip plus the card's spaceS + spaceXs gap above it
            readonly property int dockGap: 90
            width: Theme.panelSm
            height: Math.min(440, parent.height - dockGap - 2 * edgeGap)
            radius: Theme.radiusRounded
            color: Theme.surfaceRaised
            border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
            opacity: Globals.launcherOpen ? 1 : 0
            // a panel opens with a fade plus a short rise from its own edge;
            // Reduce motion zeroes the offset, leaving the fade (Theme)
            y: Math.max(edgeGap, parent.height - height - dockGap)
               + (Globals.launcherOpen ? 0 : Theme.slideOffset)
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            layer.enabled: true
            layer.effect: Elevation {}

            MouseArea { anchors.fill: parent }   // swallow
            Keys.onEscapePressed: Globals.launcherOpen = false

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spaceS + Theme.spaceXs
                spacing: Theme.spaceS + Theme.spaceXs

                // ── Search field (design system: Search field, md) ──
                Rectangle {
                    width: parent.width; height: Theme.controlMd
                    radius: Theme.radiusPrimary
                    color: Theme.surfaceSunken
                    border.width: Theme.fieldBorderWidth
                    border.color: searchIn.activeFocus ? Theme.focusRing
                                : fieldHov.hovered ? Theme.textMuted : Theme.borderStrong
                    Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                    HoverHandler { id: fieldHov }
                    Text {
                        id: searchGlyph
                        anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.icSearch
                        font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                        color: Theme.textMuted
                    }
                    TextInput {
                        id: searchIn
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spaceS + Theme.iconMd + Theme.spaceXs
                        anchors.rightMargin: Theme.spaceS
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.textPrimary
                        font.family: Theme.type.body.family
                        font.pixelSize: Theme.type.body.size
                        clip: true
                        selectionColor: Theme.accent
                        onTextChanged: root.query = text
                        // Esc clears the query, a second Esc closes the panel
                        Keys.onEscapePressed: { if (searchIn.text !== "") searchIn.text = ""; else Globals.launcherOpen = false }
                        onAccepted: { var a = root.shownApps(); if (a.length > 0) root.launch(a[0]) }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchIn.text.length === 0
                            text: "Search apps"
                            color: Theme.textMuted; font: searchIn.font
                        }
                    }
                }

                // the card's own 12px gap, so the heading keeps no extra lead-in
                SectionTitle { width: parent.width; first: true; text: root.query.trim() === "" ? "Pinned" : "Results" }

                // ── empty states (design system: Empty state, compact) ──
                Column {
                    width: parent.width
                    visible: root.shownApps().length === 0
                    spacing: Theme.spaceXs
                    topPadding: Theme.spaceMd
                    readonly property bool searching: root.query.trim() !== ""
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Theme.controlLg; height: Theme.controlLg
                        radius: Theme.radiusFull
                        color: Theme.surfaceHover
                        Text {
                            anchors.centerIn: parent
                            text: parent.parent.searching ? Theme.icSearchOff : Theme.icPin
                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                            color: Theme.textSecondary
                        }
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: parent.searching ? "No apps match “" + root.query.trim() + "”" : "No pinned apps yet"
                        color: Theme.textPrimary
                        font.family: Theme.type.bodyStrong.family
                        font.pixelSize: Theme.type.bodyStrong.size
                        font.weight: Theme.fontWeightSemibold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: parent.searching ? "Check the spelling, or find more apps in Komble."
                                               : "Search for an app and use its pin to keep it here."
                        color: Theme.textSecondary
                        font.family: Theme.type.body.family
                        font.pixelSize: Theme.type.body.size
                    }
                    // secondary button — the one way on from a dead end
                    Rectangle {
                        visible: parent.searching
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: kombleLbl.implicitWidth + 2 * (Theme.spaceS + Theme.spaceXs)
                        height: Theme.controlMd
                        radius: Theme.radiusPrimary
                        color: kombleMa.pressed ? Theme.surfacePressed
                             : kombleMa.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                        border.color: Theme.borderStrong; border.width: Theme.borderWidth1
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        Text {
                            id: kombleLbl
                            anchors.centerIn: parent
                            text: "Open Komble"
                            color: Theme.textPrimary
                            font.family: Theme.type.body.family
                            font.pixelSize: Theme.type.body.size
                            font.weight: Theme.fontWeightMedium
                        }
                        MouseArea {
                            id: kombleMa
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { Globals.launcherOpen = false; Globals.openStore() }
                        }
                    }
                }

                // ── app grid: 4 columns of grid app tiles ──
                Flickable {
                    width: parent.width
                    height: parent.height - y
                    contentHeight: grid.implicitHeight
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    Grid {
                        id: grid
                        width: parent.width; columns: 4
                        rowSpacing: Theme.spaceXxs; columnSpacing: 0
                        Repeater {
                            model: root.shownApps()
                            delegate: Item {
                                id: tile
                                required property var modelData
                                width: grid.width / 4
                                height: Theme.controlXl + Theme.lineHeightXs + 2 * Theme.spaceS + Theme.spaceXs
                                readonly property string did: (modelData.id || "") + (String(modelData.id).match(/\.desktop$/) ? "" : ".desktop")
                                readonly property bool pinned: Globals.isPinned(tile.did)
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: Theme.spaceXxs
                                    radius: Theme.radiusPrimary
                                    color: tMa.containsMouse ? Theme.surfaceHover : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                }
                                Column {
                                    anchors.centerIn: parent; spacing: Theme.spaceXs
                                    Image {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Theme.controlXl; height: Theme.controlXl
                                        sourceSize.width: 2 * Theme.controlXl; sourceSize.height: 2 * Theme.controlXl
                                        mipmap: true
                                        source: modelData.icon ? Quickshell.iconPath(modelData.icon, "application-x-executable") : ""
                                    }
                                    Text {
                                        width: tile.width - 2 * Theme.spaceS
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData.name || ""
                                        color: Theme.textSecondary
                                        font.family: Theme.type.caption.family
                                        font.pixelSize: Theme.type.caption.size
                                        elide: Text.ElideRight; maximumLineCount: 1
                                    }
                                }
                                MouseArea { id: tMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.MiddleButton; onClicked: function (mouse) { root.launch(tile.modelData, mouse.button === Qt.MiddleButton) } }
                                // pin badge — top right, on hover; always on and
                                // accent for a pinned app while searching
                                Rectangle {
                                    anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                                    anchors.top: parent.top; anchors.topMargin: Theme.spaceXxs
                                    width: Theme.iconLg + Theme.spaceXxs; height: width
                                    radius: Theme.radiusFull
                                    visible: tMa.containsMouse || pMa.containsMouse || tile.pinned
                                    color: tile.pinned ? Theme.accent : Theme.surfaceOverlay
                                    border.width: Theme.borderWidth1
                                    border.color: tile.pinned ? Theme.accent
                                                : pMa.containsMouse ? Theme.borderStrong : Theme.borderSubtle
                                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: Theme.icPin
                                        font.family: Theme.fontIcons; font.pixelSize: Theme.iconXs
                                        color: tile.pinned ? Theme.onAccent
                                             : pMa.containsMouse ? Theme.textPrimary : Theme.textSecondary
                                    }
                                    MouseArea { id: pMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Globals.togglePin(tile.did) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
