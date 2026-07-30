import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// Osd — transient on-screen indicator for volume & brightness, styled from Theme.qml.
// A click-through pill near the bottom-centre that pops on change and fades out.
//   · Volume    — reactive: watches the default sink (covers hardware keys + mute).
//   · Brightness— pushed from the brightness keybinds via `qs ipc call osd brightness`
//                 (there's no Wayland brightness service to observe).
// Suppressed while Quick Settings is open (it already shows both sliders there).
Scope {
    id: root

    property string mode: "volume"        // "volume" | "brightness"
    property real level: 0                 // 0..1
    property bool muted: false
    property bool shown: false
    property bool ready: false             // gate the initial Pipewire binding from popping the OSD

    function g(c) { return String.fromCodePoint(c) }

    function popup() {
        if (Globals.quickSettingsOpen) return    // Quick Settings already shows the sliders
        root.shown = true
        hideTimer.restart()
    }

    // ── volume: observe the default sink reactively ──
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }
    Connections {
        target: (root.sink && root.sink.audio) ? root.sink.audio : null
        function onVolumeChanged() { root.showVolume() }
        function onMutedChanged() { root.showVolume() }
    }
    function showVolume() {
        if (!root.ready || !root.sink || !root.sink.audio) return
        root.mode = "volume"
        root.muted = root.sink.audio.muted
        root.level = Math.min(1, root.sink.audio.volume)
        root.popup()
    }
    Timer { interval: 1200; running: true; onTriggered: root.ready = true }   // skip startup binding fire

    // ── brightness: pushed in over IPC, value read fresh from brightnessctl ──
    IpcHandler {
        target: "osd"
        function brightness(): void { brightProc.running = true }
        function volume(): void { root.showVolume() }   // optional manual trigger
    }
    Process {
        id: brightProc
        command: ["sh", "-c", "brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var n = parseInt(this.text.trim())
                if (isNaN(n)) return
                root.mode = "brightness"
                root.muted = false
                root.level = Math.max(0, Math.min(1, n / 100))
                root.popup()
            }
        }
    }

    Timer { id: hideTimer; interval: 1600; onTriggered: root.shown = false }

    PanelWindow {
        id: win
        // Only map the surface while the pill is actually on screen. This is a
        // full-width 140px overlay that used to stay composited for the entire
        // session for something visible a second at a time. The opacity term keeps
        // it mapped through the fade-out.
        visible: root.shown || pill.opacity > 0.01
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}                                   // click-through
        WlrLayershell.namespace: "quickshell:osd"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors { bottom: true; left: true; right: true }
        implicitHeight: 140

        Rectangle {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            width: 320; height: 56
            radius: 16
            color: Theme.panel
            border.color: Theme.stroke; border.width: 1

            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.94
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutCubic } }

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.shadow
                shadowOpacity: 0.5
                shadowBlur: 1.0
                shadowVerticalOffset: 7
                blurMax: 40
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 18; anchors.rightMargin: 18
                spacing: 14

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    horizontalAlignment: Text.AlignHCenter
                    text: root.mode === "brightness" ? Theme.icSun
                        : root.muted ? Theme.icVolLow
                        : Theme.icVolHigh
                    font.family: Theme.fontMono; font.pixelSize: 19
                    color: root.muted ? Theme.fgDim : Theme.fg
                }
                Rectangle {
                    id: trk
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 24 - 14 - 44 - 14
                    height: 7; radius: 4
                    color: Theme.hover
                    Rectangle {
                        height: parent.height; radius: 4
                        width: parent.width * Math.max(0, Math.min(1, root.level))
                        color: (root.mode === "volume" && root.muted) ? Theme.fgDim : Theme.accent
                        Behavior on width { NumberAnimation { duration: Theme.durFast } }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    horizontalAlignment: Text.AlignRight
                    text: (root.mode === "volume" && root.muted) ? "Muted" : Math.round(root.level * 100) + "%"
                    color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold
                }
            }
        }
    }
}
