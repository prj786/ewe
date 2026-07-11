import QtQuick
import QtQuick.Effects

// Avatar — THE user avatar, used everywhere one appears (Settings account card,
// lock screen). Draws Globals.faceUrl masked to the user-chosen shape
// (Globals.avatarShape: "circle" | "rounded" | "square") with an initials/icon
// placeholder when no ~/.face exists. QtQuick `clip: true` clips to the
// bounding rectangle only — it can NOT round an Image's corners — so the shape
// comes from a MultiEffect alpha mask rendered from an antialiased Rectangle.
Item {
    id: av
    property int size: 72
    property string initial: ""        // placeholder letter; "" → generic user glyph
    width: size; height: size

    readonly property real shapeRadius: Globals.avatarShape === "circle" ? size / 2
                                      : Globals.avatarShape === "square" ? Math.max(3, size * 0.08)
                                      : size * 0.25            // "rounded"

    // backplate + placeholder — same shape as the mask so every state matches
    Rectangle {
        anchors.fill: parent
        radius: av.shapeRadius
        color: Theme.elevated
        border.color: Theme.stroke; border.width: 1
        antialiasing: true
        Text {
            anchors.centerIn: parent
            visible: !img.visible
            text: av.initial !== "" ? av.initial : String.fromCodePoint(0xF0004)
            color: av.initial !== "" ? Theme.fg : Theme.fgDim
            font.family: av.initial !== "" ? Theme.fontDisplay : Theme.fontMono
            font.pixelSize: Math.round(av.size * 0.45)
            font.weight: Font.Bold
        }
    }
    Image {
        id: img
        anchors.fill: parent
        source: Globals.faceUrl
        visible: Globals.hasFace && status === Image.Ready
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
    // hairline rim over the image so the edge reads crisp on any background
    Rectangle {
        anchors.fill: parent
        visible: img.visible
        radius: av.shapeRadius
        color: "transparent"
        border.color: Theme.stroke; border.width: 1
        antialiasing: true
    }
}
