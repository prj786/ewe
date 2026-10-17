import QtQuick
import qs
import ".."

// Chat — the line you type in, pinned under the notch's scrolling part:
// a question, or a command in plain words ("volume 60", "game mode on",
// "search for …", "$ df -h"). The daemon runs plain commands itself, with
// no AI; questions go to the provider chosen in the plugin's options. The
// conversation itself is Messages.qml.
//
// An API key is typed here, never in the options: those sync to the cloud
// with ewe.conf, and a key must not (rule 2). It goes to the keyring.
Column {
    id: ch
    spacing: Theme.spaceS
    readonly property var chat: CompanionState.chat || {}
    readonly property alias input: field

    // ── the provider needs something ──
    TextCaption {
        visible: !ch.chat.ready && !!ch.chat.hint && !ch.chat.needs_key
        width: ch.width
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        text: ch.chat.hint || ""
    }
    Column {
        visible: !!ch.chat.needs_key
        width: ch.width
        spacing: Theme.spaceXs
        TextCaption {
            width: parent.width
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            text: (ch.chat.label || "This provider") + " needs an API key. It goes to your keyring, never into ewe.conf."
        }
        Row {
            width: parent.width
            spacing: Theme.spaceXs
            QsField {
                width: parent.width - save.width - Theme.spaceXs
                focused: keyIn.activeFocus
                QsFieldInput {
                    id: keyIn
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spaceS
                    anchors.rightMargin: Theme.spaceS
                    echoMode: TextInput.Password
                    placeholder: "Paste the key"
                    onAccepted: save.go()
                }
            }
            QsButton {
                id: save
                label: "Save key"
                variant: "primary"
                disabled: keyIn.text.trim() === ""
                onGo: { CompanionState.setKey(ch.chat.provider, keyIn.text.trim()); keyIn.text = "" }
            }
        }
    }

    // ── the line you type in ──
    QsField {
        width: ch.width
        focused: field.activeFocus
        QsFieldInput {
            id: field
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceS
            anchors.rightMargin: Theme.spaceS
            placeholder: "Ask anything"
            onAccepted: { CompanionState.ask(text); text = "" }
            Keys.onEscapePressed: CompanionState.dropOpen = false
        }
    }
}
