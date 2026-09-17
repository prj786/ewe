import QtQuick

// DropRow — the one dropdown used shell-wide (Settings panes, Quick
// settings): a label on the left, the Select trigger on the right, and the
// options expanding inline below it (design system: Select, Menu).
//
//   trigger  controlMd tall, surfaceSunken behind a borderStrong outline on
//            the radiusPrimary corner; hover turns the outline textMuted,
//            open or focused turns it focusRing and the chevron points up.
//            The outline is fieldBorderWidth — a field keeps its edge at
//            `stroke = none` (Look presets).
//   menu     surfaceOverlay with a borderWidth1 borderSubtle outline, the
//            radiusRounded corner and spaceXs of padding; rows are controlMd
//            on the radiusSecondary corner, hover surfaceHover, the chosen
//            one at medium weight with an accentText check.
//   disabled surfaceRaised behind borderSubtle, everything textDisabled.
//
// Exclusive-open across the whole shell via Globals.openDd keyed by ddId.
Column {
    id: dr
    property string label: ""
    property string ddId: ""
    property var options: []            // [{ label, value }]
    property var value
    property bool dim: false            // disabled look + no interaction
    property int buttonWidth: Theme.panelSm / 2 - Theme.spaceLg
    signal picked(var v)
    readonly property bool open: dr.ddId !== "" && Globals.openDd === dr.ddId
    width: parent ? parent.width : Theme.panelSm
    spacing: Theme.spaceXs
    function labelFor(v) { for (var i = 0; i < options.length; i++) if (String(options[i].value) === String(v)) return options[i].label; return "—" }

    Item {
        width: parent.width; height: Theme.controlMd
        Text {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: dr.label
            color: dr.dim ? Theme.textDisabled : Theme.textPrimary
            font.family: Theme.type.label.family
            font.pixelSize: Theme.type.label.size
            font.weight: Theme.type.label.weight
        }
        Rectangle {
            id: drBtn
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: dr.buttonWidth; height: Theme.controlMd
            radius: Theme.radiusPrimary
            color: dr.dim ? Theme.surfaceRaised : Theme.surfaceSunken
            border.width: Theme.fieldBorderWidth
            border.color: dr.dim ? Theme.borderSubtle
                        : (dr.open || drBtn.activeFocus) ? Theme.focusRing
                        : drMa.containsMouse ? Theme.textMuted : Theme.borderStrong
            Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
            activeFocusOnTab: !dr.dim
            Keys.onSpacePressed: Globals.openDd = dr.open ? "" : dr.ddId
            Keys.onReturnPressed: Globals.openDd = dr.open ? "" : dr.ddId
            Keys.onEscapePressed: Globals.openDd = ""
            Text {
                anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                anchors.right: drChev.left; anchors.rightMargin: Theme.spaceXs
                anchors.verticalCenter: parent.verticalCenter
                text: dr.labelFor(dr.value)
                color: dr.dim ? Theme.textDisabled : Theme.textPrimary
                font.family: Theme.type.body.family
                font.pixelSize: Theme.type.body.size
                elide: Text.ElideRight
            }
            Text {
                id: drChev
                anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                anchors.verticalCenter: parent.verticalCenter
                text: dr.open ? Theme.icChevronUp : Theme.icChevronDown
                font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                color: dr.dim ? Theme.textDisabled : Theme.textSecondary
            }
            MouseArea {
                id: drMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: dr.dim ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: if (!dr.dim) Globals.openDd = dr.open ? "" : dr.ddId
            }
        }
    }
    Rectangle {
        visible: dr.open
        width: parent.width
        height: Math.min(drOptCol.implicitHeight + 2 * Theme.spaceXs, 6 * Theme.controlMd)
        radius: Theme.radiusRounded
        color: Theme.surfaceOverlay
        border.color: Theme.borderSubtle
        border.width: Theme.borderWidth1
        Flickable {
            anchors.fill: parent; anchors.margins: Theme.spaceXs + Theme.borderWidth1
            contentHeight: drOptCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: drOptCol; width: parent.width
                Repeater {
                    model: dr.options
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: String(modelData.value) === String(dr.value)
                        width: parent.width; height: Theme.controlMd
                        radius: Theme.radiusSecondary
                        color: drOMa.containsMouse ? Theme.surfaceHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                            anchors.right: parent.right; anchors.rightMargin: Theme.spaceS + Theme.iconMd
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: Theme.textPrimary
                            font.family: Theme.type.body.family
                            font.pixelSize: Theme.type.body.size
                            font.weight: sel ? Theme.fontWeightMedium : Theme.type.body.weight
                            elide: Text.ElideRight
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                            anchors.verticalCenter: parent.verticalCenter
                            visible: sel
                            text: Theme.icCheck
                            font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                            color: Theme.accentText
                        }
                        MouseArea {
                            id: drOMa
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { Globals.openDd = ""; dr.picked(modelData.value) }
                        }
                    }
                }
            }
        }
    }
}
