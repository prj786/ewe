import QtQuick

// ListWell — the container a list of ListRows sits in (design system: List
// row, "list well"): surfaceRaised with a borderWidth1 borderSubtle outline,
// the radiusRounded corner and spaceXs of padding, so a row's own
// radiusSecondary corner nests inside it.
//
// Children land in the inner Column, so a Repeater's delegates use
// `width: parent.width`. `flush` drops the fill, the outline and the padding
// for a list that is already inside a card or a panel.
//     ListWell { Repeater { model: …; delegate: ListRow { … } } }
Rectangle {
    id: well
    default property alias rows: col.data
    property bool flush: false
    property alias spacing: col.spacing
    readonly property int padding: well.flush ? 0 : Theme.spaceXs

    width: parent ? parent.width : Theme.panelSm
    height: col.implicitHeight + 2 * padding + 2 * border.width
    radius: well.flush ? 0 : Theme.radiusRounded
    color: well.flush ? "transparent" : Theme.surfaceRaised
    border.color: Theme.borderSubtle
    border.width: well.flush ? 0 : Theme.borderWidth1
    Column {
        id: col
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: well.padding + well.border.width
    }
}
