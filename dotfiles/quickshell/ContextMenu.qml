import QtQuick
import Quickshell
import Quickshell.Wayland

// ContextMenu — a themed right-click menu (design system: Menu), the shell's
// answer to "options for menus": one component for the dock, the launcher,
// the Overview, the desktop, Places and any plugin (public, docs/PLUGINS.md).
// Set `items` (or build them in the handler that opens it) and call
// openAt(item, mouse.x, mouse.y) from a right-click; the menu opens at the
// pointer on that item's screen, flips to stay on screen, closes on Esc, a
// click outside or a choice, and walks with the arrow keys.
//
//   items   [{ label, icon, shortcut, note, checked, danger, disabled,
//              submenu: [ … ], action: function () {} },
//            { separator: true }, { header: "Firefox" }]
//
//   container  surfaceOverlay, a borderWidth1 borderSubtle outline, the
//              radiusRounded corner, shadowFloat, spaceXs of padding; at
//              least 6 × controlMd + spaceS (176) and at most 10 × controlLg
//              (320) wide — sized to its longest label
//   item       controlMd tall, spaceS of side padding, radiusSecondary; the
//              label in body textPrimary, elided
//   leading    an iconMd icon in textSecondary (textPrimary on hover), or a
//              check in accentText for a checked option; when one item of a
//              list has one, every item keeps the column, so labels line up
//   trailing   a shortcut or a note in caption textMuted, or a chevron for
//              a submenu (one level, to the right; flips left at the edge)
//   header     a group label in the overline style, textMuted
//   divider    borderWidth1 borderSubtle, spaceXs above and below
//
//   hover      surfaceHover (dangerSubtle for a danger item)
//   keyboard   the same fill plus a focusWidth focusRing on the item's edge
//   danger     label and icon in danger
//   disabled   textDisabled, no hover, still reachable with the arrows
//
// Keys: Up/Down move, Right opens a submenu, Left closes it, Enter runs,
// Esc closes. The menu's window takes the keyboard OnDemand while open; a
// host that owns the keyboard itself (the Overview's exclusive focus, the
// Launcher's field) sets takesKeyboard: false and forwards its key events
// to handleKey(ev), which returns true when the menu used one.
Scope {
    id: menu
    property var items: []
    property bool takesKeyboard: true
    property string name: "menu"           // layer-shell namespace suffix: quickshell:<name>
    readonly property bool open: menu._open
    signal opened()
    signal closed()

    property bool _open: false
    property var _screen: null
    property real _px: 0
    property real _py: 0
    property int cur: -1                   // the highlighted row of the main list
    property int subOf: -1                 // the main row whose submenu is out
    property int subCur: -1                // the highlighted row of the submenu
    property bool kb: false                // the highlight came from the keyboard (focus ring)

    // openAt(item, x, y): x/y item-local (a MouseArea's mouse.x/y)
    function openAt(item, x, y) {
        var p = Shell.screenPoint(item, x, y)
        if (p) menu.openOnScreen(p.screen, p.x, p.y)
    }
    function openOnScreen(screen, sx, sy) {
        if (!menu.items || menu.items.length === 0) return
        TooltipHost.hide()
        menu._screen = screen ? screen : Shell._focusedScreen()
        menu._px = sx; menu._py = sy
        menu.cur = -1; menu.subOf = -1; menu.subCur = -1; menu.kb = false
        menu._open = true
        menu.opened()
    }
    function close() {
        if (!menu._open) return
        menu._open = false
        menu.subOf = -1
        menu.closed()
    }
    function focusable(it) { return !!it && !it.separator && it.header === undefined }
    function usable(it) { return menu.focusable(it) && !it.disabled }
    function hasSub(it) { return !!it && !!it.submenu && it.submenu.length > 0 }
    function run(it) {
        if (!menu.usable(it) || menu.hasSub(it)) return
        menu.close()
        if (typeof it.action === "function") it.action()
    }
    function openSub(i) {
        var it = menu.items[i]
        if (!menu.usable(it) || !menu.hasSub(it)) return
        menu.subOf = i; menu.subCur = -1
    }
    // the next focusable row from `from` in direction d (wraps; -1 = none)
    function step(list, from, d) {
        var n = list ? list.length : 0
        if (n === 0) return -1
        var i = from < 0 ? (d > 0 ? -1 : n) : from
        for (var k = 0; k < n; k++) {
            i = (i + d + n) % n
            if (menu.focusable(list[i])) return i
        }
        return -1
    }
    function handleKey(ev) {
        if (!menu._open) return false
        var inSub = menu.subOf >= 0
        var list = inSub ? (menu.items[menu.subOf].submenu || []) : menu.items
        var k = ev.key
        if (k === Qt.Key_Escape) { menu.close(); return true }
        if (k === Qt.Key_Down || k === Qt.Key_Up) {
            menu.kb = true
            var d = k === Qt.Key_Down ? 1 : -1
            if (inSub) menu.subCur = menu.step(list, menu.subCur, d)
            else menu.cur = menu.step(list, menu.cur, d)
            return true
        }
        if (k === Qt.Key_Right) {
            menu.kb = true
            if (!inSub && menu.hasSub(menu.items[menu.cur]) && menu.usable(menu.items[menu.cur])) {
                menu.openSub(menu.cur); menu.subCur = menu.step(menu.items[menu.cur].submenu, -1, 1)
            }
            return true
        }
        if (k === Qt.Key_Left) {
            menu.kb = true
            if (inSub) { menu.subOf = -1; menu.subCur = -1 }
            return true
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            menu.kb = true
            var it = inSub ? list[menu.subCur] : menu.items[menu.cur]
            if (!inSub && menu.hasSub(it) && menu.usable(it)) { menu.openSub(menu.cur); menu.subCur = menu.step(it.submenu, -1, 1) }
            else menu.run(it)
            return true
        }
        return false
    }
    Connections { target: Shell; function onLockedChanged() { if (Shell.locked) menu.close() } }

    // A list sizes itself to its longest row, between the card's bounds.
    // These Texts are never shown; they only carry their natural width.
    component MenuSizer: Column {
        id: sizer
        property var entries: []
        visible: false
        Repeater {
            model: sizer.entries
            delegate: Row {
                required property var modelData
                spacing: Theme.spaceS
                Text {
                    text: (modelData && !modelData.separator) ? (modelData.header !== undefined ? String(modelData.header) : String(modelData.label || "")) : ""
                    font.family: Theme.type.body.family
                    font.pixelSize: Theme.type.body.size
                }
                Text {
                    visible: text !== ""
                    text: (modelData && (modelData.shortcut || modelData.note)) ? String(modelData.shortcut || modelData.note) : ""
                    font.family: Theme.type.caption.family
                    font.pixelSize: Theme.type.caption.size
                }
            }
        }
    }

    // one row: a divider, a group header or an item
    component MenuRow: Item {
        id: row
        required property var entry
        required property int index
        property var list: null            // the MenuList this row sits in
        readonly property bool sep: !!row.entry && !!row.entry.separator
        readonly property bool head: !!row.entry && row.entry.header !== undefined
        readonly property bool usable: menu.usable(row.entry)
        readonly property bool sub: menu.hasSub(row.entry)
        readonly property bool hi: row.list !== null && row.list.hi === row.index
        readonly property bool danger: row.usable && !!row.entry.danger
        readonly property bool checked: !!row.entry && !!row.entry.checked
        width: parent ? parent.width : Theme.panelSm / 2
        height: row.sep ? Theme.borderWidth1 + 2 * Theme.spaceXs : row.head ? Theme.controlSm : Theme.controlMd

        // divider: one line, spaceXs of air above and below
        Rectangle {
            visible: row.sep
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.right: parent.right
            height: Theme.borderWidth1; color: Theme.borderSubtle
        }
        // group header: the overline style
        Text {
            visible: row.head
            anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
            anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
            anchors.verticalCenter: parent.verticalCenter
            text: row.head ? String(row.entry.header) : ""
            color: Theme.textMuted
            font.family: Theme.type.overline.family
            font.pixelSize: Theme.type.overline.size
            font.weight: Theme.type.overline.weight
            font.letterSpacing: Theme.type.overline.letterSpacing
            elide: Text.ElideRight
        }

        Rectangle {
            visible: !row.sep && !row.head
            anchors.fill: parent
            radius: Theme.radiusSecondary
            color: (row.hi && row.usable) ? (row.danger ? Theme.dangerSubtle : Theme.surfaceHover) : "transparent"
            border.color: (row.hi && menu.kb) ? Theme.focusRing : "transparent"
            border.width: Theme.focusWidth
            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }

            // leading: the icon, or the check of a checked option
            Text {
                visible: row.list !== null && row.list.lead
                anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconMd
                horizontalAlignment: Text.AlignHCenter
                text: row.checked ? Theme.icCheck : (row.entry && row.entry.icon ? String(row.entry.icon) : "")
                font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                color: row.checked ? Theme.accentText
                     : !row.usable ? Theme.textDisabled
                     : row.danger ? Theme.danger
                     : row.hi ? Theme.textPrimary : Theme.textSecondary
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spaceS + ((row.list !== null && row.list.lead) ? Theme.iconMd + Theme.spaceS : 0)
                anchors.right: parent.right
                anchors.rightMargin: Theme.spaceS + (trail.visible ? trail.width + Theme.spaceS : 0)
                anchors.verticalCenter: parent.verticalCenter
                text: row.entry && row.entry.label ? String(row.entry.label) : ""
                color: !row.usable ? Theme.textDisabled : row.danger ? Theme.danger : Theme.textPrimary
                font.family: Theme.type.body.family
                font.pixelSize: Theme.type.body.size
                font.weight: row.checked ? Theme.fontWeightMedium : Theme.type.body.weight
                elide: Text.ElideRight
            }
            // trailing: a submenu chevron, or a shortcut / note
            Text {
                id: trail
                anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                anchors.verticalCenter: parent.verticalCenter
                visible: row.sub || text !== ""
                text: row.sub ? Theme.icChevronRight
                    : (row.entry && (row.entry.shortcut || row.entry.note)) ? String(row.entry.shortcut || row.entry.note) : ""
                font.family: row.sub ? Theme.fontIcons : Theme.type.caption.family
                font.pixelSize: row.sub ? Theme.iconMd : Theme.type.caption.size
                color: !row.usable ? Theme.textDisabled : row.sub ? (row.hi ? Theme.textPrimary : Theme.textSecondary) : Theme.textMuted
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: row.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: {
                    menu.kb = false
                    if (row.list === null) return
                    if (row.list.level === 0) {
                        menu.cur = row.index
                        if (row.sub && row.usable) { subDelay.pending = row.index; subDelay.restart() }
                        else { subDelay.stop(); menu.subOf = -1 }
                    } else menu.subCur = row.index
                }
                onClicked: {
                    if (row.list !== null && row.list.level === 0 && row.sub) { subDelay.stop(); menu.openSub(row.index) }
                    else menu.run(row.entry)
                }
            }
        }
    }

    // a submenu flies out after a short pause on its row
    Timer { id: subDelay; interval: Math.max(1, Theme.durFast); property int pending: -1; onTriggered: if (menu.cur === subDelay.pending) menu.openSub(subDelay.pending) }

    // the container: one list, shared by the main menu and the submenu
    component MenuList: Rectangle {
        id: ml
        property var entries: []
        property int level: 0
        property int hi: -1
        // a leading column when any row has an icon or a check
        readonly property bool lead: {
            var e = ml.entries || []
            for (var i = 0; i < e.length; i++) if (e[i] && (e[i].icon || e[i].checked)) return true
            return false
        }
        readonly property bool trail: {
            var e = ml.entries || []
            for (var i = 0; i < e.length; i++) if (e[i] && (e[i].shortcut || e[i].note || menu.hasSub(e[i]))) return true
            return false
        }
        readonly property int minW: 6 * Theme.controlMd + Theme.spaceS
        readonly property int maxW: 10 * Theme.controlLg
        readonly property int chrome: 2 * (Theme.spaceXs + Theme.borderWidth1) + 2 * Theme.spaceS
                                      + (ml.lead ? Theme.iconMd + Theme.spaceS : 0)
                                      + (ml.trail ? Theme.iconMd + Theme.spaceS : 0)
        width: Math.max(ml.minW, Math.min(ml.maxW, sizer.implicitWidth + ml.chrome))
        height: col.implicitHeight + 2 * (Theme.spaceXs + Theme.borderWidth1)
        radius: Theme.radiusRounded
        color: Theme.surfaceOverlay
        border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
        layer.enabled: true
        layer.effect: Elevation {}
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // clicks inside stay inside
        MenuSizer { id: sizer; entries: ml.entries }
        function rowY(i) { var it = rep.itemAt(i); return it ? col.y + it.y : col.y }
        Column {
            id: col
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: Theme.spaceXs + Theme.borderWidth1
            Repeater {
                id: rep
                model: ml.entries
                delegate: MenuRow { required property var modelData; entry: modelData; list: ml }
            }
        }
    }

    PanelWindow {
        id: win
        visible: menu._open || win.held
        screen: menu._screen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: (menu._open && menu.takesKeyboard) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell:" + menu.name
        anchors { top: true; bottom: true; left: true; right: true }

        // `held` keeps the window mapped through the close fade; set on OPEN
        // so no signal-order race can unmap it early (see Overview.qml)
        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durFast + 60); onTriggered: win.held = false }
        Connections { target: menu; function onOpenChanged() {
            if (menu._open) { closeTimer.stop(); win.held = true; keys.forceActiveFocus() }
            else closeTimer.restart()
        } }

        // a press anywhere else closes — any button
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: menu.close() }
        Item { id: keys; anchors.fill: parent; focus: true; Keys.onPressed: function (ev) { if (menu.handleKey(ev)) ev.accepted = true } }

        // the main list, at the pointer; flipped when it would run off screen
        MenuList {
            id: mainBox
            entries: menu.items
            level: 0
            hi: menu.cur
            x: Math.round(Math.max(Theme.windowGap, Math.min(win.width - width - Theme.windowGap, (menu._px + width + Theme.windowGap <= win.width) ? menu._px : menu._px - width)))
            y: Math.round(Math.max(Theme.windowGap, Math.min(win.height - height - Theme.windowGap, (menu._py + height + Theme.windowGap <= win.height) ? menu._py : menu._py - height)))
            // a fade plus a slideOffset drop, in at durBase and out at durFast
            opacity: menu._open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: menu._open ? Theme.durBase : Theme.durFast; easing.type: Theme.ease } }
            transform: Translate {
                y: (menu._open || Theme.reduceMotion) ? 0 : -Theme.slideOffset
                Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            }
        }
        // the submenu (one level), beside its row, to the right unless there is no room
        MenuList {
            id: subBox
            visible: menu._open && menu.subOf >= 0
            entries: (menu.subOf >= 0 && menu.items[menu.subOf]) ? (menu.items[menu.subOf].submenu || []) : []
            level: 1
            hi: menu.subCur
            x: Math.round((mainBox.x + mainBox.width + Theme.spaceXs + width + Theme.windowGap <= win.width)
                          ? mainBox.x + mainBox.width + Theme.spaceXs
                          : Math.max(Theme.windowGap, mainBox.x - Theme.spaceXs - width))
            y: Math.round(Math.max(Theme.windowGap, Math.min(win.height - height - Theme.windowGap,
                          mainBox.y + mainBox.rowY(menu.subOf) - (Theme.spaceXs + Theme.borderWidth1))))
        }
    }
}
