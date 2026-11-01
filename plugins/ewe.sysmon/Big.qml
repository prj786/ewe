import QtQuick
import qs

// Big — a figure that leads a section: fontSize2xl on lineHeight2xl, medium,
// mono with tabular digits so it does not shift as it changes, textPrimary.
Text {
    color: Theme.textPrimary
    font.family: Theme.type.mono.family
    font.pixelSize: Theme.fontSize2xl
    font.weight: Theme.fontWeightMedium
    font.features: ({ "tnum": 1 })
    lineHeightMode: Text.FixedHeight
    lineHeight: Theme.lineHeight2xl
    verticalAlignment: Text.AlignVCenter
}
