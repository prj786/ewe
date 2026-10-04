import QtQuick

// QsSegmented — Segmented control (md, full width): a surfaceSunken well, the
// chosen segment surfaceSelected. `options` = [{ label, value, disabled }];
// `picked(value)` fires on click (the caller sets `value`).
Rectangle {
    id: seg
    property var options: []
    property var value
    signal picked(var v)
    width: parent ? parent.width : Theme.panelSm
    height: Theme.controlMd
    radius: Theme.radiusPrimary
    color: Theme.surfaceSunken
    border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
    Row {
        id: segRow
        anchors.fill: parent
        anchors.margins: Theme.spaceXxs + seg.border.width
        spacing: Theme.spaceXxs
        Repeater {
            model: seg.options
            delegate: Rectangle {
                id: sgItem
                required property var modelData
                readonly property bool sel: String(modelData.value) === String(seg.value)
                readonly property bool dis: !!modelData.disabled
                width: (segRow.width - (seg.options.length - 1) * segRow.spacing) / Math.max(1, seg.options.length)
                height: segRow.height
                radius: Theme.radiusSecondary
                color: sgItem.sel ? Theme.surfaceSelected : "transparent"
                border.color: sgItem.sel ? Theme.borderSubtle : "transparent"
                border.width: Theme.borderWidth1
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                Text {
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - 2 * Theme.spaceXs)
                    text: sgItem.modelData.label
                    elide: Text.ElideRight
                    color: sgItem.dis ? Theme.textDisabled : (sgItem.sel || sgMa.containsMouse) ? Theme.textPrimary : Theme.textSecondary
                    font.family: Theme.type.label.family
                    font.pixelSize: Theme.type.label.size
                    font.weight: Theme.type.label.weight
                }
                MouseArea { id: sgMa; anchors.fill: parent; hoverEnabled: true; enabled: !sgItem.dis; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(sgItem.modelData.value) }
            }
        }
    }
}
