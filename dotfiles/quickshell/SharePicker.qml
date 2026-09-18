import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// SharePicker — the screen-share chooser for xdg-desktop-portal-hyprland.
//
// Any app that asks the portal for a ScreenCast (Cast to TV, OBS, a browser
// call, gpu-screen-recorder…) makes xdph run its picker. The stock one is a
// white Qt list of connector names — "DP-3"? "eDP-1"? — that tells you
// nothing about what you're about to share. xdph lets us swap it
// (screencopy:custom_picker_binary → /usr/local/bin/ewe-share-picker), and
// that wrapper simply asks THIS scope over IPC and waits on a fifo:
//
//     qs ipc call picker open <fifo> <allowTokenDefault>
//     $fifo.windows  ← $XDPH_WINDOW_SHARING_LIST, one "<handle>[HC>]<class>
//                      [HT>]<title>[HE>]<hyprAddress>[HA>]" per window
//
// We draw a modal on the focused monitor (design system: Share picker):
// every screen as a LIVE thumbnail (ScreencopyView — the same capture the
// Overview uses) named by its model, every shareable window with its live
// preview, and a region option (slurp). One click writes the answer line and
// closes; Esc / Cancel writes an empty line, which xdph reads as
// "cancelled". xdph's window handles are ITS resource ids, so the list it
// hands us is the source of truth for windows — we only use
// Hyprland.toplevels to find a preview for each address.
//
//   panel   at most panelLg + panelSm less spaceLg + spaceS (880) wide and
//           spaceXl + spaceMd (80) from the screen edges, surfaceRaised with
//           a borderWidth1 borderSubtle outline, the radiusRounded corner,
//           shadowFloat, spaceMd + spaceS of padding and spaceMd + spaceXxs
//           between sections, over `scrim`
//   card    surfaceSunken inside a borderWidth1 borderSubtle outline on the
//           radiusRounded corner, spaceS of padding, a 16:9 thumbnail on the
//           radiusPrimary corner, the name in body semibold and the meta line
//           in caption textMuted; hover surfaceHover with an accent edge
//   footer  above a borderWidth1 divider: the "remember" checkbox, then
//           "Select a region…" (secondary) and Cancel (ghost)
//
// NEW (the card): keyboard selection — the arrow keys walk the cards, Enter
// shares the one with the ring, Esc cancels.
Scope {
    id: root

    property string fifo: ""                 // "" = closed
    property bool allowToken: false          // "remember this choice" (xdph restore token)
    property var windows: []                 // [{handle, cls, title, addr, tl}]
    readonly property bool open: fifo !== ""

    IpcHandler {
        target: "picker"
        function open(fifo: string, allow: string): void { root.show(fifo, allow === "1") }
        function cancel(): void { root.answer("") }
        // scripted selection (tests): "screen:eDP-1" / "window:123" / "region:eDP-1@0,0,10,10"
        function select(sel: string): void { root.answer(sel) }
    }

    function show(path, allow) {
        if (root.open) root.answer("")      // a second prompt supersedes the first
        root.allowToken = allow
        root.windows = []
        root.fifo = path
        winList.running = true
    }

    // ONE line → fifo → wrapper → xdph. An empty line = cancel (no [SELECTION]).
    function answer(sel) {
        if (!root.open) return
        var line = sel === "" ? "" : ("[SELECTION]" + (root.allowToken ? "r" : "") + "/" + sel)
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$0" > "$1"', line, root.fifo])
        root.fifo = ""
        root.windows = []
    }

    // The window list xdph wrote beside the fifo. Each entry carries the
    // Hyprland window address; match it to a toplevel for the live preview.
    Process {
        id: winList
        command: ["sh", "-c", 'cat "$0.windows" 2>/dev/null', root.fifo]
        stdout: StdioCollector { onStreamFinished: root.windows = root.parseWindows(this.text) }
    }
    function normAddr(a) { return String(a || "").replace(/^0x/i, "").replace(/^0+/, "").toLowerCase() }
    function parseWindows(raw) {
        var out = [], tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
        var byAddr = {}
        for (var t = 0; t < tls.length; t++) if (tls[t].address) byAddr[normAddr(tls[t].address)] = tls[t]
        var ents = String(raw || "").split("[HA>]")
        for (var i = 0; i < ents.length; i++) {
            var e = ents[i]; if (e === "") continue
            var a = e.indexOf("[HC>]"), b = e.indexOf("[HT>]"), c = e.indexOf("[HE>]")
            if (a < 0 || b < 0 || c < 0) continue
            var handle = e.substring(0, a), cls = e.substring(a + 5, b), title = e.substring(b + 5, c)
            // hyprland pointers are < 2^48, so the decimal survives a double exactly
            var addr = parseInt(e.substring(c + 5), 10)
            var hex = isNaN(addr) ? "" : addr.toString(16)
            var tl = byAddr[normAddr(hex)] || null
            out.push({ handle: handle, cls: cls, title: title !== "" ? title : (cls !== "" ? cls : "Window"), tl: tl })
        }
        return out
    }
    function iconFor(cls) {
        if (!cls) return Quickshell.iconPath("application-x-executable")
        var e = DesktopEntries.heuristicLookup(cls)
        return Quickshell.iconPath(e && e.icon ? e.icon : cls, "application-x-executable")
    }
    function screenLabel(s) {
        if (!s) return ""
        if (/^(eDP|LVDS|DSI)/.test(s.name)) return "Built-in display"
        var m = String(s.model || "").trim()
        return m !== "" ? m : s.name
    }

    // region: hide the modal, let slurp draw, then answer with its geometry
    Process {
        id: slurp
        command: ["slurp", "-f", "%o@%x,%y,%w,%h"]
        stdout: StdioCollector {
            onStreamFinished: {
                var g = this.text.trim()
                if (g !== "") root.answer("region:" + g)
                else root.hidden = false
            }
        }
        onExited: (code, status) => { if (code !== 0) root.hidden = false }
    }
    property bool hidden: false

    // ── keyboard selection (new) ──────────────────────────────────────────
    // One index over displays then windows, so the arrows walk the panel in
    // reading order without the two grids having to know about each other.
    property int sel: -1
    readonly property int screenCount: root.open ? Quickshell.screens.length : 0
    readonly property int cardCount: root.screenCount + (root.open ? root.windows.length : 0)
    function step(d) {
        if (root.cardCount === 0) return
        root.sel = root.sel < 0 ? 0 : (root.sel + d + root.cardCount) % root.cardCount
    }
    function activate() {
        if (root.sel < 0 || root.sel >= root.cardCount) return
        if (root.sel < root.screenCount) root.answer("screen:" + Quickshell.screens[root.sel].name)
        else root.answer("window:" + root.windows[root.sel - root.screenCount].handle)
    }

    PanelWindow {
        id: win
        visible: root.open && !root.hidden
        screen: {
            var s = Quickshell.screens, fm = Hyprland.focusedMonitor
            if (fm) for (var i = 0; i < s.length; i++) if (s[i].name === fm.name) return s[i]
            return s.length > 0 ? s[0] : null
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:share-picker"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }

        Rectangle { anchors.fill: parent; color: Theme.scrim }
        MouseArea { anchors.fill: parent; onClicked: root.answer("") }   // click outside = cancel

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.answer("")
            Keys.onRightPressed: root.step(1)
            Keys.onDownPressed: root.step(1)
            Keys.onLeftPressed: root.step(-1)
            Keys.onUpPressed: root.step(-1)
            Keys.onReturnPressed: root.activate()
            Keys.onEnterPressed: root.activate()
            Keys.onSpacePressed: root.activate()
            Connections { target: win; function onVisibleChanged() {
                if (win.visible) { root.sel = -1; keys.forceActiveFocus() }
            } }
        }

        Rectangle {
            id: panel
            anchors.centerIn: parent
            // the card's bounds, in tokens
            width: Math.min(Theme.panelLg + Theme.panelSm - Theme.spaceLg - Theme.spaceS,
                            parent.width - 2 * (Theme.spaceXl + Theme.spaceMd))
            height: Math.min(body.implicitHeight + 2 * (Theme.spaceMd + Theme.spaceS),
                             parent.height - 2 * (Theme.spaceXl + Theme.spaceMd))
            radius: Theme.radiusRounded
            color: Theme.surfaceRaised
            border.color: Theme.borderSubtle
            border.width: Theme.borderWidth1
            layer.enabled: true
            layer.effect: Elevation {}
            MouseArea { anchors.fill: parent }       // eat clicks so they don't cancel

            // the body scrolls on a short screen instead of clipping the footer
            Flickable {
                anchors.fill: parent; anchors.margins: Theme.spaceMd + Theme.spaceS
                contentWidth: width; contentHeight: body.implicitHeight
                clip: true; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: body
                width: parent.width
                spacing: Theme.spaceMd + Theme.spaceXxs

                Column {
                    width: parent.width; spacing: Theme.spaceXxs
                    Text {
                        text: "Share your screen"
                        color: Theme.textPrimary
                        font.family: Theme.type.h3.family
                        font.pixelSize: Theme.type.h3.size
                        font.weight: Theme.type.h3.weight
                        font.letterSpacing: Theme.type.h3.letterSpacing
                    }
                    Text {
                        width: parent.width; wrapMode: Text.Wrap
                        text: "An app wants to see your screen. Pick a display, a window or a region; it is shared right away."
                        color: Theme.textSecondary
                        font.family: Theme.type.body.family
                        font.pixelSize: Theme.type.body.size
                    }
                }

                // ── screens: live thumbnails, named by model ──
                Column {
                    width: parent.width; spacing: Theme.spaceS
                    SectionTitle { text: "Displays" }
                    Flow {
                        width: parent.width; spacing: Theme.spaceS + Theme.spaceXs
                        Repeater {
                            // ONLY while the picker is open (2026-09-03). A
                            // ScreencopyView with a monitor as its captureSource
                            // holds an ext_output_image_capture_source_v1 for that
                            // output; this Scope is created eagerly by shell.qml,
                            // so an unguarded `model: Quickshell.screens` meant the
                            // shell held one per monitor from login to logout for a
                            // picker that is open for seconds a month. On a monitor
                            // hotplug the delegates rebuild against an output the
                            // compositor is tearing down, and the manager answers
                            //   ext_output_image_capture_source_manager_v1:
                            //     error -1: invalid output resource
                            // A Wayland protocol error is FATAL to the whole client,
                            // so the entire shell died on plugging a dock in — and
                            // took every app in ewe.service's cgroup with it when
                            // systemd restarted the unit (see systemd/ewe.service).
                            model: root.open ? Quickshell.screens : []
                            Rectangle {
                                id: scard
                                required property var modelData
                                required property int index
                                readonly property real aspect: modelData.height > 0 ? modelData.width / modelData.height : 16 / 9
                                readonly property bool picked: root.sel === scard.index
                                width: Quickshell.screens.length > 2
                                       ? (body.width - 2 * (Theme.spaceS + Theme.spaceXs)) / 3
                                       : (body.width - (Theme.spaceS + Theme.spaceXs)) / 2
                                height: thumb.height + label.height + 3 * Theme.spaceS
                                radius: Theme.radiusRounded
                                color: (sMa.containsMouse || scard.picked) ? Theme.surfaceHover : Theme.surfaceSunken
                                border.color: (sMa.containsMouse || scard.picked) ? Theme.accent : Theme.borderSubtle
                                border.width: Theme.borderWidth1
                                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                Rectangle {
                                    id: thumb
                                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.spaceS }
                                    height: Math.round(width / scard.aspect)
                                    radius: Theme.radiusPrimary; color: Theme.surfaceBase; clip: true
                                    ScreencopyView {
                                        anchors.fill: parent
                                        // belt and braces: drop the source the moment
                                        // the surface goes away, not just on close
                                        captureSource: win.visible ? scard.modelData : null
                                        live: win.visible
                                        paintCursor: false
                                    }
                                }
                                Column {
                                    id: label
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                                              margins: Theme.spaceS; bottomMargin: Theme.spaceS }
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: root.screenLabel(scard.modelData)
                                        color: Theme.textPrimary
                                        font.family: Theme.type.bodyStrong.family
                                        font.pixelSize: Theme.type.bodyStrong.size
                                        font.weight: Theme.fontWeightSemibold
                                    }
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: scard.modelData.name + " · " + scard.modelData.width + "×" + scard.modelData.height
                                        color: Theme.textMuted
                                        font.family: Theme.type.caption.family
                                        font.pixelSize: Theme.type.caption.size
                                    }
                                }
                                // the focus ring sits outside the card's edge
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -(parent.border.width + Theme.focusWidth)
                                    radius: Theme.radiusRounded
                                    color: "transparent"
                                    visible: scard.picked
                                    border.color: Theme.focusRing; border.width: Theme.focusWidth
                                    antialiasing: true
                                }
                                MouseArea { id: sMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.answer("screen:" + scard.modelData.name) }
                            }
                        }
                    }
                }

                // ── windows: what xdph offers, previewed when we can match a toplevel ──
                Column {
                    width: parent.width; spacing: Theme.spaceS
                    visible: root.windows.length > 0
                    SectionTitle { text: "Windows" }
                    Flickable {
                        width: parent.width
                        height: Math.min(winFlow.implicitHeight, 2 * Theme.panelLg / 4 + Theme.panelSm / 4)
                        contentHeight: winFlow.implicitHeight
                        clip: true
                        Flow {
                            id: winFlow
                            width: parent.width; spacing: Theme.spaceS + Theme.spaceXs
                            Repeater {
                                model: root.open ? root.windows : []
                                Rectangle {
                                    id: wcard
                                    required property var modelData
                                    required property int index
                                    readonly property bool picked: root.sel === root.screenCount + wcard.index
                                    width: (body.width - 3 * (Theme.spaceS + Theme.spaceXs)) / 4
                                    height: wthumb.height + wlabel.height + 3 * Theme.spaceS
                                    radius: Theme.radiusRounded
                                    color: (wMa.containsMouse || wcard.picked) ? Theme.surfaceHover : Theme.surfaceSunken
                                    border.color: (wMa.containsMouse || wcard.picked) ? Theme.accent : Theme.borderSubtle
                                    border.width: Theme.borderWidth1
                                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                    Rectangle {
                                        id: wthumb
                                        anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.spaceS }
                                        height: Theme.control2xl + Theme.controlMd
                                        radius: Theme.radiusPrimary; color: Theme.surfaceBase; clip: true
                                        ScreencopyView {
                                            id: wsc
                                            anchors.fill: parent
                                            visible: hasContent && !!captureSource
                                            captureSource: (wcard.modelData.tl && wcard.modelData.tl.wayland) ? wcard.modelData.tl.wayland : null
                                            live: win.visible
                                        }
                                        Image {
                                            anchors.centerIn: parent; visible: !wsc.visible
                                            width: Theme.icon2xl; height: Theme.icon2xl
                                            sourceSize.width: 2 * Theme.icon2xl; sourceSize.height: 2 * Theme.icon2xl
                                            mipmap: true
                                            source: root.iconFor(wcard.modelData.cls)
                                        }
                                    }
                                    Column {
                                        id: wlabel
                                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                                                  margins: Theme.spaceS; bottomMargin: Theme.spaceS }
                                        Text {
                                            width: parent.width; elide: Text.ElideRight
                                            text: wcard.modelData.title
                                            color: Theme.textPrimary
                                            font.family: Theme.type.bodyStrong.family
                                            font.pixelSize: Theme.type.bodyStrong.size
                                            font.weight: Theme.fontWeightSemibold
                                        }
                                        Text {
                                            width: parent.width; elide: Text.ElideRight
                                            text: wcard.modelData.cls
                                            color: Theme.textMuted
                                            font.family: Theme.type.caption.family
                                            font.pixelSize: Theme.type.caption.size
                                        }
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: -(parent.border.width + Theme.focusWidth)
                                        radius: Theme.radiusRounded
                                        color: "transparent"
                                        visible: wcard.picked
                                        border.color: Theme.focusRing; border.width: Theme.focusWidth
                                        antialiasing: true
                                    }
                                    MouseArea { id: wMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.answer("window:" + wcard.modelData.handle) }
                                }
                            }
                        }
                    }
                }

                // ── footer: remember · region · cancel, above a divider ──
                Column {
                    width: parent.width
                    spacing: Theme.spaceS + Theme.spaceXs
                    Rectangle { width: parent.width; height: Theme.borderWidth1; color: Theme.borderSubtle }
                    Item {
                        width: parent.width; height: Theme.controlMd
                        Row {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spaceS
                            Rectangle {
                                width: Theme.iconMd; height: Theme.iconMd
                                radius: Theme.radiusSlight
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.allowToken ? Theme.accent : Theme.surfaceSunken
                                border.color: root.allowToken ? Theme.accent : Theme.borderStrong
                                border.width: Theme.borderWidth1
                                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                Text {
                                    anchors.centerIn: parent; visible: root.allowToken
                                    text: Theme.icCheck
                                    font.family: Theme.fontIcons; font.pixelSize: Theme.iconXs
                                    color: Theme.onAccent
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.allowToken = !root.allowToken }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Remember for this app. Don\u2019t ask next time."
                                color: Theme.textSecondary
                                font.family: Theme.type.body.family
                                font.pixelSize: Theme.type.body.size
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.allowToken = !root.allowToken }
                            }
                        }
                        Row {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spaceS
                            Rectangle {
                                width: regionTxt.implicitWidth + 2 * (Theme.spaceS + Theme.spaceXs)
                                height: Theme.controlMd
                                radius: Theme.radiusPrimary
                                color: rMa.pressed ? Theme.surfacePressed
                                     : rMa.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                                border.color: Theme.borderStrong; border.width: Theme.borderWidth1
                                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                Text {
                                    id: regionTxt
                                    anchors.centerIn: parent; text: "Select a region…"
                                    color: Theme.textPrimary
                                    font.family: Theme.type.body.family
                                    font.pixelSize: Theme.type.body.size
                                    font.weight: Theme.fontWeightMedium
                                }
                                MouseArea { id: rMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.hidden = true; slurp.running = true } }
                            }
                            Rectangle {
                                width: cancelTxt.implicitWidth + 2 * (Theme.spaceS + Theme.spaceXs)
                                height: Theme.controlMd
                                radius: Theme.radiusPrimary
                                color: cMa.pressed ? Theme.surfacePressed
                                     : cMa.containsMouse ? Theme.surfaceHover : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                Text {
                                    id: cancelTxt
                                    anchors.centerIn: parent; text: "Cancel"
                                    color: Theme.textPrimary
                                    font.family: Theme.type.body.family
                                    font.pixelSize: Theme.type.body.size
                                    font.weight: Theme.fontWeightMedium
                                }
                                MouseArea { id: cMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.answer("") }
                            }
                        }
                    }
                }
            }
            }
        }
    }
}
