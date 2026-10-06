import QtQuick
import QtQuick.Effects
import qs

// SlackAvatar — a round photo from a local file (the helper caches Slack's
// avatars in the state dir), the name's first letter while there is none.
// The shell's Avatar shows only the user's own ~/.face, hence this one.
Item {
    id: av
    property int size: Theme.controlMd
    property string source: ""
    property string name: ""
    width: size; height: size

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusFull
        color: Theme.accentSubtle
        antialiasing: true
        Text {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready
            text: av.name !== "" ? av.name.charAt(0).toUpperCase() : Theme.icUser
            color: Theme.accentText
            font.family: av.name !== "" ? Theme.fontSans : Theme.fontIcons
            font.pixelSize: Math.round(av.size * 0.45)
            font.weight: Theme.fontWeightSemibold
        }
    }
    Image {
        id: img
        anchors.fill: parent
        source: av.source !== "" ? "file://" + av.source : ""
        visible: status === Image.Ready
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: av.size * 2; sourceSize.height: av.size * 2
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }
    Item {
        id: mask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle { anchors.fill: parent; radius: Theme.radiusFull; antialiasing: true }
    }
}
