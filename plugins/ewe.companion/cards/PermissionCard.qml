import QtQuick
import qs
import ".."

// PermissionCard — "Claude wants to run npm install in ewe-browser/".
//
// The words come from the daemon (companion-core's Claude dialect), so the
// card only lays them out: who and where, what, a preview (the command, or
// the edit as − / + lines), then Allow · Deny · Always for <thing> ·
// Answer in terminal. "Always" is Claude's own suggestion, said in words;
// its hint says where Claude will save the rule.
Column {
    id: pc
    property var card: ({})
    spacing: Theme.spaceS

    readonly property var detail: pc.card.payload ? pc.card.payload.detail : null
    readonly property string preview: {
        var d = pc.detail
        if (!d) return ""
        if (d.kind === "diff") {
            var out = [], n = 0, cap = 12
            var edits = d.edits || []
            for (var i = 0; i < edits.length && n < cap; i++) {
                var o = String(edits[i].old || ""), w = String(edits[i].new || "")
                if (o !== "") o.split("\n").forEach(function (l) { if (n++ < cap) out.push("− " + l) })
                if (w !== "") w.split("\n").forEach(function (l) { if (n++ < cap) out.push("+ " + l) })
            }
            return out.join("\n")
        }
        return d.text || ""
    }
    readonly property var always: {
        var a = pc.card.actions || []
        for (var i = 0; i < a.length; i++) if (String(a[i].id).indexOf("always:") === 0) return a[i]
        return null
    }

    TextCaption { text: "Claude · " + (pc.card.project || "") + "/"; width: pc.width }
    TextStrong { text: pc.card.title || ""; width: pc.width; wrapMode: Text.Wrap; maximumLineCount: 2 }
    Rectangle {
        visible: pc.preview !== ""
        width: pc.width
        height: pre.implicitHeight + 2 * Theme.spaceS
        radius: Theme.radiusPrimary
        color: Theme.surfaceSunken
        Text {
            id: pre
            x: Theme.spaceS; y: Theme.spaceS
            width: parent.width - 2 * Theme.spaceS
            text: pc.preview
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 12
            elide: Text.ElideRight
            color: Theme.textPrimary
            font.family: Theme.type.mono.family
            font.pixelSize: Theme.type.mono.size
            font.weight: Theme.type.mono.weight
        }
    }
    TextCaption {
        visible: !!(pc.detail && pc.detail.description)
        text: pc.detail && pc.detail.description ? pc.detail.description : ""
        width: pc.width
    }
    Flow {
        width: pc.width
        spacing: Theme.spaceXs
        Repeater {
            model: pc.card.actions || []
            QsButton {
                required property var modelData
                label: modelData.label
                variant: modelData.style || "secondary"
                onGo: CompanionState.answer(pc.card.id, modelData.id)
            }
        }
    }
    TextCaption {
        visible: pc.always !== null && pc.always.hint !== undefined && pc.always.hint !== ""
        text: pc.always ? pc.always.label + ": " + pc.always.hint : ""
        width: pc.width
    }
}
