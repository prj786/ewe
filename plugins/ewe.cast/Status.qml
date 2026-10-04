import QtQuick
import qs

// ewe.cast — the screencast glyph inside the bar's Quick settings pill while
// a cast session exists: accent = picture on glass, the pill's ink = still
// handshaking. Takes no space otherwise.
BarStatusGlyph {
    property string pluginId: ""
    property var settings: ({})
    property var screen: null
    property var barWindow: null
    text: Theme.icCast
    shown: CastState.casting
    color: CastState.streaming ? Theme.barAccentText : ink
}
