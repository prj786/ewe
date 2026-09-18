import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import qs

// ewe.clipboard — Panel: a Win+V-style popup the bar's scissors widget opens.
// Two tabs: clipboard history (cliphist) and an emoji grid; click to copy.
// Service.qml records copies (wl-paste → clip-store.sh, which drops
// passwords); Widget.qml is the scissors in the bar. The three talk over
// this plugin's IPC target only — no shell state is touched.
//     qs ipc call ewe.clipboard toggle          qs ipc call ewe.clipboard toggleAt 812
Scope {
    id: root
    property bool open: false
    property real anchorX: 0            // screen-local x of the scissors (the widget says)
    property var settings: ({})         // {emoji: bool}

    // every colour, size and duration comes from Theme (design system v3)
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

    function refresh() { if (root.open) clipList.running = true }
    function copyClip(id) { Quickshell.execDetached(["sh", "-c", "cliphist decode " + id + " | wl-copy"]); root.open = false }
    function copyEmoji(e) { Quickshell.execDetached(["wl-copy", "--", e]); root.open = false }
    function clearClips() { Quickshell.execDetached(["cliphist", "wipe"]); root.clips = []; }

    onOpenChanged: { if (root.open) { root.filter = ""; root.refresh() } }

    IpcHandler {
        target: "ewe.clipboard"
        function toggle(): void { root.open = !root.open }
        function toggleAt(x: int): void { root.anchorX = x; root.open = !root.open }
        function hide(): void { root.open = false }
        function isOpen(): bool { return root.open }
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
        visible: root.open || win.held
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
        WlrLayershell.namespace: "quickshell:ewe.clipboard"
        WlrLayershell.layer: WlrLayer.Overlay
        // Exclusive (not OnDemand): the popup is opened by a click on the *bar*,
        // so OnDemand never actually grants this surface keyboard focus and the
        // search field drops focus on the first pointer move. Exclusive keeps it.
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }

        // `held` keeps the window mapped through the close animation; set on
        // OPEN so no signal-order race can unmap it early (see Overview.qml)
        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durSlow + 60); onTriggered: win.held = false }
        Connections {
            target: root
            function onOpenChanged() {
                if (root.open) { closeTimer.stop(); win.held = true; searchField.forceActiveFocus() }
                else closeTimer.restart()
            }
        }

        MouseArea { anchors.fill: parent; onClicked: root.open = false }

        // Clip box pinned to the bar's bottom edge, positioned under the scissors
        // icon; the panel slides DOWN out of it (reads as part of the topbar).
        // A panel is solid (never Glass): surfaceRaised, a borderSubtle
        // outline, radiusRounded on the corners that hang free.
        Item {
            id: clipBox
            anchors.top: parent.top
            anchors.topMargin: Theme.barHeight   // window spans the full output → offset by the bar
            x: Math.max(Theme.windowGap, Math.min(root.anchorX - width / 2, win.width - width - Theme.windowGap))
            // wider in step with Text size, so the history keeps its lines
            width: Theme.grow(Theme.panelMd)
            height: Theme.panelLg
            clip: true

            Rectangle {
                id: panel
                width: parent.width
                height: parent.height
                y: root.open ? 0 : -height
                Behavior on y { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeSlow } }
                // square top (flush with the bar), rounded bottom — drops out of the bar
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: Theme.radiusRounded
                bottomRightRadius: Theme.radiusRounded
                color: Theme.surfaceRaised
                border.color: Theme.borderSubtle
                border.width: Theme.borderWidth1
                layer.enabled: true
                layer.effect: Elevation {}
                MouseArea { anchors.fill: parent }   // swallow

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spaceS + Theme.spaceXs
                spacing: Theme.spaceS

                // ── tabs: a full-width Segmented control (lg) ──
                Rectangle {
                    id: seg
                    visible: root.settings.emoji !== false
                    width: parent.width; height: Theme.controlLg
                    radius: Theme.radiusPrimary
                    color: Theme.surfaceSunken
                    border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                    Row {
                        anchors.fill: parent; anchors.margins: Theme.spaceXxs
                        spacing: Theme.spaceXxs
                        Repeater {
                            model: [{ ic: 0xE086, label: "Clipboard" }, { ic: 0xE164, label: "Emoji" }]
                            delegate: Rectangle {
                                id: segItem
                                required property var modelData
                                required property int index
                                readonly property bool sel: root.tab === index
                                width: (parent.width - parent.spacing) / 2
                                height: parent.height
                                radius: Theme.radiusSecondary
                                color: sel ? Theme.surfaceSelected : "transparent"
                                border.color: sel ? Theme.borderSubtle : "transparent"
                                border.width: Theme.borderWidth1
                                Row {
                                    anchors.centerIn: parent; spacing: Theme.spaceXs
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: root.g(segItem.modelData.ic); font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                                           color: segItem.sel || segMa.containsMouse ? Theme.textPrimary : Theme.textSecondary }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: segItem.modelData.label
                                           color: segItem.sel || segMa.containsMouse ? Theme.textPrimary : Theme.textSecondary
                                           font.family: Theme.type.bodyStrong.family; font.pixelSize: Theme.type.bodyStrong.size; font.weight: Theme.type.bodyStrong.weight }
                                }
                                MouseArea { id: segMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = segItem.index }
                            }
                        }
                    }
                }

                // ── search (clipboard tab) + clear ──
                Item {
                    id: searchRow
                    width: parent.width; height: Theme.controlMd; visible: root.tab === 0
                    // Search field (md): the Text field's box, its own border
                    // turns focusRing on focus
                    Rectangle {
                        anchors.left: parent.left; anchors.right: clearBtn.left; anchors.rightMargin: Theme.spaceS
                        height: parent.height; radius: Theme.radiusPrimary
                        color: Theme.surfaceSunken
                        border.color: searchField.activeFocus ? Theme.focusRing : searchMa.containsMouse ? Theme.textMuted : Theme.borderStrong
                        border.width: Theme.fieldBorderWidth
                        MouseArea { id: searchMa; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton; cursorShape: Qt.IBeamCursor }
                        Text { id: searchIcon; anchors.left: parent.left; anchors.leftMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter; text: Theme.icSearch; font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm; color: Theme.textMuted }
                        TextInput {
                            id: searchField
                            anchors.fill: parent; anchors.leftMargin: Theme.spaceS + Theme.iconSm + Theme.spaceXs; anchors.rightMargin: Theme.spaceS
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.textPrimary; font.family: Theme.type.body.family; font.pixelSize: Theme.type.body.size
                            selectionColor: Theme.accent; selectedTextColor: Theme.onAccent; clip: true
                            onTextChanged: root.filter = text
                            Keys.onEscapePressed: root.open = false
                            Text { anchors.verticalCenter: parent.verticalCenter; visible: searchField.text.length === 0; text: "Search clipboard"; color: Theme.textMuted; font: searchField.font }
                        }
                    }
                    // Icon button (md, danger on hover): clears the history
                    Rectangle {
                        id: clearBtn
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: Theme.controlMd; height: Theme.controlMd; radius: Theme.radiusPrimary
                        color: clearMa.pressed ? Theme.surfacePressed : clearMa.containsMouse ? Theme.dangerSubtle : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        Accessible.role: Accessible.Button; Accessible.name: "Clear clipboard history"
                        Text { anchors.centerIn: parent; text: Theme.icTrash; font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: clearMa.containsMouse ? Theme.danger : Theme.textSecondary }
                        MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clearClips() }
                    }
                }

                // ── clipboard list ──
                ListView {
                    id: clipView
                    width: parent.width
                    height: parent.height - (seg.visible ? seg.height + parent.spacing : 0) - searchRow.height - parent.spacing
                    visible: root.tab === 0
                    clip: true
                    spacing: Theme.spaceXxs
                    boundsBehavior: Flickable.StopAtBounds
                    model: {
                        if (root.filter === "") return root.clips
                        var f = root.filter.toLowerCase(), out = []
                        for (var i = 0; i < root.clips.length; i++) if (root.clips[i].preview.toLowerCase().indexOf(f) >= 0) out.push(root.clips[i])
                        return out
                    }
                    // a List row (two lines of preview): surfaceHover on
                    // hover, surfacePressed while pressed
                    delegate: Rectangle {
                        required property var modelData
                        width: clipView.width
                        height: Math.max(Theme.controlXl, clipText.implicitHeight + 2 * Theme.spaceXs)
                        radius: Theme.radiusSecondary
                        color: clMa.pressed ? Theme.surfacePressed : clMa.containsMouse ? Theme.surfaceHover : "transparent"
                        Text {
                            id: clipText
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.preview
                            color: Theme.textPrimary; font.family: Theme.type.body.family; font.pixelSize: Theme.type.body.size
                            lineHeight: Theme.type.body.lineHeight; lineHeightMode: Text.FixedHeight
                            elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap
                        }
                        MouseArea { id: clMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.copyClip(modelData.id) }
                    }
                    // Empty state: what is missing, then what to do
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 2 * Theme.spaceMd
                        spacing: Theme.spaceXs
                        visible: clipView.count === 0
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.cliphistOk ? Theme.icClipboard : Theme.icWarning
                            font.family: Theme.fontIcons; font.pixelSize: Theme.icon2xl; color: Theme.textMuted
                        }
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                            text: root.cliphistOk ? (root.filter === "" ? "Clipboard history is empty" : "Nothing matches “" + root.filter + "”")
                                                  : "cliphist isn’t installed"
                            color: Theme.textPrimary; font.family: Theme.type.bodyStrong.family; font.pixelSize: Theme.type.bodyStrong.size; font.weight: Theme.type.bodyStrong.weight
                        }
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                            visible: root.filter === "" || !root.cliphistOk
                            text: root.cliphistOk ? "Copy something and it shows up here." : "Install it with: sudo pacman -S cliphist"
                            color: Theme.textMuted; font.family: Theme.type.caption.family; font.pixelSize: Theme.type.caption.size
                        }
                    }
                }

                // ── emoji grid ──
                Flickable {
                    width: parent.width
                    height: parent.height - seg.height - parent.spacing
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
                                width: emojiGrid.width / emojiGrid.columns
                                height: width
                                radius: Theme.radiusPrimary
                                color: emMa.pressed ? Theme.surfacePressed : emMa.containsMouse ? Theme.surfaceHover : "transparent"
                                Text { anchors.centerIn: parent; text: modelData; font.family: "Noto Color Emoji"; font.pixelSize: Theme.iconXl }
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
