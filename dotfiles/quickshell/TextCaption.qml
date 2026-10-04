import QtQuick

// TextCaption — the caption style in textMuted: a status, a hint, a time.
Text {
    color: Theme.textMuted
    font.family: Theme.type.caption.family
    font.pixelSize: Theme.type.caption.size
    font.weight: Theme.type.caption.weight
    elide: Text.ElideRight
}
