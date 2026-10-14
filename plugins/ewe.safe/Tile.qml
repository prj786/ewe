import QtQuick
import qs

// ewe.safe — the Quick settings tile. Tap: lock an open safe, or unlock a
// locked one (Safe's own prompt asks for the master password — never this
// panel). The details zone opens the Safe window. Before a safe exists the
// tap opens Safe to set one up.
Tile {
    id: root
    property string pluginId: ""
    property var settings: ({})
    property bool panelOpen: false

    ic: SafeState.unlocked ? Theme.icLockOpen : Theme.icLock
    label: "Safe"
    sub: SafeState.tileSub
    active: SafeState.unlocked
    hasMenu: SafeState.appInstalled
    disabled: SafeState.phase === "missing"
    onClicked: SafeState.toggleLock()
    onMenu: SafeState.openApp("")
}
