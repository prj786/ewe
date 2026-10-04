import QtQuick
import qs

// ewe.phone — the phone glyph inside the bar's Quick settings pill (was
// Bar.qml's KDE Connect row): shown only while a phone is paired AND
// reachable; an accent dot for unread phone notifications (the phone's own
// count is already on the phone — here it only has to say "unread") and
// the phone's battery percentage beside the glyph.
BarStatusGlyph {
    id: st
    property string pluginId: ""
    property var settings: ({})
    property var screen: null
    property var barWindow: null

    text: Theme.icPhone
    shown: Phone.connected

    readonly property bool hasBattery: Phone.connected && Phone.device.batteryCharge >= 0
    readonly property bool hasDot: Phone.unreadCount > 0
    // the dot hangs off the glyph's corner — reserve that overhang, and the
    // battery text's room, so the pill's Row packs the neighbours after them
    readonly property real overhang: hasDot ? Math.max(0, dot.width - Theme.spaceXxs) : 0
    width: implicitWidth + overhang + (hasBattery ? Theme.spaceXs + batt.implicitWidth : 0)

    // presence only — a Badge dot at the glyph's top-right, ringed in the
    // bar's colour (the Bar card's rule; Glass leaves the ring out)
    Badge {
        id: dot
        visible: st.hasDot
        dot: true
        tone: "accent"; solid: true
        ring: !Theme.glass
        ringColor: Theme.barGround
        x: Theme.barIcon - Theme.spaceXxs
        y: -Theme.borderWidth1
    }
    Text {
        id: batt
        visible: st.hasBattery
        x: st.implicitWidth + st.overhang + Theme.spaceXs
        anchors.verticalCenter: parent.verticalCenter
        text: st.hasBattery ? Phone.device.batteryCharge + "%" : ""
        font.family: Theme.type.label.family
        font.pixelSize: Theme.barLarge ? Theme.fontSizeMd : Theme.fontSizeS
        font.features: ({ "tnum": 1 })
        color: st.ink
    }
}
