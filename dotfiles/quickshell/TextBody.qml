import QtQuick

// TextBody — text in the system's body style (design system: Type). Public
// to plugins (docs/PLUGINS.md "Public components"); promoted out of
// QuickSettings.qml in API 3.
Text {
    color: Theme.textPrimary
    font.family: Theme.type.body.family
    font.pixelSize: Theme.type.body.size
    font.weight: Theme.type.body.weight
    elide: Text.ElideRight
}
