import QtQuick
import Quickshell
import Quickshell.Io
import qs

// acme.v3demo — the popup behind the dock item: the manifest's dockItem.action
// ("acme.v3demo.toggle") is registered here, the dock calls it with the
// button's anchor, and an AnchoredPopup opens above the dock on that screen.
// `qs ipc call acme.v3demo toggle` opens it on the focused screen.
Scope {
    id: root
    property string pluginId: ""
    property string stateDir: ""
    property var settings: ({})

    Component.onCompleted: Shell.registerAction("acme.v3demo.toggle", function (anchor) { pop.toggleAt(anchor) })

    IpcHandler {
        target: "acme.v3demo"
        function toggle(): void { pop.toggleAt(null) }
        function hide(): void { pop.close() }
    }

    AnchoredPopup {
        id: pop
        name: "acme.v3demo"
        action: "acme.v3demo.toggle"
        implicitWidth: Theme.panelSm
        implicitHeight: Theme.control2xl * 3
        Column {
            anchors.fill: parent
            anchors.margins: Theme.spaceS + Theme.spaceXs
            spacing: Theme.spaceS
            TextStrong { text: "Demo popup" }
            TextCaption { text: "An AnchoredPopup opened by the dock item's action." }
            Row {
                spacing: Theme.spaceS
                QsButton { label: "Toast"; variant: "primary"; onGo: { Shell.toast("Hello from the demo popup"); pop.close() } }
                QsButton { label: "Close"; onGo: pop.close() }
            }
        }
    }
}
