import QtQuick

// TextStrong — the body-strong style: a row's title, a page's name.
Text {
    color: Theme.textPrimary
    font.family: Theme.type.bodyStrong.family
    font.pixelSize: Theme.type.bodyStrong.size
    font.weight: Theme.type.bodyStrong.weight
    elide: Text.ElideRight
}
