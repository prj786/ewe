import QtQuick

// NoteReply — the inline-reply field of a notification that offers one
// (design system: Notification, "reply"; a Text field md + an Icon button).
// Enter or the send button hands the text to the sender
// (`Notification.sendInlineReply`), so the reply never opens the app's own
// dialog. `focused` is true while the field has the keyboard: a banner holds
// its countdown for as long.
//     NoteReply { note: n; onSent: …dismiss }
Item {
    id: nr
    property var note: null
    readonly property bool focused: input.activeFocus
    readonly property bool canSend: input.text.trim().length > 0
    signal sent()
    width: parent ? parent.width : Theme.panelSm
    height: Theme.controlMd
    function send() {
        if (!nr.canSend || !nr.note) return
        try { nr.note.sendInlineReply(input.text.trim()) } catch (e) {}
        input.text = ""
        nr.sent()
    }
    QsField {
        id: box
        anchors.left: parent.left; anchors.right: sendBtn.left; anchors.rightMargin: Theme.spaceXs
        focused: input.activeFocus
        // the whole box takes the click (not only the text line)
        MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: input.forceActiveFocus() }
        QsFieldInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceS + Theme.spaceXs; anchors.rightMargin: Theme.spaceS + Theme.spaceXs
            placeholder: nr.note && nr.note.inlineReplyPlaceholder ? nr.note.inlineReplyPlaceholder : "Reply"
            onAccepted: nr.send()
        }
    }
    QsIconButton {
        id: sendBtn
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        size: "md"
        ic: Theme.icSend
        tip: "Send"
        glyph: nr.canSend ? Theme.accentText : Theme.textDisabled
        onGo: nr.send()
    }
}
