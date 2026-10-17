import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import "cards"
import "sections"

// Drop — the notch (overlay): a tab of the bar's own material hanging from
// the bar's centre, joined to it with fillets (the owner chose this over a
// pill inside the bar, 2026-10-14).
//
//   hidden    nothing runs: no notch at all (the owner, 2026-10-14: "just
//             when it's expanded or a process is running"). Super+A opens it
//   compact   an agent works or waits, a line to say, a question in flight,
//             game mode: the Indicator, at one fixed size
//   cards     a card waits: the notch grows to show it (not in Do not
//             disturb or on the lock screen: the count says it then)
//   home      opened by hand (click, Super+A): cards, then only what is
//             live now (agents, what needs a look, what plays), quick
//             actions, and the chat
//
// One window per screen on the Top layer, like the bar: a fullscreen window
// covers it, nothing steals focus, and the input mask is the notch alone.
// Opened by hand, a Hyprland focus grab closes it on a click outside.
//
// The window never changes size while anything is drawn on it. When a
// layer surface grows, Hyprland stretches the old buffer to the new size
// until the next frame lands: that was the blink on opening (owner,
// 2026-10-14). So the window takes its full size while it is still empty,
// the notch comes out once it has, and it shrinks only after the notch has
// gone back in.
//
// The ack: a card's delegate tells the daemon it has the card. No ack
// within 800 ms and the agent gets "no opinion" (C2): a broken notch costs
// a terminal prompt, never a lost one.
Scope {
    id: drop
    property string pluginId: ""
    property var settings: ({})

    readonly property bool byHand: CompanionState.dropOpen
    readonly property string screenSetting: (drop.settings && drop.settings.screen) || "primary"

    // ── the stack: a ListModel synced by id, so a delegate (and a half-made
    //    choice in a question) survives every state push ─────────────────
    ListModel { id: stack }
    function asks(c) { return c.kind === "permission" || c.kind === "question" }
    function sync() {
        var pend = CompanionState.pending, want = {}
        for (var i = 0; i < pend.length; i++) want[pend[i].id] = pend[i]
        for (var j = stack.count - 1; j >= 0; j--) if (!want[stack.get(j).cid]) stack.remove(j)
        var have = {}
        for (var k = 0; k < stack.count; k++) have[stack.get(k).cid] = true
        for (var m = 0; m < pend.length; m++) {
            var c = pend[m]
            if (have[c.id]) continue
            // newest first; agent cards above everything else
            var at = 0
            if (!drop.asks(c)) { while (at < stack.count && stack.get(at).asks) at++ }
            stack.insert(at, { cid: c.id, asks: drop.asks(c), json: JSON.stringify(c) })
        }
    }
    Connections { target: CompanionState; function onPendingChanged() { drop.sync() } }

    // one plugin popup at a time (Shell.closePopups)
    Connections {
        target: Shell
        function onPopupsClosing(exceptId) { if (exceptId !== drop.pluginId) CompanionState.dropOpen = false }
        function onLockedChanged() { if (Shell.locked) CompanionState.dropOpen = false }
    }
    onByHandChanged: {
        if (!drop.byHand) return
        Shell.closePopups(drop.pluginId)
        CompanionState.send({ type: "glance.refresh" })   // disk and updates as they are now
    }

    // something runs: what keeps the notch out when it is not open
    readonly property bool busy: CompanionState.connected
                                 && (CompanionState.lead !== null || CompanionState.peek !== null
                                     || CompanionState.thinking || CompanionState.gameMode
                                     || CompanionState.asking > 0)

    Component { id: permission; PermissionCard {} }
    Component { id: question; QuestionCard {} }
    Component { id: note; NoteCard {} }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            // where cards and home open; every screen shows the compact notch
            // with "Show on: every screen"
            readonly property bool main: win.modelData.name === CompanionState.screenName
            readonly property bool wanted: !Shell.locked && (drop.screenSetting === "all" || win.main)
            readonly property bool expanded: win.main && !Shell.locked
                                             && (drop.byHand || (stack.count > 0 && !Shell.dnd && CompanionState.connected))
            readonly property bool present: win.wanted && (win.expanded || drop.busy)

            // the home sections stay through the fold, so they fade with
            // the notch instead of vanishing under it
            property bool homeHeld: false
            readonly property bool home: win.main && (drop.byHand || win.homeHeld)
            Connections {
                target: drop
                function onByHandChanged() {
                    if (drop.byHand) { homeTimer.stop(); win.homeHeld = false }
                    else { win.homeHeld = true; homeTimer.restart() }
                }
            }
            Timer { id: homeTimer; interval: Math.max(1, Theme.durBase); onTriggered: win.homeHeld = false }

            // ── scrolling: the newest message comes into view by itself, a
            //    new card goes to the top, and opening by hand starts at the
            //    top (what is live now) ──
            property bool followEnd: false
            function scrollToEnd() {
                var end = Math.max(0, scroller.contentHeight - scroller.height)
                if (Math.abs(scroller.contentY - end) < 1) return
                scrollAnim.to = end
                scrollAnim.restart()
            }
            NumberAnimation { id: scrollAnim; target: scroller; property: "contentY"; duration: Theme.durBase; easing.type: Theme.ease }
            Timer { id: followTimer; interval: Math.max(1, Theme.durBase * 2); onTriggered: win.followEnd = false }
            Connections {
                target: CompanionState
                function onMessagesChanged() { win.followEnd = true; followTimer.restart(); Qt.callLater(win.scrollToEnd) }
                function onThinkingChanged() { if (CompanionState.thinking) { win.followEnd = true; followTimer.restart(); Qt.callLater(win.scrollToEnd) } }
            }
            Connections {
                target: stack
                function onCountChanged() { scrollAnim.stop(); scroller.contentY = 0 }
            }
            Connections {
                target: drop
                function onByHandChanged() { if (drop.byHand) { scrollAnim.stop(); win.followEnd = false; scroller.contentY = 0 } }
            }
            onExpandedChanged: if (win.expanded && drop.byHand && win.main) Qt.callLater(function () { chat.input.forceActiveFocus() })

            // ── size first, then come out (see the header) ──
            property bool sized: false
            property bool out: false
            function settle() {
                if (win.present) {
                    shrinkTimer.stop()
                    win.sized = true
                    if (win.height >= win.fullH) win.out = true
                    else revealTimer.restart()
                } else {
                    revealTimer.stop()
                    win.out = false
                    shrinkTimer.restart()
                }
            }
            onPresentChanged: win.settle()
            onHeightChanged: if (win.present && win.sized && !win.out && win.height >= win.fullH) win.out = true
            Component.onCompleted: win.settle()
            // a compositor that never gives the full height still gets a notch
            Timer { id: revealTimer; interval: Math.max(1, Theme.durFast); onTriggered: if (win.present) win.out = true }
            Timer { id: shrinkTimer; interval: Math.max(1, Theme.durBase + Theme.durFast); onTriggered: if (!win.present) win.sized = false }

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell:companion"
            WlrLayershell.keyboardFocus: win.main && drop.byHand ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            // top only: the window is centred under the bar, as wide as the
            // open notch and its fillets
            anchors { top: true }
            implicitWidth: win.openW + 2 * win.fil + 2 * Theme.spaceXs
            implicitHeight: win.sized ? win.fullH : 1
            mask: Region { item: hit }

            // a click anywhere else closes the home panel. The grab starts a
            // beat after the keyboard turns Exclusive: Hyprland ends every
            // grab when an exclusive layer takes the keyboard, so a grab
            // started with it was cleared at once (2026-10-14)
            readonly property bool grabWanted: win.main && drop.byHand && win.out
            onGrabWantedChanged: { if (win.grabWanted) grabTimer.restart(); else { grabTimer.stop(); grab.active = false } }
            Timer { id: grabTimer; interval: Math.max(1, Theme.durFast); onTriggered: if (win.grabWanted) grab.active = true }
            HyprlandFocusGrab {
                id: grab
                windows: [win]
                onCleared: CompanionState.dropOpen = false
            }

            // ── sizes: tokens, and none of them follows the pointer ──
            readonly property int edgeGap: Theme.spaceS + Theme.spaceXs
            readonly property int barH: Globals.barVisible ? Theme.barHeight : 0
            readonly property int fil: Theme.r(Theme.radiusRounded)       // the fillet into the bar
            readonly property int corner: Theme.r(Theme.radiusRounded)    // the notch's own corners
            readonly property int headH: Theme.controlLg
            readonly property int compactW: Math.min(Theme.grow(Theme.panelSm), win.modelData.width - 2 * win.edgeGap)
            readonly property int openW: Math.min(Theme.grow(Theme.panelMd), win.modelData.width - 2 * win.edgeGap)
            // the open notch stops at 60 % of the screen (Quick settings' own
            // idea of a panel's ceiling); past it, everything but the line
            // you type in scrolls (owner, 2026-10-14)
            readonly property int maxOpenH: Math.min(Math.round(win.modelData.height * 0.6),
                                                     win.modelData.height - win.barH - 2 * win.edgeGap)
            // the line you type in, pinned under the scrolling part
            readonly property int dockH: win.home ? dock.implicitHeight + Theme.spaceS : 0
            readonly property int openH: Math.min(win.headH + body.implicitHeight + win.dockH + Theme.spaceMd, win.maxOpenH)
            readonly property int fullH: win.barH + win.maxOpenH + Theme.spaceXs

            Item { id: hit; x: notch.x - win.fil; y: win.barH; width: win.out ? notch.width + 2 * win.fil : 0; height: notch.height }

            // ── the material: one path, the bar's ground and its rule ─────
            // The rule runs along the bar's lower edge, bends down the fillet,
            // round the notch and back up into the bar. The curve renderer
            // draws it analytically, so it stays smooth at any scale.
            //
            // The bar's material, the same as the bar's own: the bar's ground
            // at the bar's opacity over the blurred wallpaper (the blur rule
            // is xray, Service.applyBlur), so whatever window sits under the
            // notch never shows through (owner, 2026-10-17: "background
            // should always be same as topbars").
            //
            // It is clipped at the bar's edge. The ground starts above it and
            // the clip cuts it on a whole device pixel, where the bar's own
            // ground ends: started at the edge, the anti-aliased top row
            // showed the bar's rule as a hairline (2026-10-14); left inside
            // the bar, that half-covered row got the whole xray blur under it
            // and drew a seam, darker in light mode, lighter in dark (bar
            // 40 px at 1.8, 2026-10-17). A clip is a scissor: a hard edge.
            Item {
                y: win.barH
                width: parent.width
                height: Math.max(0, parent.height - win.barH)
                clip: true
                visible: notch.height > 0
                Shape {
                    id: ground
                    y: -win.barH
                    width: win.width
                    height: win.height
                    preferredRendererType: Shape.CurveRenderer
                    readonly property real lw: Theme.borderWidth1
                    // the corners grow with the notch as it comes out of the bar
                    readonly property real k: Math.max(0, Math.min(1, (notch.height - lw) / Math.max(1, win.fil + win.corner)))
                    readonly property real f: win.fil * k
                    readonly property real c: win.corner * k
                    readonly property real x0: notch.x
                    readonly property real x1: notch.x + notch.width
                    readonly property real y0: win.barH               // the bar's lower edge
                    readonly property real yr: win.barH + lw / 2      // its rule's centre line
                    readonly property real y1: win.barH + notch.height

                    // the ground starts one rule above the bar's edge, for the
                    // clip to cut (above)
                    ShapePath {
                        strokeColor: "transparent"
                        fillColor: Theme.barGround
                        startX: ground.x0 - ground.f; startY: ground.y0 - ground.lw
                        PathLine { x: ground.x0 - ground.f; y: ground.yr }
                        PathArc { x: ground.x0; y: ground.yr + ground.f; radiusX: ground.f; radiusY: ground.f }
                        PathLine { x: ground.x0; y: ground.y1 - ground.c }
                        PathArc { x: ground.x0 + ground.c; y: ground.y1; radiusX: ground.c; radiusY: ground.c; direction: PathArc.Counterclockwise }
                        PathLine { x: ground.x1 - ground.c; y: ground.y1 }
                        PathArc { x: ground.x1; y: ground.y1 - ground.c; radiusX: ground.c; radiusY: ground.c; direction: PathArc.Counterclockwise }
                        PathLine { x: ground.x1; y: ground.yr + ground.f }
                        PathArc { x: ground.x1 + ground.f; y: ground.yr; radiusX: ground.f; radiusY: ground.f }
                        PathLine { x: ground.x1 + ground.f; y: ground.y0 - ground.lw }
                        PathLine { x: ground.x0 - ground.f; y: ground.y0 - ground.lw }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Theme.barOutline
                        strokeWidth: ground.lw
                        capStyle: ShapePath.FlatCap
                        joinStyle: ShapePath.RoundJoin
                        startX: ground.x0 - ground.f; startY: ground.yr
                        PathArc { x: ground.x0; y: ground.yr + ground.f; radiusX: ground.f; radiusY: ground.f }
                        PathLine { x: ground.x0; y: ground.y1 - ground.c }
                        PathArc { x: ground.x0 + ground.c; y: ground.y1; radiusX: ground.c; radiusY: ground.c; direction: PathArc.Counterclockwise }
                        PathLine { x: ground.x1 - ground.c; y: ground.y1 }
                        PathArc { x: ground.x1; y: ground.y1 - ground.c; radiusX: ground.c; radiusY: ground.c; direction: PathArc.Counterclockwise }
                        PathLine { x: ground.x1; y: ground.yr + ground.f }
                        PathArc { x: ground.x1 + ground.f; y: ground.yr; radiusX: ground.f; radiusY: ground.f }
                    }
                }
            }

            // ── the notch: its geometry, and everything in it ──
            Item {
                id: notch
                width: win.expanded ? win.openW : win.compactW
                height: !win.out ? 0 : win.expanded ? win.openH : win.headH
                x: Math.round((win.width - width) / 2)
                y: win.barH
                clip: true
                Behavior on width { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
                Behavior on height { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
                MouseArea { anchors.fill: parent }   // clicks inside stay inside

                // ── the indicator line, always on top ──
                Item {
                    id: head
                    width: parent.width
                    height: win.headH
                    opacity: win.out ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                    Indicator {
                        id: ind
                        settings: drop.settings
                        open: win.expanded
                        x: Theme.spaceMd
                        width: parent.width - 2 * Theme.spaceMd
                        height: parent.height
                    }
                    MouseArea {
                        id: headMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onContainsMouseChanged: CompanionState.peekHeld = containsMouse && CompanionState.peek !== null
                        onClicked: function (m) {
                            var p = CompanionState.peek
                            if (m.button === Qt.RightButton) {
                                if (p) CompanionState.peek = null
                                else CompanionState.dropOpen = !CompanionState.dropOpen
                            } else if (p && p.actions && p.actions.length > 0 && !drop.byHand) {
                                CompanionState.peekAction(p.actions[0].id)
                            } else CompanionState.dropOpen = !CompanionState.dropOpen
                        }
                    }
                }

                // ── the open notch: laid out at its open width, so nothing
                //    reflows while the notch grows round it ──
                Flickable {
                    id: scroller
                    x: Math.round((notch.width - width) / 2)
                    y: win.headH
                    width: win.openW - 2 * Theme.spaceMd
                    height: Math.max(0, notch.height - win.headH - win.dockH - Theme.spaceMd)
                    contentWidth: width
                    contentHeight: body.implicitHeight
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    opacity: win.expanded ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }

                    Column {
                        id: body
                        width: scroller.width
                        spacing: Theme.spaceMd
                        focus: true
                        Keys.onEscapePressed: CompanionState.dropOpen = false

                        // cards: only the main notch holds them, so each is acked once
                        Repeater {
                            model: win.main ? stack : null
                            Loader {
                                id: slot
                                required property string cid
                                required property string json
                                required property int index
                                width: body.width
                                visible: slot.index < 3
                                readonly property var card: JSON.parse(slot.json)
                                sourceComponent: slot.card.kind === "permission" ? permission
                                               : slot.card.kind === "question" ? question : note
                                onLoaded: {
                                    item.width = Qt.binding(function () { return body.width })
                                    item.card = slot.card
                                    CompanionState.shown(slot.cid)
                                }
                            }
                        }
                        TextCaption {
                            visible: win.main && stack.count > 3
                            text: (stack.count - 3) + " more waiting"
                        }

                        // home: only what is live now
                        Agents { width: body.width; visible: win.home && CompanionState.sessions.length > 0 }
                        Glance { id: glance; width: body.width; visible: win.home && glance.rows.length > 0 }
                        NowPlaying { id: playing; width: body.width; visible: win.home && playing.player !== null }
                        Actions { width: body.width; visible: win.home }
                        Messages { width: body.width; visible: win.home && CompanionState.messages.length > 0 }
                    }
                    // a new answer scrolls itself into view; a new card, to the top
                    onContentHeightChanged: if (win.followEnd) win.scrollToEnd()
                }
                // the scroll position, a thin bar in the right margin, only
                // when there is more than fits
                Rectangle {
                    visible: win.expanded && scroller.contentHeight > scroller.height
                    width: Theme.spaceXxs
                    radius: width / 2          // a true pill: geometry, not a radius token
                    x: scroller.x + scroller.width + Math.round((Theme.spaceMd - width) / 2)
                    y: scroller.y + scroller.visibleArea.yPosition * scroller.height
                    height: scroller.visibleArea.heightRatio * scroller.height
                    color: Theme.borderStrong
                }
                Column {
                    id: dock
                    x: scroller.x
                    y: scroller.y + scroller.height + Theme.spaceS
                    width: scroller.width
                    visible: win.home
                    opacity: win.expanded ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
                    Chat { id: chat; width: dock.width }
                }
            }
        }
    }
}
