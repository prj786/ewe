import QtQuick
import qs
import ".."

// NoteCard — something to read with at most two actions and a Later
// (a presented notification from P3 on; a debug card today).
Column {
    id: nc
    property var card: ({})
    spacing: Theme.spaceS

    TextStrong { text: nc.card.title || ""; width: nc.width; wrapMode: Text.Wrap; maximumLineCount: 2 }
    TextBody {
        visible: text !== ""
        text: nc.card.body || ""
        width: nc.width
        wrapMode: Text.Wrap
        maximumLineCount: 4
        color: Theme.textSecondary
    }
    Row {
        spacing: Theme.spaceXs
        Repeater {
            model: (nc.card.actions || []).slice(0, 2)
            QsButton {
                required property var modelData
                label: modelData.label
                variant: modelData.style || "secondary"
                onGo: CompanionState.answer(nc.card.id, modelData.id)
            }
        }
        QsButton { label: "Later"; variant: "ghost"; onGo: CompanionState.answer(nc.card.id, "later") }
    }
}
