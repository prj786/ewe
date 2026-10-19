import QtQuick
import qs

// SlackRow — one unread conversation: avatar, name, the last unread line,
// the time and the count. A click opens it in Slack.
Item {
    id: row
    property var conv: ({})
    signal clicked()

    function fmtTime(ts) {
        var ms = Number(ts) * 1000, d = new Date(ms), now = new Date()
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "h:mm AP")
        if (now.getTime() - ms < 6 * 86400000) return Qt.formatDateTime(d, "ddd")
        return Qt.formatDateTime(d, "d MMM")
    }

    width: parent ? parent.width : Theme.panelSm
    height: Math.max(Theme.controlXl, col.implicitHeight + 2 * Theme.spaceXs)
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSecondary
        color: ma.pressed ? Theme.surfacePressed : ma.containsMouse ? Theme.surfaceHover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: row.clicked() }
    SlackAvatar {
        id: face
        anchors.left: parent.left; anchors.leftMargin: Theme.spaceXs
        anchors.verticalCenter: parent.verticalCenter
        source: row.conv.avatar || ""
        name: row.conv.name || ""
    }
    Column {
        id: col
        anchors.left: face.right; anchors.leftMargin: Theme.spaceS
        anchors.right: side.left; anchors.rightMargin: Theme.spaceS
        anchors.verticalCenter: parent.verticalCenter
        TextBody { width: parent.width; text: row.conv.name || ""; font.weight: Theme.fontWeightSemibold }
        TextCaption { width: parent.width; elide: Text.ElideRight; text: row.conv.text || ""; color: Theme.textSecondary }
    }
    Column {
        id: side
        anchors.right: parent.right; anchors.rightMargin: Theme.spaceXs
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spaceXxs
        TextCaption { anchors.right: parent.right; text: row.fmtTime(row.conv.ts) }
        Badge { anchors.right: parent.right; count: row.conv.count || 0; max: 99 }
    }
}
