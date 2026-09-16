import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// DesktopWidgets — where plugins of kind `desktop-widget` live. The plugin
// draws a sized Item; ewe owns the rest: which output, where on it, whether
// it sits on the desktop (below windows) or is STICKY (above them), whether
// it is shown at all, and the values of the options the plugin declared.
//
// Two windows per output, one per layer, each the full output and
// click-through except where a widget is (the input mask is the union of
// the widget rects), so the desktop behind stays usable. Placement comes
// from PluginHost.placement (ewe.conf plugins.widgets.<id>); a widget with
// no output of its own goes to the first screen.
//
// Arrange mode (Super+Shift+W / `qs ipc call widgets arrange`): every widget
// gets a frame with its name, a drag handle over its whole area, a sticky
// toggle and a hide button; Esc or the key again ends it. A drop persists
// through `ewe-plugin place`, which pokes `plugins reload` back — no restart.
Scope {
    id: root

    function _place(id) { return PluginHost.placement[id] || ({ x: 48, y: 64, output: "", layer: "desktop", visible: true }) }
    function _onScreen(w, screen, index) {
        var p = root._place(w.id)
        var out = p.output || ""
        return out === "" ? index === 0 : out === screen.name
    }

    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: perScreen
            required property var modelData
            // Variants hands over no index: the first screen is the one at the head of the list
            readonly property int index: Quickshell.screens.indexOf(modelData)

            // Variants, not Repeater: a Repeater needs an Item parent and a
            // Scope is not one — it would silently create nothing
            Variants {
                model: ["desktop", "top"]
                delegate: PanelWindow {
                    id: win
                    required property string modelData
                    readonly property string layerName: modelData
                    screen: perScreen.modelData
                    color: "transparent"
                    exclusionMode: ExclusionMode.Ignore
                    anchors { top: true; bottom: true; left: true; right: true }
                    WlrLayershell.namespace: "quickshell:widgets-" + layerName
                    WlrLayershell.layer: layerName === "top" ? WlrLayer.Top : WlrLayer.Bottom
                    // Esc must reach us while arranging; otherwise never take the keyboard
                    WlrLayershell.keyboardFocus: Globals.widgetsArrange ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
                    readonly property var mine: PluginHost.desktopWidgets.filter(function (w) {
                        var p = root._place(w.id)
                        return root._onScreen(w, perScreen.modelData, perScreen.index)
                            && (p.layer || "desktop") === win.layerName && p.visible !== false
                    })
                    visible: mine.length > 0
                    // input only where widgets are — everywhere else clicks fall through
                    property list<Region> regions
                    mask: Region { regions: Globals.widgetsArrange ? [] : win.regions }
                    function rebuildMask() {
                        var rs = []
                        for (var i = 0; i < rep.count; i++) {
                            var it = rep.itemAt(i)
                            if (it && it.regionObj) rs.push(it.regionObj)
                        }
                        win.regions = rs
                    }

                    Item {
                        anchors.fill: parent
                        focus: Globals.widgetsArrange
                        Keys.onEscapePressed: Globals.widgetsArrange = false

                        Repeater {
                            id: rep
                            model: win.mine
                            onItemAdded: win.rebuildMask()
                            onItemRemoved: win.rebuildMask()
                            delegate: Item {
                                id: slot
                                required property var modelData
                                readonly property var place: root._place(modelData.id)
                                x: place.x
                                y: place.y
                                width: loader.item ? loader.item.implicitWidth : 200
                                height: loader.item ? loader.item.implicitHeight : 80
                                // the window's input region for this widget follows its geometry
                                readonly property Region regionObj: Region { item: slot }

                                Loader {
                                    id: loader
                                    anchors.fill: parent
                                    source: "file://" + slot.modelData.entry
                                    onStatusChanged: {
                                        if (status === Loader.Error) Log.warn("plugins", slot.modelData.id + "/desktop-widget failed to load (see the qml error above)")
                                        else if (status === Loader.Ready) { Log.debug("plugins", "desktop-widget", slot.modelData.id, "on", perScreen.modelData.name, win.layerName); PluginHost._giveSettings(item, slot.modelData.id) }
                                    }
                                    Connections { target: PluginHost; function onSettingsChanged() { if (loader.status === Loader.Ready) PluginHost._giveSettings(loader.item, slot.modelData.id) } }
                                }

                                // ── arrange mode: frame, name, drag, sticky, hide ──
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: -6
                                    visible: Globals.widgetsArrange
                                    radius: Theme.radiusInner; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10)
                                    border.color: Theme.accent; border.width: 2
                                }
                                MouseArea {
                                    id: drag
                                    anchors.fill: parent
                                    enabled: Globals.widgetsArrange
                                    cursorShape: enabled ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
                                    property real ox: 0
                                    property real oy: 0
                                    onPressed: function (m) { ox = m.x; oy = m.y }
                                    onPositionChanged: function (m) {
                                        if (!pressed) return
                                        slot.x = Math.max(0, Math.min(win.width - slot.width, slot.x + m.x - ox))
                                        slot.y = Math.max(0, Math.min(win.height - slot.height, slot.y + m.y - oy))
                                    }
                                    onReleased: PluginHost.placeWidget(slot.modelData.id, slot.x, slot.y)
                                }
                                Row {
                                    visible: Globals.widgetsArrange
                                    anchors.left: parent.left; anchors.bottom: parent.top; anchors.bottomMargin: 10
                                    spacing: 6
                                    Rectangle {
                                        height: 24; width: nameT.implicitWidth + 16; radius: 12; color: Theme.accentFill
                                        Text { id: nameT; anchors.centerIn: parent; text: slot.modelData.name; color: Theme.accentOn; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                                    }
                                    Rectangle {
                                        height: 24; width: stickyT.implicitWidth + 16; radius: 12
                                        color: win.layerName === "top" ? Theme.accentFill : Theme.card
                                        Text { id: stickyT; anchors.centerIn: parent; text: win.layerName === "top" ? "Sticky · on" : "Sticky"; color: win.layerName === "top" ? Theme.accentOn : Theme.fg1; font.family: Theme.fontText; font.pixelSize: 11 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: PluginHost.setWidgetLayer(slot.modelData.id, win.layerName === "top" ? "desktop" : "top") }
                                    }
                                    Rectangle {
                                        height: 24; width: hideT.implicitWidth + 16; radius: 12; color: Theme.card
                                        Text { id: hideT; anchors.centerIn: parent; text: "Hide"; color: Theme.fg1; font.family: Theme.fontText; font.pixelSize: 11 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: PluginHost.setWidgetVisible(slot.modelData.id, false) }
                                    }
                                }
                            }
                        }

                        // the mode's own hint, once per screen (on the desktop layer)
                        Rectangle {
                            visible: Globals.widgetsArrange && win.layerName === "desktop"
                            anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 96
                            width: hint.implicitWidth + 28; height: 36; radius: 18; color: Theme.panel
                            Text { id: hint; anchors.centerIn: parent; text: "Arranging desktop widgets — drag to move · Sticky keeps one above windows · Esc when done"; color: Theme.fg2; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                        }
                    }
                }
            }
        }
    }
}
