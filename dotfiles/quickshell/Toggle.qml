import QtQuick

// Toggle — THE switch (design system: Switch). A setting that takes effect
// at once, never a form control that waits for a Save button.
//
//   md (default)  controlLg × lineHeightMd (32 × 18), iconXs (12) thumb
//   lg            controlXl × controlSm (40 × 24), lineHeightMd (18) thumb
//                 — the installer and touch screens
//
//   off       surfaceSunken fill, borderStrong outline, a textSecondary
//             thumb carrying an `x` in the track's colour
//   off·hover the outline turns textSecondary
//   on        accent fill and outline, an onAccent thumb carrying a `check`
//             in the accent
//   on·hover  accentHover
//   focus     a focusWidth focusRing, focusWidth outside the track
//   disabled  surfaceRaised fill, borderSubtle outline, textDisabled thumb
//
// The thumb carries a glyph, so the state never rests on colour alone. The
// outline is fieldBorderWidth, not borderWidth1: a switch keeps its edge
// even at `stroke = none` (Look presets). The thumb slides at durFast and
// jumps with Reduce motion.
//     Toggle { on: Globals.x; onToggled: Globals.x = !Globals.x }
Rectangle {
    id: tg
    property bool on: false
    property bool disabled: false
    property string size: "md"                 // md · lg
    signal toggled()

    readonly property bool _lg: tg.size === "lg"
    readonly property int _thumb: tg._lg ? Theme.lineHeightMd : Theme.iconXs
    readonly property int _pad: Theme.spaceXxs

    width: tg._lg ? Theme.controlXl : Theme.controlLg
    height: tg._lg ? Theme.controlSm : Theme.lineHeightMd
    radius: Theme.radiusFull
    color: tg.disabled ? Theme.surfaceRaised
         : tg.on ? (ma.containsMouse ? Theme.accentHover : Theme.accent)
         : Theme.surfaceSunken
    border.width: Theme.fieldBorderWidth
    border.color: tg.disabled ? Theme.borderSubtle
                : tg.on ? (ma.containsMouse ? Theme.accentHover : Theme.accent)
                : ma.containsMouse ? Theme.textSecondary : Theme.borderStrong
    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }

    activeFocusOnTab: !tg.disabled
    Keys.onSpacePressed: if (!tg.disabled) tg.toggled()
    Keys.onReturnPressed: if (!tg.disabled) tg.toggled()

    // the focus ring sits OUTSIDE the track, so it never eats into the fill
    Rectangle {
        anchors.fill: parent
        anchors.margins: -(tg.border.width + Theme.focusWidth)
        radius: Theme.radiusFull
        color: "transparent"
        visible: tg.activeFocus
        border.color: Theme.focusRing
        border.width: Theme.focusWidth
        antialiasing: true
    }

    Rectangle {
        id: knob
        width: tg._thumb; height: tg._thumb
        radius: Theme.radiusFull
        anchors.verticalCenter: parent.verticalCenter
        color: tg.disabled ? Theme.textDisabled : tg.on ? Theme.onAccent : Theme.textSecondary
        antialiasing: true
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
        x: tg.on ? tg.width - width - tg._pad - tg.border.width : tg._pad + tg.border.width
        Behavior on x {
            NumberAnimation { duration: Theme.reduceMotion ? 0 : Theme.durFast; easing.type: Theme.easeFast }
        }
        // on = check, off = x: the state is readable without colour
        Text {
            anchors.centerIn: parent
            text: tg.on ? Theme.icCheck : Theme.icClose
            font.family: Theme.fontIcons
            font.pixelSize: tg._lg ? Theme.iconXs : Theme.spaceS
            color: tg.disabled ? Theme.surfaceRaised : tg.on ? Theme.accent : Theme.surfaceSunken
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: !tg.disabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tg.toggled()
    }
}
