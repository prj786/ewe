import QtQuick
import qs

// ewe.ssh — the Quick settings home tile. Hosts are a list, not a switch, so
// body and details both open the SSH page; `active` while a tunnel is up.
// Home shows only what exists (as the shell did): no hosts and no tunnel →
// no tile. The host's slot (this tile's parent) is what takes space in the
// grid, so that is what is hidden — a tile with nothing to say leaves no gap.
Tile {
    id: root
    property string pluginId: ""
    property var settings: ({})
    property bool panelOpen: false
    onPanelOpenChanged: Ssh.tileOpen = root.panelOpen

    readonly property bool present: Ssh.hosts.length > 0 || Ssh.tunnelUp
    onPresentChanged: root.syncSlot()
    Component.onCompleted: root.syncSlot()
    function syncSlot() { if (root.parent) root.parent.visible = root.present }

    ic: Theme.icSsh; label: "SSH"
    active: Ssh.tunnelUp
    hasMenu: true
    sub: Ssh.tunnelUp ? "Tunnel on"
       : Ssh.hosts.length > 0 ? Ssh.hosts.length + (Ssh.hosts.length === 1 ? " host" : " hosts")
       : "Not set up"
    onClicked: Shell.openQuickSettings("ssh")
    onMenu: Shell.openQuickSettings("ssh")
}
