import QtQuick
import qs

// acme.v3demo — a Quick settings home tile spanning the row (quickTile.span
// 2). The host sizes it and injects pluginId / settings / panelOpen; the
// body toggles a demo flag and toasts, the details zone opens the page.
Tile {
    id: root
    property string pluginId: ""
    property var settings: ({})
    property bool panelOpen: false
    property bool on: false
    ic: Theme.icStar
    label: (root.settings.label || "Demo") + " tile"
    sub: root.on ? "On · span 2" : "Off · span 2"
    active: root.on
    hasMenu: true
    onClicked: { root.on = !root.on; Shell.toast("Demo tile " + (root.on ? "on" : "off")) }
    onMenu: Shell.openQuickSettings("demo")
}
