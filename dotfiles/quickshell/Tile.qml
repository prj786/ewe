import QtQuick

// Tile — the control-centre quick tile (spec: 62 px, card fill, 11 px
// padding, 17 px glyph). TWO independent visual states, never conflated:
//   active — the SERVICE is on   → brandBg fill + fgOnBrand text (only that)
//   opened — its list is expanded → 2 px brandStroke1 border + a turned
//            chevron. The border is drawn INSIDE the rectangle and the
//            content keeps its 11 px margins, so opening shifts nothing.
// Split button: the body toggles/acts, the 28 px detail zone on the right
// (hasMenu) expands the section — Wi-Fi can be switched off without ever
// opening the network list. The caret is hidden at rest, fades in on hover
// and turns from › to ⌄ while open. Sized for a two-up Row: half the parent
// minus the 10 px gap.
Rectangle {
    id: tile
    property string ic: ""
    property string label: ""
    property string sub: ""
    property bool active: false
    property bool opened: false
    property bool hasMenu: false
    property bool busy: false            // section is loading (scan in flight)
    signal clicked()                     // body
    signal menu()                        // detail zone
    width: parent ? (parent.width - 10) / 2 : 184
    height: 62
    radius: Theme.radiusInner
    color: tile.active
        ? (bodyMa.containsMouse ? Theme.brandBgHover : Theme.brandBg)
        : (bodyMa.containsMouse ? Theme.cardHover : Theme.card)
    // opened = BORDER ONLY — the fill never changes for opening a list, so
    // a brand fill stays unambiguous: "the service is on". On an active
    // tile the accent border would vanish into the fill, so it takes the
    // on-brand colour there.
    border.color: tile.opened ? (tile.active ? Theme.fgOnBrand : Theme.brandStroke1) : Theme.cardStroke
    border.width: tile.opened ? 2 : Theme.outline
    Behavior on color { ColorAnimation { duration: 150 } }
    Column {
        anchors.fill: parent; anchors.margins: 11; spacing: 5
        Text { text: tile.ic; font.family: Theme.fontIcons; font.pixelSize: 17; color: tile.active ? Theme.fgOnBrand : Theme.fg1 }
        Text { width: parent.width; text: tile.label; color: tile.active ? Theme.fgOnBrand : Theme.fg1; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; elide: Text.ElideRight }
    }
    Text { anchors.right: parent.right; anchors.rightMargin: tile.hasMenu ? 30 : 11; anchors.bottom: parent.bottom; anchors.bottomMargin: 11; text: tile.sub; color: tile.active ? Theme.fgOnBrand : Theme.fg3; font.family: Theme.fontText; font.pixelSize: 10; elide: Text.ElideRight }
    MouseArea { id: bodyMa; anchors.fill: parent; anchors.rightMargin: tile.hasMenu ? 28 : 0; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tile.clicked() }
    // detail zone — its own hover, its own hit area. It touches three of
    // the tile's edges, so it rounds only the two corners it shares; inset
    // by the tile's own rule so hovering never paints over the open border.
    Rectangle {
        visible: tile.hasMenu
        readonly property int inset: Math.max(Theme.hoverInset, tile.border.width)
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        anchors.margins: inset
        width: 28 - inset
        radius: 0
        topRightRadius: Theme.rIn(Theme.radiusInner, inset)
        bottomRightRadius: Theme.rIn(Theme.radiusInner, inset)
        color: chevMa.containsMouse ? (tile.active ? Theme.brandBgHover : Theme.subtleHover) : Theme.subtle
        Behavior on color { ColorAnimation { duration: 120 } }
        // hairline seam between body and detail zone, shown only while the
        // affordance itself shows
        Rectangle {
            width: Theme.hairline; height: parent.height - 24
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: tile.active ? Theme.brandBgSelected : Theme.subtleHover
            opacity: caret.opacity
        }
        Spinner {
            visible: tile.busy
            anchors.centerIn: parent
            font.pixelSize: 12
            // on-brand, not accent: the accent glyph vanishes on a brand fill
            color: tile.active ? Theme.fgOnBrand : Theme.fg1
        }
        Text {
            id: caret
            visible: !tile.busy
            anchors.centerIn: parent
            text: Theme.icChevronRight
            rotation: tile.opened ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
            opacity: tile.opened || chevMa.containsMouse || bodyMa.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
            font.family: Theme.fontIcons; font.pixelSize: 12
            color: tile.opened ? (tile.active ? Theme.fgOnBrand : Theme.accent)
                 : tile.active ? Theme.fgOnBrand : Theme.fg3
        }
        MouseArea { id: chevMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tile.menu() }
    }
}
