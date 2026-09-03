import QtQuick
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
// We draw a modal on the focused monitor: every screen as a LIVE thumbnail
// (ScreencopyView — the same capture the Overview uses) named by its model,
// every shareable window with its live preview, and a region option (slurp).
// One click writes the answer line and closes; Esc / Cancel writes an empty
// line, which xdph reads as "cancelled". xdph's window handles are ITS
// resource ids, so the list it hands us is the source of truth for windows —
// we only use Hyprland.toplevels to find a preview for each address.
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

        Rectangle { anchors.fill: parent; color: Theme.shadow }
        MouseArea { anchors.fill: parent; onClicked: root.answer("") }   // click outside = cancel

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.answer("")
            Connections { target: win; function onVisibleChanged() { if (win.visible) keys.forceActiveFocus() } }
        }

        Rectangle {
            id: panel
            anchors.centerIn: parent
            width: Math.min(900, parent.width - 80)
            height: Math.min(body.implicitHeight + 48, parent.height - 80)
            radius: Theme.radius
            color: Theme.panel
            border.color: Theme.stroke
            border.width: Theme.borderThin
            MouseArea { anchors.fill: parent }       // eat clicks so they don't cancel

            // the body scrolls on a short screen instead of clipping the footer
            Flickable {
                anchors.fill: parent; anchors.margins: 24
                contentWidth: width; contentHeight: body.implicitHeight
                clip: true; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: body
                width: parent.width
                spacing: 18

                Column {
                    width: parent.width; spacing: 4
                    Text {
                        text: "Share your screen"
                        color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge; font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width; wrapMode: Text.Wrap
                        text: "An app wants to see your screen. Click what it may have — a whole display, one window, or a region."
                        color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                    }
                }

                // ── screens: live thumbnails, named by model ──
                Column {
                    width: parent.width; spacing: 10
                    Text { text: "Displays"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase }
                    Flow {
                        width: parent.width; spacing: 12
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
                                readonly property real aspect: modelData.height > 0 ? modelData.width / modelData.height : 16 / 9
                                width: Quickshell.screens.length > 2 ? (body.width - 24) / 3 : (body.width - 12) / 2
                                height: thumb.height + 54
                                radius: Theme.radiusInner
                                color: sMa.containsMouse ? Theme.hover : Theme.elevated
                                border.color: sMa.containsMouse ? Theme.accent : "transparent"; border.width: Theme.border
                                Behavior on color { ColorAnimation { duration: Theme.durFast } }
                                Rectangle {
                                    id: thumb
                                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 8 }
                                    height: Math.round((width) / scard.aspect)
                                    radius: Theme.r(8); color: Theme.bg; clip: true
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
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                                    spacing: 1
                                    Text { width: parent.width; elide: Text.ElideRight; text: root.screenLabel(scard.modelData); color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                    Text { text: scard.modelData.name + " · " + scard.modelData.width + "×" + scard.modelData.height; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }
                                }
                                MouseArea { id: sMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.answer("screen:" + scard.modelData.name) }
                            }
                        }
                    }
                }

                // ── windows: what xdph offers, previewed when we can match a toplevel ──
                Column {
                    width: parent.width; spacing: 10
                    visible: root.windows.length > 0
                    Text { text: "Windows"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase }
                    Flickable {
                        width: parent.width
                        height: Math.min(winFlow.implicitHeight, 260)
                        contentHeight: winFlow.implicitHeight
                        clip: true
                        Flow {
                            id: winFlow
                            width: parent.width; spacing: 10
                            Repeater {
                                model: root.open ? root.windows : []
                                Rectangle {
                                    id: wcard
                                    required property var modelData
                                    width: (body.width - 30) / 4
                                    height: 118
                                    radius: Theme.radiusInner
                                    color: wMa.containsMouse ? Theme.hover : Theme.elevated
                                    border.color: wMa.containsMouse ? Theme.accent : "transparent"; border.width: Theme.border
                                    Behavior on color { ColorAnimation { duration: Theme.durFast } }
                                    Rectangle {
                                        id: wthumb
                                        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 8 }
                                        height: 70; radius: Theme.r(8); color: Theme.bg; clip: true
                                        ScreencopyView {
                                            id: wsc
                                            anchors.fill: parent
                                            visible: hasContent && !!captureSource
                                            captureSource: (wcard.modelData.tl && wcard.modelData.tl.wayland) ? wcard.modelData.tl.wayland : null
                                            live: win.visible
                                        }
                                        Image {
                                            anchors.centerIn: parent; visible: !wsc.visible
                                            width: 32; height: 32; sourceSize.width: 64; sourceSize.height: 64; mipmap: true
                                            source: root.iconFor(wcard.modelData.cls)
                                        }
                                    }
                                    Column {
                                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
                                        spacing: 0
                                        Text { width: parent.width; elide: Text.ElideRight; text: wcard.modelData.title; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                                        Text { width: parent.width; elide: Text.ElideRight; text: wcard.modelData.cls; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }
                                    }
                                    MouseArea { id: wMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.answer("window:" + wcard.modelData.handle) }
                                }
                            }
                        }
                    }
                }

                // ── footer: remember · region · cancel ──
                Item {
                    width: parent.width; height: 36
                    Row {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                        Rectangle {
                            width: 18; height: 18; radius: Theme.r(5)
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.allowToken ? Theme.accent : Theme.bg
                            border.color: root.allowToken ? Theme.accent : Theme.stroke
                            Text { anchors.centerIn: parent; visible: root.allowToken; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: 11; color: Theme.accentText }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.allowToken = !root.allowToken }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Remember for this app (no prompt next time)"
                            color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.allowToken = !root.allowToken }
                        }
                    }
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                        Rectangle {
                            width: 150; height: 36; radius: Theme.r(9)
                            color: rMa.containsMouse ? Theme.hover : Theme.elevated
                            Text { anchors.centerIn: parent; text: "Select a region…"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody }
                            MouseArea { id: rMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.hidden = true; slurp.running = true } }
                        }
                        Rectangle {
                            width: 100; height: 36; radius: Theme.r(9)
                            color: cMa.containsMouse ? Theme.hover : Theme.elevated
                            Text { anchors.centerIn: parent; text: "Cancel"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody }
                            MouseArea { id: cMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.answer("") }
                        }
                    }
                }
            }
            }
        }
    }
}
