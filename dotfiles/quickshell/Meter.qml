import QtQuick

// Meter — a labelled load bar (spec: 6 px bar r3 on bg2). The fill is the
// accent until it isn't: `warning` past `warn`, `danger` past `dangerAt`,
// so severity reads without a label. Digits are tabular so a column of
// meters lines up.
//     Meter { label: "CPU"; glyph: Theme.icCpu; value: Globals.cpuUsage }
Column {
    id: m
    property string label: ""
    property string glyph: ""
    property real value: 0               // 0..1
    property real warn: 0.6
    property real dangerAt: 0.85
    readonly property real frac: Math.max(0, Math.min(1, value))
    width: parent ? parent.width : 200
    spacing: 4
    Item {
        width: parent.width; height: 16
        Row {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 7
            Text { anchors.verticalCenter: parent.verticalCenter; visible: m.glyph !== ""; text: m.glyph; font.family: Theme.fontIcons; font.pixelSize: 13; color: Theme.fg3 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: m.label; color: Theme.fg1; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
        }
        Text {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: Math.round(m.frac * 100) + "%"; color: Theme.fg2
            font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
            font.features: ({ "tnum": 1 })
        }
    }
    Rectangle {
        width: parent.width; height: 6; radius: 3; color: Theme.bg2
        Rectangle {
            height: parent.height; radius: 3
            width: parent.width * m.frac
            color: m.frac > m.dangerAt ? Theme.danger : (m.frac > m.warn ? Theme.warning : Theme.accent)
            Behavior on width { NumberAnimation { duration: 400 } }
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }
}
