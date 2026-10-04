import QtQuick

// QsNote — a hint, a note or an error under a list: caption size, wrapping,
// muted unless `tone` says danger or warning.
Text {
    property string tone: ""            // "" (muted) · danger · warning
    width: parent ? parent.width : Theme.panelSm
    wrapMode: Text.Wrap
    color: tone === "danger" ? Theme.danger : tone === "warning" ? Theme.warning : Theme.textMuted
    font.family: Theme.type.caption.family
    font.pixelSize: Theme.type.caption.size
}
