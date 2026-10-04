import QtQuick

// QsMsgRow — a two-line message row (a phone conversation, a mail): an
// unread dot, the sender, a line of preview and the time.
Item {
    id: mr
    property string title: ""
    property string line: ""
    property string time: ""
    property bool unread: false
    signal clicked()
    width: parent ? parent.width : Theme.panelSm
    height: Math.max(Theme.controlXl, mrCol.implicitHeight + 2 * Theme.spaceXs)
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSecondary
        color: mrMa.pressed ? Theme.surfacePressed : mrMa.containsMouse ? Theme.surfaceHover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
    }
    MouseArea { id: mrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mr.clicked() }
    Badge {
        visible: mr.unread; dot: true
        anchors.left: parent.left; anchors.leftMargin: Theme.spaceXs
        anchors.verticalCenter: parent.verticalCenter
    }
    Column {
        id: mrCol
        anchors.left: parent.left; anchors.leftMargin: Theme.spaceMd
        anchors.right: mrTime.left; anchors.rightMargin: Theme.spaceS
        anchors.verticalCenter: parent.verticalCenter
        TextBody { width: parent.width; text: mr.title; font.weight: mr.unread ? Theme.fontWeightSemibold : Theme.fontWeightMedium }
        TextCaption { width: parent.width; text: mr.line; color: mr.unread ? Theme.textSecondary : Theme.textMuted }
    }
    TextCaption {
        id: mrTime
        anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
        anchors.top: parent.top; anchors.topMargin: Theme.spaceXs + Theme.spaceXxs
        text: mr.time
    }
}
