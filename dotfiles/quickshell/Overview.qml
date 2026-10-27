import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

// Overview — every window on the workspace, spread out (owner decision
// 2026-10-23, after macOS Mission Control; vault note "Overview Spreads the
// Windows"). It replaces the GNOME-style card grid with search.
//
//   · the windows FLY: each card starts exactly over its real window, so the
//     first frame looks like the desktop itself, then glides to its place in
//     the spread; closing flies every card back onto its window and the
//     surface unmaps under them. One number, `progress` (0 = the desktop as
//     it is, 1 = spread), drives every card, the backdrop, the workspace
//     strip and the bar/dock beat — one animation, no per-card timers.
//   · the spread keeps each window's proportions AND its size against the
//     others (one scale for the whole workspace, never above 1), ordered by
//     where the windows sit, in 1–4 rows.
//   · the WORKSPACE STRIP at the top: one label per workspace on this screen;
//     point at it (or drag a window up to it) and it slides down into
//     thumbnails. Click one to go there; drop a window on one to move it
//     there; drop it beside them — or on the "+" that shows while a window
//     is dragged — and it goes to a NEW workspace of this display (the next
//     number after the last one in use, like the swipe). No "add" button:
//     a workspace exists when you go to it (Super+N) or put a window on it.
//   · a window GROUP (Hyprland's tabs, Super+G) is one card: the tab on top,
//     with the tabs' icons and their count in a pill on its corner; the
//     hidden tabs are not spread out as windows of their own.
//   · no search: the app launcher (Super+D) has it; `overview find` hands
//     its query over.
//
// Performance is the brief (the owner: "performance is the must"):
//   · each window is captured ONCE when the Overview opens (`live: false`) —
//     no continuous capture of every window every frame;
//   · the backdrop is the wallpaper with a dim, no blur pass;
//   · shadows are RectangularShadow (analytic, no offscreen layer);
//   · the workspace thumbnails draw the windows as shapes with their app
//     icon — the wallpaper texture is shared with the backdrop, nothing else
//     is captured; no process is spawned on open.
//
// The open waits for the captures (a frame or two; never longer than
// durFast): until then the surface is mapped but draws nothing, so the first
// frame the user sees already has every window in place. While the cards
// fly, a WALLPAPER PATCH sits under each window's real spot so the live
// window behind the overlay never shows twice; everything else (the bar, the
// dock, the gaps) fades under the backdrop as `progress` rises.
//
// Triggers: the `ewe:overview` global shortcut (Super tapped alone),
// `qs ipc call overview toggle` (scripts, the 3-finger swipe) and the
// in-shell buttons, which flip Globals.overviewOpen directly.
Scope {
    id: root

    // ── the one number ──────────────────────────────────────────────────────
    property real progress: 0
    // the surface is mapped (open, or flying back)
    property bool held: false
    // the captures are in (or the wait ran out): the stage may draw
    property bool armed: false
    // closing by a cross-fade instead of the flight home: the workspace
    // under the cards is about to change, so there is nowhere to fly to
    property bool fading: false
    property real fade: 1
    // the spread is at rest: hover states and the title chip may show
    readonly property bool settled: Globals.overviewOpen && root.progress >= 1
    // the geometry follows `fly`; Reduce motion never flies (the whole stage
    // cross-fades with `progress` instead)
    readonly property real fly: Theme.reduceMotion ? 1 : root.progress

    property string openScreen: ""        // the output that takes the keyboard
    property int sel: -1                  // keyboard/hover selection on the open screen
    property bool dragActive: false       // a card is mid-drag (the strip opens)

    function focusedScreenName() {
        var fm = Hyprland.focusedMonitor, ss = Quickshell.screens
        if (fm) for (var i = 0; i < ss.length; i++) if (ss[i].name === fm.name) return fm.name
        return ss.length > 0 ? ss[0].name : ""
    }

    readonly property var allWins: Hyprland.toplevels ? Hyprland.toplevels.values : []
    readonly property int focusedWs: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1

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
    function addrOf(tl) {
        var a = (tl && tl.address) ? String(tl.address) : ""
        if (a !== "" && a.indexOf("0x") !== 0) a = "0x" + a   // Hyprland events sometimes omit the 0x
        return a
    }
    // a window group (Hyprland's tabs): every member lists the group in
    // `grouped`; a group is ONE card, the tab on top, so the tabs behind it
    // are left out. The tab on top is the member Hyprland lets input through
    // to — 0.56 reports the others `acceptsInput: false` (older builds
    // `hidden: true`); should none or several read that way (the group on a
    // workspace off screen), it is the member focused last.
    function groupOf(tl) {
        var o = tl && tl.lastIpcObject ? tl.lastIpcObject : null
        return (o && o.grouped && o.grouped.length > 1) ? o.grouped : null
    }
    function topOfGroup(g) {
        var by = {}, cand = [], best = "", bestRank = 1e9
        for (var i = 0; i < root.allWins.length; i++) by[root.addrOf(root.allWins[i])] = root.allWins[i]
        for (i = 0; i < g.length; i++) {
            var a = String(g[i])
            if (a.indexOf("0x") !== 0) a = "0x" + a
            var t = by[a]
            if (!t) continue
            var o = t.lastIpcObject || {}
            if (o.hidden !== true && o.acceptsInput !== false) cand.push(a)
            var r = (o.focusHistoryID !== undefined) ? o.focusHistoryID : 1e8
            if (r < bestRank) { bestRank = r; best = a }
        }
        return cand.length === 1 ? cand[0] : best
    }
    function isHiddenTab(tl) {
        var g = root.groupOf(tl)
        return !!g && root.addrOf(tl) !== root.topOfGroup(g)
    }
    // the group's members as toplevels, in tab order ([] for a lone window)
    function tabsOf(tl) {
        var g = root.groupOf(tl)
        if (!g) return []
        var by = {}
        for (var i = 0; i < root.allWins.length; i++) by[root.addrOf(root.allWins[i])] = root.allWins[i]
        var out = []
        for (i = 0; i < g.length; i++) {
            var a = String(g[i])
            if (a.indexOf("0x") !== 0) a = "0x" + a
            if (by[a]) out.push(by[a])
        }
        return out
    }

    // a window's real rectangle on its monitor (screen-local, logical px),
    // or null while its IPC object has not arrived
    function realRect(tl, mon) {
        var o = tl ? tl.lastIpcObject : null
        if (!o || !o.at || !o.size || o.size[0] <= 0 || o.size[1] <= 0) return null
        var mx = mon ? mon.x : 0, my = mon ? mon.y : 0
        return { x: o.at[0] - mx, y: o.at[1] - my, w: o.size[0], h: o.size[1] }
    }
    // stacking at rest: fullscreen over floating over tiled, the focused
    // window on top of its kind — what the desktop shows at progress 0
    function stackOf(tl) {
        var o = tl ? tl.lastIpcObject : null
        var z = (o && o.fullscreen) ? 4 : (o && o.floating) ? 2 : 0
        return z + (tl && tl.activated ? 1 : 0)
    }

    // ── the spread ──────────────────────────────────────────────────────────
    // items: [{ x, y, w, h }] real rects, in model order. Returns the target
    // rect per item (same order), inside a W x H field. One scale `s` for
    // every window (relative sizes survive, like macOS), never above 1; try
    // 1–4 rows of windows sorted top-to-bottom, each row left-to-right, and
    // keep the arrangement with the largest scale.
    function spread(items, W, H) {
        var n = items.length
        if (n === 0 || W <= 0 || H <= 0) return []
        var gap = Theme.spaceLg
        var rowGap = Theme.spaceMd + Theme.controlMd   // room for the title chip under a card
        var idx = []
        for (var i = 0; i < n; i++) idx.push(i)
        idx.sort(function (a, b) { return (items[a].y + items[a].h / 2) - (items[b].y + items[b].h / 2) })
        var best = null
        for (var rows = 1; rows <= Math.min(n, 4); rows++) {
            var per = Math.ceil(n / rows), rr = []
            for (var r = 0; r < rows; r++) {
                var chunk = idx.slice(r * per, (r + 1) * per)
                if (!chunk.length) continue
                chunk.sort(function (a, b) { return (items[a].x + items[a].w / 2) - (items[b].x + items[b].w / 2) })
                rr.push(chunk)
            }
            var s = 1, sumH = 0
            for (r = 0; r < rr.length; r++) {
                var sw = 0, mh = 0
                for (var k = 0; k < rr[r].length; k++) { sw += items[rr[r][k]].w; mh = Math.max(mh, items[rr[r][k]].h) }
                s = Math.min(s, (W - (rr[r].length - 1) * gap) / sw)
                sumH += mh
            }
            s = Math.min(s, (H - (rr.length - 1) * rowGap) / sumH)
            if (!best || s > best.s) best = { rr: rr, s: s }
        }
        var sc = Math.max(0.02, best.s)
        var heights = [], blockH = (best.rr.length - 1) * rowGap
        for (r = 0; r < best.rr.length; r++) {
            var h = 0
            for (k = 0; k < best.rr[r].length; k++) h = Math.max(h, items[best.rr[r][k]].h * sc)
            heights.push(h); blockH += h
        }
        var out = new Array(n)
        var y = Math.max(0, (H - blockH) / 2)
        for (r = 0; r < best.rr.length; r++) {
            var rowW = (best.rr[r].length - 1) * gap
            for (k = 0; k < best.rr[r].length; k++) rowW += items[best.rr[r][k]].w * sc
            var x = (W - rowW) / 2
            for (k = 0; k < best.rr[r].length; k++) {
                var it = items[best.rr[r][k]]
                var cw = it.w * sc, ch = it.h * sc
                out[best.rr[r][k]] = { x: Math.round(x), y: Math.round(y + (heights[r] - ch) / 2), w: Math.round(cw), h: Math.round(ch) }
                x += cw + gap
            }
            y += heights[r] + rowGap
        }
        return out
    }

    // ── actions ─────────────────────────────────────────────────────────────
    function jump(tl) {
        // by ADDRESS, so Hyprland raises it (and switches, should it live
        // elsewhere); the card then flies home on top of the others
        Globals.focusToplevel(tl)
        root.close()
    }
    function moveWin(tl, ws) {
        var a = root.addrOf(tl)
        if (a === "" || root.wsOf(tl) === ws) return
        Hyprland.dispatch('hl.dsp.window.move({workspace=' + ws + ', window="address:' + a + '", follow=false})')
    }
    // a drop on the strip beside the workspaces (or on its "+"): the window
    // goes to a NEW workspace of this display — the number after the last
    // one in use in the display's block of ten (workspaces.lua), the way
    // the swipe makes one; the lowest free number once 10 is taken. All ten
    // in use: a toast, nothing moves.
    function moveToNew(tl, shownWs, ids) {
        var block = Globals.wsBlock(shownWs), used = {}, last = 0
        for (var i = 0; i < ids.length; i++) { var n = Globals.wsNumber(ids[i]); used[n] = true; last = Math.max(last, n) }
        var target = 0
        if (last < 10) target = last + 1
        else for (n = 1; n <= 10; n++) if (!used[n]) { target = n; break }
        if (target === 0) { Shell.toast("Every workspace of this display is in use", "warning"); return }
        root.moveWin(tl, block * 10 + target)
    }
    function killWin(tl) {
        var a = root.addrOf(tl)
        if (a !== "") Hyprland.dispatch('hl.dsp.window.close({window="address:' + a + '"})')
    }
    function gotoWs(ws) {
        // another workspace: its windows are not under these cards, so the
        // Overview cross-fades away while Hyprland slides the workspace in
        if (ws !== root.focusedWs) {
            root.fading = true
            Hyprland.dispatch("hl.dsp.focus({workspace=" + ws + "})")
        }
        root.close()
    }
    function close() { Globals.overviewOpen = false }
    function toggle() { Globals.overviewOpen = !Globals.overviewOpen }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.toggle() }
        function show(): void { Globals.overviewOpen = true }
        function hide(): void { Globals.overviewOpen = false }
        // public verb (Rule 4) from the days the Overview had a search
        // field: the query now goes to the app launcher, which searches apps
        // and files
        function find(q: string): void { Globals.overviewOpen = false; Globals.launcherFind(q) }
    }

    // Super tapped alone. hyprland.lua binds the key (on release) to
    // `hl.dsp.global("ewe:overview")`, which Hyprland delivers to this
    // process over the global-shortcuts protocol — no `qs ipc` spawn. A
    // release bind sends `released` only, a press bind `pressed` and
    // `released`, a dispatch `pressed` only (Hyprland 0.56): toggling on
    // `released` toggles exactly once for either kind of bind, which is why
    // the 3-finger swipe (a dispatch) keeps its `qs ipc call overview toggle`.
    GlobalShortcut {
        appid: "ewe"; name: "overview"
        description: "Toggle the Overview"
        onReleased: root.toggle()
    }
    // The 3-finger swipe up (a gesture action = a dispatch, which sends
    // `pressed` only): its own shortcut, toggling on pressed, so the swipe
    // needs no `qs ipc call` spawn either.
    GlobalShortcut {
        appid: "ewe"; name: "overview-swipe"
        description: "Toggle the Overview (swipe)"
        onPressed: root.toggle()
    }

    // ── the sequence ────────────────────────────────────────────────────────
    // open:  map (held) → wait for the captures (armed) → fly 0 → 1 (durSlow)
    //        with the bar and dock leaving on the same frame (overviewCover)
    // close: fly 1 → 0 (durBase) with the bar and dock coming back, then
    //        unmap under the cards — or, after a workspace switch, fade.
    NumberAnimation {
        id: flight
        target: root; property: "progress"
        easing.type: Theme.ease
        onFinished: if (!Globals.overviewOpen) root.settleClosed()
    }
    NumberAnimation {
        id: fadeOut
        target: root; property: "fade"
        from: 1; to: 0
        duration: Math.max(1, Theme.durBase)
        easing.type: Theme.easeFast
        onFinished: root.settleClosed()
    }
    function flyTo(to, dur) {
        flight.stop()
        flight.from = root.progress
        flight.to = to
        flight.duration = Math.max(1, dur)
        flight.start()
    }
    function settleClosed() {
        if (Globals.overviewOpen) return
        root.held = false
        root.armed = false
        root.fading = false
        root.fade = 1
        root.progress = 0
        root.dragActive = false
    }

    // cards register here so the open can wait for their first frame
    property var _cards: []
    function cardAdded(c) { root._cards = root._cards.concat([c]); root.checkArmed() }
    function cardRemoved(c) {
        var out = []
        for (var i = 0; i < root._cards.length; i++) if (root._cards[i] !== c) out.push(root._cards[i])
        root._cards = out
        root.checkArmed()
    }
    function checkArmed() {
        if (root.armed || !Globals.overviewOpen || !root.held) return
        for (var i = 0; i < root._cards.length; i++) if (!root._cards[i].ready) return
        root.go()
    }
    // the most the open ever waits for a capture
    Timer { id: armDeadline; interval: Math.max(1, Theme.durFast); onTriggered: root.go() }
    function go() {
        if (root.armed || !Globals.overviewOpen) return
        armDeadline.stop()
        root.armed = true
        Globals.overviewCover = true
        root.flyTo(1, Theme.reduceMotion ? Theme.durFast : Theme.durSlow)
    }

    Connections {
        target: Globals
        function onOverviewOpenChanged() {
            if (Globals.overviewOpen) {
                fadeOut.stop()
                root.fade = 1
                root.fading = false
                root.sel = -1
                if (root.held && root.armed) {
                    // reopened mid-close: the captures are still there
                    Globals.overviewCover = true
                    root.flyTo(1, Theme.reduceMotion ? Theme.durFast : Theme.durSlow)
                    return
                }
                root.openScreen = root.focusedScreenName()
                root.progress = 0
                root.armed = false
                root.held = true
                // fresh geometry for the flight's starting points (the
                // scrolling layout moves windows without an IPC event)
                Hyprland.refreshToplevels()
                armDeadline.restart()
                Qt.callLater(root.checkArmed)
            } else {
                armDeadline.stop()
                Globals.overviewCover = false
                root.dragActive = false
                if (!root.armed) { root.settleClosed(); return }
                if (root.fading && !Theme.reduceMotion) { flight.stop(); fadeOut.restart() }
                else root.flyTo(0, Theme.reduceMotion ? Theme.durFast : Theme.durBase)
            }
        }
    }

    // ── one Overview per monitor: each screen shows ITS active workspace ────
    Variants {
        model: Quickshell.screens

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData
        visible: Globals.overviewOpen || root.held
        color: "transparent"
        // the Overview owns the whole output; the bar and a dock plugin keep
        // their reserved strips (windows must not relayout) and translate
        // out of view (Globals.overviewCover)
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        // ONE window takes the keyboard — the output focused when it opened
        WlrLayershell.keyboardFocus: (Globals.overviewOpen && win.isFocused) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell:overview"
        anchors { top: true; bottom: true; left: true; right: true }
        // flying home: clicks fall through to the desktop
        mask: Globals.overviewOpen ? null : noInput
        Region { id: noInput }

        readonly property var hyMon: Hyprland.monitorFor(win.screen)
        readonly property bool isFocused: win.screen ? win.screen.name === root.openScreen : false
        readonly property int liveWs: hyMon && hyMon.activeWorkspace ? hyMon.activeWorkspace.id : root.focusedWs
        // the workspace the cards show — held still while the Overview fades
        // out after a switch, so the old cards don't turn into the new ones
        property int shownWs: -1
        Binding on shownWs { when: !root.fading; value: win.liveWs; restoreMode: Binding.RestoreNone }
        // Everything below is built only while this window is mapped: the
        // windows exist all session (hidden), and a closed Overview must cost
        // nothing — no cards, no layout, no bindings chasing window events.
        readonly property var winWins: {
            var out = []
            if (!win.visible) return out
            for (var i = 0; i < root.allWins.length; i++)
                if (root.wsOf(root.allWins[i]) === win.shownWs && !root.isHiddenTab(root.allWins[i])) out.push(root.allWins[i])
            return out
        }

        // the workspaces of this screen, for the strip. Each display owns a
        // block of ten ids (workspaces.lua): separate — the ones on this
        // screen; shared — every number in use on ANY display, as this
        // screen's own part of it (one set across all of them)
        readonly property var wsIds: {
            if (!win.visible) return []
            var ws = Hyprland.workspaces ? Hyprland.workspaces.values : []
            var name = win.screen ? win.screen.name : ""
            var block = Globals.wsBlock(win.shownWs)
            var seen = {}, out = []
            for (var i = 0; i < ws.length; i++) {
                var w = ws[i]
                if (!w || w.id < 1) continue
                var id = w.id
                if (Globals.workspacesShared) id = block * 10 + Globals.wsNumber(w.id)
                else if (w.monitor && name !== "" && w.monitor.name !== name) continue
                if (!seen[id]) { seen[id] = true; out.push(id) }
            }
            if (win.shownWs > 0 && !seen[win.shownWs]) out.push(win.shownWs)
            out.sort(function (a, b) { return a - b })
            return out
        }

        // ── geometry: real rects, the field, the spread ──
        readonly property var reals: {
            var out = []
            for (var i = 0; i < win.winWins.length; i++) out.push(root.realRect(win.winWins[i], win.hyMon))
            return out
        }
        readonly property real fieldX: Theme.spaceXl
        readonly property real fieldY: strip.restH + Theme.spaceLg
        readonly property real fieldW: Math.max(1, win.width - 2 * Theme.spaceXl)
        readonly property real fieldH: Math.max(1, win.height - win.fieldY - Theme.spaceLg - Theme.controlMd)
        readonly property var targets: {
            var items = []
            for (var i = 0; i < win.reals.length; i++)
                items.push(win.reals[i] || { x: win.width / 4, y: win.height / 4, w: win.width / 2, h: win.height / 2 })
            var t = root.spread(items, win.fieldW, win.fieldH)
            for (i = 0; i < t.length; i++) { t[i].x += win.fieldX; t[i].y += win.fieldY }
            return t
        }

        readonly property string wall: win.screen ? Wallpaper.pathFor(win.screen.name) : ""
        readonly property url wallSource: win.wall ? "file://" + win.wall : ""
        // decoded at the SCREEN's size, never the window's — Wallpaper.qml
        // warms this exact cache key at shell start, so nothing decodes on
        // open; every Image below with this source + size shares one texture
        readonly property size wallSize: win.screen ? Qt.size(win.screen.width, win.screen.height) : Qt.size(0, 0)

        // keyboard: Esc closes, arrows move, Enter opens. Nothing to type.
        FocusScope {
            id: scope
            anchors.fill: parent
            focus: true
            Keys.onPressed: function (ev) {
                var n = win.winWins.length
                if (ev.key === Qt.Key_Escape) { root.close(); ev.accepted = true }
                else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                    if (n > 0) root.jump(win.winWins[Math.max(0, Math.min(root.sel, n - 1))])
                    else root.close()
                    ev.accepted = true
                } else if (ev.key === Qt.Key_Left || ev.key === Qt.Key_Up || ev.key === Qt.Key_Backtab) {
                    if (n > 0) root.sel = root.sel < 0 ? n - 1 : (root.sel - 1 + n) % n
                    ev.accepted = true
                } else if (ev.key === Qt.Key_Right || ev.key === Qt.Key_Down || ev.key === Qt.Key_Tab) {
                    if (n > 0) root.sel = root.sel < 0 ? 0 : (root.sel + 1) % n
                    ev.accepted = true
                }
            }

        Item {
            id: stage
            anchors.fill: parent
            // nothing draws until the captures are in; Reduce motion
            // cross-fades the whole stage instead of flying it
            opacity: (root.armed ? 1 : 0) * root.fade * (Theme.reduceMotion ? root.progress : 1)

            // ── the backdrop: the wallpaper and a dim. It fades with the
            //    flight, so the bar, the dock and the gaps between windows
            //    go smoothly; the patches below hide the windows at once ──
            Item {
                id: backdrop
                anchors.fill: parent
                opacity: Theme.reduceMotion ? 1 : root.progress
                Rectangle { anchors.fill: parent; color: Theme.surfaceSunken }   // the ground, and a video wallpaper's stand-in
                Image {
                    anchors.fill: parent
                    source: win.wallSource
                    sourceSize: win.wallSize
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                }
                MouseArea { anchors.fill: parent; onClicked: root.close() }
            }

            // ── patches: the wallpaper over each window's REAL spot, from
            //    the first frame, so the live window behind the overlay
            //    never shows next to its flying card. spaceXs wider all
            //    round for Hyprland's border. ──
            Repeater {
                model: Theme.reduceMotion ? [] : win.winWins
                delegate: Item {
                    required property int index
                    readonly property var r: win.reals[index]
                    visible: !!r
                    x: r ? r.x - Theme.spaceXs : 0
                    y: r ? r.y - Theme.spaceXs : 0
                    width: r ? r.w + 2 * Theme.spaceXs : 0
                    height: r ? r.h + 2 * Theme.spaceXs : 0
                    clip: true
                    Rectangle { x: -parent.x; y: -parent.y; width: win.width; height: win.height; color: Theme.surfaceSunken }
                    Image {
                        x: -parent.x; y: -parent.y
                        width: win.width; height: win.height
                        source: win.wallSource
                        sourceSize: win.wallSize
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }
                }
            }

            // the dim over both, under the cards: half the scrim, as the
            // flight lands (the shipped wallpapers are dark already)
            Rectangle {
                anchors.fill: parent
                color: Theme.scrim
                opacity: root.progress / 2
            }

            // ══ WINDOW CARDS ══════════════════════════════════════════════
            Item {
                id: cardLayer
                anchors.fill: parent
                // the strip's thumbnails push the spread down: the field
                // shrinks toward its bottom edge — one transform, so the
                // windows never re-arrange (a relayout flipped 3 rows to 2
                // under the pointer). Scaled by `fly`, so a card that starts
                // over its window starts exactly there.
                readonly property real push: strip.height - strip.restH
                transform: Scale {
                    origin.x: win.width / 2
                    origin.y: win.fieldY + win.fieldH
                    xScale: 1 - (win.fieldH > 0 ? cardLayer.push / win.fieldH : 0) * root.fly
                    yScale: xScale
                }

                Repeater {
                    model: win.winWins
                    delegate: Item {
                        id: card
                        required property var modelData
                        required property int index
                        // the open waits for this (Quickshell has no capture
                        // for a toplevel without a Wayland handle)
                        readonly property bool ready: sc.hasContent || !modelData.wayland || !win.visible
                        onReadyChanged: if (ready) root.checkArmed()
                        Component.onCompleted: root.cardAdded(card)
                        Component.onDestruction: root.cardRemoved(card)

                        readonly property var home: win.reals[index] || null
                        readonly property var target: index < win.targets.length ? win.targets[index] : { x: 0, y: 0, w: 0, h: 0 }
                        // a window without geometry yet starts where it lands
                        readonly property var start: card.home || card.target
                        readonly property real f: root.fly
                        x: card.start.x + (card.target.x - card.start.x) * f
                        y: card.start.y + (card.target.y - card.start.y) * f
                        width: card.start.w + (card.target.w - card.start.w) * f
                        height: card.start.h + (card.target.h - card.start.h) * f
                        // the desktop's own stacking while near it; the
                        // selected card lifts once spread
                        z: root.stackOf(modelData) + (card.seld ? 10 : 0)

                        readonly property bool seld: root.settled && win.isFocused && root.sel === index
                        readonly property bool hot: root.settled && (cardMa.containsMouse || closeMa.containsMouse)
                        // ✕ drops this card's capture first and closes the
                        // window a beat later (the toplevel-capture race)
                        property bool closing: false
                        Timer { id: closeLater; interval: Math.max(1, Theme.durFast); onTriggered: root.killWin(card.modelData) }

                        RectangularShadow {
                            anchors.fill: content
                            visible: !cardMa.drag.active
                            radius: Theme.radiusRounded
                            offset.x: Theme.shadowFloat.x; offset.y: Theme.shadowFloat.y
                            blur: Theme.shadowFloat.blur
                            color: Theme.shadowFloat.color
                            opacity: root.fly
                        }

                        ClippingRectangle {
                            id: content
                            width: card.width; height: card.height
                            radius: Theme.radiusRounded
                            color: Theme.surfaceRaised

                            Drag.active: cardMa.drag.active
                            Drag.source: card
                            Drag.hotSpot.x: width / 2
                            Drag.hotSpot.y: height / 2
                            Drag.keys: ["overview-window"]
                            // lifted out of the card while dragging (ParentChange
                            // restores x/y on release)
                            states: State {
                                name: "dragging"; when: cardMa.drag.active
                                ParentChange { target: content; parent: dragLayer }
                                PropertyChanges { target: content; opacity: Theme.opacityGlass; scale: 0.5 }
                            }

                            // one frame, captured as the Overview opens. Captures
                            // live ONLY while the surface is mapped: a toplevel
                            // capture racing a window close gets the whole shell
                            // disconnected by Hyprland 0.56 ("invalid object N").
                            ScreencopyView {
                                id: sc
                                anchors.fill: parent
                                visible: hasContent
                                captureSource: (win.visible && !card.closing && card.modelData.wayland) || null
                                live: false
                            }
                            Image {
                                anchors.centerIn: parent
                                visible: !sc.hasContent
                                width: Theme.icon3xl; height: Theme.icon3xl
                                sourceSize.width: 2 * Theme.icon3xl; sourceSize.height: 2 * Theme.icon3xl; mipmap: true
                                source: root.iconFor(card.modelData)
                            }
                        }

                        // the hover/selection ring, outside the picture
                        Rectangle {
                            anchors.fill: content
                            anchors.margins: -Theme.borderWidth2
                            visible: card.seld || card.hot
                            color: "transparent"
                            radius: Theme.radiusRounded + Theme.borderWidth2
                            border.color: Theme.accent
                            border.width: Theme.borderWidth2
                        }

                        MouseArea {
                            id: cardMa
                            anchors.fill: parent
                            enabled: Globals.overviewOpen
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            drag.target: content
                            drag.smoothed: false
                            property bool didDrag: false
                            onPressed: didDrag = false
                            // the highlight follows the pointer (and the arrows)
                            onContainsMouseChanged: {
                                if (!win.isFocused) return
                                if (containsMouse) root.sel = card.index
                                else if (root.sel === card.index) root.sel = -1
                            }
                            onPositionChanged: if (drag.active) { didDrag = true; root.dragActive = true }
                            onClicked: if (!didDrag) root.jump(card.modelData)
                            // the drop is hit-tested against the strip (the
                            // ParentChange snaps the content back the instant
                            // the drag ends, racing a DropArea's drop event)
                            onReleased: function (mouse) {
                                // hit-test BEFORE the strip starts closing (dragActive)
                                var ws = didDrag ? strip.wsAt(cardMa.mapToItem(strip, mouse.x, mouse.y)) : -1
                                root.dragActive = false
                                if (!didDrag) return
                                if (ws > 0) root.moveWin(card.modelData, ws)
                                else if (ws === 0) root.moveToNew(card.modelData, win.shownWs, win.wsIds)
                            }
                        }

                        // close — top-left, where a window's own close sits on macOS
                        Rectangle {
                            anchors.top: parent.top; anchors.left: parent.left
                            anchors.margins: Theme.spaceS
                            width: Theme.controlMd; height: Theme.controlMd
                            radius: Theme.radiusFull
                            visible: card.hot && !cardMa.drag.active
                            color: closeMa.containsMouse ? Theme.danger : Theme.glassRaised
                            border.color: closeMa.containsMouse ? Theme.danger : Theme.glassBorder
                            border.width: Theme.borderWidth1
                            Text {
                                anchors.fill: parent
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                text: Theme.icClose; font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
                                color: closeMa.containsMouse ? Theme.onStatus : Theme.textPrimary
                            }
                            MouseArea {
                                id: closeMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { card.closing = true; closeLater.restart() }
                            }
                        }

                        // a group: the tabs' icons and their count in a Glass
                        // pill on the top right — this card is the tab on top,
                        // the others sit behind it in Hyprland's groupbar
                        readonly property var tabs: root.tabsOf(card.modelData)
                        Rectangle {
                            visible: card.tabs.length > 1 && !cardMa.drag.active
                            anchors.top: parent.top; anchors.right: parent.right
                            anchors.margins: Theme.spaceS
                            width: tabRow.implicitWidth + 2 * Theme.spaceS
                            height: Theme.controlMd
                            radius: Theme.radiusFull
                            color: Theme.glassRaised
                            border.color: Theme.glassBorder; border.width: Theme.borderWidth1
                            opacity: root.fly
                            Row {
                                id: tabRow
                                anchors.centerIn: parent
                                spacing: Theme.spaceXs
                                Repeater {
                                    model: card.tabs.slice(0, 4)
                                    delegate: Image {
                                        required property var modelData
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Theme.iconMd; height: Theme.iconMd
                                        sourceSize.width: 2 * Theme.iconMd; sourceSize.height: 2 * Theme.iconMd; mipmap: true
                                        source: root.iconFor(modelData)
                                        opacity: modelData === card.modelData ? 1 : Theme.opacityGlass
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: card.tabs.length + " tabs"
                                    color: Theme.textSecondary
                                    font.family: Theme.type.caption.family
                                    font.pixelSize: Theme.type.caption.size
                                    font.weight: Theme.fontWeightMedium
                                    font.features: ({ "tnum": 1 })
                                }
                            }
                        }

                        // the title, under the card while it is pointed at or
                        // selected (macOS shows it the same way)
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom; anchors.topMargin: Theme.spaceS
                            visible: (card.seld || card.hot) && !cardMa.drag.active
                            width: Math.min(chip.implicitWidth + 2 * Theme.spaceS, Math.max(card.width, Theme.panelSm))
                            height: Theme.controlMd
                            radius: Theme.radiusFull
                            color: Theme.glassRaised
                            border.color: Theme.glassBorder; border.width: Theme.borderWidth1
                            Row {
                                id: chip
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, parent.width - 2 * Theme.spaceS)
                                spacing: Theme.spaceXs
                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.iconMd; height: Theme.iconMd
                                    sourceSize.width: 2 * Theme.iconMd; sourceSize.height: 2 * Theme.iconMd; mipmap: true
                                    source: root.iconFor(card.modelData)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, chip.parent.width - Theme.iconMd - 3 * Theme.spaceS)
                                    text: root.titleOf(card.modelData)
                                    elide: Text.ElideRight
                                    color: Theme.textPrimary
                                    font.family: Theme.type.label.family
                                    font.pixelSize: Theme.type.label.size
                                    font.weight: Theme.fontWeightMedium
                                }
                            }
                        }

                        Accessible.role: Accessible.Button
                        Accessible.name: root.classOf(modelData) + ", " + root.titleOf(modelData) + ", workspace " + Globals.wsNumber(win.shownWs)
                                         + (card.tabs.length > 1 ? ", a group of " + card.tabs.length + " tabs" : "")
                    }
                }
            }

            // ══ WORKSPACE STRIP ══════════════════════════════════════════
            // Labels at rest; pointing at it (or dragging a window up)
            // slides the thumbnails down. It comes down from above the
            // screen with the flight.
            Item {
                id: strip
                anchors.left: parent.left; anchors.right: parent.right
                // where the strip rests (the field starts under this)
                readonly property real restH: Theme.spaceS + Theme.controlMd + Theme.spaceS
                readonly property bool open: Globals.overviewOpen && (stripHov.hovered || root.dragActive)
                readonly property real thumbH: Math.max(2 * Theme.control2xl, Math.round(win.height / 9))
                readonly property real thumbW: Math.round(strip.thumbH * (win.height > 0 ? win.width / win.height : 1.6))
                // 0 → 1 as the thumbnails slide down
                property real reveal: strip.open ? 1 : 0
                Behavior on reveal { NumberAnimation { duration: Theme.reduceMotion ? 0 : Theme.durBase; easing.type: Theme.ease } }
                height: strip.restH + strip.reveal * (strip.thumbH + Theme.spaceS)
                y: (root.fly - 1) * strip.restH
                opacity: root.progress
                z: 5

                HoverHandler { id: stripHov }

                // the band behind the thumbnails, only while they show
                Rectangle {
                    anchors.fill: parent
                    color: Theme.glassBase
                    opacity: strip.reveal
                    Rectangle {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        height: Theme.borderWidth1
                        color: Theme.glassBorder
                    }
                }

                // the workspace whose thumbnail or label is under a point
                // (strip coordinates); 0 = the strip with no workspace under
                // the point (its "+", or the band beside them — a drop there
                // makes a new workspace); -1 = not on the strip
                function wsAt(p) {
                    var q = strip.mapToItem(wsRow, p.x, p.y)
                    var c = wsRow.childAt(q.x, q.y)
                    if (c && c.wsId !== undefined) return c.wsId
                    return (p.x >= 0 && p.x <= strip.width && p.y >= 0 && p.y <= strip.height) ? 0 : -1
                }

                Row {
                    id: wsRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Theme.spaceS
                    spacing: Theme.spaceMd

                    Repeater {
                        model: win.wsIds
                        delegate: Item {
                            id: ws
                            required property int modelData
                            readonly property int wsId: modelData
                            readonly property bool current: ws.wsId === win.shownWs
                            readonly property bool dropHot: dropArea.containsDrag
                            readonly property bool hot: wsMa.containsMouse || ws.dropHot
                            width: Math.max(strip.thumbW * strip.reveal, label.width)
                            height: strip.reveal * (strip.thumbH + Theme.spaceS) + Theme.controlMd

                            // the thumbnail: wallpaper (the backdrop's texture)
                            // and the workspace's windows as shapes at their
                            // real places, each with its app icon
                            Rectangle {
                                id: thumb
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: strip.thumbW; height: strip.thumbH
                                visible: strip.reveal > 0
                                opacity: strip.reveal
                                transform: Translate { y: (strip.reveal - 1) * strip.thumbH }
                                radius: Theme.radiusPrimary
                                color: Theme.surfaceSunken
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    source: win.wallSource
                                    sourceSize: win.wallSize
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    smooth: true
                                }
                                Repeater {
                                    model: {
                                        var out = []
                                        if (strip.reveal <= 0) return out
                                        for (var i = 0; i < root.allWins.length; i++)
                                            if (root.wsOf(root.allWins[i]) === ws.wsId && !root.isHiddenTab(root.allWins[i])) out.push(root.allWins[i])
                                        return out
                                    }
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property var r: root.realRect(modelData, win.hyMon)
                                        readonly property real k: win.width > 0 ? thumb.width / win.width : 0
                                        visible: !!r
                                        x: r ? Math.round(r.x * k) : 0
                                        y: r ? Math.round(r.y * k) : 0
                                        width: r ? Math.max(Theme.spaceS, Math.round(r.w * k)) : 0
                                        height: r ? Math.max(Theme.spaceS, Math.round(r.h * k)) : 0
                                        radius: Theme.radiusSlight
                                        color: Theme.surfaceRaised
                                        border.color: Theme.glassBorder; border.width: Theme.borderWidth1
                                        Image {
                                            anchors.centerIn: parent
                                            readonly property int px: Math.min(Theme.iconLg, Math.round(parent.height * 0.6), Math.round(parent.width * 0.6))
                                            width: px; height: px
                                            sourceSize.width: 2 * Theme.iconLg; sourceSize.height: 2 * Theme.iconLg; mipmap: true
                                            source: root.iconFor(modelData)
                                        }
                                    }
                                }
                                // current: accent frame; a drop target or hover: brighter
                                Rectangle {
                                    anchors.fill: parent
                                    color: ws.hot ? Theme.glassHover : "transparent"
                                    radius: Theme.radiusPrimary
                                    border.color: (ws.current || ws.dropHot) ? Theme.accent : Theme.glassBorder
                                    border.width: (ws.current || ws.dropHot) ? Theme.borderWidth2 : Theme.borderWidth1
                                }
                            }

                            // the label — all there is while the strip rests
                            Rectangle {
                                id: label
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                width: labelText.implicitWidth + 2 * Theme.spaceS + Theme.spaceXs
                                height: Theme.controlMd
                                radius: Theme.radiusFull
                                color: ws.current ? Theme.accentSubtle
                                     : (ws.hot && strip.reveal < 1) ? Theme.glassHover : Theme.glassBase
                                border.color: ws.current ? Theme.accent : Theme.glassBorder
                                border.width: Theme.borderWidth1
                                Text {
                                    id: labelText
                                    anchors.centerIn: parent
                                    text: "Workspace " + Globals.wsNumber(ws.wsId)
                                    color: ws.current ? Theme.accentText : Theme.textPrimary
                                    font.family: Theme.type.label.family
                                    font.pixelSize: Theme.type.label.size
                                    font.weight: ws.current ? Theme.fontWeightSemibold : Theme.fontWeightMedium
                                    font.features: ({ "tnum": 1 })
                                }
                            }

                            DropArea { id: dropArea; anchors.fill: parent; keys: ["overview-window"] }
                            MouseArea {
                                id: wsMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.gotoWs(ws.wsId)
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Workspace " + Globals.wsNumber(ws.wsId)
                        }
                    }

                    // "+" — the new-workspace target, only while a window is
                    // being dragged (and a number is free): the same cell as
                    // a thumbnail, outlined, with a plus; dropping on the
                    // band beside the workspaces does the same (wsAt → 0)
                    Item {
                        id: newWs
                        readonly property int wsId: 0
                        visible: root.dragActive && win.wsIds.length < 10
                        readonly property bool dropHot: newDrop.containsDrag
                        width: Math.max(strip.thumbW * strip.reveal, newLabel.width)
                        height: strip.reveal * (strip.thumbH + Theme.spaceS) + Theme.controlMd

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: strip.thumbW; height: strip.thumbH
                            visible: strip.reveal > 0
                            opacity: strip.reveal
                            transform: Translate { y: (strip.reveal - 1) * strip.thumbH }
                            radius: Theme.radiusPrimary
                            color: newWs.dropHot ? Theme.glassHover : "transparent"
                            border.color: newWs.dropHot ? Theme.accent : Theme.glassBorder
                            border.width: newWs.dropHot ? Theme.borderWidth2 : Theme.borderWidth1
                            Text {
                                anchors.centerIn: parent
                                text: Theme.icPlus
                                font.family: Theme.fontIcons
                                font.pixelSize: Theme.iconXl
                                color: newWs.dropHot ? Theme.accentText : Theme.textSecondary
                            }
                        }
                        Rectangle {
                            id: newLabel
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: newLabelText.implicitWidth + 2 * Theme.spaceS + Theme.spaceXs
                            height: Theme.controlMd
                            radius: Theme.radiusFull
                            color: newWs.dropHot ? Theme.accentSubtle : Theme.glassBase
                            border.color: newWs.dropHot ? Theme.accent : Theme.glassBorder
                            border.width: Theme.borderWidth1
                            Text {
                                id: newLabelText
                                anchors.centerIn: parent
                                text: "New workspace"
                                color: newWs.dropHot ? Theme.accentText : Theme.textPrimary
                                font.family: Theme.type.label.family
                                font.pixelSize: Theme.type.label.size
                                font.weight: Theme.fontWeightMedium
                            }
                        }
                        DropArea { id: newDrop; anchors.fill: parent; keys: ["overview-window"] }
                        Accessible.role: Accessible.Button
                        Accessible.name: "New workspace"
                    }
                }
            }

            // the dragged card floats here (above the strip, unclipped)
            Item { id: dragLayer; anchors.fill: parent; z: 20 }
        }
        }   // FocusScope
    }
    }
}
