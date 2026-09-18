import QtQuick
import Quickshell
import qs

// ewe.clipboard — the scissors in the bar. Click opens the history popup
// under this very icon: the x is handed to the panel over IPC, so the popup
// hangs off the widget wherever the user placed it.
Item {
    id: root
    property var settings: ({})
    // a glyph-only bar module (Bar card): barModule square, radiusPrimary,
    // no fill until you point at it; the bar* roles already follow Glass
    implicitWidth: Theme.barModule
    implicitHeight: Theme.barModule

    Rectangle {
        anchors.fill: parent; radius: Theme.radiusPrimary
        color: ma.pressed ? Theme.barPressedFill : ma.containsMouse ? Theme.barHoverFill : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
    }
    Text {
        anchors.centerIn: parent
        text: Theme.icClipboard
        font.family: Theme.fontIcons; font.pixelSize: Theme.barIcon
        color: ma.containsMouse ? Theme.textPrimary : Theme.textSecondary
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
    }
    MouseArea {
        id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: {
            var x = Math.round(root.mapToItem(null, root.width / 2, 0).x)
            Quickshell.execDetached(["qs", "ipc", "call", "ewe.clipboard", "toggleAt", String(x)])
        }
    }
}
