import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// AppMenu — the "move to workspace" dropdown. The other window actions are
// inline buttons in the bar's left cluster (Bar.qml); only this one drops
// down (a workspace has to be picked). Slides out of the bar under the
// move-to button, styled like the topbar.
Scope {
    id: root

    function g(c) { return String.fromCodePoint(c) }

    readonly property var top: Hyprland.activeToplevel
    function appName() {
        var c = (top && top.lastIpcObject && top.lastIpcObject.class) ? top.lastIpcObject.class : ""
        if (!c && top && top.wayland && top.wayland.appId) c = top.wayland.appId
        if (!c) return "window"
        var s = c.split('.').pop().split('-')[0]
        return s.charAt(0).toUpperCase() + s.slice(1)
    }
    // Lua config: /dispatch evaluates its arg as Lua, so callers pass a typed
    // hl.dsp.* dispatcher expression (a plain "movetoworkspace 2" would be invalid Lua).
    function act(expr) { Hyprland.dispatch(expr); Globals.appMenuOpen = false }

    // Dynamic workspace count: 1 … (highest used or focused) + 1, capped at 10.
    property int wsCount: {
        var mx = (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id > 0) ? Hyprland.focusedWorkspace.id : 1
        var ws = Hyprland.workspaces.values
        for (var i = 0; i < ws.length; i++) { var id = ws[i].id; if (id > 0 && id < 100 && id > mx) mx = id }
        return Math.min(10, mx + 1)
    }

    PanelWindow {
        id: win
        // visible is ASSIGNED, never bound (same fix as Settings.qml): a binding
        // racing the close timer unmaps + remaps the layer for a frame — a blink.
        visible: false
        screen: {
            var s = Quickshell.screens, fm = Hyprland.focusedMonitor
            if (fm) for (var i = 0; i < s.length; i++) if (s[i].name === fm.name) return s[i]
            return s.length > 0 ? s[0] : null
        }
        color: "transparent"
        // Ignore (not exclusiveZone:0): span the FULL output, including under the
        // bar, so clicking the topbar also closes the menu (true toggle).
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:appmenu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        anchors { top: true; bottom: true; left: true; right: true }

        Timer { id: closeTimer; interval: Math.max(1, Theme.durBase); onTriggered: win.visible = false }
        Connections {
            target: Globals
            function onAppMenuOpenChanged() {
                if (Globals.appMenuOpen) { closeTimer.stop(); win.visible = true; keyCatcher.forceActiveFocus() }
                else closeTimer.restart()
            }
        }

        MouseArea { anchors.fill: parent; onClicked: Globals.appMenuOpen = false }
        Item { id: keyCatcher; anchors.fill: parent; focus: true; Keys.onEscapePressed: Globals.appMenuOpen = false }

        // clip box pinned to the bar's bottom edge, positioned under the move-to
        // button; the menu slides down out of it (reads as part of the topbar).
        Item {
            id: clipBox
            x: Math.max(8, Math.min(Globals.appAnchorX, win.width - width - 8))
            anchors.top: parent.top
            anchors.topMargin: Theme.barHeight   // window spans the full output → offset by the bar
            width: 190
            height: menu.height
            clip: true

            Rectangle {
                id: menu
                width: parent.width
                height: col.implicitHeight + 12
                y: Globals.appMenuOpen ? 0 : -height
                Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutCubic } }
                // square top (flush with the bar), rounded bottom
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: 12
                bottomRightRadius: 12
                color: Theme.panel
                layer.enabled: true
                layer.effect: Elevation {}
                MouseArea { anchors.fill: parent }   // swallow

                Column {
                    id: col
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: 6
                    spacing: 1

                    Text {
                        leftPadding: 10; topPadding: 4; bottomPadding: 4
                        text: "Move " + root.appName() + " to"
                        color: Theme.accent
                        font.family: Theme.fontDisplay; font.pixelSize: Theme.fsBody; font.weight: Font.Bold
                    }
                    Rectangle { width: parent.width; height: 1; color: Theme.stroke }

                    // workspace chips
                    Flow {
                        width: parent.width
                        spacing: 4
                        leftPadding: 10; topPadding: 6; bottomPadding: 4
                        Repeater {
                            model: root.wsCount
                            delegate: Rectangle {
                                required property int index
                                readonly property int wsId: index + 1
                                readonly property bool current: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === wsId
                                width: 26; height: 24; radius: 6
                                color: chipMa.containsMouse ? Theme.accent : (current ? Theme.hover : Theme.elevated)
                                Text { anchors.centerIn: parent; text: parent.wsId; color: chipMa.containsMouse ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: 12 }
                                MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.act("hl.dsp.window.move({workspace=" + parent.wsId + ", follow=false})") }
                            }
                        }
                    }
                }
            }
        }
    }
}
