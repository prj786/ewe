import QtQuick
import qs

// ewe.ssh — the square-terminal glyph inside the bar's Quick settings pill,
// shown while a background SOCKS tunnel started from the SSH page is up.
BarStatusGlyph {
    property string pluginId: ""
    property var settings: ({})
    property var screen: null
    property var barWindow: null
    text: Theme.icSsh
    shown: Ssh.tunnelUp
}
