import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import qs
import "logic.js" as Logic

// ewe.safe — Quick Access: every item in Safe, one keystroke away
// (Super+Shift+P, a manifest keybind; the bar glyph opens it too). Search,
// then COPY — the password, the username, the one-time code — or open the
// item in the Safe window. Filling into the focused app is Super+P's job
// (ewe.passwords); Quick Access is for everything else.
//
// No password ever reaches this file: `ewe-safe copy` makes the daemon put
// it on the clipboard (past the clipboard history, cleared after a while).
// The one secret shown is a one-time code, while its item is selected.
//   Enter       copy password (a note: open it in Safe)
//   Ctrl+C      copy username          Ctrl+O     copy one-time code
//   Ctrl+Enter  open in Safe           Ctrl+N     new login
//   Ctrl+L      lock                   Esc        close
// Locked: Enter runs `ewe-safe unlock --ask` (Safe's own prompt; the master
// password is never typed here) and Quick Access comes back when it opens.
Scope {
    id: root
    property string pluginId: ""
    property var settings: ({})

    property bool open: false
    property var items: []            // item summaries (no secrets)
    property bool busy: false
    property string loadError: ""
    property string query: ""
    property int selected: 0
    property double closedAt: 0
    property bool resumeAfterUnlock: false
    // the selected item's one-time code: {id, value, until (ms)}
    property var otp: null
    property int otpLeft: 0

    readonly property var results: Logic.rank(root.items, root.query)
    readonly property var current: root.results.length > root.selected ? root.results[root.selected] : null
    onResultsChanged: if (root.selected >= root.results.length) root.selected = Math.max(0, root.results.length - 1)
    onCurrentChanged: root.wantOtp()

    function toggle() { root.open = !root.open }

    onOpenChanged: {
        if (root.open) {
            Shell.closePopups("ewe.safe")
            Shell.closeQuickSettings()   // one surface at a time (the tile's chevron opens the window instead)
            // reopened within two minutes (copy the username, paste, come
            // back for the password): the search stays where it was
            if (Date.now() - root.closedAt > Logic.REMEMBER_QUERY_MS) { root.query = ""; root.selected = 0; input.text = "" }
            root.load()
        } else {
            root.closedAt = Date.now()
            root.otp = null              // a code is a secret: gone with the panel
        }
    }

    function load() {
        root.loadError = ""
        if (!SafeState.unlocked) { root.items = []; return }
        if (listProc.running) return     // an unlock bumps the phase AND the generation
        root.busy = true
        listProc.running = true
    }
    Connections {
        target: SafeState
        function onGenerationChanged() { if (root.open) root.load() }
        function onPhaseChanged() { if (root.open) root.load() }
        function onUnlockFinished(ok) { if (ok && root.resumeAfterUnlock) { root.resumeAfterUnlock = false; root.open = true } }
    }
    Connections {
        target: Shell
        function onPopupsClosing(exceptId) { if (exceptId !== "ewe.safe") root.open = false }
        function onLockedChanged() { if (Shell.locked) root.open = false }
    }

    // ── actions ──────────────────────────────────────────────────────────
    function enter(ctrl) {
        if (SafeState.locked) { root.resumeAfterUnlock = true; root.open = false; SafeState.unlock(); return }
        if (SafeState.phase === "new") { root.open = false; SafeState.openApp(""); return }
        var it = root.current
        if (!it) return
        if (ctrl || it.kind === "note") { root.open = false; SafeState.openApp("show", it.id); return }
        root.copy("password")
    }
    function copy(field) {
        var it = root.current
        if (!it || !SafeState.unlocked) return
        if (field === "otp" && !it.has_otp) { Shell.toast("This item has no one-time code."); return }
        if (field === "username" && !it.username) { Shell.toast("This item has no username."); return }
        if (field === "password" && !it.has_password) { Shell.toast("This item has no password."); return }
        root.open = false                // the app gets its focus back to paste
        SafeState.copy(it.id, field)
    }
    function wantOtp() {
        root.otp = null
        otpDelay.stop()
        if (root.open && root.current && root.current.has_otp && SafeState.unlocked) otpDelay.start()
    }
    Timer { id: otpDelay; interval: Theme.durBase; onTriggered: root.fetchOtp() }
    function fetchOtp() {
        var it = root.current
        if (!it || !it.has_otp || otpProc.running) return
        otpProc.forId = it.id
        otpProc.command = Logic.otpArgv(SafeState.tool, it.id)
        otpProc.running = true
    }
    Timer {
        id: otpTick
        interval: 1000
        repeat: true
        running: root.open && root.otp !== null
        onTriggered: {
            if (!root.otp) return
            root.otpLeft = Math.max(0, Math.ceil((root.otp.until - Date.now()) / 1000))
            if (root.otpLeft <= 0) { root.otp = null; root.fetchOtp() }
        }
    }

    IpcHandler {
        target: "ewe.safe"
        function toggle(): void { root.toggle() }
        function open(): void { root.open = true }
        function hide(): void { root.open = false }
        function lock(): void { SafeState.lock() }
        function unlock(): void { SafeState.unlock() }
        function status(): string { return SafeState.statusJson() }
    }
    Component.onCompleted: Shell.registerAction("ewe.safe.toggle", function (anchor) { root.toggle() })

    Process {
        id: listProc
        command: [SafeState.tool, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false
                var d = null
                try { d = JSON.parse(this.text) } catch (e) { d = null }
                if (!d) { root.loadError = "Safe gave no answer."; return }
                if (!d.ok) {
                    if (d.error === "locked") { root.items = []; return }
                    root.loadError = d.message || d.error || "Couldn't list your items."
                    return
                }
                root.items = d.items || []
            }
        }
    }
    Process {
        id: otpProc
        property string forId: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var d = null
                try { d = JSON.parse(this.text) } catch (e) { d = null }
                if (!d || !d.ok || !root.current || root.current.id !== otpProc.forId) return
                var left = Math.max(1, d.expires_in || 30)
                root.otp = { id: otpProc.forId, value: Logic.otpText(d.value), until: Date.now() + left * 1000 }
                root.otpLeft = left
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
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:ewe.safe"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }

        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durSlow); onTriggered: win.held = false }
        Connections {
            target: root
            function onOpenChanged() {
                if (root.open) { closeTimer.stop(); win.held = true; input.forceActiveFocus() }
                else closeTimer.restart()
            }
        }

        MouseArea { anchors.fill: parent; onClicked: root.open = false }

        Rectangle {
            id: panel
            // the launcher's panel card: surfaceRaised, borderSubtle,
            // radiusRounded; wider with Text size
            width: Theme.grow(Theme.panelLg)
            height: col.implicitHeight + 2 * (Theme.spaceS + Theme.spaceXs)
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.24)
            radius: Theme.radiusRounded
            color: Theme.surfaceRaised
            border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
            opacity: root.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: root.open ? Theme.durBase : Theme.durFast; easing.type: Theme.ease } }
            transform: Translate {
                y: (root.open || Theme.reduceMotion) ? 0 : Theme.slideOffset
                Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            }
            layer.enabled: true
            layer.effect: Elevation {}
            MouseArea { anchors.fill: parent }   // clicks inside stay inside

            Column {
                id: col
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: Theme.spaceS + Theme.spaceXs
                spacing: Theme.spaceS

                // ── head: Safe, the count, New / Open / Lock ──
                Item {
                    width: parent.width; height: Theme.controlMd
                    Text {
                        id: mark
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: Theme.ic(0xe58f)       // Lucide "vault" — Safe's mark (App Icons decision)
                        font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: Theme.accentText
                    }
                    TextStrong {
                        id: title
                        anchors.left: mark.right; anchors.leftMargin: Theme.spaceS
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Safe"
                    }
                    TextCaption {
                        anchors.left: title.right; anchors.leftMargin: Theme.spaceS
                        anchors.verticalCenter: parent.verticalCenter
                        visible: SafeState.unlocked && SafeState.state.items >= 0
                        text: SafeState.state.items === 1 ? "1 item" : SafeState.state.items + " items"
                        color: Theme.textMuted
                    }
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spaceXxs
                        QsIconButton { ic: Theme.icPlus; visible: SafeState.unlocked && SafeState.appInstalled; onGo: { root.open = false; SafeState.openApp("new") } }
                        QsIconButton { ic: Theme.ic(0xe0b9); visible: SafeState.appInstalled; onGo: { root.open = false; SafeState.openApp(root.current ? "show" : "", root.current ? root.current.id : "") } }
                        QsIconButton { ic: Theme.icLock; visible: SafeState.unlocked; onGo: SafeState.lock() }
                    }
                }

                // ── search: the launcher's xl Search field ──
                Rectangle {
                    width: parent.width; height: Theme.controlXl; radius: Theme.radiusPrimary
                    color: Theme.surfaceSunken
                    border.color: input.activeFocus ? Theme.focusRing : Theme.borderStrong
                    border.width: Theme.fieldBorderWidth
                    Text { anchors.left: parent.left; anchors.leftMargin: Theme.spaceS + Theme.spaceXs; anchors.verticalCenter: parent.verticalCenter; text: Theme.icSearch; font.family: Theme.fontIcons; font.pixelSize: Theme.iconLg; color: Theme.textMuted }
                    TextInput {
                        id: input
                        anchors.fill: parent; anchors.leftMargin: Theme.spaceS + Theme.spaceXs + Theme.iconLg + Theme.spaceS; anchors.rightMargin: Theme.spaceS + Theme.spaceXs
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.textPrimary; font.family: Theme.type.bodyLg.family; font.pixelSize: Theme.type.bodyLg.size
                        selectionColor: Theme.accent; selectedTextColor: Theme.onAccent; selectByMouse: true; clip: true
                        readOnly: !SafeState.unlocked
                        onTextChanged: { root.query = text; root.selected = 0 }
                        Text { visible: input.text.length === 0; anchors.verticalCenter: parent.verticalCenter; text: "Search Safe"; color: Theme.textMuted; font: input.font }
                        Keys.onPressed: function (ev) {
                            var ctrl = ev.modifiers & Qt.ControlModifier
                            if (ev.key === Qt.Key_Escape) { root.open = false; ev.accepted = true }
                            else if (ev.key === Qt.Key_Down) { root.selected = Math.min(root.selected + 1, root.results.length - 1); ev.accepted = true }
                            else if (ev.key === Qt.Key_Up) { root.selected = Math.max(root.selected - 1, 0); ev.accepted = true }
                            else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { root.enter(!!ctrl); ev.accepted = true }
                            else if (ctrl && ev.key === Qt.Key_C && input.selectedText === "") { root.copy("username"); ev.accepted = true }
                            else if (ctrl && ev.key === Qt.Key_O) { root.copy("otp"); ev.accepted = true }
                            else if (ctrl && ev.key === Qt.Key_N) { if (SafeState.unlocked) { root.open = false; SafeState.openApp("new") } ev.accepted = true }
                            else if (ctrl && ev.key === Qt.Key_L) { SafeState.lock(); ev.accepted = true }
                        }
                    }
                }

                // ── the items: List rows, two lines each ──
                ListView {
                    id: list
                    readonly property int rowH: Math.max(Theme.controlXl, Theme.type.body.lineHeight + Theme.type.caption.lineHeight + 2 * Theme.spaceXs)
                    width: parent.width
                    height: root.results.length > 0 && SafeState.unlocked ? Math.min(root.results.length, 7) * (rowH + spacing) - spacing : 2 * Theme.control2xl
                    clip: true
                    spacing: Theme.spaceXxs
                    model: SafeState.unlocked ? root.results : []
                    currentIndex: root.selected
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool sel: index === root.selected
                        readonly property bool showOtp: row.sel && root.otp !== null && root.otp.id === modelData.id
                        width: list.width; height: list.rowH
                        radius: Theme.radiusSecondary
                        color: sel ? Theme.accentSubtle : rowMa.pressed ? Theme.surfacePressed : rowMa.containsMouse ? Theme.surfaceHover : "transparent"
                        Text {
                            id: kindGlyph
                            anchors.left: parent.left; anchors.leftMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter
                            text: modelData.kind === "note" ? Theme.icFile : Theme.ic(0xe4a3)   // Lucide key-round
                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: row.sel ? Theme.accentText : Theme.textSecondary
                        }
                        Column {
                            anchors.left: kindGlyph.right; anchors.leftMargin: Theme.spaceS + Theme.spaceXs
                            anchors.right: side.left; anchors.rightMargin: Theme.spaceS
                            anchors.verticalCenter: parent.verticalCenter
                            Text { width: parent.width; text: modelData.title; color: Theme.textPrimary
                                   font.family: Theme.type.body.family; font.pixelSize: Theme.type.body.size
                                   font.weight: row.sel ? Theme.fontWeightMedium : Theme.fontWeightRegular; elide: Text.ElideRight }
                            Text { width: parent.width; text: modelData.kind === "note" ? "Note" : modelData.username
                                   visible: text !== ""; color: Theme.textMuted
                                   font.family: Theme.type.caption.family; font.pixelSize: Theme.type.caption.size; elide: Text.ElideRight }
                        }
                        Row {
                            id: side
                            anchors.right: parent.right; anchors.rightMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spaceXs
                            TextMono { visible: row.showOtp; text: row.showOtp ? root.otp.value : ""; color: Theme.textPrimary; anchors.verticalCenter: parent.verticalCenter }
                            TextCaption { visible: row.showOtp; text: root.otpLeft + " s"; color: root.otpLeft <= 5 ? Theme.warning : Theme.textMuted; anchors.verticalCenter: parent.verticalCenter }
                            Text { visible: !row.showOtp && modelData.has_otp; text: Theme.ic(0xe1e0)   // Lucide timer: has a one-time code
                                   font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm; color: Theme.textMuted; anchors.verticalCenter: parent.verticalCenter }
                            TextCaption { visible: !row.showOtp; text: Logic.rowCaption(modelData); color: Theme.textMuted; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea {
                            id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { root.selected = row.index; root.enter(false) }
                        }
                    }
                    // the states — one Item, one message each
                    Item {
                        anchors.fill: parent
                        visible: list.count === 0
                        Spinner { anchors.centerIn: parent; visible: root.busy; size: Theme.iconMd }
                        Column {
                            anchors.centerIn: parent; width: parent.width - 2 * Theme.spaceMd; spacing: Theme.spaceXs
                            visible: !root.busy
                            TextBody {
                                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                                text: SafeState.phase === "missing" ? "Safe isn't installed."
                                    : SafeState.phase === "down" ? "Safe isn't running."
                                    : SafeState.phase === "new" ? "No safe on this computer yet."
                                    : SafeState.locked ? "Safe is locked — press Enter to unlock"
                                    : root.loadError !== "" ? root.loadError
                                    : root.items.length === 0 ? "Your safe is empty."
                                    : "Nothing matches “" + root.query + "”."
                                color: root.loadError !== "" && SafeState.unlocked ? Theme.danger : Theme.textSecondary
                                maximumLineCount: 2; elide: Text.ElideRight
                            }
                            TextCaption {
                                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                                text: SafeState.phase === "missing" ? "Install Safe from Komble."
                                    : SafeState.phase === "down" ? "Its service is stopped or not installed."
                                    : SafeState.phase === "new" ? "Press Enter to set one up in Safe."
                                    : SafeState.locked && SafeState.state.keyChanged ? "The master password was changed on another computer. Unlock with the new one."
                                    : SafeState.unlocked && root.items.length === 0 && root.loadError === "" ? "Ctrl+N adds a login."
                                    : ""
                                visible: text !== ""
                                color: Theme.textMuted
                                maximumLineCount: 3; elide: Text.ElideRight
                            }
                        }
                    }
                }

                // ── foot: the chords, then how the sync stands ──
                TextCaption {
                    width: parent.width
                    text: SafeState.locked ? "Enter unlock · Esc close"
                        : SafeState.phase === "new" ? "Enter open Safe · Esc close"
                        : !SafeState.unlocked ? "Esc close"
                        : (root.current && root.current.kind === "note")
                          ? "Enter open · Ctrl+N new · Ctrl+L lock · Esc close"
                          : "Enter copy password · Ctrl+C username · Ctrl+O code · Ctrl+Enter open · Ctrl+L lock"
                    color: Theme.textMuted
                    elide: Text.ElideRight
                }
                Row {
                    width: parent.width
                    spacing: Theme.spaceXs
                    visible: SafeState.syncLine !== ""
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: SafeState.attention !== "" ? Theme.icCloudAlert
                            : (SafeState.state.sync && SafeState.state.sync.state === "offline") ? Theme.icCloudOff
                            : Theme.icCloudOk
                        font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
                        color: SafeState.attention === "danger" ? Theme.danger
                             : SafeState.attention === "warning" ? Theme.warning : Theme.textMuted
                    }
                    TextCaption {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Theme.iconSm - Theme.spaceXs
                        text: SafeState.syncLine
                        color: SafeState.attention === "danger" ? Theme.danger : Theme.textMuted
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
