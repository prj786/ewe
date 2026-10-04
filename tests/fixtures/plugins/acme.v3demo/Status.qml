import QtQuick
import qs

// acme.v3demo — a glyph inside the bar's Quick settings pill, after the
// shell's own. The pill hands it its ink (hover state); `screen` and
// `barWindow` arrive too. Always shown here so the harness can see it.
BarStatusGlyph {
    property string pluginId: ""
    property var settings: ({})
    property var screen: null
    property var barWindow: null
    text: Theme.icStar
    shown: true
}
