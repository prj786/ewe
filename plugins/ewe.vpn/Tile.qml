import QtQuick
import qs

// ewe.vpn — the Quick settings home tile: a split button. The body toggles
// (disconnect the active VPN / connect the only one / open the list when
// ambiguous), the chevron opens the VPN page. Home shows only what exists
// (as the shell did): no profiles and nothing active → no tile. The host's
// slot (this tile's parent) is what takes space in the grid, so that is what
// is hidden — a tile with nothing to say leaves no gap.
Tile {
    id: root
    property string pluginId: ""
    property var settings: ({})
    property bool panelOpen: false
    onPanelOpenChanged: Vpn.tileOpen = root.panelOpen

    readonly property bool present: Vpn.list.length > 0 || Vpn.active
    onPresentChanged: root.syncSlot()
    Component.onCompleted: root.syncSlot()
    function syncSlot() { if (root.parent) root.parent.visible = root.present }

    ic: Theme.icVpn; label: "VPN"
    active: Vpn.active
    hasMenu: true
    busy: Vpn.busyName !== ""
    sub: Vpn.busyName !== "" ? "Connecting…" : (Vpn.active ? "On" : "Off")
    onClicked: Vpn.toggleDefault()
    onMenu: Shell.openQuickSettings("vpn")
}
