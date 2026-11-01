import QtQuick

// QsSegmented — Segmented control: a surfaceSunken well, the chosen segment
// surfaceSelected. `options` = [{ label, value, disabled, icon, tip }];
// `picked(value)` fires on click (the caller sets `value`).
//
//   md (default)  controlMd tall, full width, label segments
//   sm            controlSm tall (Quick settings' power mode)
//   icon          an option with `icon` and no `label` is an icon-only,
//                 square segment; when every option is one, the control is
//                 as wide as its squares instead of its parent
//
// `hoverItem` / `hoverTip` say which segment the pointer is on and its `tip`
// (an icon-only segment's name), for the host's tooltip.
Rectangle {
    id: seg
    property var options: []
    property var value
    property string size: "md"            // md · sm
    readonly property Item hoverItem: seg._hover
    readonly property string hoverTip: seg._hoverTip
    property Item _hover: null
    property string _hoverTip: ""
    signal picked(var v)
    readonly property int _inset: Theme.spaceXxs + seg.border.width
    readonly property int _segH: seg.height - 2 * seg._inset
    readonly property bool iconOnly: {
        if (seg.options.length === 0) return false
        for (var i = 0; i < seg.options.length; i++)
            if (!seg.options[i].icon || seg.options[i].label) return false
        return true
    }
    implicitWidth: seg.iconOnly ? seg.options.length * seg._segH + (seg.options.length - 1) * Theme.spaceXxs + 2 * seg._inset
                                : (parent ? parent.width : Theme.panelSm)
    width: implicitWidth
    height: seg.size === "sm" ? Theme.controlSm : Theme.controlMd
    radius: Theme.radiusPrimary
    color: Theme.surfaceSunken
    border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
    Row {
        id: segRow
        anchors.fill: parent
        anchors.margins: seg._inset
        spacing: Theme.spaceXxs
        Repeater {
            model: seg.options
            delegate: Rectangle {
                id: sgItem
                required property var modelData
                readonly property bool sel: String(modelData.value) === String(seg.value)
                readonly property bool dis: !!modelData.disabled
                readonly property bool iconic: !!modelData.icon && !modelData.label
                width: sgItem.iconic ? segRow.height
                     : (segRow.width - (seg.options.length - 1) * segRow.spacing) / Math.max(1, seg.options.length)
                height: segRow.height
                radius: Theme.radiusSecondary
                color: sgItem.sel ? Theme.surfaceSelected : "transparent"
                border.color: sgItem.sel ? Theme.borderSubtle : "transparent"
                border.width: Theme.borderWidth1
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                readonly property color _ink: sgItem.dis ? Theme.textDisabled : (sgItem.sel || sgMa.containsMouse) ? Theme.textPrimary : Theme.textSecondary
                Text {
                    anchors.centerIn: parent
                    visible: !sgItem.iconic
                    width: Math.min(implicitWidth, parent.width - 2 * Theme.spaceXs)
                    text: sgItem.modelData.label || ""
                    elide: Text.ElideRight
                    color: sgItem._ink
                    font.family: Theme.type.label.family
                    font.pixelSize: Theme.type.label.size
                    font.weight: Theme.type.label.weight
                }
                Glyph {
                    anchors.centerIn: parent
                    visible: sgItem.iconic
                    text: sgItem.modelData.icon || ""
                    color: sgItem._ink
                    font.pixelSize: Theme.iconSm
                }
                MouseArea {
                    id: sgMa
                    anchors.fill: parent; hoverEnabled: true; enabled: !sgItem.dis
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(sgItem.modelData.value)
                    onContainsMouseChanged: {
                        if (containsMouse) { seg._hoverTip = sgItem.modelData.tip || sgItem.modelData.label || ""; seg._hover = sgItem }
                        else if (seg._hover === sgItem) { seg._hover = null; seg._hoverTip = "" }
                    }
                }
            }
        }
    }
}
