import QtQuick
import qs

// ewe.vpn — the shield inside the bar's Quick settings pill while a VPN is
// up; while a connection attempt is in flight a Spinner takes the glyph's
// place (the shell's "connecting…" spin), so the bar says something is
// happening before the shield appears.
BarStatusGlyph {
    id: root
    property string pluginId: ""
    property var settings: ({})
    property var screen: null
    property var barWindow: null
    readonly property bool busy: Vpn.busyName !== ""
    text: Theme.icVpn
    shown: Vpn.active || root.busy
    // the glyph yields its place (not its width) to the spinner
    color: root.busy ? Theme.withAlpha(root.ink, 0) : root.ink
    Spinner {
        anchors.centerIn: parent
        visible: root.busy
        size: Theme.barIcon
    }
}
