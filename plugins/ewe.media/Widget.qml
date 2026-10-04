import QtQuick
import qs

// ewe.media — the music note in the bar (API 3 bar-widget, one per monitor).
// A click runs the same action the dock item runs, with this module as the
// anchor, so the popup opens under the bar on this very screen.
//
// Shown per the `button` setting — auto: only while no dock is present
// (Shell.dockPresent); bar / both: always; dock: never — and, like the dock's
// own music button always did, only while an MPRIS player exists
// (`always_show` keeps it in place with nothing playing). A hidden widget
// collapses to zero width so the bar's Row packs nothing for it.
Item {
    id: root
    property string pluginId: ""
    property var settings: ({})
    property var screen: null
    property var barWindow: null

    MprisPick { id: pick }

    readonly property string mode: (root.settings && root.settings.button) ? String(root.settings.button) : "auto"
    readonly property bool allowed: mode === "bar" || mode === "both" || (mode === "auto" && !Shell.dockPresent)
    readonly property bool shown: allowed && (pick.player !== null || (root.settings && root.settings.always_show === true))

    implicitWidth: shown ? mod.implicitWidth : 0
    implicitHeight: mod.implicitHeight

    BarModule {
        id: mod
        visible: root.shown
        glyph: Theme.icMusic
        a11yName: "Music"
        active: Shell.isActive("ewe.media.toggle")
        onActivated: Shell.runAction("ewe.media.toggle", Shell.anchorFor(mod, root.barWindow))
    }
}
