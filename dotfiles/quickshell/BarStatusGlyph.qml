import QtQuick

// BarStatusGlyph — one glyph inside the bar's Quick settings pill (design
// system: Bar #10): Theme.barIcon in the pill's `ink`, which the pill hands
// over (textSecondary, textPrimary while hovered or while Quick settings is
// open). A bar-status entry point whose root is one of these gets `ink`
// injected. Set `text` to a Theme.ic* glyph and `shown` to whether it has
// anything to say — a glyph that is not shown takes no space in the pill.
// (`shown`, not `visible`: an Item's `visible` reads back its EFFECTIVE
// visibility, so the pill's slot cannot follow it without a cycle.)
Text {
    property color ink: Theme.textSecondary
    property bool shown: true
    visible: shown
    font.family: Theme.fontIcons
    font.pixelSize: Theme.barIcon
    color: ink
}
