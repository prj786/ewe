import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

// Lock — a Quickshell session-lock (ext-session-lock-v1) styled from Theme.qml.
// Trigger with:  qs ipc call lock lock   (keybind / hypridle / lid script).
// Auth is real PAM (pam_unix via the "login" service). If anything ever wedges
// the lock, recover from a TTY (Ctrl+Alt+F3 → login → `loginctl unlock-session`).
Scope {
    id: root

    property string pw: ""
    property bool busy: false
    property string err: ""

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
        if (!pam.start()) { root.busy = false; root.err = "Authentication unavailable" }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { lock.locked = true }
        function unlock(): void { lock.locked = false }   // emergency only
        function toggle(): void { lock.locked = !lock.locked }
    }

    Timer { interval: 1000; running: lock.locked; repeat: true; triggeredOnStart: true; onTriggered: root.tick() }

    PamContext {
        id: pam
        config: "hyprlock"          // reuse hyprlock's purpose-built locker PAM stack (auth include login)
        onPamMessage: { if (pam.responseRequired) pam.respond(root.pw) }
        onCompleted: function (result) {
            root.busy = false
            root.pw = ""
            if (result === PamResult.Success) { root.err = ""; lock.locked = false }
            else if (result === PamResult.MaxTries) root.err = "Too many attempts — wait a moment"
            else root.err = "Incorrect password"
        }
        onError: function (e) { root.busy = false; root.pw = ""; root.err = "Authentication error" }
    }

    WlSessionLock {
        id: lock
        locked: false

        WlSessionLockSurface {
            id: surf

            Rectangle {
                anchors.fill: parent
                color: Theme.bg

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

                Column {
                    anchors.centerIn: parent
                    spacing: 16

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.clock
                        color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: 76; font.weight: Font.Bold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.dateStr
                        color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: 18
                    }

                    // avatar + user name
                    Item { width: 1; height: 16 }   // spacer
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 86; height: 86; radius: 43
                        color: Theme.elevated; border.color: Theme.stroke; border.width: 1
                        clip: true
                        Image {
                            id: face
                            anchors.fill: parent
                            source: Globals.faceUrl
                            visible: status === Image.Ready
                            fillMode: Image.PreserveAspectCrop
                            cache: false
                            sourceSize.width: 172; sourceSize.height: 172
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: face.status !== Image.Ready
                            text: root.userInitial
                            color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: 38; font.weight: Font.Bold
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.userName
                        color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 16; font.weight: Font.DemiBold
                    }

                    // password field — same look as the rest of the shell's inputs
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 300; height: 46; radius: Theme.radiusInner
                        color: Theme.elevated
                        border.color: root.err !== "" ? Theme.danger : Theme.accent
                        border.width: 2
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        // entered-password dots
                        Row {
                            anchors.centerIn: parent
                            spacing: 9
                            visible: root.pw.length > 0
                            Repeater {
                                model: Math.min(root.pw.length, 18)
                                delegate: Rectangle { width: 9; height: 9; radius: 5; color: Theme.fg }
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: root.pw.length === 0
                            text: root.busy ? "Authenticating…" : "Enter Password"
                            color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                        }
                    }

                    // error line
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.err
                        visible: root.err !== ""
                        color: Theme.danger; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                    }
                }
            }
        }
    }
}
