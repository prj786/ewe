import QtQuick

// QsPageHead — a Quick settings page's head (design system: Quick settings,
// "Detail pages"): back (to the home page), the feature's name over a quiet
// status line ("Connected to home-5G", "Searching…"), extra actions
// (children), and the feature's Switch. It sits where home has the account
// row, so a page opens IN PLACE of home. Back goes through
// Shell.openQuickSettings("home"), so a plugin page needs nothing of the
// panel's internals; Esc does the same from anywhere on the page.
//
//   back     the md ghost Icon button with `chevron-left`
//   name     body-strong in textPrimary, a Spinner beside it while `busy`
//   status   caption in textMuted, under the name (only when `note` is set)
//   switch   the md Switch, at the right edge
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
    height: Math.max(Theme.controlLg, phText.implicitHeight)
    QsIconButton {
        id: phBack
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        size: "md"; ic: Theme.icBack
        onGo: Shell.openQuickSettings("home")
    }
    Column {
        id: phText
        anchors.left: phBack.right; anchors.leftMargin: Theme.spaceS
        anchors.right: phAct.left; anchors.rightMargin: Theme.spaceS
        anchors.verticalCenter: parent.verticalCenter
        Row {
            width: parent.width
            spacing: Theme.spaceXs
            TextStrong {
                id: phTitle
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - (ph.busy ? Theme.iconSm + parent.spacing : 0))
                text: ph.title
            }
            Spinner { visible: ph.busy; anchors.verticalCenter: parent.verticalCenter; size: Theme.iconSm }
        }
        TextCaption {
            visible: ph.note !== ""
            width: parent.width
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
