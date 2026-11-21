pragma Singleton
import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray

// ImeState — typing in other languages (fcitx5, on demand; bin/ewe-ime owns
// it). ONE indicator in the bar: the keyboard layout module shows the
// engine's mark ("拼", "あ", "한") while an engine is on, and fcitx5's own
// tray icon is hidden (Bar.qml filters it out of the tray).
//
// No polling. fcitx5's tray item (StatusNotifierItem id "Fcitx", which the
// bar's tray host receives anyway) changes its icon whenever the input
// method changes — Ctrl+Space, a click here, ewe Settings — so its
// appearance and every icon change ask `ewe-ime current` once. No item = no
// fcitx5 running = nothing to show.
QtObject {
    id: ime

    readonly property string tool: Quickshell.env("EWE_IME_TOOL")
        || (Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-ime")

    property bool running: false     // fcitx5 is up (its tray item exists)
    property bool active: false      // an engine is on (not the plain layout)
    property string im: ""           // fcitx5's input method name ("pinyin")
    property string glyph: ""        // what the bar shows while active
    property string label: ""        // "Chinese — Pinyin"

    // fcitx5's own tray item — hidden from the bar's tray, watched here
    function isImeItem(item) { return !!item && String(item.id) === "Fcitx" }
    property var trayItem: null
    function _findItem() {
        var vs = SystemTray.items.values, found = null
        for (var i = 0; i < vs.length; i++) if (ime.isImeItem(vs[i])) { found = vs[i]; break }
        if (found !== ime.trayItem) {
            ime.trayItem = found
            ime.running = found !== null
            if (found) ime.refresh()
            else { ime.active = false; ime.im = ""; ime.glyph = ""; ime.label = "" }
        }
    }
    property Connections _items: Connections {
        target: SystemTray.items
        function onValuesChanged() { ime._findItem() }
    }
    property Connections _icon: Connections {
        target: ime.trayItem
        ignoreUnknownSignals: true
        function onIconChanged() { ime.refresh() }
        function onTooltipTitleChanged() { ime.refresh() }
    }
    Component.onCompleted: ime._findItem()

    function _take(d) {
        if (!d || d.ok === false) return
        ime.active = d.active === true
        ime.im = d.im || ""
        ime.glyph = d.glyph || ""
        ime.label = d.label || ""
    }

    // one read at a time; a change that lands meanwhile reads again after
    property bool _again: false
    function refresh() {
        if (ime._proc.running) { ime._again = true; return }
        ime._proc.command = [ime.tool, "current"]
        ime._proc.running = true
    }
    property Process _proc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { ime._take(JSON.parse(this.text)) } catch (e) {}
            }
        }
        onExited: if (ime._again) { ime._again = false; ime.refresh() }
    }

    // the bar's click: an engine on → back to the plain layout; the menu
    // button toggles the engine (what Ctrl+Space does)
    function off() { Quickshell.execDetached(["fcitx5-remote", "-c"]) }
    function toggle() { Quickshell.execDetached(["fcitx5-remote", "-t"]) }
}
