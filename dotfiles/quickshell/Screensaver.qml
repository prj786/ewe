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
        function show(): void { Globals.saverDimming = false; if (Globals.saverEnabled && !Globals.saverLock) Globals.saverActive = true }
        function hide(): void { Globals.saverActive = false; Globals.saverDimming = false }
        function toggle(): void { Globals.saverActive = !Globals.saverActive }
        // the grace period: hypridle fires this shortly before the first
        // irreversible stage, and fires undim the moment you touch anything
        function dim(): void { Globals.saverDimming = true }
        function undim(): void { Globals.saverDimming = false }
    }

    // ── pre-lock dim ─────────────────────────────────────────────────────────
    // Click-through by design: this must never swallow the very input meant to
    // cancel it. hypridle's on-resume is what clears it — the overlay is purely
    // something to look at. Fades in slowly enough to read as a warning, out
    // quickly enough to feel like a wake.
    //
    // But that on-resume can be LOST: a Settings apply restarts hypridle
    // (pkill + relaunch) and the new instance knows nothing about a dim the old
    // one fired; the IPC can also land on a dying shell. A lost undim used to
    // leave this 55%-black overlay up permanently — at 100% backlight the panel
    // reads "dim and no brightness key fixes it" (observed live 2026-08-13).
    // Backstops, cheapest-first: unlocking proves presence → undim; waking from
    // sleep → undim (hypridle re-dims if idle genuinely continues); and a
    // watchdog — dim is a ~20 s grace before the lock stage, so if two minutes
    // pass with neither lock nor saver arriving, the idle pipeline stalled and
    // the warning no longer means anything → clear it.
    Connections {
        target: Globals
        function onLockedChanged() { if (!Globals.locked) Globals.saverDimming = false }
        function onSaverDimmingChanged() { Globals.saverDimming ? dimWatchdog.restart() : dimWatchdog.stop() }
    }
    Connections {
        target: Resume
        function onResyncPower() { Globals.saverDimming = false }
    }
    Timer {
        id: dimWatchdog
        interval: 120000
        onTriggered: {
            if (Globals.saverDimming && !Globals.locked && !Globals.saverActive) {
                Log.warn("saver", "dim overlay up 2 min with no lock/saver following — clearing (missed hypridle on-resume)")
                Globals.saverDimming = false
            }
        }
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: Globals.saverDimming || dimRect.opacity > 0.01
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            WlrLayershell.namespace: "quickshell:saver-dim"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors { top: true; bottom: true; left: true; right: true }
            Rectangle {
                id: dimRect
                anchors.fill: parent
                color: "black"
                opacity: Globals.saverDimming ? 0.55 : 0
                Behavior on opacity {
                    NumberAnimation { duration: Globals.saverDimming ? 1500 : Theme.durBase; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    // Auto idle-inhibit: playing media or a fullscreen focused window holds a
    // wayland idle inhibitor (same mechanism as Caffeine, own 1px surface), so
    // NO idle stage fires — saver, lock or suspend. Most video players inhibit
    // on their own; this covers the ones that don't and audio-only playback.
    // Mpris publishes isPlaying as a change signal, so a plain binding re-evaluates
    // on its own — the old 5 s poll was ~17k wakeups a day to usually learn nothing.
    // Note the loop deliberately does NOT break early: every player's isPlaying has
    // to be read for the binding to depend on it, or a later player starting would
    // go unnoticed.
    readonly property bool mediaPlaying: {
        var ps = Mpris.players.values, on = false
        for (var i = 0; i < ps.length; i++) if (ps[i].isPlaying) on = true
        return on
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
                    // minute-aligned: this is the idle screen, so a 1 s tick was
                    // re-evaluating bindings every second at exactly the moment the
                    // panel should be sitting in self-refresh doing nothing at all
                    Timer {
                        id: saverClock
                        interval: 1000; running: Globals.saverActive; repeat: true; triggeredOnStart: true
                        onTriggered: {
                            clockRoot.now = new Date()
                            saverClock.interval = 60000 - (Date.now() % 60000)
                        }
                    }
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
