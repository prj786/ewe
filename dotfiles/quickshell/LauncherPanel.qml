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
            x: Math.max(12, Math.min(parent.width - width - 12, Globals.launcherAnchorX - width / 2))   // centered above the launcher button
            y: parent.height - height - 90        // float above the dock
            width: 380; height: 440
            radius: Theme.radius
            color: Theme.bg1
            border.color: Theme.stroke2; border.width: Theme.borderThin
            opacity: Globals.launcherOpen ? 1 : 0
            scale: Globals.launcherOpen ? 1 : 0.96
            transformOrigin: Item.BottomLeft
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            layer.enabled: true
            layer.effect: Elevation {}

            MouseArea { anchors.fill: parent }   // swallow
            Keys.onEscapePressed: Globals.launcherOpen = false

            Column {
                anchors.fill: parent; anchors.margins: 14; spacing: 12

                // search
                Rectangle {
                    width: parent.width; height: 36; radius: Theme.radiusInner
                    color: Theme.bg3; border.color: searchIn.activeFocus ? Theme.accent : Theme.stroke1; border.width: Theme.borderThin
                    Text { anchors.left: parent.left; anchors.leftMargin: 11; anchors.verticalCenter: parent.verticalCenter; text: Theme.icSearch; font.family: Theme.fontIcons; font.pixelSize: 14; color: Theme.fg3 }
                    TextInput {
                        id: searchIn
                        anchors.fill: parent; anchors.leftMargin: 34; anchors.rightMargin: 12; verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg1; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; clip: true
                        onTextChanged: root.query = text
                        Keys.onEscapePressed: Globals.launcherOpen = false
                        onAccepted: { var a = root.shownApps(); if (a.length > 0) root.launch(a[0]) }
                        Text { anchors.verticalCenter: parent.verticalCenter; visible: searchIn.text.length === 0; text: "Search apps…"; color: Theme.fg3; font: searchIn.font }
                    }
                }

                Text {
                    width: parent.width
                    text: root.query.trim() === "" ? "PINNED" : "RESULTS"
                    color: Theme.fg3; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold
                }

                // empty-pinned hint
                Text {
                    width: parent.width; visible: root.query.trim() === "" && root.shownApps().length === 0
                    text: "No pinned apps yet. Search for an app and tap its pin badge to add it here."
                    color: Theme.fg3; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap
                }

                // app grid
                Flickable {
                    width: parent.width
                    height: parent.height - y
                    contentHeight: grid.implicitHeight
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    Grid {
                        id: grid
                        width: parent.width; columns: 4; rowSpacing: 6; columnSpacing: 0
                        Repeater {
                            model: root.shownApps()
                            delegate: Item {
                                id: tile
                                required property var modelData
                                width: grid.width / 4; height: 86
                                readonly property string did: (modelData.id || "") + (String(modelData.id).match(/\.desktop$/) ? "" : ".desktop")
                                Rectangle { anchors.fill: parent; anchors.margins: 3; radius: Theme.r(12); color: tMa.containsMouse ? Theme.subtleHover : Theme.subtle }
                                Column {
                                    anchors.centerIn: parent; spacing: 6
                                    Image { anchors.horizontalCenter: parent.horizontalCenter; width: 40; height: 40; sourceSize.width: 64; sourceSize.height: 64; mipmap: true; source: modelData.icon ? Quickshell.iconPath(modelData.icon, "application-x-executable") : "" }
                                    Text { width: tile.width - 10; horizontalAlignment: Text.AlignHCenter; text: modelData.name || ""; color: Theme.fg1; font.family: Theme.fontText; font.pixelSize: 11; elide: Text.ElideRight; maximumLineCount: 1 }
                                }
                                MouseArea { id: tMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.MiddleButton; onClicked: function (mouse) { root.launch(tile.modelData, mouse.button === Qt.MiddleButton) } }
                                // pin badge (top-right)
                                Rectangle {
                                    anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 5
                                    width: 20; height: 20; radius: 10
                                    visible: tMa.containsMouse || pMa.containsMouse || Globals.isPinned(tile.did)
                                    color: Globals.isPinned(tile.did) ? Theme.accentFill : Qt.rgba(0, 0, 0, 0.35)
                                    Text { anchors.centerIn: parent; text: Theme.icPin; font.family: Theme.fontIcons; font.pixelSize: 11; color: Globals.isPinned(tile.did) ? Theme.accentOn : Theme.fg1 }
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
