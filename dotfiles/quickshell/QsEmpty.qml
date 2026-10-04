import QtQuick

// QsEmpty — Empty state, compact: a controlLg circle with a glyph, a
// body-strong title, a description, optional actions (children).
Column {
    id: em
    property string ic: ""
    property string title: ""
    property string desc: ""
    default property alias actions: emAct.data
    width: parent ? parent.width : Theme.panelSm
    spacing: Theme.spaceXs
    topPadding: Theme.spaceMd; bottomPadding: Theme.spaceMd
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Theme.controlLg; height: Theme.controlLg
        radius: Theme.radiusFull
        color: Theme.surfaceHover
        Glyph { anchors.centerIn: parent; text: em.ic }
    }
    TextStrong {
        width: parent.width; horizontalAlignment: Text.AlignHCenter
        text: em.title
        font.weight: Theme.fontWeightSemibold
    }
    Text {
        visible: em.desc !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width, Theme.panelSm - Theme.spaceXl - Theme.spaceMd)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: em.desc
        color: Theme.textSecondary
        font.family: Theme.type.body.family
        font.pixelSize: Theme.type.body.size
    }
    Row {
        id: emAct
        anchors.horizontalCenter: parent.horizontalCenter
        topPadding: children.length > 0 ? Theme.spaceXs : 0
        spacing: Theme.spaceS
    }
}
