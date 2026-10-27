import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs

// ewe.switcher — the Alt+Tab window switcher (design system: Window
// switcher). Alt+Tab shows the open windows as their app icons, most
// recently used first, with the previous window selected; every Tab moves
// on, Shift+Tab back; letting go of Alt switches, Esc cancels. Classic.
//
// Which windows: the plugin's `scope` setting — this workspace (the
// default), this display (every workspace of the display you are on), or
// everywhere. A window on another workspace carries that number on its
// icon; a minimized window (the shell's hidden "minimized" workspace,
// Super+Z) is listed too and comes back onto the workspace in view when
// picked, the way the dock brings it back.
//
// No process per press: the manifest binds Alt+Tab / Alt+Shift+Tab to the
// global shortcuts `ewe.switcher:next|prev` (one step per `pressed`), and
// the Alt keys' RELEASE to `ewe.switcher:commit` as a `transparent` bind.
// Hyprland shadows an ordinary release bind on a modifier the moment another
// bind fires during the hold — Alt+Tab is one — and never a transparent one.
// The panel also hears the Alt release itself (it holds the keyboard while
// open), so a tap that lets go before the panel has the keyboard still
// lands: whichever arrives first commits, the other finds it closed.
//
//     qs ipc call ewe.switcher next | prev | commit | cancel | toggle | isOpen
Scope {
    id: root
    property var settings: ({})            // { scope: "workspace" | "display" | "everywhere" }
    readonly property string scope: {
        var s = root.settings ? root.settings.scope : ""
        return (s === "display" || s === "everywhere") ? s : "workspace"
    }
    readonly property string scopeLabel: root.scope === "display" ? "This display"
                                       : root.scope === "everywhere" ? "Everywhere" : "This workspace"

    property bool open: false
    property var items: []                 // the windows shown, most recent first — a snapshot taken on open
    property int sel: 0
    readonly property var cur: (root.sel >= 0 && root.sel < root.items.length) ? root.items[root.sel] : null
    // addresses in the order they were focused, newest first (activewindowv2)
    property var mru: []

    // ── windows ─────────────────────────────────────────────────────────────
    function norm(a) {
        a = String(a || "")
        if (a === "" || a === ",") return ""
        return a.indexOf("0x") === 0 ? a : "0x" + a   // Hyprland events omit the 0x
    }
    // a toplevel may be gone by the time a late binding asks (the window
    // closed under the open switcher): every reader tolerates that
    function addrOf(t) {
        try { return root.norm(t ? (t.address || (t.lastIpcObject && t.lastIpcObject.address)) : "") } catch (e) { return "" }
    }
    function classOf(t) {
        try {
            var o = t && t.lastIpcObject ? t.lastIpcObject : null
            var c = o ? (o.class || o.initialClass || "") : ""
            if (!c && t && t.wayland && t.wayland.appId) c = t.wayland.appId
            return c
        } catch (e) { return "" }
    }
    function entryOf(t) {
        var c = root.classOf(t)
        return c === "" ? null : DesktopEntries.heuristicLookup(c)
    }
    function iconFor(t) {
        var c = root.classOf(t)
        if (c === "") return Quickshell.iconPath("application-x-executable")
        var e = root.entryOf(t)
        return Quickshell.iconPath(e && e.icon ? e.icon : c, "application-x-executable")
    }
    function appOf(t) {
        var e = root.entryOf(t)
        return (e && e.name) ? e.name : (root.classOf(t) || "Window")
    }
    function titleOf(t) {
        try { return (t && t.title) ? t.title : root.appOf(t) } catch (e) { return "" }
    }
    function wsOf(t) { try { return t && t.workspace ? t.workspace : null } catch (e) { return null } }
    function isMinimizedWs(name) { return name === "special:minimized" || name === "special:pen" }
    // the workspace number to show on a window that is elsewhere, 0 here
    function wsNumberOf(t) {
        var ws = root.wsOf(t)
        if (!ws || ws.id < 1) return 0
        var f = Hyprland.focusedWorkspace
        return (f && ws.id === f.id) ? 0 : Shell.workspaceNumber(ws.id)
    }
    // where the window is, for the line under the icons
    function whereOf(t) {
        var ws = root.wsOf(t)
        if (ws && root.isMinimizedWs(String(ws.name))) return "Minimized"
        var n = root.wsNumberOf(t)
        return n > 0 ? "Workspace " + n : ""
    }

    // the windows in scope, most recently used first
    function collect() {
        var tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
        var fm = Hyprland.focusedMonitor, fws = Hyprland.focusedWorkspace
        var out = []
        for (var i = 0; i < tls.length; i++) {
            var t = tls[i]
            if (!t) continue
            var o = t.lastIpcObject
            if (o && o.mapped === false) continue
            var ws = t.workspace
            var minimized = !!(ws && root.isMinimizedWs(String(ws.name)))
            if (ws && ws.id < 1 && !minimized) continue          // a scratchpad: not a window to switch to
            if (!minimized) {
                if (root.scope === "workspace" && (!ws || !fws || ws.id !== fws.id)) continue
                if (root.scope === "display" && (!t.monitor || !fm || t.monitor.name !== fm.name)) continue
            }
            out.push(t)
        }
        var rank = function (t) {
            var i = root.mru.indexOf(root.addrOf(t))
            if (i >= 0) return i
            // never focused since the shell started: Hyprland's own order (0 = focused last)
            var o = t.lastIpcObject
            return 100000 + ((o && o.focusHistoryID !== undefined) ? o.focusHistoryID : 100000)
        }
        out.sort(function (a, b) { return rank(a) - rank(b) })
        return out
    }

    // ── actions ─────────────────────────────────────────────────────────────
    function step(d) {
        if (Shell.locked) return
        if (!root.open) {
            var list = root.collect()
            if (list.length === 0) return
            root.items = list
            // the first step lands on the PREVIOUS window: Alt+Tab, let go,
            // and you are back where you were
            root.sel = list.length > 1 ? (d > 0 ? 1 : list.length - 1) : 0
            root.open = true
            return
        }
        var n = root.items.length
        if (n > 0) root.sel = ((root.sel + d) % n + n) % n
    }
    function commit() {
        if (!root.open) return
        var t = root.cur
        root.open = false
        if (t) root.focusWindow(t)
    }
    function cancel() { root.open = false }
    function focusWindow(t) {
        var a = root.addrOf(t)
        if (a === "") { try { if (t.wayland) t.wayland.activate() } catch (e) {} return }
        var ws = root.wsOf(t)
        if (ws && root.isMinimizedWs(String(ws.name))) {
            // out of the Pen onto the workspace in view (what the dock does)
            var f = Hyprland.focusedWorkspace
            if (f) Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + f.id + ', window = "address:' + a + '", follow = false })')
        }
        // by ADDRESS, so Hyprland switches to the window's workspace (and a
        // hidden tab of a group becomes the one shown)
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + a + '" })')
    }

    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name === "activewindowv2") {
                var a = root.norm(ev.data)
                if (a === "") return
                var keep = root.mru.filter(function (x) { return x !== a })
                keep.unshift(a)
                if (keep.length > 64) keep.length = 64
                root.mru = keep
            } else if (ev.name === "closewindow" && root.open) {
                // a window that closes under the open switcher leaves the row
                var c = root.norm(ev.data)
                var left = root.items.filter(function (t) { return root.addrOf(t) !== c })
                if (left.length === 0) { root.cancel(); return }
                root.items = left
                root.sel = Math.min(root.sel, left.length - 1)
            }
        }
    }
    // the lock screen, or the Overview opening: nothing to switch over
    Connections {
        target: Shell
        function onLockedChanged() { if (Shell.locked) root.cancel() }
        function onOverviewOpenChanged() { if (Shell.overviewOpen) root.cancel() }
    }

    // the manifest's binds, over the global-shortcuts protocol (no `qs ipc`
    // spawn per Tab). A release bind delivers `released` only; `pressed` is
    // handled too, should someone bind `commit` as a plain press
    GlobalShortcut { appid: "ewe.switcher"; name: "next"; description: "Window switcher: next window"; onPressed: root.step(1) }
    GlobalShortcut { appid: "ewe.switcher"; name: "prev"; description: "Window switcher: previous window"; onPressed: root.step(-1) }
    GlobalShortcut { appid: "ewe.switcher"; name: "commit"; description: "Window switcher: switch to the selected window"; onPressed: root.commit(); onReleased: root.commit() }

    IpcHandler {
        target: "ewe.switcher"
        function next(): void { root.step(1) }
        function prev(): void { root.step(-1) }
        function commit(): void { root.commit() }
        function cancel(): void { root.cancel() }
        function toggle(): void { if (root.open) root.cancel(); else root.step(1) }
        function hide(): void { root.cancel() }
        function isOpen(): bool { return root.open }
    }

    // ── the panel ───────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: root.open || win.held
        // on the display you are on
        screen: {
            var s = Quickshell.screens, fm = Hyprland.focusedMonitor
            if (fm) for (var i = 0; i < s.length; i++) if (s[i].name === fm.name) return s[i]
            return s.length > 0 ? s[0] : null
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:ewe.switcher"
        WlrLayershell.layer: WlrLayer.Overlay
        // OnDemand, not Exclusive: the panel must hear the Alt release and
        // the arrows (Hyprland hands an on-demand overlay the keyboard as it
        // maps), and Hyprland REFUSES to focus a window while a layer surface
        // holds the keyboard exclusively — the commit's focus would be lost
        // in the race with the panel letting go
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        // fading out: clicks fall through to the desktop
        mask: root.open ? null : noInput
        Region { id: noInput }

        // mapped through the fade-out; set on OPEN so no signal order can
        // unmap it early (the Overview's idiom)
        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durFast + 20); onTriggered: win.held = false }
        Connections {
            target: root
            function onOpenChanged() {
                if (root.open) { closeTimer.stop(); win.held = true; keys.forceActiveFocus() }
                else closeTimer.restart()
            }
        }

        // a click beside the panel: cancel
        MouseArea { anchors.fill: parent; onClicked: root.cancel() }

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: function (ev) {
                if (ev.key === Qt.Key_Escape) { root.cancel(); ev.accepted = true }
                else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { root.commit(); ev.accepted = true }
                else if (ev.key === Qt.Key_Right || ev.key === Qt.Key_Down || ev.key === Qt.Key_Tab) { root.step(1); ev.accepted = true }
                else if (ev.key === Qt.Key_Left || ev.key === Qt.Key_Up || ev.key === Qt.Key_Backtab) { root.step(-1); ev.accepted = true }
            }
            // Alt let go: switch (the transparent release bind says the same
            // through `commit`; whichever comes second finds it closed)
            Keys.onReleased: function (ev) {
                if (ev.key === Qt.Key_Alt && !ev.isAutoRepeat) { root.commit(); ev.accepted = true }
            }

            // Window switcher card: surface-raised, 1px border-subtle,
            // rounded + space-xs, shadow-float, 12px padding, centred
            RectangularShadow {
                anchors.fill: card
                radius: card.radius
                offset.x: Theme.shadowFloat.x; offset.y: Theme.shadowFloat.y
                blur: Theme.shadowFloat.blur
                color: Theme.shadowFloat.color
                opacity: card.opacity
                scale: card.scale
            }
            Rectangle {
                id: card
                anchors.centerIn: parent
                readonly property int pad: Theme.spaceS + Theme.spaceXs
                // an icon cell: the 48px icon with space-md around it
                readonly property int cell: Theme.icon3xl + 2 * Theme.spaceMd
                // up to eight a row, fewer on a narrow display; more wrap
                readonly property int perRow: Math.max(1, Math.min(root.items.length, 8,
                    Math.floor((win.width - 2 * Theme.spaceXl - 2 * card.pad + Theme.spaceS) / (card.cell + Theme.spaceS))))
                width: body.width + 2 * card.pad
                height: body.height + 2 * card.pad
                radius: Theme.radiusRounded + Theme.spaceXs
                color: Theme.surfaceRaised
                border.color: Theme.borderSubtle
                border.width: Theme.borderWidth1
                opacity: root.open ? 1 : 0
                scale: root.open ? 1 : 0.96
                Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : Theme.durFast; easing.type: Theme.easeFast } }
                Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.durFast; easing.type: Theme.ease } }
                Accessible.role: Accessible.List
                Accessible.name: "Window switcher, " + root.scopeLabel

                Column {
                    id: body
                    x: card.pad; y: card.pad
                    spacing: Theme.spaceS

                    Grid {
                        id: grid
                        columns: card.perRow
                        spacing: Theme.spaceS
                        Repeater {
                            model: root.items
                            delegate: Item {
                                id: cellItem
                                required property var modelData
                                required property int index
                                width: card.cell; height: card.cell
                                readonly property bool seld: root.sel === index
                                readonly property int wsN: root.wsNumberOf(modelData)

                                // selected: surface-hover behind, a 2px accent ring
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.radiusPrimary
                                    color: (cellItem.seld || cellMa.containsMouse) ? Theme.surfaceHover : "transparent"
                                    border.color: cellItem.seld ? Theme.accent : "transparent"
                                    border.width: Theme.borderWidth2
                                }
                                Image {
                                    anchors.centerIn: parent
                                    width: Theme.icon3xl; height: Theme.icon3xl
                                    sourceSize.width: 2 * Theme.icon3xl; sourceSize.height: 2 * Theme.icon3xl
                                    mipmap: true
                                    source: root.iconFor(cellItem.modelData)
                                }
                                // elsewhere: the workspace number on the icon's corner
                                Badge {
                                    visible: cellItem.wsN > 0
                                    anchors.top: parent.top; anchors.right: parent.right
                                    anchors.margins: Theme.spaceS
                                    count: cellItem.wsN
                                    tone: "neutral"; solid: false
                                    ring: true; ringColor: Theme.surfaceRaised
                                }
                                MouseArea {
                                    id: cellMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onContainsMouseChanged: if (containsMouse) root.sel = cellItem.index
                                    onClicked: { root.sel = cellItem.index; root.commit() }
                                }
                                Accessible.role: Accessible.ListItem
                                Accessible.name: root.appOf(cellItem.modelData) + ", " + root.titleOf(cellItem.modelData)
                                                 + (root.whereOf(cellItem.modelData) !== "" ? ", " + root.whereOf(cellItem.modelData) : "")
                                Accessible.selected: cellItem.seld
                            }
                        }
                    }

                    // the selected window: its title, then the app and where it is
                    Column {
                        width: grid.width
                        spacing: Theme.spaceXxs
                        TextStrong {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                            text: root.cur ? root.titleOf(root.cur) : ""
                        }
                        TextCaption {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: {
                                if (!root.cur) return ""
                                var w = root.whereOf(root.cur)
                                return root.appOf(root.cur) + (w !== "" ? " · " + w : "")
                            }
                        }
                    }

                    // the hints
                    TextCaption {
                        width: grid.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.scopeLabel + " · Tab next · Shift+Tab previous · Esc cancel"
                    }
                }
            }
        }
    }
}
