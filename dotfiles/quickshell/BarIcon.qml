import QtQuick

// BarIcon — one glyph on the bar, with an optional COUNT badge.
//
// Counts used to sit as a separate Text beside the glyph, so "3" floated in
// the row looking like a label for whatever came next, and every indicator
// spelled the pairing out again with its own Row + spacing. The count belongs
// TO the icon, the way a notification badge does everywhere else: a filled
// accent disc pinned to the glyph's top-right corner.
//
// The badge is a PILL, not a fixed circle — it is at least as wide as it is
// tall (so 1-9 is a true circle) and grows for wider text. Anything past
// `max` renders as "<max>+" — and on the BAR max is 9: a glyph 16 px tall
// cannot carry "99+" without the pill swallowing it and touching the bar's
// edge (2026-09-16). "9+" says all a bar badge needs to; the exact figure
// lives in the panel behind the icon.
Item {
    id: root

    property string glyph: ""
    property color color: Theme.fg2
    property int count: 0             // 0 = no badge
    property int max: 9
    property int pixelSize: Theme.barIconPx
    // a plain dot instead of a number — for "something is unread" where the
    // exact figure is noise (the phone's notification pip)
    property bool dotOnly: false
    // what the badge is sitting on — drawn as a hairline ring so the disc
    // separates from the glyph underneath it
    property color ringColor: Theme.barTop

    readonly property string countText: root.count > root.max
                                        ? root.max + "+" : String(root.count)
    readonly property bool showBadge: root.count > 0

    // The badge hangs off the glyph's corner, so the item has to RESERVE that
    // overhang — otherwise the Row packs neighbours against it and a wide
    // "99+" runs into whatever sits to the right.
    implicitWidth: g.implicitWidth + (root.showBadge ? Math.round(badge.width * 0.45) : 0)
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

    Rectangle {
        id: badge
        visible: root.showBadge
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: -Math.round(height * 0.2)

        // Half the glyph (was 0.58): a badge sized to the icon covers it, and
        // on a 30 px bar the old pill ran into the top edge. This sits ON the
        // corner and still leaves the glyph readable, which is the whole
        // point of putting the count there instead of beside it.
        readonly property int h: root.dotOnly ? 6 : Math.max(10, Math.round(root.pixelSize * 0.5))
        height: h
        width: root.dotOnly ? h : Math.max(h, num.implicitWidth + Math.round(h * 0.6))
        radius: height / 2
        color: Theme.accentFill
        // a hairline in the bar's own colour, so the disc reads as a separate
        // object sitting above the glyph rather than merging into its strokes
        border.color: root.ringColor
        border.width: 1

        Text {
            id: num
            visible: !root.dotOnly
            anchors.centerIn: parent
            text: root.countText
            font.family: Theme.fontText
            font.pixelSize: Math.max(7, Math.round(badge.h * 0.72))
            font.weight: Font.Bold
            color: Theme.accentOn
        }
    }
}
