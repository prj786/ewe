import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// ewe.insomnia — the service. While Insomnia is on, a wayland idle inhibitor
// is held on a tiny always-mapped surface. Hyprland then stops reporting
// idle, so hypridle never fires (no auto-lock, no screen blank, no
// auto-suspend). Off releases it and normal idle behaviour resumes at once.
//
// This only affects *idle* timers — the lid and a manual lock still work.
// The layer namespace stays `quickshell:caffeine`: hyprland.lua's layer
// rules and ewe-conf's blur list know the surface by that name.
Scope {
    id: root
    property string pluginId: ""
    property var settings: ({})

    // the `auto_off` setting (minutes, 0 = never) — pushed live by the host
    onSettingsChanged: Insomnia.autoOff = Math.max(0, parseInt(root.settings.auto_off) || 0)
    Component.onCompleted: Insomnia.autoOff = Math.max(0, parseInt(root.settings.auto_off) || 0)

    PanelWindow {
        id: w
        // a 1px transparent surface parked in a corner, behind everything, click-through
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        visible: true
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}                                   // no input region → fully click-through
        WlrLayershell.namespace: "quickshell:caffeine"
        WlrLayershell.layer: WlrLayer.Background
        anchors { top: true; left: true }

        IdleInhibitor {
            window: w
            enabled: Insomnia.on
        }
    }

    // qs ipc call ewe.insomnia toggle | on | off | status
    IpcHandler {
        target: "ewe.insomnia"
        function toggle(): void { Insomnia.toggle() }
        function on(): void { Insomnia.set(true) }
        function off(): void { Insomnia.set(false) }
        function status(): string { return Insomnia.status() }
    }
}
