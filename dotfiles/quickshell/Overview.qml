import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

// Overview — GNOME/macOS-style activities view (per the user's SVG mockup).
//
// The wallpaper stays visible under a light scrim, and the top bar / dock stay
// on screen (normal exclusion): the overview reads as a MODE of the desktop,
// not a separate screen.
//
//   · centre-top LAUNCHER: rounded search field; typing fuses a results panel
//     under it — Apps ("Application"), open Windows ("Jump to", with their
//     desktop), and a Files fallback (fd/find in $HOME, xdg-open). One list,
//     one keyboard order: ↑/↓ + Enter.
//   · the current desktop's windows stay as live-preview CARDS (soft shadow,
//     hairline border, app badge, hover ✕). While searching they dim and
//     ignore input — the launcher floats above them, mockup-style.
//   · workspace PAGER bottom-centre: each desktop is a miniature monitor-shaped
//     glass box with a stylised layout of its windows ("desktop boxes",
//     shrunk); current is accent-framed, the trailing empty one shows "+".
//     Click switches; drop a dragged card on one to move the window there.
// Animation: GNOME-like zoom — the stage zooms out into view on open and back
// in on close (scale + fade, Theme.dur*).
//
// Trigger: `qs ipc call overview toggle` (Super tap / 3-finger swipe up).
Scope {
    id: root

    property string query: ""
    property int sel: 0
    property bool dragActive: false      // a card is mid-drag (dots inflate)

    // one shared launcher-row look: icon square, title(+sub), right type tag
    component ResultRow: Item {
        id: rr
        property bool seld: false
        property string icon: ""       // themed icon path ("" → glyph chip)
        property string glyph: ""
        property string title: ""
        property string sub: ""
        property string tag: ""
        signal go()
        height: rr.sub !== "" ? 54 : 46
        Rectangle {
            anchors.fill: parent; radius: 10
            color: rr.seld ? Qt.rgba(1, 1, 1, 0.12) : (rrMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
        }
        Row {
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
            spacing: 13
            Item {
                width: 28; height: 28
                anchors.verticalCenter: parent.verticalCenter
                Image {
                    visible: rr.icon !== ""
                    anchors.fill: parent
                    sourceSize.width: 56; sourceSize.height: 56
                    source: rr.icon
                }
                Rectangle {
                    visible: rr.icon === ""
                    anchors.fill: parent; radius: 7
                    color: Qt.rgba(1, 1, 1, 0.10)
                    Text { anchors.centerIn: parent; text: rr.glyph; font.family: Theme.fontIcons; font.pixelSize: 15; color: Theme.fgSecondary }
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter; spacing: 1
                width: parent.width - 28 - 13 - tagLbl.implicitWidth - 8
                Text { width: parent.width; text: rr.title; elide: Text.ElideRight; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.Medium }
                Text { visible: rr.sub !== ""; width: parent.width; text: rr.sub; elide: Text.ElideRight; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
            }
        }
        Text {
            id: tagLbl
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: rr.tag
            color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
        }
        MouseArea {
            id: rrMa
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: rr.go()
        }
    }

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

    // ── workspaces: 1 … max(used, focused), + one trailing empty, cap 10 ──
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

    // pager thumbs: window blocks as [x, y, w, h] fractions of the thumb
    function miniLayout(n) {
        if (n <= 0) return []
        if (n === 1) return [[0.10, 0.14, 0.80, 0.72]]
        if (n === 2) return [[0.09, 0.14, 0.39, 0.72], [0.52, 0.14, 0.39, 0.72]]
        if (n === 3) return [[0.09, 0.14, 0.39, 0.72], [0.52, 0.14, 0.39, 0.33], [0.52, 0.53, 0.39, 0.33]]
        return [[0.09, 0.14, 0.39, 0.33], [0.52, 0.14, 0.39, 0.33], [0.09, 0.53, 0.39, 0.33], [0.52, 0.53, 0.39, 0.33]]
    }

    // ── current desktop's windows ──
    readonly property var curWins: currentWins()
    function currentWins() {
        var out = []
        for (var i = 0; i < root.allWins.length; i++)
            if (root.wsOf(root.allWins[i]) === root.focusedWs) out.push(root.allWins[i])
        return out
    }

    // ── search: apps + open windows + files ──
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
        return pre.concat(mid).slice(0, 5)
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

    // files fallback — debounced fd/find in $HOME; the query rides as an
    // argument ($1), never spliced into the script (no shell injection)
    property var fileResults: []
    property Process _fileProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n")
                var home = Quickshell.env("HOME")
                var out = []
                for (var i = 0; i < lines.length && out.length < 5; i++) {
                    var p = lines[i].trim()
                    if (p === "") continue
                    var slash = p.lastIndexOf("/")
                    var dir = slash > 0 ? p.substring(0, slash) : "/"
                    if (dir.indexOf(home) === 0) dir = "~" + dir.substring(home.length)
                    out.push({ path: p, name: p.substring(slash + 1), dir: dir })
                }
                root.fileResults = out
            }
        }
    }
    property Timer _fileDebounce: Timer { interval: 220; onTriggered: root.runFileSearch() }
    function runFileSearch() {
        var q = root.query.trim()
        if (q === "") return
        root._fileProc.command = ["sh", "-c",
            'if command -v fd >/dev/null 2>&1; then fd --ignore-case --max-results 5 --type f --fixed-strings -- "$1" "$HOME" 2>/dev/null; ' +
            'else find "$HOME" -maxdepth 4 -type f -iname "*$1*" 2>/dev/null | head -5; fi',
            "hs-files", q]
        root._fileProc.running = false
        root._fileProc.running = true
    }
    function openFile(f) { if (f) Quickshell.execDetached(["xdg-open", f.path]); root.close() }

    // keyboard-nav list: search → apps, windows, files; otherwise the cards
    readonly property int navCount: root.searching
        ? root.appResults.length + root.winResults.length + root.fileResults.length
        : root.curWins.length
    function activateSel() {
        if (root.searching) {
            var na = root.appResults.length, nw = root.winResults.length
            if (root.sel < na) root.launchApp(root.appResults[root.sel])
            else if (root.sel < na + nw) root.jump(root.winResults[root.sel - na])
            else if (root.fileResults.length) root.openFile(root.fileResults[Math.min(root.sel - na - nw, root.fileResults.length - 1)])
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

    onQueryChanged: {
        root.sel = 0
        root.fileResults = []
        if (root.searching) root._fileDebounce.restart()
    }
    onNavCountChanged: if (root.sel >= navCount) root.sel = Math.max(0, navCount - 1)

    IpcHandler {
        target: "overview"
        function toggle(): void { Globals.overviewOpen = !Globals.overviewOpen }
        function show(): void { Globals.overviewOpen = true }
        function hide(): void { Globals.overviewOpen = false }
        // open pre-filled (scripting / keybinds like "Super+F → find")
        function find(q: string): void { Globals.overviewOpen = true; search.text = q }
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
        // NORMAL exclusion: the bar and dock stay visible around the overview,
        // so it reads as a mode of the desktop (mockup) rather than a takeover
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell:overview"
        anchors { top: true; bottom: true; left: true; right: true }

        onVisibleChanged: if (visible) Qt.callLater(function () { search.text = ""; search.forceActiveFocus() })
        Connections {
            target: Globals
            function onOverviewOpenChanged() { if (Globals.overviewOpen) search.forceActiveFocus() }
        }

        // light scrim — the wallpaper stays part of the picture; click to dismiss
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.45)
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
            readonly property color glassBg: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.90)
            readonly property color hairline: Qt.rgba(1, 1, 1, 0.16)

            // ══ WINDOW CARDS — always present; dim + freeze while searching ═══
            Flickable {
                id: cardArea
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: searchBox.bottom; anchors.topMargin: 34
                anchors.bottom: pagerRow.top; anchors.bottomMargin: 18
                clip: true
                contentWidth: width
                contentHeight: Math.max(height, cardFlow.implicitHeight)
                boundsBehavior: Flickable.StopAtBounds
                interactive: !root.searching
                opacity: root.searching ? 0.35 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.dur; easing.type: Easing.OutCubic } }
                // card size scales down as the desktop gets busier
                readonly property real cardH: Math.round(height * (root.curWins.length <= 2 ? 0.52 : root.curWins.length <= 6 ? 0.40 : 0.30))
                readonly property real cardW: Math.round(cardH * stage.monAR)

                Flow {
                    id: cardFlow
                    width: Math.min(cardArea.width - 80, (cardArea.cardW + 30) * Math.min(Math.max(root.curWins.length, 1), 3))
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.max(0, (cardArea.height - implicitHeight) / 2)
                    spacing: 30

                    Repeater {
                        model: root.curWins
                        delegate: MouseArea {
                            id: dragArea
                            required property var modelData
                            required property int index
                            readonly property bool seld: index === root.sel && !root.searching
                            width: cardArea.cardW; height: cardArea.cardH
                            enabled: !root.searching
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            drag.target: cardContent
                            drag.smoothed: false
                            property bool didDrag: false
                            onPressed: didDrag = false
                            onPositionChanged: {
                                if (drag.active) { didDrag = true; root.dragActive = true }
                                else root.sel = index
                            }
                            onClicked: root.jump(modelData)
                            // Resolve the drop by hit-testing the dots row (ParentChange
                            // snaps the clone back the instant the drag ends, racing the
                            // DropArea's drop event).
                            onReleased: function (mouse) {
                                root.dragActive = false
                                if (!didDrag) return
                                var p = dragArea.mapToItem(pagerRow, mouse.x, mouse.y)
                                var pi = pagerRow.childAt(p.x, p.y)
                                if (pi && pi.wsId !== undefined) root.moveWin(modelData, pi.wsId)
                            }

                            // soft drop shadow — a black silhouette behind the card;
                            // the card covers its centre, only the blur spills out
                            Rectangle {
                                id: shadowProxy
                                anchors.fill: cardContent
                                radius: 14
                                color: "black"
                                visible: false
                            }
                            MultiEffect {
                                anchors.fill: shadowProxy
                                source: shadowProxy
                                visible: !dragArea.drag.active
                                shadowEnabled: true
                                shadowBlur: 1.0
                                shadowColor: Qt.rgba(0, 0, 0, 0.5)
                                shadowVerticalOffset: 10
                            }

                            // ClippingRectangle: children (preview, chip) clip to the rounded border
                            ClippingRectangle {
                                id: cardContent
                                width: dragArea.width
                                height: dragArea.height
                                radius: 14
                                color: Theme.panel
                                border.color: dragArea.seld ? Theme.accent : stage.hairline
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
                                        horizontalAlignment: Text.AlignHCenter
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
                            Rectangle {
                                anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 10
                                z: 50
                                width: 24; height: 24; radius: 12
                                visible: !dragArea.drag.active && !root.searching && (dragArea.containsMouse || closeMa.containsMouse)
                                color: closeMa.containsMouse ? Theme.danger : Qt.rgba(0, 0, 0, 0.6)
                                border.color: closeMa.containsMouse ? Theme.danger : Theme.accent; border.width: 1
                                Text {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                    text: Theme.icClose; font.family: Theme.fontIcons; font.pixelSize: 14
                                    color: closeMa.containsMouse ? Theme.accentText : Theme.accent
                                }
                                MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.killWin(dragArea.modelData) }
                            }
                        }
                    }
                }

                // empty desktop — one quiet line, nothing to look at on purpose
                Text {
                    anchors.centerIn: parent
                    visible: root.curWins.length === 0 && !root.searching
                    text: "No active windows"
                    color: Theme.fg
                    opacity: 0.35
                    font.family: Theme.fontDisplay; font.pixelSize: Theme.fsTitle
                }
            }

            // ══ LAUNCHER — search field + fused results panel (above the cards) ══
            Rectangle {
                id: searchShadowProxy
                anchors.fill: searchBox
                radius: 16
                color: "black"
                visible: false
            }
            MultiEffect {
                anchors.fill: searchShadowProxy
                source: searchShadowProxy
                shadowEnabled: true
                shadowBlur: 1.0
                shadowColor: Qt.rgba(0, 0, 0, 0.45)
                shadowVerticalOffset: 12
            }
            Rectangle {
                id: searchBox
                anchors.horizontalCenter: parent.horizontalCenter
                y: 30
                width: 560; height: 52
                radius: 16
                color: stage.glassBg
                border.color: search.activeFocus ? Qt.rgba(1, 1, 1, 0.24) : stage.hairline
                border.width: 1
                z: 10

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 20; anchors.rightMargin: 20
                    spacing: 12
                    Text { anchors.verticalCenter: parent.verticalCenter; text: Theme.icSearch; font.family: Theme.fontIcons; font.pixelSize: 16; color: Theme.fgDim }
                    TextInput {
                        id: search
                        width: parent.width - 40
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge
                        selectionColor: Theme.accent; selectByMouse: true; clip: true
                        // accent caret, macOS-style blink
                        cursorDelegate: Rectangle {
                            width: 2; radius: 1
                            height: search.cursorRectangle.height
                            color: Theme.accent
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite; running: search.activeFocus
                                NumberAnimation { from: 1; to: 1; duration: 520 }
                                NumberAnimation { from: 1; to: 0; duration: 60 }
                                NumberAnimation { from: 0; to: 0; duration: 380 }
                                NumberAnimation { from: 0; to: 1; duration: 60 }
                            }
                        }
                        onTextChanged: root.query = text
                        Text { visible: search.text.length === 0; anchors.verticalCenter: parent.verticalCenter; text: "Search apps, windows and files…"; color: Theme.fgDim; font: search.font }
                        Keys.onPressed: function (ev) {
                            if (ev.key === Qt.Key_Escape) { root.close(); ev.accepted = true }
                            else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { root.activateSel(); ev.accepted = true }
                            else if (ev.key === Qt.Key_Left || ev.key === Qt.Key_Up) { root.sel = Math.max(0, root.sel - 1); ev.accepted = true }
                            else if (ev.key === Qt.Key_Right || ev.key === Qt.Key_Down) { root.sel = Math.min(root.navCount - 1, root.sel + 1); ev.accepted = true }
                        }
                    }
                }
            }

            // results panel — fused 8 px under the field, one list: apps,
            // windows, files, each row with a right-side type tag (mockup)
            Rectangle {
                id: resultsPanel
                visible: root.searching && Globals.overviewOpen
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: searchBox.bottom; anchors.topMargin: 8
                width: searchBox.width
                height: Math.min(resCol.implicitHeight + 16, stage.height - searchBox.y - searchBox.height - 60)
                radius: 16
                color: stage.glassBg
                border.color: stage.hairline; border.width: 1
                z: 10

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    contentWidth: width
                    contentHeight: resCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: resCol
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: root.appResults
                            delegate: ResultRow {
                                required property var modelData
                                required property int index
                                width: resCol.width
                                seld: index === root.sel
                                icon: root.appIcon(modelData)
                                title: modelData.name || ""
                                tag: "Application"
                                onGo: root.launchApp(modelData)
                            }
                        }
                        Repeater {
                            model: root.winResults
                            delegate: ResultRow {
                                required property var modelData
                                required property int index
                                width: resCol.width
                                seld: root.appResults.length + index === root.sel
                                icon: root.iconFor(modelData)
                                title: root.titleOf(modelData)
                                sub: "Open window on Desktop " + root.wsOf(modelData)
                                tag: "Jump to"
                                onGo: root.jump(modelData)
                            }
                        }
                        Repeater {
                            model: root.fileResults
                            delegate: ResultRow {
                                required property var modelData
                                required property int index
                                width: resCol.width
                                seld: root.appResults.length + root.winResults.length + index === root.sel
                                glyph: Theme.icFile
                                title: modelData.name
                                tag: modelData.dir
                                onGo: root.openFile(modelData)
                            }
                        }

                        // dead-end state
                        Item {
                            visible: root.navCount === 0
                            width: resCol.width; height: 46
                            Row {
                                anchors.centerIn: parent; spacing: 10
                                Text { anchors.verticalCenter: parent.verticalCenter; text: Theme.icSearchOff; font.family: Theme.fontIcons; font.pixelSize: 16; color: Theme.fgDim }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: "Nothing matches “" + root.query + "”"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsBody }
                            }
                        }
                    }
                }
            }

            // ══ workspace pager — bottom-centre: each desktop is a miniature
            // monitor-shaped glass box with a stylised layout of its windows
            // (this DE's "desktop boxes", shrunk). Current = accent frame,
            // trailing empty = "+", drag a card over one to move the window.
            Row {
                id: pagerRow
                anchors.horizontalCenter: parent.horizontalCenter
                // clear of the dock, which draws above the overview in the same
                // layer (dockH + its 8 px float + breathing room)
                anchors.bottom: parent.bottom; anchors.bottomMargin: 96
                spacing: 12
                opacity: root.searching ? 0.35 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.dur; easing.type: Easing.OutCubic } }
                Repeater {
                    model: root.wsPills
                    delegate: Item {
                        id: thumb
                        required property var modelData
                        readonly property int wsId: modelData.ws
                        readonly property bool current: wsId === root.focusedWs
                        readonly property bool empty: modelData.count === 0
                        width: 58; height: 38
                        scale: thumbDrop.containsDrag ? 1.14 : (thumbMa.containsMouse ? 1.06 : 1)
                        Behavior on scale { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }

                        Rectangle {
                            id: thumbBox
                            anchors.fill: parent
                            radius: 9
                            color: thumbDrop.containsDrag ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.30)
                                 : thumb.current ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                 : Qt.rgba(1, 1, 1, thumbMa.containsMouse ? 0.13 : 0.07)
                            border.color: (thumb.current || thumbDrop.containsDrag) ? Theme.accent : stage.hairline
                            border.width: thumb.current || thumbDrop.containsDrag ? 2 : 1
                            Behavior on color { ColorAnimation { duration: Theme.durFast } }

                            // stylised windows: 1 = full, 2 = split, 3 = master+stack,
                            // 4+ = grid — a pager you can read at a glance
                            Repeater {
                                model: root.miniLayout(Math.min(thumb.modelData.count, 4))
                                delegate: Rectangle {
                                    required property var modelData
                                    x: Math.round(thumbBox.width * modelData[0])
                                    y: Math.round(thumbBox.height * modelData[1])
                                    width: Math.round(thumbBox.width * modelData[2])
                                    height: Math.round(thumbBox.height * modelData[3])
                                    radius: 2.5
                                    opacity: root.dragActive ? 0.25 : 1
                                    color: thumb.current ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.75)
                                                         : Qt.rgba(1, 1, 1, 0.40)
                                    Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
                                }
                            }

                            // trailing empty desktop reads as "new one lives here"
                            Text {
                                anchors.centerIn: parent
                                visible: thumb.empty && !thumb.current && !root.dragActive
                                text: "+"
                                color: Qt.rgba(1, 1, 1, 0.45)
                                font.family: Theme.fontDisplay; font.pixelSize: 17; font.weight: Font.DemiBold
                            }

                            // while a card is being dragged, the number is the target
                            Text {
                                anchors.centerIn: parent
                                visible: root.dragActive
                                text: thumb.wsId
                                color: thumbDrop.containsDrag ? "#ffffff" : Theme.fgSecondary
                                font.family: Theme.fontDisplay; font.pixelSize: 14; font.weight: Font.DemiBold
                            }
                        }
                        DropArea { id: thumbDrop; anchors.fill: parent; keys: ["overview-window"] }
                        MouseArea {
                            id: thumbMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.gotoWs(thumb.wsId)
                        }
                    }
                }
            }

            // floating layer the dragged card reparents into (so it isn't clipped)
            Item { id: dragLayer; anchors.fill: parent; z: 2000 }
        }
    }
}
