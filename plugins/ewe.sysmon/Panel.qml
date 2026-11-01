import QtQuick
import Quickshell
import Quickshell.Io
import qs

// ewe.sysmon — the card the bar readout opens (API 3 `panel`, one instance):
// an AnchoredPopup under the bar on the screen that was clicked; Esc or a
// click outside closes it, and it closes when another plugin popup opens.
// panelSm wide, spaceS + spaceXs (12) of padding, Card.qml inside. Samples
// while open (SysMon.hold) — with the readout on, they are already running.
//
// Entry points: the action `ewe.sysmon.toggle` (registered here, run by
// Widget.qml with the readout's anchor) and IPC —
//     qs ipc call ewe.sysmon toggle|hide
// (with no click to anchor it, it opens under the readout on the focused
// output, else at the bottom of the screen like any anchorless popup)
Scope {
    id: root
    property string pluginId: ""
    property var settings: ({})

    function toggle(anchor) {
        if (pop.open) { pop.close(); return }
        pop.openAt(anchor || SysMon.barAnchor())
    }

    Component.onCompleted: Shell.registerAction("ewe.sysmon.toggle", function (a) { root.toggle(a) })
    Component.onDestruction: { Shell.registerAction("ewe.sysmon.toggle", null); SysMon.hold(root, false) }

    IpcHandler {
        target: "ewe.sysmon"
        function toggle(): void { root.toggle(null) }
        function hide(): void { pop.close() }
    }

    AnchoredPopup {
        id: pop
        name: "sysmon"                      // layer namespace quickshell:sysmon
        owner: "ewe.sysmon"
        action: "ewe.sysmon.toggle"
        readonly property int pad: Theme.spaceS + Theme.spaceXs
        implicitWidth: Theme.grow(Theme.panelSm)
        implicitHeight: card.implicitHeight + 2 * pop.pad
        onOpenChanged: SysMon.hold(root, pop.open)

        Card {
            id: card
            x: pop.pad; y: pop.pad
            width: parent.width - 2 * pop.pad
            inBits: SysMon.bits(root.settings)
            onOptions: { pop.close(); Shell.openStore("addons") }
        }
    }
}
