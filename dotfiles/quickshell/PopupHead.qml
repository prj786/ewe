import QtQuick
import QtQuick.Layouts

// PopupHead — the head row of a bar card (0.45, additive to plugin API 3 —
// docs/PLUGINS.md). The System monitor card's head, lifted out so every
// card the bar opens starts the same way:
//
//   glyph     iconMd in accentText
//   title     body-strong at fontWeightSemibold, elided
//   subtitle  optional caption under the title (a path, a count)
//   actions   right-aligned QsIconButtons (options cog, back, refresh…),
//             spaceXs apart — declare them as children
//
// At least controlSm tall (the head of a card with a cog), centred.
//
//   PopupHead { glyph: Theme.icMusic; title: "Now playing"
//               QsIconButton { ic: Theme.icCog; onGo: … } }
Item {
    id: head
    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    default property alias actions: acts.data

    implicitWidth: row.implicitWidth
    implicitHeight: Math.max(Theme.controlSm, row.implicitHeight)

    RowLayout {
        id: row
        anchors.left: parent.left; anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spaceS
        Glyph {
            visible: head.glyph !== ""
            text: head.glyph
            color: Theme.accentText
            Layout.alignment: Qt.AlignVCenter
        }
        Column {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            TextStrong {
                width: parent.width
                text: head.title
                font.weight: Theme.fontWeightSemibold
                elide: Text.ElideRight
            }
            TextCaption {
                visible: head.subtitle !== ""
                width: parent.width
                text: head.subtitle
                elide: Text.ElideMiddle
            }
        }
        Row {
            id: acts
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spaceXs
        }
    }
}
