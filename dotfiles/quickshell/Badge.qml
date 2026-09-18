import QtQuick

// Badge — a small, never-interactive label: a status, a count, or "there is
// something new" (design system: Badge).
//
//   pill   radiusFull, lineHeightXs + 2 × borderWidth1 (16) tall, spaceXs of
//          side padding, at least as wide as it is tall so a single digit is
//          a circle and "99+" grows instead of clipping
//   text   the caption size at medium weight, tabular figures, CENTRED ON
//          CAP HEIGHT — the card's rule, because a font's line box puts
//          digits and capitals off-centre by a pixel at this size
//   icon   an iconXs glyph before the text, spaceXxs away from it
//   dot    spaceS (8), for presence without a number
//   ring   a borderWidth2 ring in the surface colour, so a badge sitting on
//          an icon separates from it
//
// Tones: neutral · accent · success · warning · danger · info, each subtle
// (a -subtle ground) or `solid` (the tone itself, with on-accent / on-status
// ink). The default is the solid accent the bar's counts use.
//     Badge { count: 3 }     Badge { label: "Update" }     Badge { dot: true }
Rectangle {
    id: b
    property int count: 0
    property int max: 99
    property bool dot: false
    property string label: ""            // text instead of a count
    property string icon: ""             // leading glyph
    property string tone: "accent"       // neutral · accent · success · warning · danger · info
    property bool solid: true
    property bool ring: false            // separate it from the icon underneath
    property color ringColor: Theme.surfaceBase
    property int size: Theme.lineHeightXs + 2 * Theme.borderWidth1
    readonly property string countText: b.count > b.max ? b.max + "+" : String(b.count)
    readonly property string shownText: b.label !== "" ? b.label : b.countText

    readonly property color _fill: b.tone === "success" ? (b.solid ? Theme.success : Theme.successSubtle)
                                 : b.tone === "warning" ? (b.solid ? Theme.warning : Theme.warningSubtle)
                                 : b.tone === "danger"  ? (b.solid ? Theme.danger : Theme.dangerSubtle)
                                 : b.tone === "info"    ? (b.solid ? Theme.info : Theme.infoSubtle)
                                 : b.tone === "neutral" ? (b.dot ? Theme.textMuted : Theme.surfaceHover)
                                 : (b.solid ? Theme.accent : Theme.accentSubtle)
    readonly property color _ink: b.tone === "neutral" ? Theme.textSecondary
                                : b.solid && b.tone === "accent" ? Theme.onAccent
                                : b.solid ? Theme.onStatus
                                : b.tone === "success" ? Theme.success
                                : b.tone === "warning" ? Theme.warning
                                : b.tone === "danger"  ? Theme.danger
                                : b.tone === "info"    ? Theme.info
                                : Theme.accentText

    height: b.dot ? Theme.spaceS : b.size
    width: b.dot ? Theme.spaceS : Math.max(height, content.implicitWidth + 2 * Theme.spaceXs)
    radius: Theme.radiusFull
    color: b._fill
    antialiasing: true

    // the ring that lifts a badge off the icon it sits on
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.borderWidth2
        radius: Theme.radiusFull
        visible: b.ring
        z: -1
        color: b.ringColor
        antialiasing: true
    }

    Row {
        id: content
        visible: !b.dot
        anchors.centerIn: parent
        spacing: Theme.spaceXxs
        Text {
            visible: b.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: b.icon
            font.family: Theme.fontIcons; font.pixelSize: Theme.iconXs
            color: b._ink
        }
        Item {
            // the label box is the badge's own height, and the glyphs are
            // placed by their CAP HEIGHT inside it, not by the line box
            width: num.implicitWidth; height: b.height
            FontMetrics { id: fm; font: num.font }
            Text {
                id: num
                text: b.shownText
                font.family: Theme.type.caption.family
                font.pixelSize: Theme.type.caption.size
                font.weight: Theme.fontWeightMedium
                font.features: ({ "tnum": 1 })
                color: b._ink
                y: Math.round(parent.height / 2 + fm.capitalHeight / 2 - fm.ascent)
            }
        }
    }
}
