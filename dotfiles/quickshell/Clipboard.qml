import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland

// Clipboard — a Win+V-style popup opened by the bar's scissors icon. Two tabs:
//   • Clipboard: history (via cliphist); click an entry to copy it.
//   • Emoji: a grid of emoji; click to copy.
// Anything you copy gets recorded by the `wl-paste --watch cliphist store`
// daemon (autostart), so new copies appear here.
Scope {
    id: root

    // all colours come from Theme.qml (single source of truth)
    function g(c) { return String.fromCodePoint(c) }

    property int tab: 0                 // 0 = clipboard, 1 = emoji
    property var clips: []              // [{ id, preview }]
    property bool cliphistOk: true
    property string filter: ""

    readonly property var emojis: [
        "😀","😃","😄","😁","😆","😅","🤣","😂","🙂","🙃","😉","😊","😇","🥰","😍","🤩",
        "😘","😗","😚","😙","😋","😛","😜","🤪","😝","🤗","🤭","🤫","🤔","😐","😑","😶",
        "😏","😒","🙄","😬","😴","😪","😮","😯","😲","🥱","😌","😔","😕","🙁","☹️","😣",
        "😖","😫","😩","🥺","😢","😭","😤","😠","😡","🤬","🤯","😳","🥵","🥶","😱","😨",
        "😰","😥","🤝","🙏","👍","👎","👊","✊","🤛","🤜","👏","🙌","👐","🤲","🤙","💪",
        "👈","👉","👆","👇","☝️","✋","🤚","🖐️","🖖","👋","🤟","✌️","🤞","🫶","❤️","🧡",
        "💛","💚","💙","💜","🖤","🤍","🤎","💔","❣️","💕","💞","💓","💗","💖","💘","💝",
        "🔥","✨","⭐","🌟","💫","⚡","💥","💯","✅","❌","❓","❗","💤","🎉","🎊","🎁",
        "🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐨","🐯","🦁","🐮","🐷","🐸","🐵","🐔",
        "🍎","🍊","🍋","🍌","🍉","🍇","🍓","🍒","🍑","🥝","🍅","🥑","🌽","🍞","🧀","🍕",
        "🍔","🍟","🌮","🍣","🍜","🍩","🍪","🎂","🍰","☕","🍵","🍺","🍷","🥂","🍸","🧋",
        "⚽","🏀","🏈","⚾","🎾","🎮","🎯","🎲","🎸","🎧","🎤","💻","📱","⌨️","🖱️","🖥️",
        "🚗","✈️","🚀","🏠","🌍","🌙","☀️","☁️","🌧️","❄️","🌈","💡","🔑","🔒","📌","📎"
    ]

    function refresh() { if (Globals.clipboardOpen) clipList.running = true }
    function copyClip(id) { Quickshell.execDetached(["sh", "-c", "cliphist decode " + id + " | wl-copy"]); Globals.clipboardOpen = false }
    function copyEmoji(e) { Quickshell.execDetached(["wl-copy", "--", e]); Globals.clipboardOpen = false }
    function clearClips() { Quickshell.execDetached(["cliphist", "wipe"]); root.clips = []; }

    Connections { target: Globals; function onClipboardOpenChanged() { if (Globals.clipboardOpen) { root.filter = ""; root.refresh() } } }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { Globals.clipboardOpen = !Globals.clipboardOpen }
        function show(): void { Globals.clipboardOpen = true }
        function hide(): void { Globals.clipboardOpen = false }
    }

    Process {
        id: clipList
        command: ["cliphist", "list"]
        onExited: function (code) { if (code !== 0) root.cliphistOk = false }
        stdout: StdioCollector {
            onStreamFinished: {
                root.cliphistOk = true
                var lines = this.text.split("\n"), arr = []
                for (var i = 0; i < lines.length; i++) {
                    if (!lines[i]) continue
                    var t = lines[i].indexOf("\t")
                    if (t < 0) continue
                    arr.push({ id: lines[i].slice(0, t), preview: lines[i].slice(t + 1) })
                }
                root.clips = arr
            }
        }
    }

    PanelWindow {
        id: win
        visible: Globals.clipboardOpen || win.held
        screen: {
            var s = Quickshell.screens, fm = Hyprland.focusedMonitor
            if (fm) for (var i = 0; i < s.length; i++) if (s[i].name === fm.name) return s[i]
            return s.length > 0 ? s[0] : null
        }
        color: "transparent"
        // Ignore (not exclusiveZone:0): span the FULL output, including under the
        // bar, so a click on the topbar also hits the click-outside MouseArea and
        // closes the popup. exclusiveZone:0 would force "Normal" mode → top at y=30.
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:clipboard"
        WlrLayershell.layer: WlrLayer.Overlay
        // Exclusive (not OnDemand): the popup is opened by a click on the *bar*,
        // so OnDemand never actually grants this surface keyboard focus and the
        // search field drops focus on the first pointer move. Exclusive keeps it.
        WlrLayershell.keyboardFocus: Globals.clipboardOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }

        // `held` keeps the window mapped through the close animation; set on
        // OPEN so no signal-order race can unmap it early (see Overview.qml)
        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durSlow + 60); onTriggered: win.held = false }
        Connections {
            target: Globals
            function onClipboardOpenChanged() {
                if (Globals.clipboardOpen) { closeTimer.stop(); win.held = true; searchField.forceActiveFocus() }
                else closeTimer.restart()
            }
        }

        MouseArea { anchors.fill: parent; onClicked: Globals.clipboardOpen = false }

        // Clip box pinned to the bar's bottom edge, positioned under the scissors
        // icon; the panel slides DOWN out of it (reads as part of the topbar).
        Item {
            id: clipBox
            anchors.top: parent.top
            anchors.topMargin: Theme.barHeight   // window spans the full output → offset by the bar
            x: Math.max(8, Math.min(Globals.clipAnchorX - width / 2, win.width - width - 8))
            width: 380
            height: 480
            clip: true

            Rectangle {
                id: panel
                width: parent.width
                height: parent.height
                y: Globals.clipboardOpen ? 0 : -height
                Behavior on y { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.ease } }
                // square top (flush with the bar), rounded bottom — drops out of the bar
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: Theme.radius
                bottomRightRadius: Theme.radius
                color: Theme.panel
                border.width: 0
                layer.enabled: true
                layer.effect: Elevation {}
                MouseArea { anchors.fill: parent }   // swallow

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                // ── tabs ──
                Row {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: [{ ic: 0xE198, label: "Clipboard" }, { ic: 0xE436, label: "Emoji" }]
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: (parent.width - 8) / 2
                            height: 34
                            radius: Theme.radiusInner
                            color: root.tab === index ? Theme.accent : Theme.elevated
                            Row {
                                anchors.centerIn: parent; spacing: 8
                                Text { anchors.verticalCenter: parent.verticalCenter; text: root.g(modelData.ic); font.family: Theme.fontIcons; font.pixelSize: 14; color: root.tab === index ? Theme.accentText : Theme.fg }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: root.tab === index ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = index }
                        }
                    }
                }

                // ── search (clipboard tab) + clear ──
                Item {
                    width: parent.width; height: 34; visible: root.tab === 0
                    Rectangle {
                        anchors.left: parent.left; anchors.right: clearBtn.left; anchors.rightMargin: 8
                        height: parent.height; radius: Theme.radiusInner
                        color: Theme.bg; border.color: searchField.activeFocus ? Theme.accent : Theme.stroke; border.width: 1
                        Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: Theme.icSearch; font.family: Theme.fontIcons; font.pixelSize: 12; color: Theme.fgDim }
                        TextInput {
                            id: searchField
                            anchors.fill: parent; anchors.leftMargin: 30; anchors.rightMargin: 10; verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                            onTextChanged: root.filter = text
                            Keys.onEscapePressed: Globals.clipboardOpen = false
                            Text { anchors.verticalCenter: parent.verticalCenter; visible: searchField.text.length === 0; text: "Search clipboard…"; color: Theme.fgDim; font: searchField.font }
                        }
                    }
                    Rectangle {
                        id: clearBtn
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: 34; height: 34; radius: Theme.radiusInner
                        color: clearMa.containsMouse ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.2) : Theme.elevated
                        Text { anchors.centerIn: parent; text: Theme.icTrash; font.family: Theme.fontIcons; font.pixelSize: 13; color: clearMa.containsMouse ? Theme.danger : Theme.fgDim }
                        MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clearClips() }
                    }
                }

                // ── clipboard list ──
                ListView {
                    id: clipView
                    width: parent.width
                    height: parent.height - (root.tab === 0 ? 88 : 44)
                    visible: root.tab === 0
                    clip: true
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    model: {
                        if (root.filter === "") return root.clips
                        var f = root.filter.toLowerCase(), out = []
                        for (var i = 0; i < root.clips.length; i++) if (root.clips[i].preview.toLowerCase().indexOf(f) >= 0) out.push(root.clips[i])
                        return out
                    }
                    delegate: Rectangle {
                        required property var modelData
                        width: clipView.width
                        height: 46
                        radius: Theme.radiusInner
                        color: clMa.containsMouse ? Theme.hover : Theme.elevated
                        Text {
                            anchors.fill: parent; anchors.margins: 10
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.preview
                            color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                            elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap
                        }
                        MouseArea { id: clMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.copyClip(modelData.id) }
                    }
                    // empty / missing-cliphist state
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 20
                        horizontalAlignment: Text.AlignHCenter
                        visible: clipView.count === 0
                        text: root.cliphistOk ? "Clipboard history is empty.\nCopy something to get started." : "cliphist isn't installed.\nRun: sudo pacman -S cliphist"
                        color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap
                    }
                }

                // ── emoji grid ──
                Flickable {
                    width: parent.width
                    height: parent.height - 44
                    visible: root.tab === 1
                    contentHeight: emojiGrid.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Grid {
                        id: emojiGrid
                        width: parent.width
                        columns: 8
                        Repeater {
                            model: root.emojis
                            delegate: Rectangle {
                                required property var modelData
                                width: emojiGrid.width / 8
                                height: width
                                radius: 8
                                color: emMa.containsMouse ? Theme.hover : "transparent"
                                Text { anchors.centerIn: parent; text: modelData; font.family: "Noto Color Emoji"; font.pixelSize: 22 }
                                MouseArea { id: emMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.copyEmoji(modelData) }
                            }
                        }
                    }
                }
            }
            }
        }
    }
}
