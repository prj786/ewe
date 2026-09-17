import QtQuick
import QtQuick.Effects

// Avatar — the person, the account or the machine (design system: Avatar),
// used wherever one appears (Settings account card, lock screen).
//
//   photo     ~/.face, cropped to fill
//   initials  weight semibold, accentText on accentSubtle
//   neither   a `user` glyph in textSecondary on surfaceHover
//   shape     the person's own preference (Globals.avatarShape): circle,
//             rounded, or the square form with the radiusPrimary corner
//   status    a dot a quarter of the avatar's size at the bottom right,
//             inside a borderWidth2 ring in the surface colour — always
//             repeat it in words nearby
//
// Sizes come from the size ramp: controlSm (24) inline · controlMd (28) in
// list rows · controlLg (32) the quick settings header · control2xl (48)
// accounts and the power menu · icon4xl (64) the lock screen · 96 in user
// settings and the installer.
//
// QtQuick `clip: true` clips to the bounding rectangle only — it can NOT
// round an Image's corners — so the shape comes from a MultiEffect alpha
// mask rendered from an antialiased Rectangle.
Item {
    id: av
    property int size: Theme.control2xl
    property string initial: ""        // placeholder letter; "" → generic user glyph
    property string source: Globals.faceUrl
    property string status: ""         // online · away · busy · offline
    property color ringColor: Theme.surfaceBase
    width: size; height: size

    readonly property real shapeRadius: Globals.avatarShape === "circle" ? size / 2
                                      : Globals.avatarShape === "square" ? Theme.radiusPrimary
                                      : size * 0.25            // "rounded"
    readonly property color statusColor: av.status === "away" ? Theme.warning
                                       : av.status === "busy" ? Theme.danger
                                       : av.status === "offline" ? Theme.textDisabled
                                       : Theme.success

    // backplate + placeholder — same shape as the mask so every state matches
    Rectangle {
        anchors.fill: parent
        radius: av.shapeRadius
        color: av.initial !== "" ? Theme.accentSubtle : Theme.surfaceHover
        antialiasing: true
        Text {
            anchors.centerIn: parent
            visible: !img.visible
            text: av.initial !== "" ? av.initial : Theme.icUser
            color: av.initial !== "" ? Theme.accentText : Theme.textSecondary
            font.family: av.initial !== "" ? Theme.fontSans : Theme.fontIcons
            font.pixelSize: Math.round(av.size * 0.45)
            font.weight: Theme.fontWeightSemibold
        }
    }
    Image {
        id: img
        anchors.fill: parent
        source: av.source
        visible: Globals.hasFace && img.status === Image.Ready
        fillMode: Image.PreserveAspectCrop
        cache: false
        sourceSize.width: av.size * 2; sourceSize.height: av.size * 2
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: maskShape
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }
    Item {
        id: maskShape
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle { anchors.fill: parent; radius: av.shapeRadius; antialiasing: true }
    }
    // the status dot, in its ring of the surface colour
    Rectangle {
        visible: av.status !== ""
        width: Math.max(Theme.spaceS, Math.round(av.size / 4)); height: width
        radius: Theme.radiusFull
        anchors.right: parent.right; anchors.bottom: parent.bottom
        color: av.ringColor
        antialiasing: true
        Rectangle {
            anchors.fill: parent
            anchors.margins: Theme.borderWidth2
            radius: Theme.radiusFull
            color: av.statusColor
            antialiasing: true
        }
    }
}
