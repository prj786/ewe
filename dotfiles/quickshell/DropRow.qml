import QtQuick

// DropRow — the one dropdown used shell-wide (Settings panes, Quick Settings):
// label left, bordered button right showing the current value, options expand
// inline below (scrollable past ~6 entries). Exclusive-open across the whole
// shell via Globals.openDd keyed by ddId.
Column {
    id: dr
    property string label: ""
    property string ddId: ""
    property var options: []            // [{ label, value }]
    property var value
    property bool dim: false            // disabled look + no interaction
    property int buttonWidth: 150
    signal picked(var v)
    readonly property bool open: dr.ddId !== "" && Globals.openDd === dr.ddId
    width: parent ? parent.width : 0
    spacing: 3
    function labelFor(v) { for (var i = 0; i < options.length; i++) if (String(options[i].value) === String(v)) return options[i].label; return "—" }
    Item {
        width: parent.width; height: 28; opacity: dr.dim ? 0.45 : 1
        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: dr.label; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
        Rectangle {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: dr.buttonWidth; height: 26; radius: Theme.r(7)
            color: drMa.containsMouse && !dr.dim ? Theme.hover : Theme.panel
            border.color: (dr.open || drBtn.activeFocus) ? Theme.accent : Theme.stroke; border.width: Theme.borderThin
            activeFocusOnTab: !dr.dim; id: drBtn
            Keys.onSpacePressed: Globals.openDd = dr.open ? "" : dr.ddId
            Keys.onReturnPressed: Globals.openDd = dr.open ? "" : dr.ddId
            Text { anchors.left: parent.left; anchors.leftMargin: 9; anchors.right: drChev.left; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: dr.labelFor(dr.value); color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; elide: Text.ElideRight }
            Text { id: drChev; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: dr.open ? Theme.icChevronUp : Theme.icChevronDown; font.family: Theme.fontIcons; font.pixelSize: 9; color: Theme.fgDim }
            MouseArea { id: drMa; anchors.fill: parent; hoverEnabled: true; cursorShape: dr.dim ? Qt.ArrowCursor : Qt.PointingHandCursor; onClicked: if (!dr.dim) Globals.openDd = dr.open ? "" : dr.ddId }
        }
    }
    Rectangle {
        visible: dr.open
        width: parent.width; height: Math.min(drOptCol.implicitHeight + 10, 172)
        radius: Theme.r(7); color: Theme.bg; border.color: Theme.stroke; border.width: Theme.borderThin
        Flickable {
            anchors.fill: parent; anchors.margins: 5
            contentHeight: drOptCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: drOptCol; width: parent.width
                Repeater {
                    model: dr.options
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: String(modelData.value) === String(dr.value)
                        width: parent.width; height: 26; radius: Theme.r(6)
                        color: drOMa.containsMouse ? Theme.hover : "transparent"
                        Text { anchors.left: parent.left; anchors.leftMargin: 8; anchors.right: parent.right; anchors.rightMargin: 26; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: sel ? Theme.accent : Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; font.weight: sel ? Font.DemiBold : Font.Normal; elide: Text.ElideRight }
                        Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; visible: sel; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: 11; color: Theme.accent }
                        MouseArea { id: drOMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Globals.openDd = ""; dr.picked(modelData.value) } }
                    }
                }
            }
        }
    }
}
