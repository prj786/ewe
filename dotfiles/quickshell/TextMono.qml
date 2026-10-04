import QtQuick

// TextMono — mono-numeric figures that do not shift (a percentage, a clock).
Text {
    color: Theme.textSecondary
    font.family: Theme.type.monoNumeric.family
    font.pixelSize: Theme.type.monoNumeric.size
    font.weight: Theme.type.monoNumeric.weight
    font.features: ({ "tnum": 1 })
}
