import QtQuick
import qs

// acme.v3demo — a Quick settings page (quickPage.key "demo"): reached from
// the rail, the tile's details zone, `qs ipc call quicksettings tab demo`
// and Shell.openQuickSettings("demo"). Built from the public components.
Column {
    id: root
    property string pluginId: ""
    property string stateDir: ""
    property var settings: ({})
    property bool panelOpen: false
    property bool flag: false
    spacing: Theme.spaceS
    QsPageHead { title: "Demo"; note: root.panelOpen ? "on screen" : "" }
    QsSwitchRow { ic: Theme.icStar; label: "A switch row"; desc: "QsSwitchRow from the public set"; on: root.flag; onToggled: root.flag = !root.flag }
    QsSegmented { options: [{ label: "One", value: 1 }, { label: "Two", value: 2 }]; value: 1 }
    Row {
        spacing: Theme.spaceS
        QsButton { label: "Toast"; ic: Theme.icBellRing; variant: "primary"; onGo: Shell.toast("Hello from the demo page") }
        QsButton { label: "Home"; onGo: Shell.openQuickSettings("home") }
        QsIconButton { ic: Theme.icClose; onGo: Shell.closeQuickSettings() }
    }
    QsNote { text: "pluginId " + root.pluginId + " · stateDir " + root.stateDir + " · bottomInset " + Shell.bottomInset }
    QsEmpty { ic: Theme.icStar; title: "An empty state"; desc: "QsEmpty, for a page with nothing to list yet." }
}
