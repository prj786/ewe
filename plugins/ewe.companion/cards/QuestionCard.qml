import QtQuick
import qs
import ".."

// QuestionCard — Claude's AskUserQuestion, answered in the island.
//
// One single-choice question sends on the first click (scene 2: "you pick
// one"). Several questions, or a multi-select one, collect picks and send
// with Send. Answer in terminal leaves the question to Claude's own prompt
// and jumps there. The daemon and the relay check every answer against the
// options Claude offered; anything else becomes "no opinion".
Column {
    id: qc
    property var card: ({})
    property var picks: ({})          // question → label, or [labels] for multi
    spacing: Theme.spaceS

    readonly property var questions: (qc.card.payload && qc.card.payload.questions) || []
    readonly property bool quick: qc.questions.length === 1 && !qc.questions[0].multiSelect
    readonly property bool complete: {
        for (var i = 0; i < qc.questions.length; i++) {
            var p = qc.picks[qc.questions[i].question]
            if (p === undefined || (Array.isArray(p) && p.length === 0)) return false
        }
        return qc.questions.length > 0
    }

    function picked(q, label) {
        var p = qc.picks[q.question]
        return Array.isArray(p) ? p.indexOf(label) >= 0 : p === label
    }
    function pick(q, label) {
        var next = Object.assign({}, qc.picks)
        if (q.multiSelect) {
            var cur = Array.isArray(next[q.question]) ? next[q.question].slice() : []
            var at = cur.indexOf(label)
            if (at >= 0) cur.splice(at, 1); else cur.push(label)
            next[q.question] = cur
        } else {
            next[q.question] = label
        }
        qc.picks = next
        if (qc.quick) CompanionState.answer(qc.card.id, "answer", qc.picks)
    }

    TextCaption { text: "Claude · " + (qc.card.project || "") + "/"; width: qc.width }
    TextStrong { text: qc.card.title || ""; width: qc.width }
    Repeater {
        model: qc.questions
        Column {
            id: qrow
            required property var modelData
            width: qc.width
            spacing: Theme.spaceXs
            TextCaption {
                visible: qrow.modelData.header !== ""
                text: String(qrow.modelData.header).toUpperCase()
                font.family: Theme.type.overline.family
                font.pixelSize: Theme.type.overline.size
                font.weight: Theme.type.overline.weight
                font.letterSpacing: Theme.type.overline.letterSpacing
            }
            TextBody { text: qrow.modelData.question; width: qc.width; wrapMode: Text.Wrap }
            Flow {
                width: qc.width
                spacing: Theme.spaceXs
                Repeater {
                    model: qrow.modelData.options || []
                    QsButton {
                        required property var modelData
                        label: modelData.label
                        variant: qc.picked(qrow.modelData, modelData.label) ? "primary" : "secondary"
                        onGo: qc.pick(qrow.modelData, modelData.label)
                    }
                }
            }
            TextCaption {
                // what the picked option means, in Claude's words
                readonly property var opt: {
                    var o = qrow.modelData.options || []
                    for (var i = 0; i < o.length; i++) if (qc.picked(qrow.modelData, o[i].label)) return o[i]
                    return null
                }
                visible: opt !== null && opt.description !== ""
                text: opt ? opt.description : ""
                width: qc.width
            }
        }
    }
    Row {
        spacing: Theme.spaceXs
        QsButton {
            visible: !qc.quick
            label: "Send"
            variant: "primary"
            disabled: !qc.complete
            onGo: CompanionState.answer(qc.card.id, "answer", qc.picks)
        }
        QsButton { label: "Answer in terminal"; variant: "ghost"; onGo: CompanionState.answer(qc.card.id, "terminal") }
    }
}
