import QtQuick

// ListWell — the recessed well a list of ListRows sits in (spec: bg3,
// r18, 5 px padding). Children land in the inner Column, so a Repeater's
// delegates use `width: parent.width`. No outline (rule 09): the step from
// the card's fill to bg3 is what draws the well.
//     ListWell { Repeater { model: ...; delegate: ListRow { ... } } }
Rectangle {
    id: well
    default property alias rows: col.data
    width: parent ? parent.width : 200
    height: col.implicitHeight + 10
    radius: Theme.r(18)
    color: Theme.bg3
    Column {
        id: col
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: 5
    }
}
