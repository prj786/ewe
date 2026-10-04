import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs

// ewe.dock — the dock, as an add-on (ewe 0.25, plugin API 3). A small,
// centred bottom dock on the main screen:
//   [ apps ] [ overview ] [ komble ] [ plugin dock items … ] | [ the Pen ] [ workspace boxes … ]
// The sheep opens the pinned-apps popup (PinnedApps.qml, IPC `launcher`),
// the layers glyph opens the window Overview, the store glyph brings Komble
// forward; every other add-on with a `dock-item` (Music, Places, …) gets a
// button here that runs its action with this button as the anchor. Each
// workspace box shows its windows as little app tiles (click a tile to
// focus that window, click the box to switch to that workspace); the Pen is
// ewe's hidden workspace (special:pen, Super+Z).
//
// What the shell gives it: Shell.dockPrefs (enabled · autohide · iconSize —
// Settings → Layout → Dock, ewe.conf [desktop.dock]; this file falls back to
// the same prefs on Globals while the shell is older), Shell.pinnedApps /
// Shell.setPinned, Shell.overviewOpen, Shell.activeCount, the dock-item
// registry (Shell.dockItems) and Theme's dock roles and sizes.
//
// What it gives the shell: Shell.setBottomInset("ewe.dock", px, reserved) —
// the strip it takes from the bottom of every screen (dock + windowGap), 0
// while the dock is off in prefs and 0 again when this plugin is removed;
// Toast, OSD, AnchoredPopup and the other bottom panels read it.
// Rule 8: every colour, size and duration is a Theme token.
Scope {
    id: root
    property string pluginId: "ewe.dock"

    // ── prefs: Shell.dockPrefs (API 3.1), else Globals' dock prefs ─────────
    readonly property var prefs: ("dockPrefs" in Shell && Shell.dockPrefs)
                                 ? Shell.dockPrefs
                                 : ({ enabled: Globals.dockEnabled !== false,
                                      autohide: Globals.dockAutohide === true,
                                      iconSize: Globals.dockIconSize || "normal" })
    readonly property bool enabled: root.prefs.enabled !== false
    readonly property bool autohide: root.prefs.autohide === true
    readonly property string iconSize: String(root.prefs.iconSize || "normal")

    // Settings → Layout → Dock → Icon size (Dock card, "Sizes"): the cell is
    // the button/box edge — small 40 · normal 48 · large 64 — Theme's dockCell
    // (the generator's `dock` block, which Text size leaves alone).
    readonly property bool small: root.iconSize === "small"
    readonly property bool large: root.iconSize === "large"
    readonly property int cell: (Theme.dockCell !== undefined) ? Theme.dockCell
                              : root.small ? Theme.controlXl : root.large ? Theme.icon4xl : Theme.control2xl
    // the container: spaceS of padding above and below the cells, windowGap
    // above the screen edge — the clearance is everything it takes
    readonly property int dockH: root.cell + 2 * Theme.spaceS
    readonly property int clearance: root.dockH + Theme.windowGap

    // ── the published inset (Shell.bottomInset): the strip plus windowGap
    //    while enabled, 0 when off — and whether the strip is a layer-shell
    //    exclusive zone (autohide off), which bottom-anchored surfaces read
    //    as Shell.bottomReserved. Withdrawn when this plugin goes. ─────────
    readonly property int publishedInset: root.enabled ? root.clearance : 0
    readonly property bool publishedReserved: root.enabled && !root.autohide
    function publishInset() { Shell.setBottomInset(root.pluginId, root.publishedInset, root.publishedReserved) }
    onPublishedInsetChanged: root.publishInset()
    onPublishedReservedChanged: root.publishInset()
    Component.onCompleted: root.publishInset()
    Component.onDestruction: Shell.setBottomInset(root.pluginId, 0, false)

    // ── the pinned-apps popup (PinnedApps.qml) ─────────────────────────────
    property bool launcherOpen: false
    property real launcherAnchorX: 200        // screen-local x of the sheep button (the popup centres on it)
    function toggleLauncher(btn) {
        if (btn) root.launcherAnchorX = btn.mapToItem(null, btn.width / 2, 0).x
        root.closeStoreFallback()
        if (!root.launcherOpen) Shell.closePopups(root.pluginId)   // one add-on popup at a time
        root.launcherOpen = !root.launcherOpen
    }
    // opening one dock panel closes the others: Shell.closePopups (every
    // AnchoredPopup and Places call it when they open) — and, belt and
    // braces, another add-on's popup reporting itself open through
    // Shell.setActive; the in-shell store fallback through its flag
    Connections {
        target: Shell
        function onPopupsClosing(exceptId) { if (exceptId !== root.pluginId) root.launcherOpen = false }
        function onActiveCountChanged() { if (Shell.activeCount > 0) root.launcherOpen = false }
        function onAboutToSleep() { root.launcherOpen = false }
        function onLockedChanged() { if (Shell.locked) root.launcherOpen = false }
    }
    onStoreOpenStateChanged: if (root.storeOpenState) root.launcherOpen = false

    // pinned apps: Shell.pinnedApps / Shell.setPinned (API 3.1), else Globals'
    // pinnedApps / togglePin — the implementation (ewe-conf apps.pinned) stays
    // in the shell either way
    readonly property var pinnedApps: ("pinnedApps" in Shell) ? (Shell.pinnedApps || []) : (Globals.pinnedApps || [])
    function isPinned(id) { return (root.pinnedApps || []).indexOf(id) >= 0 }
    function setPinned(id, on) {
        if (typeof Shell.setPinned === "function") Shell.setPinned(id, !!on)
        else if (root.isPinned(id) !== !!on) Globals.togglePin(id)
    }

    // ── IPC: the new target, and the legacy `launcher` alias (manifest
    //    ipcAliases) that keybinds and scripts already call ─────────────────
    IpcHandler {
        target: "ewe.dock"
        function launcher(): void { root.toggleLauncher(null) }
        function showLauncher(): void { root.launcherOpen = true }
        function hideLauncher(): void { root.launcherOpen = false }
        function isLauncherOpen(): bool { return root.launcherOpen }
    }
    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggleLauncher(null) }
        function show(): void { root.launcherOpen = true }
        function hide(): void { root.launcherOpen = false }
    }

    PinnedApps { host: root }

    // ── the Overview: Shell.overviewOpen says it is open; the slide follows
    //    the Overview's "cover" beat — out on the open frame (D8: one step,
    //    durBase), back a durFast beat after it closes, once the cards have
    //    gone (vault: Overview Takes the Screen). Shell.overviewCover, when
    //    the shell exposes it, is that same flag. ──────────────────────────
    property bool _cover: false
    readonly property bool cover: ("overviewCover" in Shell) ? (Shell.overviewCover === true) : root._cover
    Timer { id: coverBeat; interval: Math.max(1, Theme.durFast); onTriggered: if (!Shell.overviewOpen) root._cover = false }
    Connections {
        target: Shell
        function onOverviewOpenChanged() {
            if (Shell.overviewOpen) { coverBeat.stop(); root._cover = true }
            else coverBeat.restart()
        }
    }
    // in-shell: flip the flag (a `qs ipc call` spawn cost 50-70 ms per click)
    function toggleOverview() { Shell.toggleOverview() }

    // ── Komble: the software manager when installed; the shell's in-shell
    //    quick-installer panel is only the fallback, anchored on the button ─
    readonly property bool storeOpenState: ("storeOpen" in Globals) ? (Globals.storeOpen === true) : false
    function storeGo(btn) {
        if (Globals.kombleInstalled === false && ("storeOpen" in Globals)) {
            if (btn) Globals.storeAnchorX = btn.mapToItem(null, btn.width / 2, 0).x
            root.launcherOpen = false
            Globals.storeOpen = !Globals.storeOpen
            return
        }
        Shell.openStore()
    }
    function closeStoreFallback() { if ("storeOpen" in Globals && Globals.storeOpen) Globals.storeOpen = false }

    // ── the main screen: the shell's primary output (a shell concept —
    //    Wayland has none; Shell.primaryScreenName) ──────────────────────────
    readonly property string primaryName: String(Shell.primaryScreenName || "")

    // ── windows ─────────────────────────────────────────────────────────────
    function clsOf(t) { return (t && t.lastIpcObject && t.lastIpcObject.class) ? t.lastIpcObject.class : (t && t.wayland ? (t.wayland.appId || "") : "") }
    function iconFor(t) { var e = DesktopEntries.heuristicLookup(root.clsOf(t)); return Quickshell.iconPath(e && e.icon ? e.icon : root.clsOf(t), "application-x-executable") }
    function goWorkspace(id) { Hyprland.dispatch("hl.dsp.focus({workspace=" + id + "})") }
    // Focus one window by ADDRESS, so Hyprland switches to its workspace; the
    // foreign-toplevel activate is only the fallback for a toplevel whose
    // IPC object has not arrived yet (the shell's own rule).
    function focusToplevel(t) {
        if (!t) return false
        var a = String(t.address || (t.lastIpcObject && t.lastIpcObject.address) || "")
        if (a === "") {
            if (t.wayland) { t.wayland.activate(); return true }
            return false
        }
        if (a.indexOf("0x") !== 0) a = "0x" + a   // Hyprland events sometimes omit the 0x
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + a + '" })')
        return true
    }

    // the Pen: windows stashed on the special workspace (id < 0) — Super+Z
    readonly property var penWins: {
        var rev = root.claimRev
        var out = []
        var tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (var i = 0; i < tls.length; i++) { var t = tls[i]; if (t.workspace && t.workspace.id < 0) out.push(t) }
        return out
    }

    // workspaces (id>0) that have windows, plus the focused one — sorted, each with its toplevels
    readonly property var wsList: {
        var byws = {}
        var tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (var i = 0; i < tls.length; i++) { var t = tls[i]; var w = t.workspace ? t.workspace.id : -1; if (w > 0) { (byws[w] = byws[w] || []).push(t) } }
        var fid = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
        if (fid > 0 && !byws[fid]) byws[fid] = []
        var ids = Object.keys(byws).map(Number).sort(function (a, b) { return a - b })
        var out = []
        for (var k = 0; k < ids.length; k++) out.push({ id: ids[k], wins: byws[ids[k]] })
        return out
    }

    // Intelligent hide needs to know when floating/fullscreen state changes —
    // those live only in lastIpcObject, which Quickshell doesn't refetch on
    // its own for these events. Bump a revision so wsClaimed re-evaluates.
    property int claimRev: 0
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            var n = ev.name
            if (n === "openwindow" || n === "closewindow" || n === "movewindow"
             || n === "changefloatingmode" || n === "fullscreen") {
                Hyprland.refreshToplevels()
                root.claimRev++
            }
            // entering/leaving the Pen — the monitor's specialWorkspace field
            // only lives in lastIpcObject, so refetch it on the raw event
            if (n === "activespecial") {
                Hyprland.refreshMonitors()
                root.claimRev++
            }
        }
    }

    // One window per screen, visible only on the primary — NOT a single window
    // with a screen: binding. Rebinding screen mid-hotplug (the primary name
    // going stale while the output detaches) could resolve to null and destroy
    // the window for good; per-screen windows are created/destroyed by the
    // screen model itself, so the dock always lands on whatever remains.
    Variants {
        model: Quickshell.screens

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData
        // primary = the shell's primary flag; if no connected screen carries
        // that name (mid-hotplug, stale profile), fall back to the first screen
        readonly property bool isPrimary: {
            var ss = Quickshell.screens
            for (var i = 0; i < ss.length; i++)
                if (ss[i].name === root.primaryName) return win.modelData.name === root.primaryName
            return ss.length > 0 && win.modelData === ss[0]
        }
        // Only on the primary, and only while the dock is enabled — the dock
        // is not a surface of the Overview (the Overview owns the whole
        // screen and the dock slides out of view instead).
        visible: win.isPrimary && root.enabled
        color: "transparent"
        // Always-visible dock reserves its strip so windows tile/maximize ABOVE it
        // instead of sliding underneath; intelligent-hide keeps zero reserve so
        // windows get the full height and the dock overlays only when revealed.
        // The reserve is expressed through the NUMERIC zone, never by flipping
        // exclusionMode at runtime — a live Normal→Ignore switch was not always
        // recommitted to the compositor, leaving a ghost strip that windows
        // refused to use until the dock was toggled off and on.
        exclusiveZone: (root.enabled && !root.autohide) ? win.dockH + Theme.windowGap : 0
        // Always Top. The dock used to hop to Overlay so it drew above the
        // Overview; the Overview now owns the whole screen and the dock slides
        // out of view instead.
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell:dock"
        anchors { bottom: true; left: true; right: true }

        // every other figure is its own token per size rather than a
        // multiplier — 40/20/32x28/16, 48/24/36x32/20, 64/32/48x40/24
        readonly property int cell:      root.cell
        readonly property int glyphPx:   root.small ? Theme.iconLg : root.large ? Theme.icon2xl : Theme.iconXl
        readonly property int tileW:     root.small ? Theme.controlLg : root.large ? Theme.control2xl : Theme.controlLg + Theme.spaceXs
        readonly property int tileH:     root.small ? Theme.controlMd : root.large ? Theme.controlXl : Theme.controlLg
        readonly property int appPx:     root.small ? Theme.iconMd : root.large ? Theme.iconXl : Theme.iconLg
        // the container: spaceS of padding all round, and a radius that stays
        // concentric with the radiusPrimary items inside it
        readonly property int dockH: root.dockH
        readonly property int dockR: Theme.r(Theme.radiusPrimary + Theme.spaceS)
        // the sliver left on screen while hidden (Dock card: auto-hide)
        readonly property int peek: Theme.spaceXs + Theme.spaceXxs
        implicitHeight: dockH + 2 * Theme.windowGap + Theme.spaceXxs

        // Intelligent hide, made intelligent: the dock ducks only when this
        // screen's active workspace has a window that actually claims the
        // screen (tiled, or fullscreened in any mode). An empty or
        // floating-only workspace keeps the dock out even with autohide on.
        // A toplevel whose IPC object hasn't arrived yet counts as claiming —
        // better a dock that ducks a beat early than one sitting over a tile.
        readonly property var hyMon: Hyprland.monitorFor(win.screen)
        // the second flow: the Pen is OPEN on this screen — the dock then
        // shows only the Pen box, no numbered desktops (you are elsewhere)
        readonly property bool penOpen: {
            var rev = root.claimRev
            var o = win.hyMon ? win.hyMon.lastIpcObject : null
            return !!(o && o.specialWorkspace && String(o.specialWorkspace.name).indexOf("special") === 0)
        }
        readonly property bool wsClaimed: {
            var rev = root.claimRev
            var wid = win.hyMon && win.hyMon.activeWorkspace ? win.hyMon.activeWorkspace.id : -1
            var tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
            for (var i = 0; i < tls.length; i++) {
                var t = tls[i]
                if (!t.workspace || t.workspace.id !== wid) continue
                var o = t.lastIpcObject
                if (!o || !o.floating || o.fullscreen) return true
            }
            return false
        }

        // Revealed when: autohide off · nothing on the workspace claims the screen ·
        // hovering the fixed bottom edge · hovering the dock itself · a popup is open
        // (ours, the store fallback, or any add-on's — Shell.activeCount) · within
        // the close grace period · the Overview is open. The bottom edge trigger
        // is FIXED (never moves), so revealing can't slide the dock out from under
        // the cursor → no flicker.
        property bool revealed: !root.autohide || !win.wsClaimed || edgeHov.hovered
                                 || dockHov.hovered
                                 || closeHold.running || root.launcherOpen || root.storeOpenState
                                 || Shell.overviewOpen || Shell.activeCount > 0
        // the grace period after the pointer leaves (the built-in had a raw
        // 280 ms; a token now — Rule 8)
        Timer { id: closeHold; interval: Math.max(1, Theme.durSlow) }
        function maybeHide() { if (!edgeHov.hovered && !dockHov.hovered && !root.launcherOpen && !root.storeOpenState && Shell.activeCount === 0) closeHold.restart() }
        Connections { target: edgeHov; function onHoveredChanged() { win.maybeHide() } }
        Connections { target: dockHov; function onHoveredChanged() { win.maybeHide() } }

        // input region: a fixed bottom-edge trigger strip (always) ∪ the dock pill
        mask: Region {
            Region { x: edge.x; y: win.height - win.peek; width: edge.width; height: win.peek }
            Region { x: Math.max(0, dock.x - Theme.spaceS); y: dock.y; width: dock.width + 2 * Theme.spaceS; height: win.height - dock.y }
        }

        // fixed bottom-edge hover trigger (does not move when the dock slides)
        Item { id: edge; x: dock.x; width: dock.width; anchors.bottom: parent.bottom; height: win.peek; HoverHandler { id: edgeHov } }

        // ── the dock pill ──
        Rectangle {
            id: dock
            anchors.horizontalCenter: parent.horizontalCenter
            // windowGap above the bottom edge (Dock card, "Placement")
            y: win.revealed ? (parent.height - height - Theme.windowGap) : (parent.height - win.peek)
            Behavior on y { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            // Entrance: slide up from below the screen edge once the shell is
            // up (mirrors the bar's slide-down; also plays on hotplug). Runs
            // on a Translate so it never fights the revealed/peek y binding.
            // Reduce motion drops the slide; the pill just fades in.
            transform: [
                Translate {   // entrance — unchanged
                    // Reduce motion can turn on (the tokens land late) while
                    // this is running: finish it, never stop it off-screen.
                    NumberAnimation on y {
                        readonly property bool rm: Theme.reduceMotion
                        onRmChanged: if (rm) complete()
                        from: win.implicitHeight; to: 0
                        duration: Theme.reduceMotion ? 0 : Theme.durSlow; easing.type: Theme.easeSlow
                    }
                },
                Translate {   // the Overview owns the screen: slide fully out of
                              // view (not to the autohide peek — nothing to grab
                              // at), back after the cards have gone. Reduce
                              // motion keeps y and fades instead (see opacity).
                    y: (root.cover && !Theme.reduceMotion) ? win.implicitHeight : 0
                    Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
                }
            ]
            // Reduce motion: no slides. The pill fades in at start, and
            // auto-hide jumps to the peek and back while the pill fades out
            // and in at durFast, so it still says where it went.
            property bool entered: false
            Component.onCompleted: dock.entered = true
            opacity: !dock.entered ? 0 : (Theme.reduceMotion && (!win.revealed || root.cover)) ? 0 : 1
            Behavior on opacity { enabled: Theme.reduceMotion; NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
            height: win.dockH
            width: row.implicitWidth + 2 * Theme.spaceS
            radius: win.dockR
            // surfaceRaised, or glassRaised once bar opacity drops below 100
            color: Theme.dockGround
            border.color: Theme.dockOutline
            border.width: Theme.borderWidth1
            HoverHandler { id: dockHov }
            layer.enabled: true
            layer.effect: Elevation {}

            // a square dock launcher (Dock card, "States"): radiusPrimary, no
            // fill by default, surfaceHover on hover, surfacePressed while
            // pressed, and accentSubtle with an accentText glyph while its
            // panel is open. Inside Glass those become the glass tints.
            component DockBtn: Rectangle {
                id: db
                property string glyph: ""
                property string image: ""          // an SVG instead of a glyph (the ewe mark: the line-art logo, bold cut), tinted like one
                property bool activeState: false
                // a toolbar button named by what it opens (Dock card, Accessibility)
                property string a11yName: ""
                Accessible.role: Accessible.Button
                Accessible.name: db.a11yName
                signal go()
                width: win.cell; height: win.cell; radius: Theme.radiusPrimary
                color: db.activeState ? Theme.dockOpenFill
                     : dbMa.pressed ? Theme.barPressedFill
                     : dbMa.containsMouse ? Theme.barHoverFill : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                readonly property color tint: db.activeState ? Theme.barAccentText
                                            : dbMa.containsMouse ? Theme.textPrimary : Theme.textSecondary
                Text {
                    visible: db.image === ""
                    anchors.centerIn: parent
                    text: db.glyph
                    font.family: Theme.fontIcons; font.pixelSize: win.glyphPx
                    color: db.tint
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                }
                Image {
                    id: dbImg
                    visible: false
                    source: db.image
                    // the mark carries inner detail (a ringed line drawing), so it is drawn a
                    // step larger than the plain glyphs beside it, inside the same cell
                    width: Math.round(win.glyphPx * 1.35); height: width
                    sourceSize: Qt.size(width * 2, height * 2)
                    fillMode: Image.PreserveAspectFit
                }
                MultiEffect {
                    visible: db.image !== ""
                    anchors.centerIn: parent
                    width: dbImg.width; height: dbImg.height
                    source: dbImg
                    colorization: 1.0
                    colorizationColor: db.tint
                    Behavior on colorizationColor { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                }
                MouseArea { id: dbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: db.go() }
            }

            Row {
                id: row
                anchors.centerIn: parent
                spacing: Theme.spaceS

                DockBtn { id: launchBtn; a11yName: "Apps"; image: Qt.resolvedUrl("assets/ewe-mark.svg"); activeState: root.launcherOpen; anchors.verticalCenter: parent.verticalCenter; onGo: root.toggleLauncher(launchBtn) }
                DockBtn { a11yName: "Overview"; glyph: Theme.icStack; activeState: Shell.overviewOpen; anchors.verticalCenter: parent.verticalCenter; onGo: root.toggleOverview() }
                DockBtn { id: storeBtn; a11yName: "Komble"; glyph: Theme.icStore; activeState: root.storeOpenState; anchors.verticalCenter: parent.verticalCenter; onGo: root.storeGo(storeBtn) }
                // ── plugin dock items (API 3 dock-item): after the built-in
                //    buttons, in manifest order — Music, Places and whatever
                //    else is installed. A click runs the manifest's action
                //    with this button as the anchor (an AnchoredPopup opens
                //    above it); without a registered action it falls back to
                //    `qs ipc call <id> toggle`. Lit while the action's popup
                //    reports itself open. A plugin hides its own item at
                //    runtime through Shell.setDockItemShown (Music with no
                //    player) — shown unless it says otherwise. ──
                Repeater {
                    model: Shell.dockItems || []
                    delegate: DockBtn {
                        id: pluginBtn
                        required property var modelData
                        visible: Shell.dockItemShown(modelData.id)
                        a11yName: modelData.label
                        glyph: Theme[modelData.icon] || Theme.icApps
                        activeState: modelData.action !== "" && Shell.isActive(modelData.action)
                        anchors.verticalCenter: parent.verticalCenter
                        onGo: {
                            root.launcherOpen = false; root.closeStoreFallback()
                            var a = Shell.anchorFor(pluginBtn, win)
                            if (modelData.action === "" || !Shell.runAction(modelData.action, a))
                                Quickshell.execDetached(["qs", "ipc", "call", modelData.id, "toggle"])
                        }
                    }
                }

                // spaceS shorter than the items beside it (Dock card #3)
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Theme.borderWidth1; height: win.cell - Theme.spaceS; color: Theme.dockOutline }

                // ── the Pen — ewe's hidden workspace (special:pen). Appears
                //    only while something is stashed: package glyph + a tile
                //    per window. Tile → fetch that window; box → show/hide
                //    the Pen; Super+Z stashes/toggles from the keyboard. ──
                Rectangle {
                    id: penBox
                    visible: root.penWins.length > 0 || win.penOpen
                    anchors.verticalCenter: parent.verticalCenter
                    height: win.cell; radius: Theme.radiusPrimary
                    width: Math.max(win.cell, penRow.implicitWidth + 2 * Theme.spaceS)
                    // open = accentSubtle with an accent border (Dock card)
                    color: win.penOpen ? Theme.dockSelectedFill
                         : penMa.hovered ? Theme.barHoverFill : "transparent"
                    border.color: win.penOpen ? Theme.accent : Theme.dockOutline
                    border.width: Theme.borderWidth1
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                    MouseArea { id: penMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        readonly property bool hovered: containsMouse
                        onClicked: Hyprland.dispatch('hl.dsp.workspace.toggle_special("pen")') }
                    Row {
                        id: penRow
                        anchors.centerIn: parent
                        spacing: Theme.spaceXs
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.icPen
                            color: win.penOpen ? Theme.barAccentText : Theme.barTextMuted
                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
                        }
                        Repeater {
                            model: root.penWins
                            delegate: Rectangle {
                                required property var modelData
                                anchors.verticalCenter: parent.verticalCenter
                                width: win.tileW; height: win.tileH; radius: Theme.radiusSecondary
                                color: modelData.activated && win.penOpen ? Theme.accent
                                     : penTileMa.containsMouse ? Theme.barHoverFill : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                Image {
                                    anchors.centerIn: parent
                                    width: win.appPx; height: win.appPx
                                    sourceSize.width: 2 * win.appPx; sourceSize.height: 2 * win.appPx; mipmap: true
                                    source: root.iconFor(modelData)
                                }
                                MouseArea {
                                    id: penTileMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                    // left: go to that window (inside the Pen);
                                    // middle: send it home to the normal flow
                                    onClicked: function (m) {
                                        if (m.button === Qt.MiddleButton) {
                                            // move THAT window (by address, not "the
                                            // active one"), then focus it where it lands
                                            var ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
                                            var a = String(modelData.address || "")
                                            if (a !== "" && a.indexOf("0x") !== 0) a = "0x" + a
                                            if (a !== "") Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + ws + ', window = "address:' + a + '", follow = false })')
                                            root.focusToplevel(modelData)
                                        } else root.focusToplevel(modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── workspace boxes (hidden while the Pen flow is open —
                //    one flow at a time, exactly what you see) ──
                Repeater {
                    model: win.penOpen ? [] : root.wsList
                    delegate: Rectangle {
                        id: wsBox
                        required property var modelData
                        readonly property bool focused: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData.id
                        anchors.verticalCenter: parent.verticalCenter
                        height: win.cell; radius: Theme.radiusPrimary
                        width: Math.max(win.cell, wsRow.implicitWidth + 2 * Theme.spaceS)
                        color: focused ? Theme.dockSelectedFill
                             : wsMa.containsMouse ? Theme.barHoverFill : "transparent"
                        border.color: focused ? Theme.accent : Theme.dockOutline
                        border.width: Theme.borderWidth1
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }

                        // background click → switch workspace (window tiles sit on top)
                        MouseArea { id: wsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.goWorkspace(wsBox.modelData.id) }

                        Row {
                            id: wsRow
                            anchors.centerIn: parent
                            spacing: Theme.spaceXs
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: wsBox.modelData.id + ":"
                                color: wsBox.focused ? Theme.barAccentText : Theme.barTextMuted
                                font.family: Theme.type.label.family
                                font.pixelSize: Theme.type.label.size
                                font.weight: Theme.fontWeightSemibold
                                font.features: ({ "tnum": 1 })
                            }
                            // empty-workspace hint
                            Text {
                                visible: wsBox.modelData.wins.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "empty"; color: Theme.textSecondary
                                font.family: Theme.type.label.family
                                font.pixelSize: Theme.type.label.size
                            }
                            // window tiles
                            Repeater {
                                model: wsBox.modelData.wins
                                delegate: Rectangle {
                                    required property var modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: win.tileW; height: win.tileH; radius: Theme.radiusSecondary
                                    color: modelData.activated ? Theme.accent
                                         : tileMa.containsMouse ? Theme.barHoverFill : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                    Image {
                                        anchors.centerIn: parent
                                        width: win.appPx; height: win.appPx
                                        sourceSize.width: 2 * win.appPx; sourceSize.height: 2 * win.appPx; mipmap: true
                                        source: root.iconFor(modelData)
                                    }
                                    MouseArea {
                                        id: tileMa
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.focusToplevel(modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    }
}
