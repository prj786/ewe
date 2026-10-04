import QtQuick
import qs

// ewe.places — the folder in the bar (API 3 bar-widget, one per monitor).
// A click runs the same action the dock item runs, with this module as the
// anchor, so the panel opens under the bar on this very screen.
//
// Shown per the `button` setting — auto: only while no dock is present
// (Shell.dockPresent); bar / both: always; dock: never. A hidden widget
// collapses to zero width so the bar's Row packs nothing for it.
Item {
    id: root
    property string pluginId: ""
    property var settings: ({})
    property var screen: null
    property var barWindow: null

    readonly property string mode: (root.settings && root.settings.button) ? String(root.settings.button) : "auto"
    readonly property bool shown: mode === "bar" || mode === "both" || (mode === "auto" && !Shell.dockPresent)

    implicitWidth: shown ? mod.implicitWidth : 0
    implicitHeight: mod.implicitHeight

    BarModule {
        id: mod
        visible: root.shown
        glyph: Theme.icFolder
        a11yName: "Places"
        active: Shell.isActive("ewe.places.toggle")
        onActivated: Shell.runAction("ewe.places.toggle", Shell.anchorFor(mod, root.barWindow))
    }
}
