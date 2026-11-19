import QtQuick
import qs

// ewe.insomnia — the Quick settings tile: a coffee cup (the eye was the
// show-password glyph), lit while awake. The status says how long is left
// when an auto-off is set.
Tile {
    id: root
    property string pluginId: ""
    property var settings: ({})
    property bool panelOpen: false
    ic: Theme.icCoffee
    label: "Insomnia"
    sub: Insomnia.on ? (Insomnia.until > 0 ? "On · off in " + Insomnia.leftText : "On") : "Off"
    active: Insomnia.on
    onClicked: Insomnia.toggle()
}
