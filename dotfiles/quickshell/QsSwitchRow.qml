import QtQuick

// QsSwitchRow — a settings row: glyph, label and description on the left,
// the Switch on the right; clicking anywhere on the row fires `toggled`.
Item {
    id: sr
    property string ic: ""
    property string label: ""
    property string desc: ""
    property bool on: false
    property bool disabled: false
    property bool busy: false
    signal toggled()
    width: parent ? parent.width : Theme.panelSm
    height: Math.max(Theme.controlLg, srText.implicitHeight + 2 * Theme.spaceXs)
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSecondary
        color: (srMa.containsMouse && !sr.disabled) ? Theme.surfaceHover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
    }
    MouseArea { id: srMa; anchors.fill: parent; hoverEnabled: true; enabled: !sr.disabled; cursorShape: Qt.PointingHandCursor; onClicked: sr.toggled() }
    Glyph {
        id: srIc
        visible: sr.ic !== ""
        width: visible ? Theme.iconMd : 0
        anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
        anchors.verticalCenter: parent.verticalCenter
        text: sr.ic
        color: sr.disabled ? Theme.textDisabled : sr.on ? Theme.accentText : Theme.textSecondary
    }
    Column {
        id: srText
        anchors.left: srIc.right; anchors.leftMargin: sr.ic !== "" ? Theme.spaceS + Theme.spaceXs : Theme.spaceS
        anchors.right: srSw.left; anchors.rightMargin: Theme.spaceS
        anchors.verticalCenter: parent.verticalCenter
        TextBody { width: parent.width; text: sr.label; color: sr.disabled ? Theme.textDisabled : Theme.textPrimary }
        Row {
            visible: sr.desc !== "" || sr.busy
            spacing: Theme.spaceXs
            Spinner { visible: sr.busy; anchors.verticalCenter: parent.verticalCenter; size: Theme.iconSm }
            TextCaption { width: Math.min(implicitWidth, srText.width - (sr.busy ? Theme.iconSm + Theme.spaceXs : 0)); text: sr.desc }
        }
    }
    Toggle {
        id: srSw
        anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
        anchors.verticalCenter: parent.verticalCenter
        on: sr.on; disabled: sr.disabled
        onToggled: sr.toggled()
    }
}
