import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

// Lock — a Quickshell session-lock (ext-session-lock-v1) (design system:
// Lock screen, Glass). Trigger with: qs ipc call lock lock (keybind /
// hypridle / lid script). Auth is real PAM (pam_unix via the "login"
// service). If anything ever wedges the lock, recover from a TTY
// (Ctrl+Alt+F3 → login → `loginctl unlock-session`).
//
//   background  this output's wallpaper, blurred and dimmed
//   card        panelMd wide on the radiusRounded corner with shadowFloat —
//               the ONE Glass surface besides the bar and the dock, so its
//               fill follows the bar opacity setting and Hyprland blurs the
//               layer (EWE_NO_BLUR=1 leaves it translucent but sharp)
//   clock       the display-xl style (64, weight 300) with tabular figures
//               so the minute never shifts the line, and the date in body-lg
//               textSecondary
//   account     an icon4xl Avatar and the name in h4
//   password    a controlXl field with a lock glyph and a primary icon
//               button; a Spinner takes the button's place while PAM answers
//   message     a line that is ALWAYS reserved (lineHeightXs), so nothing
//               below it jumps when there is something to say
//
// EWE DARK, WHATEVER THE SCHEME (the decision list). The generator emits no
// second role set, so the neutral roles are read from the constant neutral
// ramp — which is the same in every scheme — at the Ewe Dark steps in
// guidelines/40-implementation.md. The accent stays the person's own.
Scope {
    id: root

    property string pw: ""
    property bool busy: false
    property string err: ""

    // ── the Ewe Dark roles, in tokens (see the header) ────────────────────
    readonly property color inkPrimary:   Theme.neutral50
    readonly property color inkSecondary: Theme.neutral300
    readonly property color inkMuted:     Theme.neutral400
    readonly property color cardFill:     Theme.neutral900
    readonly property color wellFill:     Theme.black
    readonly property color wellBorder:   Theme.neutral500

    readonly property string userName: Quickshell.env("USER") || "user"
    readonly property string userInitial: userName.length > 0 ? userName.charAt(0).toUpperCase() : "?"
    // avatar state lives in Globals (shared with Settings, which can replace
    // ~/.face at runtime); Globals.faceUrl is already cache-busted

    property string clock: ""
    property string dateStr: ""
    function tick() {
        var d = new Date()
        root.clock = Qt.formatDateTime(d, "h:mm AP")
        root.dateStr = Qt.formatDateTime(d, "dddd, d MMMM")
    }

    function submit() {
        if (root.busy || root.pw.length === 0) return
        root.err = ""
        root.busy = true
        if (!pam.start()) { root.busy = false; root.err = "Couldn\u2019t reach the password check." }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.locked = true }
        function unlock(): void { root.locked = false }   // emergency only
        function toggle(): void { root.locked = !root.locked }
    }

    // ── logind ────────────────────────────────────────────────────────────────
    // `loginctl lock-session` / `unlock-session` emit Lock/Unlock on our session.
    // The header above has promised the unlock-session escape hatch since this
    // file was written, but nothing listened for it until now — hypridle owned
    // the Lock signal and there was no unlock path at all.
    Connections {
        target: Logind
        function onLockRequested() { root.locked = true }
        function onUnlockRequested() { root.locked = false }
        // We hold a logind delay inhibitor, so this runs BEFORE the machine
        // suspends rather than racing it. Lock, then release immediately — the
        // lock surface is up synchronously, so there is nothing to wait for.
        function onAboutToSleep() {
            root.locked = true
            Logind.sleepReady()
        }
    }
    // One source of truth for "is the screen locked": OUR property, which the
    // WlSessionLock follows via binding. quickshell 0.3.1's WlSessionLock.locked
    // reads back what you set but emits no change signal, so anything bound to
    // it (the clock Timer, the LockedHint mirror) silently froze — never bind
    // to lock.locked, bind to root.locked.
    property bool locked: false
    onLockedChanged: {
        Globals.locked = root.locked                    // one shell-wide source of truth
        Logind.setLockedHint(root.locked)
        if (root.locked) Globals.saverDimming = false   // the lock replaces the dim
    }

    // The lock clock's Timer was frozen mid-tick through the suspend, so the
    // displayed minute is stale on wake — which is the first thing you look at.
    // Just re-tick: the timer re-aims itself on its next fire, and restart()
    // here would break `running: lock.locked`.
    Connections {
        target: Resume
        function onResyncTime() { root.tick() }
    }

    // minute-aligned — the lock clock shows "h:mm", so a 1 s tick bought nothing
    Timer {
        id: lockClock
        interval: 1000; running: root.locked; repeat: true; triggeredOnStart: true
        onTriggered: {
            root.tick()
            lockClock.interval = 60000 - (Date.now() % 60000)
        }
    }

    PamContext {
        id: pam
        config: "hyprlock"          // reuse hyprlock's purpose-built locker PAM stack (auth include login)
        onPamMessage: { if (pam.responseRequired) pam.respond(root.pw) }
        onCompleted: function (result) {
            root.busy = false
            root.pw = ""
            if (result === PamResult.Success) { root.err = ""; root.locked = false }
            else if (result === PamResult.MaxTries) root.err = "Too many attempts. Wait a moment and try again."
            else root.err = "Wrong password. Try again."
        }
        onError: function (e) { root.busy = false; root.pw = ""; root.err = "Couldn\u2019t check the password." }
    }

    WlSessionLock {
        id: lock
        locked: root.locked

        WlSessionLockSurface {
            id: surf

            // 2026-09-13 remaster: the desktop RECEDES rather than a curtain
            // dropping — this output's wallpaper, blurred and dimmed (the
            // Overview's recipe), with one glass card on it. A video wallpaper
            // (which Image cannot draw) falls back to the flat ground.
            Rectangle {
                anchors.fill: parent
                color: root.wellFill                // opaque ground, always (the protocol wants one)

                readonly property string wall: surf.screen ? Wallpaper.pathFor(surf.screen.name) : ""
                Image {
                    id: wallImg
                    anchors.fill: parent
                    source: parent.wall ? "file://" + parent.wall : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize: Qt.size(surf.width, surf.height)
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: wallImg
                    visible: wallImg.status === Image.Ready
                    blurEnabled: true
                    blurMax: 2 * Theme.blurGlass
                    blur: 0.75
                }
                // the desktop recedes: the wallpaper under the card's own scrim
                Rectangle { anchors.fill: parent; color: Theme.scrim }

                // keyboard capture — multi-monitor safe (no TextInput focus juggling)
                Item {
                    id: kb
                    anchors.fill: parent
                    focus: true
                    Component.onCompleted: forceActiveFocus()
                    Keys.onPressed: function (e) {
                        if (root.busy) { e.accepted = true; return }
                        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.submit()
                        else if (e.key === Qt.Key_Backspace) root.pw = root.pw.slice(0, -1)
                        else if (e.key === Qt.Key_Escape) root.pw = ""
                        else if (e.text.length === 1 && e.text.charCodeAt(0) >= 0x20) root.pw += e.text
                        e.accepted = true
                    }
                }

                // the card: clock, date, who, and the field — the one Glass
                // surface besides the bar and the dock
                Rectangle {
                    id: card
                    anchors.centerIn: parent
                    width: Theme.panelMd
                    height: col.implicitHeight + 2 * Theme.spaceLg
                    radius: Theme.radiusRounded
                    color: Theme.glass ? Theme.withAlpha(root.cardFill, Theme.barAlpha) : root.cardFill
                    // glass keeps its edge so the card reads over any wallpaper
                    border.color: Theme.glassBorder
                    border.width: Theme.glass ? Theme.borderWidth1 : 0
                    layer.enabled: true
                    layer.effect: Elevation {}
                }
                Column {
                    id: col
                    anchors.centerIn: parent
                    spacing: Theme.spaceMd

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.spaceXxs
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.clock
                            color: root.inkPrimary
                            font.family: Theme.type.displayXl.family
                            font.pixelSize: Theme.type.displayXl.size
                            font.weight: Theme.type.displayXl.weight
                            font.letterSpacing: Theme.type.displayXl.letterSpacing
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.dateStr
                            color: root.inkSecondary
                            font.family: Theme.type.bodyLg.family
                            font.pixelSize: Theme.type.bodyLg.size
                        }
                    }

                    // avatar + user name
                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.spaceS
                        Avatar {
                            anchors.horizontalCenter: parent.horizontalCenter
                            size: Theme.icon4xl
                            initial: root.userInitial
                            // Ewe Dark whatever the scheme: the surface-hover
                            // step, with the person's accent for the letter
                            plateColor: Theme.neutral800
                            inkColor: Theme.accent
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.userName
                            color: root.inkPrimary
                            font.family: Theme.type.h4.family
                            font.pixelSize: Theme.type.h4.size
                            font.weight: Theme.type.h4.weight
                        }
                    }

                    // the password field: a lock glyph, the typed dots and a
                    // primary button — the Spinner takes its place while PAM
                    // is answering
                    Rectangle {
                        id: field
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Theme.panelMd - 2 * Theme.spaceLg
                        height: Theme.controlXl
                        radius: Theme.radiusPrimary
                        color: root.wellFill
                        border.width: Theme.fieldBorderWidth
                        border.color: root.err !== "" ? Theme.danger
                                    : root.pw.length > 0 ? Theme.focusRing : root.wellBorder
                        Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }

                        Text {
                            id: fieldIcon
                            anchors.left: parent.left; anchors.leftMargin: Theme.spaceS + Theme.spaceXs
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.icLock
                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconLg
                            color: root.inkMuted
                        }
                        // entered-password dots
                        Row {
                            anchors.left: fieldIcon.right; anchors.leftMargin: Theme.spaceS
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spaceXs + Theme.spaceXxs
                            visible: root.pw.length > 0
                            Repeater {
                                model: Math.min(root.pw.length, 18)
                                delegate: Rectangle {
                                    width: Theme.spaceS; height: Theme.spaceS
                                    radius: Theme.radiusFull
                                    color: root.inkPrimary
                                }
                            }
                        }
                        Text {
                            anchors.left: fieldIcon.right; anchors.leftMargin: Theme.spaceS
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.pw.length === 0
                            text: "Password"
                            color: root.inkMuted
                            font.family: Theme.type.bodyLg.family
                            font.pixelSize: Theme.type.bodyLg.size
                        }
                        // primary icon button, or the Spinner while unlocking
                        Rectangle {
                            id: go
                            anchors.right: parent.right; anchors.rightMargin: Theme.spaceXs
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.controlLg; height: Theme.controlLg
                            radius: Theme.radiusPrimary
                            visible: !root.busy
                            // nothing typed: the Button's disabled look, in the
                            // Ewe Dark steps (surfaceRaised, borderSubtle,
                            // textDisabled) instead of a faded accent
                            readonly property bool ready: root.pw.length > 0
                            color: !go.ready ? Theme.neutral900
                                 : goMa.pressed ? Theme.accentPressed
                                 : goMa.containsMouse ? Theme.accentHover : Theme.accent
                            border.color: go.ready ? "transparent" : Theme.neutral800
                            border.width: Theme.borderWidth1
                            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                            Text {
                                anchors.centerIn: parent
                                text: Theme.icChevronRight
                                font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                                color: go.ready ? Theme.onAccent : Theme.neutral600
                            }
                            MouseArea {
                                id: goMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.submit()
                            }
                        }
                        Spinner {
                            anchors.right: parent.right; anchors.rightMargin: Theme.spaceS + Theme.spaceXs
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.busy
                            size: Theme.iconLg
                        }
                    }

                    // the message line, always reserved so nothing jumps
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: field.width
                        height: Theme.lineHeightXs
                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spaceXs
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.err !== ""
                                text: Theme.icWarning
                                font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
                                color: Theme.danger
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.err !== "" ? root.err
                                    : root.busy ? "Unlocking…"
                                    : "Type your password to unlock"
                                color: root.err !== "" ? Theme.danger : root.inkSecondary
                                font.family: Theme.type.caption.family
                                font.pixelSize: Theme.type.caption.size
                            }
                        }
                    }
                }
            }
        }
    }
}
