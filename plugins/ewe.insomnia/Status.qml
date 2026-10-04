import QtQuick
import qs

// ewe.insomnia — the eye in the bar's Quick settings pill, shown only
// while Insomnia is on (the pill hands over its ink).
BarStatusGlyph {
    property string pluginId: ""
    property var settings: ({})
    property var screen: null
    property var barWindow: null
    text: Theme.icEye
    shown: Insomnia.on
}
