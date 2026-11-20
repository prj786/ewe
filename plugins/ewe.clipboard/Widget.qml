import QtQuick
import qs

// ewe.clipboard — the clipboard glyph in the bar (API 3 bar-widget, one per
// monitor, 1.3.0). A click runs the panel's action with this module as the
// anchor, so the card opens under this very icon on this screen — no
// `qs ipc call` process per click any more.
Item {
    id: root
    property string pluginId: ""
    property var settings: ({})
    property var screen: null
    property var barWindow: null

    implicitWidth: mod.implicitWidth
    implicitHeight: mod.implicitHeight

    BarModule {
        id: mod
        glyph: Theme.icClipboard
        a11yName: "Clipboard"
        active: Shell.isActive("ewe.clipboard.toggle")
        onActivated: Shell.runAction("ewe.clipboard.toggle", Shell.anchorFor(mod, root.barWindow))
    }
}
