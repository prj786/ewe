import QtQuick

// BarModule — a BAR MODULE (design system: Bar → Module states). barModule
// tall (28 / 32 / 40 by icon size), radiusPrimary, spaceS of side padding,
// no fill until you point at it. Default glyphs are textSecondary; hover
// takes surfaceHover and textPrimary, an open popup surfacePressed — inside
// Glass those are the glass tints, which Theme.barHoverFill /
// barPressedFill already resolve.
//
// Declare content as children (they land centred in a Row, spaceXs apart);
// `glyph` alone draws one icon and is the common case. Public to plugins
// (docs/PLUGINS.md); promoted out of Bar.qml in API 3.
Item {
    id: si
    property string glyph: ""
    property color fg: Theme.textSecondary
    property int fontPx: Theme.barIcon
    property bool active: false      // its popup is open
    // .ewe-barmod: spaceS of side padding (spaceS + spaceXs on the large
    // bar); a glyph-only module has none and is just barModule square
    property int padH: si.glyph !== "" ? 0 : Theme.barLarge ? Theme.spaceS + Theme.spaceXs : Theme.spaceS
    // the workspace chip's mark: a spaceMd × borderWidth2 accent rule
    // spaceXs above the chip's bottom edge, always on
    property bool underline: false
    default property alias content: inner.data
    readonly property alias hovered: ma.containsMouse
    // each module is a button named with its state (Bar card, Accessibility)
    property string a11yName: ""
    Accessible.role: Accessible.Button
    Accessible.name: si.a11yName
    signal activated()
    signal secondary()
    signal tertiary()
    signal scrolled(real dy)
    implicitWidth: Math.max(Theme.barModule, inner.implicitWidth + 2 * si.padH)
    // barModule, or taller when its content is (a larger text size,
    // Georgian) — the bar grows with it
    implicitHeight: Math.max(Theme.barModule, inner.implicitHeight + 2 * Theme.spaceXxs)
    height: implicitHeight
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusPrimary
        color: si.active ? Theme.barPressedFill
             : ma.containsMouse ? Theme.barHoverFill : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
    }
    Row {
        id: inner
        anchors.centerIn: parent
        spacing: Theme.spaceXs
        Text {
            visible: si.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: si.glyph
            color: ma.containsMouse && si.fg === Theme.textSecondary ? Theme.textPrimary : si.fg
            font.family: Theme.fontIcons
            font.pixelSize: si.fontPx
            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
        }
    }
    Rectangle {
        visible: si.underline
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spaceXs
        anchors.horizontalCenter: parent.horizontalCenter
        width: Theme.spaceMd; height: Theme.borderWidth2
        radius: Theme.borderWidth2
        color: Theme.accent
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: function (m) {
            if (m.button === Qt.RightButton) si.secondary()
            else if (m.button === Qt.LeftButton) si.activated()
        }
        // middle-click fires on press — onClicked is unreliable for the
        // middle button (wheel-press / trackpad taps often aren't "clicks").
        onPressed: function (m) {
            if (m.button === Qt.MiddleButton) si.tertiary()
        }
        onWheel: function (w) { si.scrolled(w.angleDelta.y) }
    }
}
