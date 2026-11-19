import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

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
//   leading    an iconMd column every row keeps, so labels line up: the
//              item's own icon (textSecondary, textPrimary on hover), or its
//              state — a toggle shows square / check-square, an option
//              circle / circle-dot, the on state in accentText (a bare tick
//              on radios and nothing on an off toggle read wrong)
//   submenu    an iconMd chevron at the trailing edge; the submenu flies out
//              to the right of its row, to the LEFT when it would leave the
//              screen, and never below the bottom edge; any depth
//   divider    a borderWidth1 borderSubtle line with spaceXs above and below
//
//   hover     surfaceHover · disabled textDisabled, no hover
//
// Submenus open on hover after a short pause and close after a grace period
// (2 × durBase), so the pointer can cross the parent's other rows on its
// way to the flyout. Esc closes the whole menu; so does a click outside.
// DBusMenu items carry no shortcuts or tones, so the card's Kbd and danger
// forms have nothing to render here.
Scope {
    id: root
    function glyph(c) { return String.fromCodePoint(c) }

    // ── the open submenus, outermost first: { entry, px, pw, ry } — the
    //    QsMenuEntry, its parent box's x and width, and the row's y in the
    //    window — so each level can place itself beside the one before ──
    property var chain: []
    // a pending open (entry) or close (null) for a level, applied after the
    // hover grace so crossing rows on the way to a flyout does not close it
    property int pendLevel: -1
    property var pendEntry: null
    property var pendGeom: null
    Timer { id: grace; onTriggered: root.applyPending() }
    function schedule(level, entry, geom, ms) {
        root.pendLevel = level; root.pendEntry = entry; root.pendGeom = geom
        grace.interval = Math.max(1, ms); grace.restart()
    }
    function cancelPending() { grace.stop(); root.pendLevel = -1; root.pendEntry = null }
    function applyPending() {
        if (root.pendLevel < 0) return
        root.setLevel(root.pendLevel, root.pendEntry, root.pendGeom)
        root.pendLevel = -1; root.pendEntry = null
    }
    // open `entry`'s flyout as level `level` (null = close from there on)
    function setLevel(level, entry, g) {
        var c = root.chain.slice(0, level)
        if (entry) c.push({ entry: entry, px: g.px, pw: g.pw, ry: g.ry, dir: g.dir })
        root.chain = c
    }
    // a row at `level` (0 = the main menu) is pointed at
    function rowHovered(level, entry, geom) {
        if (entry.hasChildren) {
            // already open at this level: keep it (and drop any pending close)
            if (root.chain.length > level && root.chain[level].entry === entry) { root.cancelPending(); return }
            root.schedule(level, entry, geom, Theme.durFast)
        } else if (root.chain.length > level) {
            root.schedule(level, null, null, 2 * Theme.durBase)
        } else root.cancelPending()
    }
    // the pointer reached a flyout: whatever was about to close it, forget
    function boxEntered(level) { if (root.pendLevel >= 0 && root.pendLevel < level) root.cancelPending() }

    readonly property int menuMin: 6 * Theme.controlMd + Theme.spaceS
    readonly property int menuMax: 10 * Theme.controlLg
    // the leading column, both gaps and the trailing chevron
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

    // a single menu row, shared by every level
    component MenuRow: Item {
        id: row
        required property var entry
        property int level: 0
        property Item menuBox: null             // the MenuBox this row sits in
        readonly property bool separator: row.entry !== null && row.entry.isSeparator
        readonly property bool usable: row.entry !== null && row.entry.enabled && !row.separator
        readonly property bool toggle: row.entry !== null && row.entry.buttonType === QsMenuButtonType.CheckBox
        readonly property bool option: row.entry !== null && row.entry.buttonType === QsMenuButtonType.RadioButton
        readonly property bool on: row.entry !== null && row.entry.checkState === Qt.Checked
        readonly property bool hasIcon: row.entry !== null && String(row.entry.icon || "") !== ""
        readonly property bool openHere: root.chain.length > row.level && root.chain[row.level].entry === row.entry
        width: parent ? parent.width : Theme.panelSm / 2
        height: row.separator ? Theme.borderWidth1 + 2 * Theme.spaceXs : Theme.controlMd
        function geom() {
            var p = row.mapToItem(null, 0, 0)
            var b = row.menuBox
            return { px: b ? b.x : 0, pw: b ? b.width : 0, ry: p.y, dir: b ? b.dir : 1 }
        }

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
            color: ((rowMa.containsMouse || row.openHere) && row.usable) ? Theme.surfaceHover : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }

            // the leading column — kept whether or not the item fills it, so
            // every label starts at the same x: the toggle / option state,
            // else the item's own icon
            Item {
                id: lead
                anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconMd; height: Theme.iconMd
                Text {
                    anchors.centerIn: parent
                    visible: row.toggle || row.option
                    text: row.toggle ? (row.on ? Theme.icCheckboxOn : Theme.icCheckbox)
                                     : (row.on ? Theme.icRadioOn : Theme.icRadio)
                    font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                    color: !row.usable ? Theme.textDisabled : row.on ? Theme.accentText
                         : rowMa.containsMouse ? Theme.textPrimary : Theme.textSecondary
                }
                Image {
                    anchors.fill: parent
                    visible: !(row.toggle || row.option) && row.hasIcon
                    source: visible ? row.entry.icon : ""
                    sourceSize.width: 2 * Theme.iconMd; sourceSize.height: 2 * Theme.iconMd
                    mipmap: true
                }
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
                font.weight: row.on ? Theme.fontWeightMedium : Theme.type.body.weight
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
                onEntered: root.rowHovered(row.level, row.entry, row.geom())
                onClicked: {
                    if (!row.entry) return
                    if (row.entry.hasChildren) {   // a click opens the flyout at once
                        root.cancelPending()
                        root.setLevel(row.level, row.entry, row.geom())
                        return
                    }
                    row.entry.triggered()
                    Globals.trayMenuOpen = false
                }
            }
        }
    }

    // one menu box: the main menu (level 0) or a flyout
    component MenuBox: Rectangle {
        id: box
        property var menuHandle: null
        property int level: 0
        property int dir: 1                     // which side of its parent it opened on (+1 right, -1 left)
        QsMenuOpener { id: op; menu: box.menuHandle }
        MenuSizer { id: sizer; entries: op.children }
        width: Math.max(root.menuMin, Math.min(root.menuMax, sizer.implicitWidth + root.menuChrome))
        height: col.implicitHeight + 2 * Theme.spaceXs
        radius: Theme.radiusRounded
        color: Theme.surfaceOverlay
        border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
        layer.enabled: true
        layer.effect: Elevation {}
        MouseArea { anchors.fill: parent }   // swallow clicks inside the box
        HoverHandler { onHoveredChanged: if (hovered) root.boxEntered(box.level) }
        Column {
            id: col
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: Theme.spaceXs + parent.border.width
            Repeater {
                model: op.children
                delegate: MenuRow { required property var modelData; entry: modelData; level: box.level; menuBox: box }
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
        // the keyboard while open, so Esc closes it
        WlrLayershell.keyboardFocus: Globals.trayMenuOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell:traymenu"
        anchors { top: true; bottom: true; left: true; right: true }

        // `held` keeps the window mapped through the close animation; set on
        // OPEN so no signal-order race can unmap it early (see Overview.qml)
        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durBase + 60); onTriggered: win.held = false }
        Connections { target: Globals; function onTrayMenuOpenChanged() {
            root.cancelPending(); root.chain = []
            if (Globals.trayMenuOpen) { closeTimer.stop(); win.held = true; root.openScreen = root.focusedScreen(); keys.forceActiveFocus() }
            else closeTimer.restart()
        } }

        MouseArea { anchors.fill: parent; onClicked: Globals.trayMenuOpen = false }
        Item { id: keys; focus: true; Keys.onEscapePressed: Globals.trayMenuOpen = false }

        // main menu
        MenuBox {
            id: mainBox
            level: 0
            menuHandle: Globals.trayMenuHandle
            x: Math.max(Theme.windowGap,
                        Math.min(parent.width - width - Theme.windowGap,
                                 Globals.trayMenuAnchorX - width / 2))
            // the card's spaceXs below the module it belongs to
            y: Theme.barHeight + Theme.spaceXs
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
        }

        // the flyouts, one per open level: beside the box they came from —
        // to its right, or to its left at the screen's right edge — with the
        // first row level with the row that opened it, kept on screen at
        // the bottom
        Repeater {
            model: root.chain
            delegate: MenuBox {
                id: sub
                required property var modelData
                required property int index
                level: index + 1
                menuHandle: modelData.entry
                visible: Globals.trayMenuOpen
                // keep going the way the chain already went (a flyout that
                // flipped left would otherwise fold its children back over
                // the menu it came from); the other side only when that one
                // runs off the screen
                readonly property bool fitsRight: modelData.px + modelData.pw + Theme.spaceXs + width <= win.width - Theme.windowGap
                readonly property bool fitsLeft: modelData.px - Theme.spaceXs - width >= Theme.windowGap
                dir: modelData.dir < 0 ? (fitsLeft ? -1 : 1) : (fitsRight ? 1 : -1)
                x: dir > 0 ? modelData.px + modelData.pw + Theme.spaceXs
                           : Math.max(Theme.windowGap, modelData.px - Theme.spaceXs - width)
                // never over the bar, never past the bottom edge
                y: Math.max(mainBox.y,
                            Math.min(win.height - height - Theme.windowGap,
                                     modelData.ry - Theme.spaceXs - Theme.borderWidth1))
            }
        }
    }
}
