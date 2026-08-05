import QtQuick

// A whisper of light across the top of a rounded surface — the "milled edge"
// that makes a dark panel read as a physical object instead of a flat fill.
// Pure eye candy: no input, no layout. Place as the FIRST child of a panel
// Rectangle and match its radius:   Sheen { radius: parent.radius }
Rectangle {
    anchors.fill: parent
    property real strength: 0.05
    radius: Theme.radius
    border.width: 0
    gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, strength) }
        GradientStop { position: 0.3; color: "transparent" }
        GradientStop { position: 1.0; color: "transparent" }
    }
}
