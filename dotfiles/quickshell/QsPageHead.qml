import QtQuick

// QsPageHead — a Quick settings page's head: back (to the home grid), the
// feature's name and a quiet status, extra actions (children), and the
// feature's Switch. Back goes through Shell.openQuickSettings("home"), so a
// plugin page needs nothing of the panel's internals.
Item {
    id: ph
    property string title: ""
    property string note: ""
    property bool busy: false
    property bool hasSwitch: false
    property bool on: false
    property bool switchDisabled: false
    default property alias actions: phAct.data
    signal toggled()
    width: parent ? parent.width : Theme.panelSm
    height: Theme.controlLg
    QsIconButton {
        id: phBack
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        size: "md"; ic: Theme.icBack
        onGo: Shell.openQuickSettings("home")
    }
    Row {
        anchors.left: phBack.right; anchors.leftMargin: Theme.spaceS
        anchors.right: phAct.left; anchors.rightMargin: Theme.spaceS
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spaceS
        TextStrong { id: phTitle; anchors.verticalCenter: parent.verticalCenter; text: ph.title; width: Math.min(implicitWidth, parent.width) }
        Spinner { visible: ph.busy; anchors.verticalCenter: parent.verticalCenter; size: Theme.iconSm }
        TextCaption {
            visible: ph.note !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - phTitle.width - (ph.busy ? Theme.iconSm + Theme.spaceS : 0) - Theme.spaceS)
            text: ph.note
        }
    }
    Row {
        id: phAct
        anchors.right: phSw.visible ? phSw.left : parent.right
        anchors.rightMargin: phSw.visible ? Theme.spaceS : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spaceXxs
    }
    Toggle {
        id: phSw
        visible: ph.hasSwitch
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        on: ph.on; disabled: ph.switchDisabled
        onToggled: ph.toggled()
    }
}
