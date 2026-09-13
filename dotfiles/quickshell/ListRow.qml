import QtQuick

// ListRow — one row in a ListWell (spec: 28 px, r12, 24 px icon gutter,
// hover = subtleHover, selection = accent colour + weight 600 with NO fill
// so a long list stays quiet). Extra trailing content declared as children
// lands in a Row at the right edge, left of the built-in caption / tick /
// spinner; its own MouseAreas sit above the row's, so they win the click.
//     ListRow { glyph: Theme.icWifi; label: ssid; selected: active; check: active; onClicked: ... }
Item {
    id: row
    property string glyph: ""
    property string label: ""
    property string kind: ""             // quiet right-hand caption ("open", "1 Gb/s")
    property bool selected: false
    property bool check: false           // accent tick at the right edge
    property bool busy: false            // spinner in the tick's place
    property color glyphColor: row.selected ? Theme.accent : Theme.fg3
    property int glyphSize: 13
    default property alias trailing: trail.data
    readonly property alias hovered: ma.containsMouse
    signal clicked()

    width: parent ? parent.width : 200
    height: 28

    Rectangle {
        anchors.fill: parent; radius: Theme.radiusControl
        color: ma.containsMouse ? Theme.subtleHover : Theme.subtle
        Behavior on color { ColorAnimation { duration: 130 } }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: row.clicked() }
    Text {
        visible: row.glyph !== ""
        anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
        width: 24
        text: row.glyph; font.family: Theme.fontIcons; font.pixelSize: row.glyphSize; color: row.glyphColor
    }
    Text {
        anchors.left: parent.left; anchors.leftMargin: row.glyph !== "" ? 32 : 8
        anchors.right: trail.left; anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: row.label
        color: row.selected ? Theme.accent : Theme.fg1
        font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
        font.weight: row.selected ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
    }
    Row {
        id: trail
        anchors.right: builtins.left; anchors.rightMargin: builtins.width > 0 ? 6 : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
    }
    Row {
        id: builtins
        anchors.right: parent.right; anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Text { visible: row.kind !== ""; anchors.verticalCenter: parent.verticalCenter; text: row.kind; color: Theme.fg3; font.family: Theme.fontText; font.pixelSize: 10 }
        Spinner { visible: row.busy; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12 }
        Text { visible: row.check && !row.busy; anchors.verticalCenter: parent.verticalCenter; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: 11; color: Theme.accent }
    }
}
