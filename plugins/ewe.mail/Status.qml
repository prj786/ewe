import QtQuick
import qs

// ewe.mail — the envelope inside the bar's Quick settings pill (was Bar.qml's
// Mail BarIcon): shown only while there is unread mail, with the count as a
// solid accent Badge on the glyph's top-right corner. A bar badge counts to
// 9, not 99 — "9+" says all a bar needs to; the figure lives on the page.
BarStatusGlyph {
    id: st
    property string pluginId: ""
    property var settings: ({})
    property var screen: null
    property var barWindow: null

    text: Theme.icMail
    shown: Inbox.available && Inbox.unread > 0

    // the badge hangs off the glyph's corner — reserve that overhang so the
    // pill's Row does not pack the next glyph into it
    readonly property real overhang: Math.max(0, badge.width - Theme.spaceS)
    width: implicitWidth + overhang

    Badge {
        id: badge
        count: Inbox.unread
        max: 9
        tone: "accent"; solid: true
        // the ring is the bar's colour; Glass leaves it out (Bar card)
        ring: !Theme.glass
        ringColor: Theme.barGround
        // top-right of the glyph: spaceS above it, starting spaceS before its right edge
        x: Theme.barIcon - Theme.spaceS
        y: -Theme.spaceS
    }
}
