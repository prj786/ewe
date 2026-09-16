import QtQuick
import Quickshell
import qs

// ewe.clipboard — the scissors in the bar. Click opens the history popup
// under this very icon: the x is handed to the panel over IPC, so the popup
// hangs off the widget wherever the user placed it.
Item {
    id: root
    property var settings: ({})
    implicitWidth: Theme.barItemHeight + 4
    implicitHeight: Theme.barItemHeight

    Rectangle {
        anchors.fill: parent; radius: Theme.radiusControl
        color: ma.containsMouse ? Theme.subtleHover : "transparent"
        Behavior on color { ColorAnimation { duration: 130 } }
    }
    Text {
        anchors.centerIn: parent
        text: Theme.icClipboard
        font.family: Theme.fontIcons; font.pixelSize: Theme.barIconPx
        color: ma.containsMouse ? Theme.fg1 : Theme.fg2
    }
    MouseArea {
        id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: {
            var x = Math.round(root.mapToItem(null, root.width / 2, 0).x)
            Quickshell.execDetached(["qs", "ipc", "call", "ewe.clipboard", "toggleAt", String(x)])
        }
    }
}
