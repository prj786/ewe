import QtQuick

// QsFieldInput — the TextInput that lives inside a QsField, with a muted
// placeholder while empty. "Empty" includes the input method's preedit:
// while Chinese/Japanese/Korean is being composed `text` is still "" and the
// placeholder used to show through the letters being typed.
TextInput {
    id: fi
    property string placeholder: ""
    verticalAlignment: TextInput.AlignVCenter
    color: Theme.textPrimary
    selectionColor: Theme.accentSubtle
    selectedTextColor: Theme.textPrimary
    font.family: Theme.type.body.family
    font.pixelSize: Theme.type.body.size
    clip: true
    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: fi.text.length === 0 && fi.preeditText.length === 0
        text: fi.placeholder
        color: Theme.textMuted
        font: fi.font
    }
}
