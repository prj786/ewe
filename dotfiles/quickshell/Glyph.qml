import QtQuick

// Glyph — one icon-font glyph at iconMd in textSecondary. Set `text` to a
// Theme.ic* name's value (Theme.icStar), never a raw code point.
Text {
    font.family: Theme.fontIcons
    font.pixelSize: Theme.iconMd
    color: Theme.textSecondary
}
