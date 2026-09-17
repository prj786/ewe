import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// Osd — the on-screen display: it confirms a hardware key or a quick change
// (design system: On-screen display).
//
//   pill   control2xl (48) tall, panelSm less spaceLg + spaceMd + spaceS of
//          margin wide, surfaceOverlay with a borderWidth1 borderSubtle
//          outline, the radiusFull corner and the shadowFloat elevation,
//          spaceMd of side padding
//   icon   iconLg, following the level (volume-2 · volume-1 · volume-x);
//          danger when muted
//   level  the lg Slider, or a short message
//   value  the mono-numeric style on the right: the percentage, or "Muted"
//
//   · Volume     — reactive: it watches the default sink, so hardware keys
//                  and mute both land here.
//   · Brightness — pushed in by the brightness keybinds over
//                  `qs ipc call osd brightness`; there is no Wayland
//                  brightness service to observe.
//
// It sits control2xl above the bottom edge, centred, and goes after 1.5 s of
// quiet; repeated presses update it in place. Suppressed while Quick settings
// is open, which already shows both sliders.
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

    // the card's 1.5 s of quiet — a dwell time, not a motion duration, so the
    // animation speed setting leaves it alone
    Timer { id: hideTimer; interval: 1500; onTriggered: root.shown = false }

    PanelWindow {
        id: win
        // Only map the surface while the pill is actually on screen. This is a
        // full-width overlay that used to stay composited for the entire
        // session for something visible a second at a time. The opacity term keeps
        // it mapped through the fade-out.
        visible: root.shown || pill.opacity > 0.01
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}                                   // click-through
        WlrLayershell.namespace: "quickshell:osd"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors { bottom: true; left: true; right: true }
        implicitHeight: Theme.control2xl * 2 + Theme.spaceLg

        Rectangle {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.control2xl
            width: Theme.panelSm - Theme.spaceLg - Theme.spaceMd - Theme.spaceS
            height: Theme.control2xl
            radius: Theme.radiusFull
            color: Theme.surfaceOverlay
            border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
            layer.enabled: true
            layer.effect: Elevation {}

            // fade plus a slideOffset lift from the bottom edge — in at
            // durBase, out at durFast, no overshoot
            opacity: root.shown ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity {
                NumberAnimation { duration: root.shown ? Theme.durBase : Theme.durFast; easing.type: Theme.ease }
            }
            transform: Translate {
                y: (root.shown || Theme.reduceMotion) ? 0 : Theme.slideOffset
                Behavior on y { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceMd; anchors.rightMargin: Theme.spaceMd
                spacing: Theme.spaceS + Theme.spaceXs

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.iconLg
                    horizontalAlignment: Text.AlignHCenter
                    text: root.mode === "brightness" ? Theme.icSun
                        : root.muted ? Theme.icVolMute
                        : root.level < 0.5 ? Theme.icVolLow
                        : Theme.icVolHigh
                    font.family: Theme.fontIcons; font.pixelSize: Theme.iconLg
                    color: root.muted ? Theme.danger : Theme.textPrimary
                }
                // the lg Slider's own track; the OSD is click-through, so this
                // reports rather than takes input
                Rectangle {
                    id: trk
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.iconLg - val.width - 2 * parent.spacing
                    height: Theme.spaceS
                    radius: Theme.radiusFull
                    color: Theme.surfaceHover
                    Rectangle {
                        height: parent.height; radius: Theme.radiusFull
                        width: parent.width * Math.max(0, Math.min(1, root.level))
                        color: (root.mode === "volume" && root.muted) ? Theme.textDisabled : Theme.accent
                        Behavior on width { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                    }
                }
                Text {
                    id: val
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.spaceLg + Theme.spaceXs
                    horizontalAlignment: Text.AlignRight
                    text: (root.mode === "volume" && root.muted) ? "Muted" : Math.round(root.level * 100) + "%"
                    color: Theme.textSecondary
                    font.family: Theme.type.monoNumeric.family
                    font.pixelSize: Theme.type.monoNumeric.size
                    font.weight: Theme.type.monoNumeric.weight
                    font.features: ({ "tnum": 1 })
                }
            }
        }
    }
}
