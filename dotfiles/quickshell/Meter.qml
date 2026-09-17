import QtQuick

// Meter — how full something is: CPU, memory, disk, battery (design system:
// Meter). A level, never a task — a task that finishes is a progress bar.
//
//   header  an iconSm glyph and the label in the label style, textSecondary,
//           with the value in the mono-numeric style on the right
//   track   spaceXs + borderWidth2 (6) tall, surfaceHover, radiusFull
//   fill    accent · warning past `warn` (70%) · danger past `dangerAt`
//           (90%), which also turns the value danger, so severity reads
//           without a word
//
// `segmented` draws the ten equal segments quick settings uses for the
// battery. The thresholds are per resource — a battery is critical BELOW
// 10%, so its caller passes its own.
//     Meter { label: "CPU"; glyph: Theme.icCpu; value: Globals.cpuUsage }
Column {
    id: m
    property string label: ""
    property string glyph: ""
    property real value: 0               // 0..max
    property real max: 1
    property string valueText: ""        // overrides the percentage
    property real warn: 0.7
    property real dangerAt: 0.9
    property bool segmented: false       // ten equal segments
    readonly property real frac: Math.max(0, Math.min(1, m.max > 0 ? value / m.max : 0))
    readonly property bool critical: m.frac > m.dangerAt
    readonly property color fillColor: m.critical ? Theme.danger
                                     : m.frac > m.warn ? Theme.warning : Theme.accent

    width: parent ? parent.width : Theme.panelSm
    spacing: Theme.spaceXs

    Item {
        width: parent.width; height: Theme.lineHeightS
        Row {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spaceXs
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: m.glyph !== ""
                text: m.glyph; font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
                color: Theme.textSecondary
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: m.label; color: Theme.textSecondary
                font.family: Theme.type.label.family
                font.pixelSize: Theme.type.label.size
                font.weight: Theme.type.label.weight
            }
        }
        Text {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: m.valueText !== "" ? m.valueText : Math.round(m.frac * 100) + "%"
            color: m.critical ? Theme.danger : Theme.textPrimary
            font.family: Theme.type.monoNumeric.family
            font.pixelSize: Theme.type.monoNumeric.size
            font.weight: Theme.type.monoNumeric.weight
            font.features: ({ "tnum": 1 })
        }
    }
    Rectangle {
        width: parent.width
        height: Theme.spaceXs + Theme.borderWidth2
        radius: Theme.radiusFull
        color: Theme.surfaceHover
        Rectangle {
            visible: !m.segmented
            height: parent.height; radius: Theme.radiusFull
            width: parent.width * m.frac
            color: m.fillColor
            Behavior on width { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeSlow } }
            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
        }
        // the segmented form: ten equal bars with borderWidth2 gaps
        Row {
            visible: m.segmented
            anchors.fill: parent
            spacing: Theme.borderWidth2
            Repeater {
                model: 10
                delegate: Rectangle {
                    required property int index
                    width: (parent.width - 9 * parent.spacing) / 10
                    height: parent.height
                    radius: Theme.radiusFull
                    color: (index + 1) / 10 <= m.frac + 0.0001 ? m.fillColor : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                }
            }
        }
    }
}
