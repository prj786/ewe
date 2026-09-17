import QtQuick

// BarIcon — one glyph on the bar, with an optional COUNT badge (design
// system: Bar → Badges).
//
// The count belongs TO the icon, never beside it: a solid accent Badge
// pinned to the glyph's top-right corner, spaceS above the glyph and
// starting spaceS before its right edge, with a borderWidth2 ring in the
// bar's own colour so the disc separates from the strokes underneath. On
// Glass the ring is left out — the card's rule, because a ring in a
// translucent fill reads as a smudge.
//
// A bar badge counts to 9, not 99: a 16px pill cannot carry "99+" beside a
// 20px glyph without swallowing it, and "9+" says all a bar needs to. The
// exact figure lives in the panel the icon opens. `dotOnly` is the same
// badge with no number — presence only, as on the phone indicator.
Item {
    id: root

    property string glyph: ""
    property color color: Theme.textSecondary
    property int count: 0             // 0 = no badge
    property int max: 9
    property int pixelSize: Theme.barIcon
    property bool dotOnly: false
    // what the badge is sitting on — the ring colour (Glass drops the ring)
    property color ringColor: Theme.barFill

    readonly property bool showBadge: root.count > 0

    // The badge hangs off the glyph's corner, so the item has to RESERVE that
    // overhang — otherwise the Row packs neighbours against it and a wide
    // "9+" runs into whatever sits to the right.
    implicitWidth: g.implicitWidth + (root.showBadge ? Math.max(0, badge.width - Theme.spaceS) : 0)
    implicitHeight: g.implicitHeight

    Text {
        id: g
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.glyph
        font.family: Theme.fontIcons
        font.pixelSize: root.pixelSize
        color: root.color
    }

    Badge {
        id: badge
        visible: root.showBadge
        dot: root.dotOnly
        count: root.count
        max: root.max
        tone: "accent"
        solid: true
        // the ring is the bar's colour; Glass leaves it out (Bar card)
        ring: !Theme.glass
        ringColor: root.ringColor
        // top-right of the GLYPH: spaceS above it, starting spaceS before its
        // right edge (spaceXxs for a dot, which is small enough to sit closer)
        x: g.x + root.pixelSize - (root.dotOnly ? Theme.spaceXxs : Theme.spaceS)
        y: g.y - (root.dotOnly ? Theme.borderWidth1 : Theme.spaceS)
    }
}
