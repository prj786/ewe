import QtQuick
import qs

// Level — the Meter's track without its head (design system: Meter), for a
// card that prints the figures itself: spaceXs + borderWidth2 (6) tall,
// surfaceHover, radiusFull; the fill is the accent, warning past 70 %,
// danger past 90 % — the Meter's own thresholds.
Rectangle {
    id: lv
    property real value: 0                // 0..1
    readonly property real frac: Math.max(0, Math.min(1, lv.value))
    implicitHeight: Theme.spaceXs + Theme.borderWidth2
    radius: Theme.radiusFull
    color: Theme.surfaceHover
    Rectangle {
        height: parent.height
        radius: Theme.radiusFull
        width: parent.width * lv.frac
        color: lv.frac > 0.9 ? Theme.danger : lv.frac > 0.7 ? Theme.warning : Theme.accent
        Behavior on width { NumberAnimation { duration: Theme.reduceMotion ? 0 : Theme.durSlow; easing.type: Theme.easeSlow } }
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
    }
}
