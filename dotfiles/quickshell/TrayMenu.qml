import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray

// TrayMenu — a THEMED popup that renders a system-tray item's context menu
// (SNI DBusMenu) via QsMenuOpener, styled entirely from Theme.qml and anchored
// under the icon that was clicked. Replaces the native (white, unthemed)
// QsMenuAnchor menu. Driven by Globals.trayMenu{Handle,AnchorX,Open}, set by Bar.
Scope {
    id: root
    function glyph(c) { return String.fromCodePoint(c) }

    QsMenuOpener { id: opener; menu: Globals.trayMenuHandle }

    // one submenu level, flown out to the right on hover
    property var subEntry: null
    property real subY: 0
    QsMenuOpener { id: subOpener; menu: root.subEntry }

    // latch the monitor on open (avoid focus-follows-mouse surface-remap blink)
    property var openScreen: null
    function focusedScreen() {
        var fm = Hyprland.focusedMonitor, ss = Quickshell.screens
        if (fm) for (var i = 0; i < ss.length; i++) if (ss[i].name === fm.name) return ss[i]
        return ss.length > 0 ? ss[0] : null
    }
    Component.onCompleted: root.openScreen = root.focusedScreen()

    // a single menu row, shared by the main menu and the submenu
    component MenuRow: Item {
        id: row
        required property var entry
        property bool sub: false
        width: parent ? parent.width : 220
        height: (entry && entry.isSeparator) ? 7 : 26

        // separator
        Rectangle {
            visible: row.entry && row.entry.isSeparator
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 10; anchors.rightMargin: 10
            height: 1; color: Theme.stroke; opacity: 0.6
        }

        Rectangle {
            visible: !(row.entry && row.entry.isSeparator)
            anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 4
            radius: Theme.radiusInner
            color: (rowMa.containsMouse && row.entry && row.entry.enabled) ? Theme.hover : "transparent"

            // check / radio indicator
            Text {
                anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                visible: row.entry && row.entry.checkState === Qt.Checked
                text: root.glyph(0xF012C)            // check
                font.family: Theme.fontMono; font.pixelSize: 13; color: Theme.accent
            }
            Text {
                anchors.left: parent.left; anchors.leftMargin: 26
                anchors.right: parent.right; anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: row.entry ? row.entry.text : ""
                color: (row.entry && row.entry.enabled) ? Theme.fg : Theme.fgDim
                font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                elide: Text.ElideRight
            }
            // submenu arrow
            Text {
                anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                visible: row.entry && row.entry.hasChildren
                text: root.glyph(0xF0142)            // chevron-right
                font.family: Theme.fontMono; font.pixelSize: 13; color: Theme.fgDim
            }

            MouseArea {
                id: rowMa
                anchors.fill: parent
                hoverEnabled: true
                enabled: row.entry && row.entry.enabled && !row.entry.isSeparator
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    if (row.sub) return
                    if (row.entry && row.entry.hasChildren) { root.subEntry = row.entry; root.subY = row.mapToItem(mainBox, 0, 0).y }
                    else root.subEntry = null
                }
                onClicked: {
                    if (!row.entry || row.entry.hasChildren) return   // hover opens submenus
                    row.entry.triggered()
                    Globals.trayMenuOpen = false
                }
            }
        }
    }

    PanelWindow {
        id: win
        visible: Globals.trayMenuOpen || closeTimer.running
        screen: root.openScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell:traymenu"
        anchors { top: true; bottom: true; left: true; right: true }

        Timer { id: closeTimer; interval: Math.max(1, Theme.durBase) }
        Connections { target: Globals; function onTrayMenuOpenChanged() {
            if (Globals.trayMenuOpen) { root.openScreen = root.focusedScreen(); root.subEntry = null }
            else closeTimer.restart()
        } }

        MouseArea { anchors.fill: parent; onClicked: Globals.trayMenuOpen = false }

        // main menu
        Rectangle {
            id: mainBox
            x: Math.max(6, Math.min(parent.width - width - 6, Globals.trayMenuAnchorX - width / 2))
            y: Theme.barHeight + 4
            width: 230
            height: mainCol.implicitHeight + 10
            radius: Theme.radius; color: Theme.panel; border.color: Theme.stroke; border.width: 1
            opacity: Globals.trayMenuOpen ? 1 : 0
            scale: Globals.trayMenuOpen ? 1 : 0.97
            transformOrigin: Item.Top
            Behavior on opacity { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Theme.shadow; shadowOpacity: 0.5; shadowBlur: 1.0; shadowVerticalOffset: 6; blurMax: 48 }
            MouseArea { anchors.fill: parent }   // swallow clicks inside the box
            Column {
                id: mainCol
                width: parent.width; y: 5
                Repeater { model: opener.children; delegate: MenuRow { required property var modelData; entry: modelData } }
            }
        }

        // submenu (one level), to the right of the main box
        Rectangle {
            id: subBox
            visible: root.subEntry !== null && Globals.trayMenuOpen
            x: Math.min(parent.width - width - 6, mainBox.x + mainBox.width - 4)
            y: mainBox.y + root.subY
            width: 210
            height: subCol.implicitHeight + 10
            radius: Theme.radius; color: Theme.panel; border.color: Theme.stroke; border.width: 1
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Theme.shadow; shadowOpacity: 0.5; shadowBlur: 1.0; shadowVerticalOffset: 6; blurMax: 48 }
            MouseArea { anchors.fill: parent }
            Column {
                id: subCol
                width: parent.width; y: 5
                Repeater { model: subOpener.children; delegate: MenuRow { required property var modelData; entry: modelData; sub: true } }
            }
        }
    }
}
