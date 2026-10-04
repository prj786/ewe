import QtQuick
import qs

// ewe.insomnia — the Quick settings tile: eye open while awake, eye-off
// while the idle inhibitor is released. The status says how long is left
// when an auto-off is set.
Tile {
    id: root
    property string pluginId: ""
    property var settings: ({})
    property bool panelOpen: false
    ic: Insomnia.on ? Theme.icEye : Theme.icEyeOff
    label: "Insomnia"
    sub: Insomnia.on ? (Insomnia.until > 0 ? "On · off in " + Insomnia.leftText : "On") : "Off"
    active: Insomnia.on
    onClicked: Insomnia.toggle()
}
