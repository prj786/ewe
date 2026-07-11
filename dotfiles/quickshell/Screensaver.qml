import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Hyprland

// Screensaver — decorative idle overlay across all outputs. NOT a lock: any
// key/click/motion dismisses it (flip "Require password" on Settings →
// Screensaver to idle straight into the real session lock instead). Timing is
// owned by hypridle via the generated hypridle.conf, whose listeners call
// `qs ipc call saver show` / `hide`; on-resume also hides it, so even if the
// overlay misses an input the compositor's resume signal dismisses it.
Scope {
    id: root

    IpcHandler {
        target: "saver"
        // gate on the setting so a stale hypridle config can't flash the saver
        function show(): void { if (Globals.saverEnabled && !Globals.saverLock) Globals.saverActive = true }
        function hide(): void { Globals.saverActive = false }
        function toggle(): void { Globals.saverActive = !Globals.saverActive }
    }

    // Auto idle-inhibit: playing media or a fullscreen focused window holds a
    // wayland idle inhibitor (same mechanism as Caffeine, own 1px surface), so
    // NO idle stage fires — saver, lock or suspend. Most video players inhibit
    // on their own; this covers the ones that don't and audio-only playback.
    property bool mediaPlaying: false
    Timer {
        interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            var ps = Mpris.players.values, on = false
            for (var i = 0; i < ps.length; i++) if (ps[i].isPlaying) { on = true; break }
            root.mediaPlaying = on
        }
    }
    property bool fullscreenFocused: false
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name === "fullscreen" || ev.name === "activewindow" || ev.name === "workspace") fsProbe.restart()
        }
    }
    Timer { id: fsProbe; interval: 300; onTriggered: { fsProc.running = false; fsProc.running = true } }
    Process {
        id: fsProc
        command: ["sh", "-c", "hyprctl -j activewindow 2>/dev/null | grep -c '\"fullscreen\": [1-9]'"]
        stdout: StdioCollector { onStreamFinished: root.fullscreenFocused = this.text.trim() === "1" }
    }
    PanelWindow {
        id: inhibitWin
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        visible: true
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.namespace: "quickshell:saver-inhibit"
        WlrLayershell.layer: WlrLayer.Background
        anchors { top: true; left: true }
        IdleInhibitor {
            window: inhibitWin
            enabled: root.mediaPlaying || root.fullscreenFocused
        }
    }

    // ── the saver itself — one fullscreen overlay per output ──────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: w
            required property var modelData
            screen: modelData
            visible: Globals.saverActive
            color: "black"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:screensaver"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: Globals.saverActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }

            // ignore pointer motion for a moment after mapping — the enter event
            // the surface receives on show must not instantly dismiss it
            Timer { id: dismissArm; interval: 700 }
            onVisibleChanged: if (visible) dismissArm.restart()
            function dismiss() { Globals.saverActive = false }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: w.dismiss()
                opacity: Globals.saverActive ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.durSlow } }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: w.dismiss()
                    onPositionChanged: if (!dismissArm.running) w.dismiss()
                }
                Loader {
                    anchors.fill: parent
                    active: Globals.saverActive
                    sourceComponent: Globals.saverStyle === "blank" ? blankSaver : clockSaver
                }
            }

            // ── styles (pluggable — add a component + a Settings option) ──────
            Component { id: blankSaver; Item {} }
            Component {
                id: clockSaver
                Item {
                    id: clockRoot
                    property date now: new Date()
                    Timer { interval: 1000; running: Globals.saverActive; repeat: true; triggeredOnStart: true; onTriggered: clockRoot.now = new Date() }
                    Column {
                        anchors.centerIn: parent
                        spacing: 10
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatTime(clockRoot.now, "h:mm")
                            color: Theme.fg; opacity: 0.92
                            font.family: Theme.fontDisplay; font.pixelSize: 132; font.weight: Font.Bold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDate(clockRoot.now, "dddd, d MMMM")
                            color: Theme.fgSecondary
                            font.family: Theme.fontText; font.pixelSize: 22
                        }
                    }
                }
            }
        }
    }
}
