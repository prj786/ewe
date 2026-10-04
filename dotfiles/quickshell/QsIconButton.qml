import QtQuick

// QsIconButton — Icon button (design system: Icon button), ghost: textSecondary,
// hover surfaceHover with a textPrimary glyph, selected accentSubtle with an
// accentText glyph. `square` draws the stop mark instead of a glyph.
Rectangle {
    id: ib
    property string ic: ""
    property bool selected: false
    property bool danger: false          // the glyph turns danger on hover
    property bool square: false
    property string size: "sm"           // sm · md
    property color glyph: Theme.textSecondary
    readonly property alias hovered: ibMa.containsMouse
    signal go()
    width: ib.size === "sm" ? Theme.controlSm : Theme.controlMd
    height: width
    radius: Theme.radiusPrimary
    color: ib.selected ? Theme.accentSubtle
         : ibMa.pressed ? Theme.surfacePressed
         : ibMa.containsMouse ? Theme.surfaceHover : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
    readonly property color _ink: ib.selected ? Theme.accentText
                                : ibMa.containsMouse ? (ib.danger ? Theme.danger : Theme.textPrimary) : ib.glyph
    Glyph {
        visible: !ib.square
        anchors.centerIn: parent; text: ib.ic; color: ib._ink
        font.pixelSize: ib.size === "sm" ? Theme.iconSm : Theme.iconMd
    }
    Rectangle {
        visible: ib.square
        anchors.centerIn: parent
        width: Theme.spaceS; height: Theme.spaceS
        radius: Theme.radiusSlight / 2
        color: ib._ink
    }
    MouseArea { id: ibMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.go() }
}
