import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Splash — the after-login "Welcome, <user>" overlay. Shown once when the shell
// starts (i.e. right after the greeter hands off to the Hyprland session), then
// fades out as the desktop settles. Covers EVERY output. Plymouth handles the
// pre-greeter boot splash (phase 35); this is purely the session-start moment.
// Themed from Theme.qml.
Scope {
    id: root
    property bool done: false                 // true once faded out → all windows hide
    property string userName: ""              // display name (GECOS) or login name

    // Resolve the user's display name once. GECOS full name if set, else login name.
    Process {
        id: nameProc
        running: true
        command: ["sh", "-c", "n=$(getent passwd \"$(id -un)\" 2>/dev/null | cut -d: -f5 | cut -d, -f1); [ -n \"$n\" ] || n=$(id -un); printf '%s' \"$n\""]
        stdout: StdioCollector { onStreamFinished: { var t = this.text.trim(); if (t.length) root.userName = t } }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: win.modelData
            visible: !root.done
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell:splash"
            anchors { top: true; bottom: true; left: true; right: true }

            Rectangle {
                id: bg
                anchors.fill: parent
                color: Theme.bg

                // hold briefly, then fade the whole overlay (text included) out
                Timer { running: true; interval: 1500; onTriggered: fade.start() }
                NumberAnimation {
                    id: fade; target: bg; property: "opacity"
                    from: 1; to: 0; duration: 700; easing.type: Easing.OutCubic
                    onFinished: root.done = true
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    // brand mark (the ewe sheep, white line art), shipped in assets/logo.png
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        source: Qt.resolvedUrl("assets/logo.png")
                        sourceSize.width: 256; sourceSize.height: 256
                        width: 110; height: 110; smooth: true
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Welcome"
                        color: Theme.fgDim
                        font.family: Theme.fontDisplay; font.pixelSize: 22; font.weight: Font.Medium
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: text.length > 0
                        text: root.userName
                        color: Theme.fg
                        font.family: Theme.fontDisplay; font.pixelSize: 54; font.weight: Font.Bold
                    }
                    // thin accent underline that grows in — a subtle "loading" beat
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 3; radius: 2; color: Theme.accent
                        width: 0; opacity: 0.9
                        NumberAnimation on width { from: 0; to: 120; duration: 1400; easing.type: Easing.OutCubic; running: true }
                    }
                }
            }
        }
    }
}
