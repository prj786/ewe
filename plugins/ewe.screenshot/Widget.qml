import QtQuick
import Quickshell
import qs

// ewe.screenshot — the camera in the bar. Left: a region · Right: the whole
// screen · Middle: the focused window. Each runs this plugin's screenshot.sh,
// which saves to ~/Pictures/Screenshots, copies (if the setting says so) and
// pops the preview stack.
Item {
    id: root
    property var settings: ({})
    // the tray's cell: 16 px glyph in an 18 px slot, like every app icon beside it
    implicitWidth: Theme.trayIconPx + 2
    implicitHeight: Theme.barItemHeight
    readonly property string script: Qt.resolvedUrl("screenshot.sh").toString().replace(/^file:\/\//, "")
    function shoot(mode) {
        Quickshell.execDetached(["sh", "-c", 'EWE_SHOT_COPY="$2" exec "$1" "$3"', "_", root.script, root.settings.copy === false ? "0" : "1", mode])
    }

    Rectangle {
        anchors.centerIn: parent; width: parent.width + 6; height: parent.width + 6; radius: Theme.radiusControl
        color: ma.containsMouse ? Theme.subtleHover : "transparent"
        Behavior on color { ColorAnimation { duration: 130 } }
    }
    Text {
        anchors.centerIn: parent
        text: Theme.icCamera
        font.family: Theme.fontIcons; font.pixelSize: Theme.trayIconPx
        color: ma.containsMouse ? Theme.fg1 : Theme.fg2
    }
    MouseArea {
        id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: function (m) {
            root.shoot(m.button === Qt.RightButton ? "full" : m.button === Qt.MiddleButton ? "activewindow" : "region")
        }
    }
}
