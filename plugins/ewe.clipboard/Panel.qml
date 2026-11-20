import QtQuick
import Quickshell
import Quickshell.Io
import qs

// ewe.clipboard — Panel: the card the bar's scissors opens (API 3, 1.3.0:
// the shell's BarPopup — the same card as every bar dropdown, the System
// monitor's look). Two tabs: clipboard history (cliphist) and an emoji
// grid; click to copy. Service.qml records copies (wl-paste →
// clip-store.sh, which drops passwords); Widget.qml is the scissors.
//
//   head     the clipboard glyph, "Clipboard", the Clear button on the right
//            (the first click arms it — "Clear all?" in danger — the second
//            within a few seconds wipes)
//   tabs     Clipboard · Emoji (QsSegmented), when the emoji tab is on
//   search   the history filter; it has the keys as soon as the card opens
//            (exclusiveKeyboard: the card was opened by a click on the BAR)
//   list     two-line previews, click copies, right-click Copy / Delete
//
// Entry points: the action `ewe.clipboard.toggle` (registered here, run by
// Widget.qml with the scissors as the anchor) and IPC —
//     qs ipc call ewe.clipboard toggle          qs ipc call ewe.clipboard toggleAt 812
Scope {
    id: root
    property string pluginId: ""
    property var settings: ({})         // {emoji: bool}
    property real anchorX: -1           // the last scissors x (screen-local), for IPC toggles

    property int tab: 0                 // 0 = clipboard, 1 = emoji
    property var clips: []              // [{ id, preview }]
    property bool cliphistOk: true
    property string filter: ""
    readonly property bool open: pop.open

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

    function refresh() { if (pop.open) clipList.running = true }
    function copyClip(id) { Quickshell.execDetached(["sh", "-c", "cliphist decode " + id + " | wl-copy"]); pop.close() }
    function copyEmoji(e) { Quickshell.execDetached(["wl-copy", "--", e]); pop.close() }
    // Clear needs a second click (1.2.0): the first turns the trash into a
    // "Clear all?" pill for a few seconds; a wipe cannot be undone
    property bool clearArmed: false
    Timer { id: clearHold; interval: Math.max(1, 3 * Theme.durDim); onTriggered: root.clearArmed = false }
    function clearClips() {
        if (!root.clearArmed) { root.clearArmed = true; clearHold.restart(); return }
        root.clearArmed = false; clearHold.stop()
        Quickshell.execDetached(["cliphist", "wipe"]); root.clips = []
        Shell.toast("Clipboard history cleared")
    }
    // one entry: cliphist reads "<id>\t…" lines on stdin
    function deleteClip(id) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\t.\\n" "$1" | cliphist delete', "sh", String(id)])
        root.clips = root.clips.filter(function (c) { return c.id !== id })
    }
    // a row's right-click menu (ContextMenu): Copy, Delete
    ContextMenu { id: clipMenu; name: "clipboard-menu"; takesKeyboard: false }
    function clipMenuFor(c) {
        return [{ label: "Copy", icon: Theme.icClipboard, action: function () { root.copyClip(c.id) } },
                { separator: true },
                { label: "Delete", icon: Theme.icTrash, danger: true, action: function () { root.deleteClip(c.id) } }]
    }

    // an IPC toggle has no click to hang off: under the bar of the focused
    // display, at the scissors' last x (else the middle of the screen)
    function ipcAnchor(x) {
        var scr = Shell._focusedScreen()
        var ax = (x !== undefined && x !== null && x >= 0) ? x : root.anchorX >= 0 ? root.anchorX : (scr ? scr.width / 2 : 0)
        return { screen: scr, x: ax, y: 0, edge: "top" }
    }
    function toggle(anchor) {
        if (pop.open) { pop.close(); return }
        if (anchor && anchor.edge === "top") root.anchorX = anchor.x
        pop.openAt(anchor || root.ipcAnchor())
    }

    Component.onCompleted: Shell.registerAction("ewe.clipboard.toggle", function (a) { root.toggle(a) })
    Component.onDestruction: Shell.registerAction("ewe.clipboard.toggle", null)

    IpcHandler {
        target: "ewe.clipboard"
        function toggle(): void { root.toggle(null) }
        function toggleAt(x: int): void { root.anchorX = x; root.toggle(root.ipcAnchor(x)) }
        function hide(): void { pop.close() }
        function isOpen(): bool { return pop.open }
    }

    // `cliphist list` exits 1 ("please store something first") until the
    // first copy — a fresh install is an EMPTY history, not a missing tool:
    // only a missing binary (127) says "isn't installed"
    Process {
        id: clipList
        command: ["sh", "-c", "command -v cliphist >/dev/null 2>&1 || exit 127; cliphist list 2>/dev/null; exit 0"]
        onExited: function (code) { root.cliphistOk = code !== 127 }
        stdout: StdioCollector {
            onStreamFinished: {
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

    BarPopup {
        id: pop
        name: "ewe.clipboard"               // layer namespace quickshell:ewe.clipboard, as before
        owner: "ewe.clipboard"
        action: "ewe.clipboard.toggle"
        title: root.tab === 1 ? "Emoji" : "Clipboard"
        glyph: root.tab === 1 ? Theme.icSmile : Theme.icClipboard
        exclusiveKeyboard: true
        onOpened: {
            root.clearArmed = false; clearHold.stop(); clipMenu.close()
            root.filter = ""; searchField.text = ""; root.refresh()
            // after the card takes focus on open (AnchoredPopup)
            Qt.callLater(function () { if (root.tab === 0) searchField.forceActiveFocus() })
        }
        onClosed: { root.clearArmed = false; clearHold.stop(); clipMenu.close() }

        // Icon button (danger on hover): clears the history — the first
        // click arms it ("Clear all?" in danger), the second wipes
        headActions: Rectangle {
            id: clearBtn
            visible: root.tab === 0 && root.clips.length > 0
            width: root.clearArmed ? clearLbl.implicitWidth + 2 * Theme.spaceS : Theme.controlSm
            height: Theme.controlSm; radius: Theme.radiusPrimary
            color: clearMa.pressed ? Theme.surfacePressed : (clearMa.containsMouse || root.clearArmed) ? Theme.dangerSubtle : "transparent"
            border.color: root.clearArmed ? Theme.danger : "transparent"; border.width: Theme.borderWidth1
            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
            Behavior on width { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
            Accessible.role: Accessible.Button; Accessible.name: root.clearArmed ? "Clear all? Click again to confirm" : "Clear clipboard history"
            Text { visible: !root.clearArmed; anchors.centerIn: parent; text: Theme.icTrash; font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm; color: clearMa.containsMouse ? Theme.danger : Theme.textSecondary }
            Text { id: clearLbl; visible: root.clearArmed; anchors.centerIn: parent; text: "Clear all?"; color: Theme.danger
                   font.family: Theme.type.label.family; font.pixelSize: Theme.type.label.size; font.weight: Theme.fontWeightMedium }
            MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clearClips() }
            Tooltip { text: root.clearArmed ? "Click again to clear everything" : "Clear history" }
        }

        // ── tabs ──
        QsSegmented {
            visible: root.settings.emoji !== false
            width: parent.width
            options: [{ label: "Clipboard", value: 0 }, { label: "Emoji", value: 1 }]
            value: root.tab
            onPicked: function (v) { root.tab = v; if (v === 0) searchField.forceActiveFocus() }
        }

        // ── search (clipboard tab) ──
        QsField {
            id: searchBox
            visible: root.tab === 0
            width: parent.width
            focused: searchField.activeFocus
            Text { id: searchIcon; anchors.left: parent.left; anchors.leftMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter; text: Theme.icSearch; font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm; color: Theme.textMuted }
            TextInput {
                id: searchField
                anchors.fill: parent; anchors.leftMargin: Theme.spaceS + Theme.iconSm + Theme.spaceXs; anchors.rightMargin: Theme.spaceS
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.textPrimary; font.family: Theme.type.body.family; font.pixelSize: Theme.type.body.size
                selectionColor: Theme.accent; selectedTextColor: Theme.onAccent; clip: true
                onTextChanged: root.filter = text
                Keys.onPressed: function (ev) {
                    if (clipMenu.handleKey(ev)) { ev.accepted = true; return }     // an open row menu takes the keys first
                    if (ev.key === Qt.Key_Escape) { pop.close(); ev.accepted = true }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; visible: searchField.text.length === 0; text: "Search clipboard"; color: Theme.textMuted; font: searchField.font }
            }
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.IBeamCursor }
        }

        // ── clipboard list: a steady height, so filtering never jumps the card ──
        ListView {
            id: clipView
            width: parent.width
            height: Math.min(Theme.panelSm, pop.maxBodyHeight - (root.settings.emoji !== false ? Theme.controlMd + pop.pad : 0) - searchBox.height - pop.pad)
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
                id: clipRow
                required property var modelData
                width: clipView.width
                height: Math.max(Theme.controlXl, clipText.implicitHeight + 2 * Theme.spaceXs)
                radius: Theme.radiusSecondary
                color: clMa.pressed ? Theme.surfacePressed : clMa.containsMouse ? Theme.surfaceHover : "transparent"
                readonly property bool hot: clMa.containsMouse || delMa.containsMouse
                Text {
                    id: clipText
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: Theme.spaceS
                    // room for the delete button while the row is pointed at
                    anchors.rightMargin: Theme.spaceS + (clipRow.hot ? Theme.controlSm + Theme.spaceXs : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    text: clipRow.modelData.preview
                    color: Theme.textPrimary; font.family: Theme.type.body.family; font.pixelSize: Theme.type.body.size
                    lineHeight: Theme.type.body.lineHeight; lineHeightMode: Text.FixedHeight
                    elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap
                }
                // click copies; right-click → Copy / Delete
                MouseArea {
                    id: clMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function (m) {
                        if (m.button === Qt.RightButton) { clipMenu.items = root.clipMenuFor(clipRow.modelData); clipMenu.openAt(clMa, m.x, m.y) }
                        else root.copyClip(clipRow.modelData.id)
                    }
                }
                // per-entry delete (Icon button sm, danger on hover), on hover
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: Theme.spaceXs
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.controlSm; height: Theme.controlSm; radius: Theme.radiusSecondary
                    visible: clipRow.hot
                    color: delMa.containsMouse ? Theme.dangerSubtle : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                    Accessible.role: Accessible.Button; Accessible.name: "Delete this entry"
                    Text { anchors.centerIn: parent; text: Theme.icClose; font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm; color: delMa.containsMouse ? Theme.danger : Theme.textSecondary }
                    MouseArea { id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.deleteClip(clipRow.modelData.id) }
                    Tooltip { text: "Delete this entry" }
                }
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

        // ── emoji grid: the list's height, eight to a row ──
        Flickable {
            width: parent.width
            height: clipView.height + searchBox.height + pop.pad
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
