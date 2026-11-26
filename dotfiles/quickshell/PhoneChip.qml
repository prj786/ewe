import QtQuick

// PhoneChip — "this came from your phone": the phone glyph and the phone's
// name, caption style, muted (design system: Notification, "from your phone").
Row {
    id: chip
    property string name: ""
    property real maxWidth: Theme.panelSm
    spacing: Theme.spaceXxs
    Glyph {
        anchors.verticalCenter: parent.verticalCenter
        text: Theme.icPhone
        font.pixelSize: Theme.iconSm
        color: Theme.textMuted
    }
    TextCaption {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.name
        width: Math.min(implicitWidth, Math.max(0, chip.maxWidth - Theme.iconSm - chip.spacing))
    }
}
