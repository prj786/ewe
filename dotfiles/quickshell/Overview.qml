import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Io

// Overview — GNOME-style activities view (redesigned per the user's mockup).
//
// Opened-apps state:
//   · search pill top-centre (the workspace id lives in the topbar),
//   · a row of workspace PILLS under the search (every active desktop + one
//     empty trailing one; the current desktop is accented). Click a pill to
//     switch desktop; DRAG a window card onto a pill to move it there.
//   · the CURRENT desktop's windows as large cards (live preview, app-icon
//     badge top-right, ✕ to close, click to focus).
// Search state (anything typed):
//   · "Apps" — launcher-style rows, click/Enter launches,
//   · "Windows" — same rows for every matching open window on any desktop;
//     click navigates to it, ✕ closes it.
// Animation: GNOME-like zoom — the whole stage zooms out into view on open
// and zooms back in on close (scale + fade only, driven by Theme.dur*).
//
// Trigger: `qs ipc call overview toggle` (Super tap / 3-finger swipe up).
Scope {
    id: root

    property string query: ""
    property int sel: 0

    function g(c) { return String.fromCodePoint(c) }

    readonly property var allWins: Hyprland.toplevels ? Hyprland.toplevels.values : []
    readonly property int focusedWs: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    readonly property bool searching: root.query.trim() !== ""

    function classOf(tl) {
        var o = tl && tl.lastIpcObject ? tl.lastIpcObject : null
        var c = o ? (o.class || o.initialClass || "") : ""
        // lastIpcObject can lag behind the IPC — the Wayland appId is always there
        if (!c && tl && tl.wayland && tl.wayland.appId) c = tl.wayland.appId
        return c
    }
    function titleOf(tl) { return (tl && tl.title) ? tl.title : (root.classOf(tl) || "Window") }
    function wsOf(tl) { return (tl && tl.workspace) ? tl.workspace.id : -1 }
    function iconFor(tl) {
        var cls = root.classOf(tl)
        if (cls === "") return Quickshell.iconPath("application-x-executable")
        var e = DesktopEntries.heuristicLookup(cls)
        return Quickshell.iconPath(e && e.icon ? e.icon : cls, "application-x-executable")
    }

    // ── workspace pills: 1 … max(used, focused), + one trailing empty, cap 10 ──
    readonly property var wsPills: buildPills()
    function buildPills() {
        var byWs = {}, maxWs = 1
        for (var i = 0; i < root.allWins.length; i++) {
            var w = root.wsOf(root.allWins[i])
            if (w < 1) continue
            if (w > maxWs) maxWs = w
            byWs[w] = (byWs[w] || 0) + 1
        }
        if (root.focusedWs > maxWs) maxWs = root.focusedWs
        // one "not active" trailing desktop — but never stack empties
        var top = Math.min((byWs[maxWs] || 0) > 0 || maxWs === root.focusedWs ? maxWs + 1 : maxWs, 10)
        var out = []
        for (var ws = 1; ws <= top; ws++) out.push({ ws: ws, count: byWs[ws] || 0 })
        return out
    }

    // ── current desktop's windows (opened-apps state) ──
    readonly property var curWins: currentWins()
    function currentWins() {
        var out = []
        for (var i = 0; i < root.allWins.length; i++)
            if (root.wsOf(root.allWins[i]) === root.focusedWs) out.push(root.allWins[i])
        return out
    }

    // ── search: apps (like the launcher) + open windows on any desktop ──
    readonly property var appResults: suggestApps()
    function suggestApps() {
        var q = root.query.trim().toLowerCase()
        if (q === "") return []
        var all = DesktopEntries.applications ? DesktopEntries.applications.values : []
        var pre = [], mid = []
        for (var i = 0; i < all.length; i++) {
            var a = all[i]
            if (!a || a.noDisplay) continue
            var name = (a.name || "").toLowerCase()
            var hay = name + " " + (a.genericName || "").toLowerCase() + " " + (a.comment || "").toLowerCase()
            if (hay.indexOf(q) < 0) continue
            if (name.indexOf(q) === 0) pre.push(a); else mid.push(a)   // name-prefix first
        }
        return pre.concat(mid).slice(0, 6)
    }
    readonly property var winResults: matchWins()
    function matchWins() {
        var q = root.query.trim().toLowerCase()
        if (q === "") return []
        var out = []
        for (var i = 0; i < root.allWins.length; i++) {
            var tl = root.allWins[i]
            if (root.wsOf(tl) < 1) continue
            if ((root.titleOf(tl) + " " + root.classOf(tl)).toLowerCase().indexOf(q) >= 0) out.push(tl)
        }
        return out
    }
    function appIcon(a) { return Quickshell.iconPath(a && a.icon ? a.icon : "", "application-x-executable") }

    // keyboard-nav list: search → apps then windows; otherwise the current desktop's cards
    readonly property int navCount: root.searching ? root.appResults.length + root.winResults.length : root.curWins.length
    function activateSel() {
        if (root.searching) {
            if (root.sel < root.appResults.length) root.launchApp(root.appResults[root.sel])
            else if (root.winResults.length) root.jump(root.winResults[Math.min(root.sel - root.appResults.length, root.winResults.length - 1)])
        } else if (root.curWins.length) {
            root.jump(root.curWins[Math.min(root.sel, root.curWins.length - 1)])
        }
    }

    // ── actions ──
    function launchApp(a) { if (a) a.execute(); root.close() }
    function jump(tl) {
        if (tl && tl.wayland) tl.wayland.activate()
        else if (tl && tl.address) Hyprland.dispatch("focuswindow address:" + tl.address)
        root.close()
    }
    function addrOf(tl) {
        var a = (tl && tl.address) ? String(tl.address) : ""
        if (a !== "" && a.indexOf("0x") !== 0) a = "0x" + a   // Hyprland events sometimes omit the 0x
        return a
    }
    function moveWin(tl, ws) {
        var a = root.addrOf(tl)
        if (a === "" || root.wsOf(tl) === ws) return
        Hyprland.dispatch('hl.dsp.window.move({workspace=' + ws + ', window="address:' + a + '", follow=false})')
    }
    function killWin(tl) {
        var a = root.addrOf(tl)
        if (a !== "") Hyprland.dispatch('hl.dsp.window.close({window="address:' + a + '"})')
    }
    function gotoWs(ws) { if (ws !== root.focusedWs) Hyprland.dispatch("hl.dsp.focus({workspace=" + ws + "})") }
    function close() { Globals.overviewOpen = false }

    onQueryChanged: root.sel = 0
    onNavCountChanged: if (root.sel >= navCount) root.sel = Math.max(0, navCount - 1)

    IpcHandler {
        target: "overview"
        function toggle(): void { Globals.overviewOpen = !Globals.overviewOpen }
        function show(): void { Globals.overviewOpen = true }
        function hide(): void { Globals.overviewOpen = false }
    }

    Timer { id: closeTimer; interval: Math.max(1, Theme.durSlow) }
    Connections { target: Globals; function onOverviewOpenChanged() { if (!Globals.overviewOpen) closeTimer.restart() } }

    PanelWindow {
        id: win
        visible: Globals.overviewOpen || closeTimer.running
        // open on whichever monitor is focused (dual-monitor: follow the active screen)
        screen: {
            var fm = Hyprland.focusedMonitor
            if (!fm) return null
            var ss = Quickshell.screens
            for (var i = 0; i < ss.length; i++) if (ss[i].name === fm.name) return ss[i]
            return null
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore                 // span the whole screen, OVER the top bar
        WlrLayershell.layer: WlrLayer.Overlay                // above the bar (Top layer)
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell:overview"
        anchors { top: true; bottom: true; left: true; right: true }

        onVisibleChanged: if (visible) Qt.callLater(function () { search.text = ""; search.forceActiveFocus() })
        Connections {
            target: Globals
            function onOverviewOpenChanged() { if (Globals.overviewOpen) search.forceActiveFocus() }
        }

        // dim scrim; click empty space to dismiss
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.88)
            opacity: Globals.overviewOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durSlow; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent; onClicked: root.close() }
        }

        // ── the stage: GNOME-like zoom out on open, zoom back in on close ──
        Item {
            id: stage
            anchors.fill: parent
            opacity: Globals.overviewOpen ? 1 : 0
            scale: Globals.overviewOpen ? 1 : 1.10
            transformOrigin: Item.Center
            Behavior on opacity { NumberAnimation { duration: Theme.durSlow; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: Theme.durSlow; easing.type: Easing.OutCubic } }

            readonly property real monAR: (win.screen && win.screen.height > 0) ? (win.screen.width / win.screen.height) : 1.6

            // ── search pill (top-centre) ──
            Rectangle {
                id: searchBox
                anchors.horizontalCenter: parent.horizontalCenter
                y: 36
                width: 540; height: 48
                radius: height / 2
                color: Theme.elevated
                border.color: Theme.accent; border.width: 2
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 20; anchors.rightMargin: 20
                    spacing: 12
                    Text { anchors.verticalCenter: parent.verticalCenter; text: Theme.icSearch; font.family: Theme.fontMono; font.pixelSize: 17; color: Theme.fgDim }
                    TextInput {
                        id: search
                        width: parent.width - 40
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge
                        selectionColor: Theme.accent; selectByMouse: true; clip: true
                        onTextChanged: root.query = text
                        Text { visible: search.text.length === 0; anchors.verticalCenter: parent.verticalCenter; text: "Search apps and open windows…"; color: Theme.fgDim; font: search.font }
                        Keys.onPressed: function (ev) {
                            if (ev.key === Qt.Key_Escape) { root.close(); ev.accepted = true }
                            else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { root.activateSel(); ev.accepted = true }
                            else if (ev.key === Qt.Key_Left || ev.key === Qt.Key_Up) { root.sel = Math.max(0, root.sel - 1); ev.accepted = true }
                            else if (ev.key === Qt.Key_Right || ev.key === Qt.Key_Down) { root.sel = Math.min(root.navCount - 1, root.sel + 1); ev.accepted = true }
                        }
                    }
                }
            }

            // ══ OPENED-APPS STATE ══════════════════════════════════════════════
            // workspace pills — active desktops + one empty; current is accented
            Row {
                id: pillRow
                visible: !root.searching
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: searchBox.bottom; anchors.topMargin: 26
                spacing: 14
                Repeater {
                    model: root.wsPills
                    delegate: Rectangle {
                        id: pill
                        required property var modelData
                        readonly property int wsId: modelData.ws
                        readonly property bool current: wsId === root.focusedWs
                        width: 84; height: 52
                        radius: 12
                        color: pillDrop.containsDrag ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                             : current ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                             : Theme.elevated
                        border.color: (current || pillDrop.containsDrag) ? Theme.accent : Theme.stroke
                        border.width: current || pillDrop.containsDrag ? 2 : 1
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                        DropArea { id: pillDrop; anchors.fill: parent; keys: ["overview-window"] }
                        Text {
                            anchors.centerIn: parent
                            text: pill.wsId
                            color: pill.current ? Theme.accent : Theme.fgSecondary
                            font.family: Theme.fontDisplay; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold
                        }
                        // tiny window-count dots along the pill's bottom
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 7
                            spacing: 3
                            Repeater {
                                model: Math.min(pill.modelData.count, 5)
                                delegate: Rectangle { width: 4; height: 4; radius: 2; color: pill.current ? Theme.accent : Theme.fgDim }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.gotoWs(pill.wsId)
                        }
                    }
                }
            }

            // the current desktop's windows as large cards
            Flickable {
                id: cardArea
                visible: !root.searching
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: pillRow.bottom; anchors.topMargin: 30
                anchors.bottom: parent.bottom; anchors.bottomMargin: 32
                clip: true
                contentWidth: width
                contentHeight: Math.max(height, cardFlow.implicitHeight)
                boundsBehavior: Flickable.StopAtBounds
                // card size scales down as the desktop gets busier
                readonly property real cardH: Math.round(height * (root.curWins.length <= 2 ? 0.52 : root.curWins.length <= 6 ? 0.40 : 0.30))
                readonly property real cardW: Math.round(cardH * stage.monAR)

                Flow {
                    id: cardFlow
                    width: Math.min(cardArea.width - 80, (cardArea.cardW + 26) * Math.min(root.curWins.length, 3))
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.max(0, (cardArea.height - implicitHeight) / 2)
                    spacing: 26

                    Repeater {
                        model: root.curWins
                        delegate: MouseArea {
                            id: dragArea
                            required property var modelData
                            required property int index
                            readonly property bool seld: index === root.sel
                            width: cardArea.cardW; height: cardArea.cardH
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            drag.target: cardContent
                            drag.smoothed: false
                            property bool didDrag: false
                            onPressed: didDrag = false
                            onPositionChanged: { if (drag.active) didDrag = true; else root.sel = index }
                            onClicked: root.jump(modelData)
                            // Resolve the drop by hit-testing the pill row (ParentChange
                            // snaps the clone back the instant the drag ends, racing the
                            // DropArea's drop event).
                            onReleased: function (mouse) {
                                if (!didDrag) return
                                var p = dragArea.mapToItem(pillRow, mouse.x, mouse.y)
                                var pi = pillRow.childAt(p.x, p.y)
                                if (pi && pi.wsId !== undefined) root.moveWin(modelData, pi.wsId)
                            }

                            // ClippingRectangle: children (preview, chip) clip to the rounded border
                            ClippingRectangle {
                                id: cardContent
                                width: dragArea.width
                                height: dragArea.height
                                radius: Theme.radius
                                color: Theme.panel
                                border.color: dragArea.seld ? Theme.accent : Theme.stroke
                                border.width: dragArea.seld ? 2 : 1

                                Drag.active: dragArea.drag.active
                                Drag.source: dragArea
                                Drag.hotSpot.x: width / 2
                                Drag.hotSpot.y: height / 2
                                Drag.keys: ["overview-window"]

                                // float above everything while dragging; ParentChange
                                // saves & restores x/y, snapping back on release
                                states: State {
                                    name: "dragging"; when: dragArea.drag.active
                                    ParentChange { target: cardContent; parent: dragLayer }
                                    PropertyChanges { target: cardContent; opacity: 0.92; z: 3000; scale: 0.5 }
                                }

                                // live window preview, icon fallback
                                ScreencopyView {
                                    id: sc
                                    visible: hasContent && dragArea.modelData.wayland
                                    captureSource: dragArea.modelData.wayland || null
                                    live: Globals.overviewOpen && !cardContent.Drag.active
                                    anchors.fill: parent
                                }
                                Image {
                                    anchors.centerIn: parent; visible: !sc.visible
                                    width: 56; height: 56; sourceSize.width: 112; sourceSize.height: 112
                                    source: root.iconFor(dragArea.modelData)
                                }

                                // title chip (bottom)
                                Rectangle {
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                    height: 28
                                    color: Qt.rgba(0, 0, 0, 0.55)
                                    Text {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                                        verticalAlignment: Text.AlignVCenter
                                        text: root.titleOf(dragArea.modelData)
                                        color: dragArea.seld ? Theme.fg : Theme.fgSecondary
                                        font.family: Theme.fontText; font.pixelSize: 12
                                        font.weight: dragArea.seld ? Font.DemiBold : Font.Normal
                                        elide: Text.ElideRight
                                    }
                                }

                                // app-icon badge — top-right, as in the mockup
                                Rectangle {
                                    anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 10
                                    width: 34; height: 34; radius: 17
                                    color: Qt.rgba(0, 0, 0, 0.55)
                                    Image {
                                        anchors.centerIn: parent
                                        width: 22; height: 22; sourceSize.width: 44; sourceSize.height: 44
                                        source: root.iconFor(dragArea.modelData)
                                    }
                                }
                            }

                            // close (✕) — top-left on hover (badge owns the top-right corner).
                            // Accent glyph on the dark chip (black-on-black was invisible) and
                            // box-centred via alignment (centerIn drifts on glyph metrics).
                            Rectangle {
                                anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 10
                                z: 50
                                width: 24; height: 24; radius: 12
                                visible: !dragArea.drag.active && (dragArea.containsMouse || closeMa.containsMouse)
                                color: closeMa.containsMouse ? Theme.danger : Qt.rgba(0, 0, 0, 0.6)
                                border.color: closeMa.containsMouse ? Theme.danger : Theme.accent; border.width: 1
                                Text {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                    text: Theme.icClose; font.family: Theme.fontMono; font.pixelSize: 14
                                    color: closeMa.containsMouse ? Theme.accentText : Theme.accent
                                }
                                MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.killWin(dragArea.modelData) }
                            }
                        }
                    }
                }

                // empty-desktop hint
                Column {
                    anchors.centerIn: parent
                    visible: root.curWins.length === 0
                    spacing: 12
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: Theme.icMonitorOff; font.family: Theme.fontMono; font.pixelSize: 40; color: Theme.fgDim }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "No windows on this desktop"; color: Theme.fgDim; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsTitle }
                }
            }

            // ══ SEARCH STATE — Apps + Windows, launcher-style rows ═══════════════
            Flickable {
                visible: root.searching
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: searchBox.bottom; anchors.topMargin: 28
                anchors.bottom: parent.bottom; anchors.bottomMargin: 32
                clip: true
                contentWidth: width
                contentHeight: resCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: resCol
                    width: Math.min(parent.width - 120, 640)
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6

                    Text {
                        visible: root.appResults.length > 0
                        text: "Apps"
                        color: Theme.fgSecondary; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold
                        topPadding: 4; bottomPadding: 2
                    }
                    Repeater {
                        model: root.appResults
                        delegate: Item {
                            id: appRow
                            required property var modelData
                            required property int index
                            readonly property bool seld: index === root.sel
                            width: resCol.width; height: 54
                            Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: appRow.seld ? Theme.accent : (arMa.containsMouse ? Theme.hover : "transparent") }
                            Row {
                                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 14
                                Image { anchors.verticalCenter: parent.verticalCenter; width: 34; height: 34; sourceSize.width: 68; sourceSize.height: 68; source: root.appIcon(appRow.modelData) }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                    Text { text: appRow.modelData.name || ""; color: appRow.seld ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.Medium }
                                    Text { visible: !!appRow.modelData.genericName; text: appRow.modelData.genericName || ""; color: appRow.seld ? Theme.accentText : Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                }
                            }
                            MouseArea { id: arMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onPositionChanged: root.sel = appRow.index; onClicked: root.launchApp(appRow.modelData) }
                        }
                    }

                    Text {
                        visible: root.winResults.length > 0
                        text: "Windows"
                        color: Theme.fgSecondary; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold
                        topPadding: 12; bottomPadding: 2
                    }
                    Repeater {
                        model: root.winResults
                        delegate: Item {
                            id: winRow
                            required property var modelData
                            required property int index
                            readonly property int navIdx: root.appResults.length + index
                            readonly property bool seld: navIdx === root.sel
                            width: resCol.width; height: 54
                            Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: winRow.seld ? Theme.accent : (wrMa.containsMouse ? Theme.hover : "transparent") }
                            Row {
                                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 48; spacing: 14
                                Image { anchors.verticalCenter: parent.verticalCenter; width: 34; height: 34; sourceSize.width: 68; sourceSize.height: 68; source: root.iconFor(winRow.modelData) }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                    Text { width: resCol.width - 130; text: root.titleOf(winRow.modelData); elide: Text.ElideRight; color: winRow.seld ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.Medium }
                                    Text { text: "Desktop " + root.wsOf(winRow.modelData); color: winRow.seld ? Theme.accentText : Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                }
                            }
                            MouseArea { id: wrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onPositionChanged: root.sel = winRow.navIdx; onClicked: root.jump(winRow.modelData) }
                            // close this window right from the results — accent ✕, box-centred
                            Rectangle {
                                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                width: 24; height: 24; radius: 12
                                visible: wrMa.containsMouse || wxMa.containsMouse || winRow.seld
                                color: wxMa.containsMouse ? Theme.danger : Qt.rgba(0, 0, 0, 0.35)
                                border.color: wxMa.containsMouse ? Theme.danger : Theme.accent; border.width: 1
                                Text {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                    text: Theme.icClose; font.family: Theme.fontMono; font.pixelSize: 14
                                    color: (winRow.seld || wxMa.containsMouse) ? Theme.accentText : Theme.accent
                                }
                                MouseArea { id: wxMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.killWin(winRow.modelData) }
                            }
                        }
                    }

                    // dead-end state
                    Column {
                        width: parent.width
                        visible: root.appResults.length === 0 && root.winResults.length === 0
                        spacing: 10
                        Text { anchors.horizontalCenter: parent.horizontalCenter; topPadding: 40; text: Theme.icSearch; font.family: Theme.fontMono; font.pixelSize: 36; color: Theme.fgDim }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Nothing matches “" + root.query + "”"; color: Theme.fgDim; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsTitle }
                    }
                }
            }

            // floating layer the dragged card reparents into (so it isn't clipped)
            Item { id: dragLayer; anchors.fill: parent; z: 2000 }
        }
    }
}
