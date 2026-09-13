import QtQuick

// Badge — a count pill or a plain dot (spec: 14 px pill r7 on brandBg with
// 9 px / 700 fgOnBrand text; dot = 6 px accent). At least as wide as it is
// tall, so 1-9 is a true circle and "99+" grows instead of clipping.
//     Badge { count: 3 }          Badge { dot: true }
Rectangle {
    id: b
    property int count: 0
    property int max: 99
    property bool dot: false
    property int size: 14
    readonly property string countText: b.count > b.max ? b.max + "+" : String(b.count)
    height: b.dot ? 6 : b.size
    width: b.dot ? 6 : Math.max(height, num.implicitWidth + 10)
    radius: height / 2
    color: b.dot ? Theme.accent : Theme.brandBg
    Text {
        id: num
        visible: !b.dot
        anchors.centerIn: parent
        text: b.countText
        font.family: Theme.fontText
        font.pixelSize: Math.max(8, Math.round(b.size * 0.64))
        font.weight: Font.Bold
        color: Theme.fgOnBrand
    }
}
