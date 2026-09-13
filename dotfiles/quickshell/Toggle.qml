import QtQuick

// Toggle — THE switch (spec: 38×22, 18 px knob, 150 ms travel).
// on  = brandBg fill + fgOnBrand knob · off = bg2 well + fg3 knob.
// No outline (rule 09) — the keyboard focus ring is the one stroke it draws.
//     Toggle { on: Globals.x; onToggled: Globals.x = !Globals.x }
Rectangle {
    id: tg
    property bool on: false
    signal toggled()
    width: 38; height: 22; radius: 11
    color: tg.on ? Theme.brandBg : Theme.bg2
    Behavior on color { ColorAnimation { duration: 150 } }
    activeFocusOnTab: true
    border.color: Theme.strokeFocus2
    border.width: tg.activeFocus ? Theme.focusWidth : 0
    Keys.onSpacePressed: tg.toggled()
    Keys.onReturnPressed: tg.toggled()
    Rectangle {
        width: 18; height: 18; radius: 9
        anchors.verticalCenter: parent.verticalCenter
        color: tg.on ? Theme.fgOnBrand : Theme.fg3
        Behavior on color { ColorAnimation { duration: 150 } }
        x: tg.on ? tg.width - width - 2 : 2
        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled() }
}
