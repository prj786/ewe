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
        height: Theme.controlXl
        Rectangle {
            anchors.fill: parent; radius: Theme.radiusPrimary
            // pointing at a row is how it gets selected, so both are glassHover
            color: rr.seld || rrMa.containsMouse ? Theme.glassHover : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
        }
        Row {
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
            spacing: Theme.spaceS + Theme.spaceXs
            Item {
                width: Theme.iconXl; height: Theme.iconXl
                anchors.verticalCenter: parent.verticalCenter
                Image {
                    visible: rr.icon !== ""
                    anchors.fill: parent
                    sourceSize.width: 2 * Theme.iconXl; sourceSize.height: 2 * Theme.iconXl; mipmap: true
                    source: rr.icon
                }
                Rectangle {
                    visible: rr.icon === ""
                    anchors.fill: parent; radius: Theme.radiusSecondary
                    color: Theme.glassHover
                    Text { anchors.centerIn: parent; text: rr.glyph; font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: Theme.textSecondary }
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Theme.iconXl - (Theme.spaceS + Theme.spaceXs) - tagLbl.implicitWidth - Theme.spaceS
                Text { width: parent.width; text: rr.title; elide: Text.ElideRight; color: Theme.textPrimary; font.family: Theme.type.bodyStrong.family; font.pixelSize: Theme.type.bodyStrong.size; font.weight: Theme.fontWeightMedium }
                // inside Glass, text-muted remaps to text-secondary (Glass card)
                Text { visible: rr.sub !== ""; width: parent.width; text: rr.sub; elide: Text.ElideRight; color: Theme.textSecondary; font.family: Theme.type.caption.family; font.pixelSize: Theme.type.caption.size }
            }
        }
        Text {
            id: tagLbl
            anchors.right: parent.right; anchors.rightMargin: Theme.spaceS + Theme.spaceXs
            anchors.verticalCenter: parent.verticalCenter
            text: rr.tag
            color: Theme.textSecondary; font.family: Theme.type.caption.family; font.pixelSize: Theme.type.caption.size
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
    function launchApp(a) { Globals.launchEntry(a, false); root.close() }
    function jump(tl) {
        // by ADDRESS, so a window on another workspace (a "Jump to" result)
        // takes you there; the foreign-toplevel activate does not switch
        var a = root.addrOf(tl)
        if (a !== "") Hyprland.dispatch('hl.dsp.focus({ window = "address:' + a + '" })')
        else if (tl && tl.wayland) tl.wayland.activate()
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

    // ── window-group map: address → member count ──
    // Queried straight from `hyprctl -j clients` (its `grouped` field lists the
    // whole group, self included). NOT read from lastIpcObject: Quickshell only
    // refreshes that on window open/close/move, so grouping done while the
    // overview is closed would never show up.
    property var groupsByAddr: ({})
    property Process _groupProc: Process {
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector { onStreamFinished: {
            var m = {}
            try {
                var arr = JSON.parse(this.text)
                for (var i = 0; i < arr.length; i++)
                    if (arr[i].grouped && arr[i].grouped.length) m[arr[i].address] = arr[i].grouped.length
            } catch (e) {}
            root.groupsByAddr = m
        } }
    }
    function refreshGroups() { root._groupProc.running = false; root._groupProc.running = true }
    // keep the map live while open — group membership can change under the
    // overview (keybinds fire through it); cheap enough to just re-query
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (!Globals.overviewOpen) return
            var n = ev.name
            if (n.indexOf("group") >= 0 || n === "openwindow" || n === "closewindow") root.refreshGroups()
        }
    }

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
        // open pre-filled (scripting / keybinds like "Super+F → find") — sets
        // root.query; each window's search box mirrors it (Connections below)
        function find(q: string): void { Globals.overviewOpen = true; root.query = q }
    }

    // The window stays mapped through the QML close animation via `held`, which
    // flips true on OPEN and only drops when closeTimer fires. Binding visible
    // to `closeTimer.running` directly was a signal-order race: on close, the
    // visible binding (connected later, notified first) saw open=false with the
    // timer not yet started and unmapped the surface instantly — then the
    // Connections handler started the timer, remapping it mid-fade, and the
    // timer expiring unmapped it again. Gone, back, gone: the blink.
    property bool held: false
    Timer { id: closeTimer; interval: Math.max(1, Theme.durSlow + 60); onTriggered: root.held = false }
    Connections {
        target: Globals
        function onOverviewOpenChanged() {
            if (Globals.overviewOpen) { closeTimer.stop(); root.held = true; root.refreshGroups() }
            else closeTimer.restart()
        }
    }

    // ── one overview per monitor: each screen shows ITS active workspace's
    //    windows; the search UI lives on the focused screen only ──
    Variants {
        model: Quickshell.screens

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData
        visible: Globals.overviewOpen || root.held
        color: "transparent"
        // IGNORE exclusive zones so the scrim runs under the dock (the dock
        // jumps to the Overlay layer while the overview is open and draws on
        // top) — an always-visible dock's reserved strip used to cut the
        // backdrop off above it. Only the bar keeps its space, via a margin.
        exclusionMode: ExclusionMode.Ignore
        margins.top: Globals.barVisible ? Theme.barHeight : 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell:overview"
        anchors { top: true; bottom: true; left: true; right: true }

        // this screen's Hyprland monitor + its active workspace and windows
        readonly property var hyMon: Hyprland.monitorFor(win.screen)
        readonly property int winWs: hyMon && hyMon.activeWorkspace ? hyMon.activeWorkspace.id : root.focusedWs
        readonly property bool isFocused: win.winWs === root.focusedWs
        readonly property var winWins: {
            var out = []
            for (var i = 0; i < root.allWins.length; i++)
                if (root.wsOf(root.allWins[i]) === win.winWs) out.push(root.allWins[i])
            return out
        }

        onVisibleChanged: if (visible) Qt.callLater(function () { search.text = ""; root.query = ""; if (win.isFocused) search.forceActiveFocus() })
        Connections {
            target: Globals
            function onOverviewOpenChanged() { if (Globals.overviewOpen && win.isFocused) search.forceActiveFocus() }
        }
        // mirror an externally-set query (IPC find) into this window's box
        Connections {
            target: root
            function onQueryChanged() { if (search.text !== root.query) search.text = root.query }
        }

        // ── the backdrop: the WALLPAPER, opaque, not a see-through scrim ──
        // A 45 % scrim left every real window visible behind its own card, so
        // each app was on screen twice — live, and as a thumbnail floating
        // over itself. GNOME's overview never shows the live windows: it
        // shows the wallpaper, dimmed, and the cards on top of that. Same
        // here. The image is blurred so the cards read against any picture,
        // and a video wallpaper (which Image cannot draw) falls back to a
        // flat ground. Click anywhere on it to dismiss.
        Item {
            id: backdrop
            anchors.fill: parent
            opacity: Globals.overviewOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? Theme.durFast : Theme.durSlow; easing.type: Theme.easeSlow } }

            readonly property string wall: win.screen ? Wallpaper.pathFor(win.screen.name) : ""

            Rectangle { anchors.fill: parent; color: Theme.surfaceSunken }   // opaque ground, always
            Image {
                id: wallImg
                anchors.fill: parent
                source: backdrop.wall ? "file://" + backdrop.wall : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                // decoded at screen size, not the file's — a 6000px photo
                // would otherwise cost tens of MB of texture per monitor
                sourceSize: Qt.size(win.width, win.height)
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: wallImg
                visible: wallImg.status === Image.Ready
                blurEnabled: true
                // the card's own backdrop: blurGlass, brightness 0.82,
                // saturate 0.85 (Overview card #1 / .ewe-ov__bg)
                blurMax: Theme.blurGlass
                blur: 1.0
                // dimmed, but not to black: the shipped wallpapers are already
                // near-black gradients, and any darker reads as no wallpaper
                // at all. A bright photo still drops far enough for cards.
                brightness: -0.18
                saturation: -0.15
            }
            MouseArea { anchors.fill: parent; onClicked: root.close() }
        }

        // ── the stage: GNOME-like zoom out on open, zoom back in on close ──
        Item {
            id: stage
            anchors.fill: parent
            // opens with a slight zoom and fade at durSlow, closes in the
            // reverse; Reduce motion drops the zoom to a durFast fade
            opacity: Globals.overviewOpen ? 1 : 0
            scale: (Globals.overviewOpen || Theme.reduceMotion) ? 1 : 1.10
            transformOrigin: Item.Center
            Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? Theme.durFast : Theme.durSlow; easing.type: Theme.easeSlow } }
            Behavior on scale   { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeSlow } }

            readonly property real monAR: (win.screen && win.screen.height > 0) ? (win.screen.width / win.screen.height) : 1.6

            // ══ WINDOW CARDS — always present; dim + freeze while searching ═══
            Flickable {
                id: cardArea
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: searchBox.bottom; anchors.topMargin: Theme.spaceLg
                anchors.bottom: pagerRow.top; anchors.bottomMargin: Theme.spaceMd
                clip: true
                contentWidth: width
                contentHeight: Math.max(height, cardLayout.blockH + 2 * Theme.spaceMd)
                boundsBehavior: Flickable.StopAtBounds
                interactive: !root.searching
                opacity: root.searching ? 0.35 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }

                // ── GNOME-style organic packing ─────────────────────────────
                // Every card keeps ITS OWN window's aspect ratio; a row shares
                // one height and rows scale down as the desktop gets busier.
                // Different window shapes → different card widths → the field
                // reads natural instead of an arithmetic grid of identical
                // monitor-shaped rectangles.
                readonly property real fieldW: Math.max(1, width - 2 * Theme.spaceLg)
                readonly property real fieldH: Math.max(1, height - Theme.spaceMd)
                readonly property var cardLayout: computeLayout(win.winWins, fieldW, fieldH)
                function computeLayout(wins, W, H) {
                    var n = wins.length
                    if (n === 0) return { rects: [], blockH: 0 }
                    // 16px between rows, 24px between cards in a row
                    var gap = Theme.spaceMd + Theme.spaceS
                    var rowGap = Theme.spaceMd
                    // window aspect from the real geometry; monitor aspect as
                    // fallback; clamped so one extreme window can't starve a row
                    var asp = []
                    for (var i = 0; i < n; i++) {
                        var o = wins[i].lastIpcObject
                        var a = (o && o.size && o.size[1] > 0) ? o.size[0] / o.size[1] : stage.monAR
                        asp.push(Math.max(0.5, Math.min(2.4, a)))
                    }
                    // try 1..4 rows of contiguous chunks; keep whichever uses
                    // the most area (the classic shell-overview heuristic)
                    var best = null
                    for (var rows = 1; rows <= Math.min(n, 4); rows++) {
                        var per = Math.ceil(n / rows)
                        var rr = []
                        for (var r = 0; r < rows; r++) {
                            var chunk = asp.slice(r * per, (r + 1) * per)
                            if (chunk.length) rr.push(chunk)
                        }
                        var h = (H - (rr.length - 1) * rowGap) / rr.length
                        for (r = 0; r < rr.length; r++) {
                            var sum = 0
                            for (var k = 0; k < rr[r].length; k++) sum += rr[r][k]
                            var hr = (W - (rr[r].length - 1) * gap) / sum
                            if (hr < h) h = hr
                        }
                        h = Math.min(h, H * (n <= 2 ? 0.55 : 0.78))
                        var area = 0
                        for (r = 0; r < rr.length; r++)
                            for (k = 0; k < rr[r].length; k++) area += rr[r][k] * h * h
                        if (!best || area > best.area) best = { rr: rr, h: h, area: area }
                    }
                    var blockH = best.rr.length * best.h + (best.rr.length - 1) * rowGap
                    var rects = []
                    var y = 0
                    for (r = 0; r < best.rr.length; r++) {
                        var rowW = (best.rr[r].length - 1) * gap
                        for (k = 0; k < best.rr[r].length; k++) rowW += best.rr[r][k] * best.h
                        var x = (W - rowW) / 2
                        for (k = 0; k < best.rr[r].length; k++) {
                            var wpx = best.rr[r][k] * best.h
                            rects.push({ x: Math.round(x), y: Math.round(y), w: Math.round(wpx), h: Math.round(best.h) })
                            x += wpx + gap
                        }
                        y += best.h + rowGap
                    }
                    return { rects: rects, blockH: blockH }
                }

                Item {
                    id: cardField
                    x: Theme.spaceLg
                    y: Math.max(Theme.spaceS, (cardArea.height - cardArea.cardLayout.blockH) / 2)
                    width: cardArea.fieldW
                    height: cardArea.cardLayout.blockH

                    Repeater {
                        model: win.winWins
                        delegate: MouseArea {
                            id: dragArea
                            required property var modelData
                            required property int index
                            readonly property bool seld: win.isFocused && index === root.sel && !root.searching
                            readonly property int groupN: root.groupsByAddr[root.addrOf(modelData)] || 0
                            readonly property var rect: index < cardArea.cardLayout.rects.length
                                ? cardArea.cardLayout.rects[index] : { x: 0, y: 0, w: 0, h: 0 }
                            x: rect.x; y: rect.y
                            width: rect.w; height: rect.h
                            // cards glide to their new spot when the set changes
                            Behavior on x { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
                            Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
                            Behavior on width { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
                            Behavior on height { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
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
                                radius: Theme.radiusRounded
                                color: Theme.black
                                visible: false
                            }
                            // shadowFloat, the one shadow a floating surface gets
                            Elevation {
                                anchors.fill: shadowProxy
                                source: shadowProxy
                                visible: !dragArea.drag.active
                            }

                            // ClippingRectangle: children (preview, chip) clip to the rounded border
                            ClippingRectangle {
                                id: cardContent
                                width: dragArea.width
                                height: dragArea.height
                                radius: Theme.radiusRounded
                                color: Theme.surfaceRaised
                                // selected takes a borderWidth2 accent outline
                                border.color: dragArea.seld ? Theme.accent : Theme.glassBorder
                                border.width: dragArea.seld ? Theme.borderWidth2 : Theme.borderWidth1

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
                                    width: Theme.icon3xl; height: Theme.icon3xl
                                    sourceSize.width: 2 * Theme.icon3xl; sourceSize.height: 2 * Theme.icon3xl; mipmap: true
                                    source: root.iconFor(dragArea.modelData)
                                }

                                // title chip — Glass, centred at the bottom,
                                // semibold in textPrimary while selected
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.spaceS
                                    width: Math.min(titleLbl.implicitWidth + 2 * Theme.spaceS,
                                                    cardContent.width - Theme.spaceMd)
                                    height: Theme.controlMd
                                    radius: Theme.radiusPrimary
                                    color: Theme.glassBase
                                    border.color: Theme.glassBorder; border.width: Theme.borderWidth1
                                    Text {
                                        id: titleLbl
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        text: root.titleOf(dragArea.modelData)
                                        color: dragArea.seld ? Theme.textPrimary : Theme.textSecondary
                                        font.family: Theme.type.label.family
                                        font.pixelSize: Theme.type.label.size
                                        font.weight: dragArea.seld ? Theme.fontWeightSemibold : Theme.fontWeightRegular
                                        elide: Text.ElideRight
                                    }
                                }

                                // app badge — top right: the app's icon, plus a
                                // `layers` glyph and the count when this window
                                // is one tab of a group (Overview card #4)
                                Rectangle {
                                    id: appBadge
                                    anchors.top: parent.top; anchors.right: parent.right
                                    anchors.margins: Theme.spaceS
                                    width: badgeRow.implicitWidth + 2 * Theme.spaceXs
                                    height: Theme.controlLg
                                    radius: Theme.radiusPrimary
                                    color: Theme.glassBase
                                    border.color: Theme.glassBorder; border.width: Theme.borderWidth1
                                    Row {
                                        id: badgeRow
                                        anchors.centerIn: parent; spacing: Theme.spaceXs
                                        Image {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Theme.iconLg; height: Theme.iconLg
                                            sourceSize.width: 2 * Theme.iconLg; sourceSize.height: 2 * Theme.iconLg; mipmap: true
                                            source: root.iconFor(dragArea.modelData)
                                        }
                                        Text {
                                            visible: dragArea.groupN > 1
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Theme.icStack
                                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
                                            color: Theme.glassAccent
                                        }
                                        Text {
                                            visible: dragArea.groupN > 1
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: dragArea.groupN
                                            color: Theme.textPrimary
                                            font.family: Theme.type.label.family
                                            font.pixelSize: Theme.type.label.size
                                            font.weight: Theme.fontWeightSemibold
                                            font.features: ({ "tnum": 1 })
                                        }
                                    }
                                }
                            }

                            // close (✕) — top-left on hover (badge owns the top-right corner).
                            Rectangle {
                                anchors.top: parent.top; anchors.left: parent.left
                                anchors.margins: Theme.spaceS
                                z: 50
                                width: Theme.controlMd; height: Theme.controlMd
                                radius: Theme.radiusPrimary
                                visible: !dragArea.drag.active && !root.searching && (dragArea.containsMouse || closeMa.containsMouse)
                                color: closeMa.containsMouse ? Theme.danger : Theme.glassBase
                                border.color: closeMa.containsMouse ? Theme.danger : Theme.glassBorder
                                border.width: Theme.borderWidth1
                                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                Text {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                    text: Theme.icClose; font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
                                    color: closeMa.containsMouse ? Theme.onStatus : Theme.textPrimary
                                }
                                MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.killWin(dragArea.modelData) }
                            }
                        }
                    }
                }

                // empty desktop — one quiet line, nothing to look at on purpose
                Text {
                    anchors.centerIn: parent
                    visible: win.winWins.length === 0 && !root.searching
                    text: "No open windows"
                    color: Theme.textSecondary
                    font.family: Theme.type.h2.family
                    font.pixelSize: Theme.type.h2.size
                    font.weight: Theme.fontWeightSemibold
                }
            }

            // ══ LAUNCHER — search field + fused results panel (above the cards) ══
            Rectangle {
                id: searchShadowProxy
                anchors.fill: searchBox
                radius: Theme.radiusRounded
                color: Theme.black
                visible: false
            }
            Elevation {
                anchors.fill: searchShadowProxy
                source: searchShadowProxy
            }
            Rectangle {
                id: searchBox
                // the launcher UI follows the focused screen; the other monitors
                // show only their cards + the shared pager
                visible: win.isFocused
                anchors.horizontalCenter: parent.horizontalCenter
                // spaceLg from the top of the stage (Overview card #2)
                y: Theme.spaceLg
                width: Math.min(parent.width - 2 * Theme.spaceLg, Theme.panelLg)
                height: Theme.control2xl
                radius: Theme.radiusRounded
                color: Theme.glassRaised
                border.color: search.activeFocus ? Theme.focusRing : Theme.glassBorder
                border.width: Theme.borderWidth1
                Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                z: 10

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spaceMd; anchors.rightMargin: Theme.spaceMd
                    spacing: Theme.spaceS
                    Text { anchors.verticalCenter: parent.verticalCenter; text: Theme.icSearch; font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: Theme.textSecondary }
                    TextInput {
                        id: search
                        width: parent.width - Theme.iconMd - 2 * Theme.spaceS
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.textPrimary
                        font.family: Theme.type.bodyLg.family; font.pixelSize: Theme.type.bodyLg.size
                        selectionColor: Theme.accent; selectByMouse: true; clip: true
                        // a borderWidth2 accent caret (Overview card #2)
                        cursorDelegate: Rectangle {
                            id: caret
                            width: Theme.borderWidth2
                            height: search.cursorRectangle.height
                            color: Theme.accent
                            // blinks at the platform's cursor flash rate (a
                            // behaviour, not motion); steady under Reduce motion
                            readonly property int half: Math.max(1, Qt.styleHints.cursorFlashTime / 2)
                            SequentialAnimation {
                                loops: Animation.Infinite
                                running: search.activeFocus && !Theme.reduceMotion && Qt.styleHints.cursorFlashTime > 0
                                onRunningChanged: if (!running) caret.opacity = 1
                                PropertyAction { target: caret; property: "opacity"; value: 1 }
                                PauseAnimation { duration: caret.half }
                                PropertyAction { target: caret; property: "opacity"; value: 0 }
                                PauseAnimation { duration: caret.half }
                            }
                        }
                        onTextChanged: root.query = text
                        Text { visible: search.text.length === 0; anchors.verticalCenter: parent.verticalCenter; text: "Search apps, windows and files"; color: Theme.textSecondary; font: search.font }
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
                visible: root.searching && Globals.overviewOpen && win.isFocused
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: searchBox.bottom; anchors.topMargin: Theme.spaceS
                width: searchBox.width
                height: Math.min(resCol.implicitHeight + 2 * Theme.spaceS,
                                 stage.height - searchBox.y - searchBox.height - Theme.spaceXl)
                radius: Theme.radiusRounded
                color: Theme.glassRaised
                border.color: Theme.glassBorder; border.width: Theme.borderWidth1
                z: 10

                Flickable {
                    anchors.fill: parent
                    anchors.margins: Theme.spaceS
                    clip: true
                    contentWidth: width
                    contentHeight: resCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: resCol
                        width: parent.width
                        spacing: Theme.spaceXxs

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
                                sub: "Open window on workspace " + root.wsOf(modelData)
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

                        // dead end — the compact Empty state (Empty state card)
                        Column {
                            visible: root.navCount === 0
                            width: resCol.width
                            spacing: Theme.spaceXs
                            topPadding: Theme.spaceS; bottomPadding: Theme.spaceS
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Theme.controlLg; height: Theme.controlLg
                                radius: Theme.radiusFull
                                color: Theme.glassHover
                                Text { anchors.centerIn: parent; text: Theme.icSearchOff; font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: Theme.textSecondary }
                            }
                            Text {
                                width: parent.width; horizontalAlignment: Text.AlignHCenter
                                text: "Nothing matches “" + root.query + "”"
                                color: Theme.textPrimary
                                font.family: Theme.type.bodyStrong.family
                                font.pixelSize: Theme.type.bodyStrong.size
                                font.weight: Theme.fontWeightSemibold
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width; horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                text: "Try an app name, a window title or a file name."
                                color: Theme.textSecondary
                                font.family: Theme.type.body.family
                                font.pixelSize: Theme.type.body.size
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
                // layer: its items + spaceS padding, windowGap above the edge,
                // then spaceMd of breathing room — at every dock size
                anchors.bottom: parent.bottom
                anchors.bottomMargin: (Globals.dockIconSize === "small" ? Theme.controlXl
                                     : Globals.dockIconSize === "large" ? Theme.barHeightLg : Theme.control2xl)
                                    + 2 * Theme.spaceS + Theme.windowGap + Theme.spaceMd
                spacing: Theme.spaceS + Theme.spaceXs
                opacity: root.searching ? 0.35 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
                Repeater {
                    model: root.wsPills
                    delegate: Item {
                        id: thumb
                        required property var modelData
                        readonly property int wsId: modelData.ws
                        readonly property bool current: wsId === root.focusedWs
                        readonly property bool empty: modelData.count === 0
                        // control2xl + spaceS by controlLg + spaceXs (56 x 36)
                        width: Theme.control2xl + Theme.spaceS
                        height: Theme.controlLg + Theme.spaceXs

                        Rectangle {
                            id: thumbBox
                            anchors.fill: parent
                            radius: Theme.radiusPrimary
                            color: (thumb.current || thumbDrop.containsDrag) ? Theme.accentSubtle
                                 : thumbMa.containsMouse ? Theme.glassPressed : Theme.glassHover
                            border.color: (thumb.current || thumbDrop.containsDrag) ? Theme.accent : Theme.glassBorder
                            border.width: thumbDrop.containsDrag ? Theme.borderWidth2 : Theme.borderWidth1
                            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }

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
                                    radius: Theme.borderWidth2
                                    opacity: root.dragActive ? 0.25 : (thumb.current ? 0.8 : 0.55)
                                    color: thumb.current ? Theme.accent : Theme.textSecondary
                                    Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
                                }
                            }

                            // trailing empty desktop reads as "new one lives here"
                            // the trailing empty workspace reads as "a new one
                            // lives here" — the card's `plus` glyph
                            Text {
                                anchors.centerIn: parent
                                visible: thumb.empty && !thumb.current && !root.dragActive
                                text: Theme.icPlus
                                color: Theme.textSecondary
                                font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
                            }

                            // while a card is being dragged, the number is the target
                            Text {
                                anchors.centerIn: parent
                                visible: root.dragActive
                                text: thumb.wsId
                                color: Theme.textPrimary
                                font.family: Theme.type.label.family
                                font.pixelSize: Theme.type.label.size
                                font.weight: Theme.fontWeightSemibold
                                font.features: ({ "tnum": 1 })
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
}
