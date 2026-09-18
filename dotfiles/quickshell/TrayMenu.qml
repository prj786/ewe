import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray

// TrayMenu — a THEMED popup that renders a system-tray item's context menu
// (SNI DBusMenu) via QsMenuOpener (design system: Menu). It replaces the
// native, unthemed QsMenuAnchor menu and is anchored under the icon that was
// clicked. Driven by Globals.trayMenu{Handle,AnchorX,Open}, set by Bar.
//
//   container  surfaceOverlay with a borderWidth1 borderSubtle outline, the
//              radiusRounded corner, the shadowFloat elevation and spaceXs of
//              padding; at least 6 × controlMd + spaceS (176) and at most
//              10 × controlLg (320) wide
//   item       controlMd tall, spaceS of side padding, the radiusSecondary
//              corner so it nests evenly inside the container
//   check      an iconMd tick in accentText at the leading edge; items
//              without one keep the space, so every label lines up
//   submenu    an iconMd chevron at the trailing edge, flown out to the right
//   divider    a borderWidth1 borderSubtle line with spaceXs above and below
//
//   hover     surfaceHover · disabled textDisabled, no hover
//
// One submenu level, opened on hover — DBusMenu items carry no shortcuts or
// tones, so the card's Kbd and danger forms have nothing to render here.
Scope {
    id: root
    function glyph(c) { return String.fromCodePoint(c) }

    QsMenuOpener { id: opener; menu: Globals.trayMenuHandle }

    // one submenu level, flown out to the right on hover
    property var subEntry: null
    property real subY: 0
    QsMenuOpener { id: subOpener; menu: root.subEntry }

    readonly property int menuMin: 6 * Theme.controlMd + Theme.spaceS
    readonly property int menuMax: 10 * Theme.controlLg
    // the leading check column, both gaps and the trailing chevron
    readonly property int menuChrome: 2 * Theme.spaceXs + 2 * Theme.spaceS
                                      + 2 * (Theme.iconMd + Theme.spaceS)

    // latch the monitor on open (avoid focus-follows-mouse surface-remap blink)
    property var openScreen: null
    function focusedScreen() {
        var fm = Hyprland.focusedMonitor, ss = Quickshell.screens
        if (fm) for (var i = 0; i < ss.length; i++) if (ss[i].name === fm.name) return ss[i]
        return ss.length > 0 ? ss[0] : null
    }
    Component.onCompleted: root.openScreen = root.focusedScreen()

    // A menu sizes itself to its longest label, between the card's two
    // bounds. These Texts are never shown; they only carry their natural
    // width, which a Column reports as its own (the rows themselves follow
    // the box, so they cannot be asked).
    component MenuSizer: Column {
        id: sizer
        property var entries: []
        visible: false
        Repeater {
            model: sizer.entries
            delegate: Text {
                required property var modelData
                text: (modelData && !modelData.isSeparator) ? modelData.text : ""
                font.family: Theme.type.body.family
                font.pixelSize: Theme.type.body.size
            }
        }
    }

    // a single menu row, shared by the main menu and the submenu
    component MenuRow: Item {
        id: row
        required property var entry
        property bool sub: false
        readonly property bool separator: row.entry !== null && row.entry.isSeparator
        readonly property bool usable: row.entry !== null && row.entry.enabled && !row.separator
        width: parent ? parent.width : Theme.panelSm / 2
        height: row.separator ? Theme.borderWidth1 + 2 * Theme.spaceXs : Theme.controlMd

        // divider: one line, spaceXs of air above and below
        Rectangle {
            visible: row.separator
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.right: parent.right
            height: Theme.borderWidth1; color: Theme.borderSubtle
        }

        Rectangle {
            visible: !row.separator
            anchors.fill: parent
            radius: Theme.radiusSecondary
            color: (rowMa.containsMouse && row.usable) ? Theme.surfaceHover : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }

            // check / radio indicator — the column is kept whether or not the
            // item has one, so every label starts at the same x
            Text {
                id: tick
                anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconMd
                horizontalAlignment: Text.AlignHCenter
                visible: row.entry !== null && row.entry.checkState === Qt.Checked
                text: Theme.icCheck
                font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                color: Theme.accentText
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spaceS + Theme.iconMd + Theme.spaceS
                anchors.right: parent.right
                anchors.rightMargin: Theme.spaceS + (chev.visible ? Theme.iconMd + Theme.spaceS : 0)
                anchors.verticalCenter: parent.verticalCenter
                text: row.entry ? row.entry.text : ""
                color: (row.entry && row.entry.enabled) ? Theme.textPrimary : Theme.textDisabled
                font.family: Theme.type.body.family
                font.pixelSize: Theme.type.body.size
                font.weight: (row.entry && row.entry.checkState === Qt.Checked)
                             ? Theme.fontWeightMedium : Theme.type.body.weight
                elide: Text.ElideRight
            }
            // submenu arrow
            Text {
                id: chev
                anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                anchors.verticalCenter: parent.verticalCenter
                visible: row.entry !== null && row.entry.hasChildren
                text: Theme.icChevronRight
                font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                color: rowMa.containsMouse ? Theme.textPrimary : Theme.textSecondary
            }

            MouseArea {
                id: rowMa
                anchors.fill: parent
                hoverEnabled: true
                enabled: row.usable
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
        visible: Globals.trayMenuOpen || win.held
        screen: root.openScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell:traymenu"
        anchors { top: true; bottom: true; left: true; right: true }

        // `held` keeps the window mapped through the close animation; set on
        // OPEN so no signal-order race can unmap it early (see Overview.qml)
        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durBase + 60); onTriggered: win.held = false }
        Connections { target: Globals; function onTrayMenuOpenChanged() {
            if (Globals.trayMenuOpen) { closeTimer.stop(); win.held = true; root.openScreen = root.focusedScreen(); root.subEntry = null }
            else closeTimer.restart()
        } }

        MouseArea { anchors.fill: parent; onClicked: Globals.trayMenuOpen = false }

        MenuSizer { id: mainSizer; entries: opener.children }
        MenuSizer { id: subSizer; entries: subOpener.children }

        // main menu
        Rectangle {
            id: mainBox
            x: Math.max(Theme.windowGap,
                        Math.min(parent.width - width - Theme.windowGap,
                                 Globals.trayMenuAnchorX - width / 2))
            // the card's spaceXs below the module it belongs to
            y: Theme.barHeight + Theme.spaceXs
            width: Math.max(root.menuMin, Math.min(root.menuMax, mainSizer.implicitWidth + root.menuChrome))
            height: mainCol.implicitHeight + 2 * Theme.spaceXs
            radius: Theme.radiusRounded
            color: Theme.surfaceOverlay
            border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
            // fade plus a slideOffset drop from the bar, in at durBase and out
            // at durFast — no overshoot
            opacity: Globals.trayMenuOpen ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: Globals.trayMenuOpen ? Theme.durBase : Theme.durFast; easing.type: Theme.ease }
            }
            transform: Translate {
                y: (Globals.trayMenuOpen || Theme.reduceMotion) ? 0 : -Theme.slideOffset
                Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            }
            layer.enabled: true
            layer.effect: Elevation {}
            MouseArea { anchors.fill: parent }   // swallow clicks inside the box
            Column {
                id: mainCol
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: Theme.spaceXs + parent.border.width
                Repeater { model: opener.children; delegate: MenuRow { required property var modelData; entry: modelData } }
            }
        }

        // submenu (one level), to the right of the main box
        Rectangle {
            id: subBox
            visible: root.subEntry !== null && Globals.trayMenuOpen
            x: Math.min(parent.width - width - Theme.windowGap,
                        mainBox.x + mainBox.width + Theme.spaceXs)
            y: mainBox.y + root.subY
            width: Math.max(root.menuMin, Math.min(root.menuMax, subSizer.implicitWidth + root.menuChrome))
            height: subCol.implicitHeight + 2 * Theme.spaceXs
            radius: Theme.radiusRounded
            color: Theme.surfaceOverlay
            border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
            layer.enabled: true
            layer.effect: Elevation {}
            MouseArea { anchors.fill: parent }
            Column {
                id: subCol
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: Theme.spaceXs + parent.border.width
                Repeater { model: subOpener.children; delegate: MenuRow { required property var modelData; entry: modelData; sub: true } }
            }
        }
    }
}
