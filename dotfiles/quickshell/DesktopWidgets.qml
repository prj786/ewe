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

    // ── an arrange-mode chip (.ewe-chip): controlSm pill on surfaceOverlay
    //    with a borderSubtle edge, fontSizeXs medium textPrimary; the name
    //    chip is solid accent (semibold, onAccent); `on` is accentSubtle
    //    with an accent edge and accentText; hover is surfaceHover ──
    component Chip: Rectangle {
        id: chip
        property string glyph: ""
        property string label: ""
        property bool name: false
        property bool on: false
        signal act()
        readonly property color ink: chip.name ? Theme.onAccent : chip.on ? Theme.accentText : Theme.textPrimary
        height: Theme.controlSm; radius: Theme.radiusFull
        width: chipRow.implicitWidth + 2 * Theme.spaceS
        color: chip.name ? Theme.accent : chip.on ? Theme.accentSubtle
             : chipMa.containsMouse ? Theme.surfaceHover : Theme.surfaceOverlay
        border.color: chip.name || chip.on ? Theme.accent : Theme.borderSubtle
        border.width: Theme.borderWidth1
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
        Row {
            id: chipRow
            anchors.centerIn: parent; spacing: Theme.spaceXs
            Text {
                visible: chip.glyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: chip.glyph
                font.family: Theme.fontIcons; font.pixelSize: Theme.iconXs
                color: chip.ink
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label; color: chip.ink
                font.family: Theme.type.caption.family
                font.pixelSize: Theme.fontSizeXs
                font.weight: chip.name ? Theme.fontWeightSemibold : Theme.fontWeightMedium
            }
        }
        MouseArea {
            id: chipMa
            anchors.fill: parent
            enabled: !chip.name
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: chip.act()
        }
    }

    // 48/64 is a stored placement default shared with bin/ewe-plugin (a
    // position in ewe.conf, not a look), so it stays as it is written there
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
                        id: stageRoot
                        anchors.fill: parent
                        focus: Globals.widgetsArrange
                        // which widget the arrow keys move (new, per the card);
                        // Tab walks the widgets on this screen
                        property int focusIndex: 0
                        onFocusChanged: if (focus) focusIndex = 0
                        Keys.onEscapePressed: Globals.widgetsArrange = false
                        Keys.onTabPressed: function (ev) {
                            if (rep.count > 0) stageRoot.focusIndex = (stageRoot.focusIndex + 1) % rep.count
                            ev.accepted = true
                        }
                        // arrow keys nudge the focused widget by spaceS, or
                        // spaceLg with Shift, and persist where it lands
                        Keys.onPressed: function (ev) {
                            var dx = ev.key === Qt.Key_Left ? -1 : ev.key === Qt.Key_Right ? 1 : 0
                            var dy = ev.key === Qt.Key_Up ? -1 : ev.key === Qt.Key_Down ? 1 : 0
                            if (dx === 0 && dy === 0) return
                            var step = (ev.modifiers & Qt.ShiftModifier) ? Theme.spaceLg : Theme.spaceS
                            var it = rep.itemAt(stageRoot.focusIndex)
                            if (it) it.nudge(dx * step, dy * step)
                            ev.accepted = true
                        }

                        Repeater {
                            id: rep
                            model: win.mine
                            onItemAdded: win.rebuildMask()
                            onItemRemoved: win.rebuildMask()
                            delegate: Item {
                                id: slot
                                required property var modelData
                                required property int index
                                readonly property var place: root._place(modelData.id)
                                readonly property bool keyFocused: Globals.widgetsArrange && stageRoot.focusIndex === slot.index
                                // the Glass card ewe draws under every widget:
                                // the plugin sizes its content, ewe adds the
                                // card's own padding around it
                                readonly property int padH: Theme.spaceMd
                                readonly property int padV: Theme.spaceS + Theme.spaceXs
                                x: place.x
                                y: place.y
                                // until the plugin reports a size: half a panel-sm
                                // wide (.ewe-widget__rows) and one control2xl tall
                                width: (loader.item ? loader.item.implicitWidth : Theme.panelSm / 2) + 2 * padH
                                height: (loader.item ? loader.item.implicitHeight : Theme.control2xl) + 2 * padV
                                // the window's input region for this widget follows its geometry
                                readonly property Region regionObj: Region { item: slot }

                                function nudge(dx, dy) {
                                    slot.x = Math.max(0, Math.min(win.width - slot.width, slot.x + dx))
                                    slot.y = Math.max(0, Math.min(win.height - slot.height, slot.y + dy))
                                    PluginHost.placeWidget(slot.modelData.id, slot.x, slot.y)
                                }

                                // the card itself (Desktop widgets card, "Anatomy")
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.radiusRounded
                                    color: Theme.glassRaised
                                    border.color: Theme.glassBorder
                                    border.width: Theme.borderWidth1
                                    layer.enabled: drag.pressed
                                    layer.effect: Elevation {}
                                }

                                Loader {
                                    id: loader
                                    anchors.fill: parent
                                    anchors.leftMargin: slot.padH; anchors.rightMargin: slot.padH
                                    anchors.topMargin: slot.padV; anchors.bottomMargin: slot.padV
                                    source: "file://" + slot.modelData.entry
                                    onStatusChanged: {
                                        if (status === Loader.Error) Log.warn("plugins", slot.modelData.id + "/desktop-widget failed to load (see the qml error above)")
                                        else if (status === Loader.Ready) { Log.debug("plugins", "desktop-widget", slot.modelData.id, "on", perScreen.modelData.name, win.layerName); PluginHost._giveSettings(item, slot.modelData.id) }
                                    }
                                    Connections { target: PluginHost; function onSettingsChanged() { if (loader.status === Loader.Ready) PluginHost._giveSettings(loader.item, slot.modelData.id) } }
                                }

                                // ── arrange mode: a dashed accent outline
                                //    spaceXs outside the card; solid while it
                                //    is being dragged or has the keyboard ──
                                Canvas {
                                    id: frame
                                    anchors.fill: parent; anchors.margins: -Theme.spaceXs
                                    visible: Globals.widgetsArrange
                                    readonly property bool solid: drag.pressed
                                    onSolidChanged: requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()
                                        ctx.strokeStyle = Theme.accent
                                        ctx.lineWidth = Theme.borderWidth1
                                        ctx.setLineDash(frame.solid ? [] : [Theme.spaceXs, Theme.spaceXs])
                                        var h = Theme.borderWidth1 / 2
                                        ctx.beginPath()
                                        ctx.roundedRect(h, h, width - 2 * h, height - 2 * h, Theme.radiusRounded + Theme.spaceXs, Theme.radiusRounded + Theme.spaceXs)
                                        ctx.stroke()
                                    }
                                }
                                // the widget the arrow keys move carries the
                                // focus ring, just outside the dashed outline
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -(Theme.spaceXs + Theme.spaceXxs)
                                    visible: Globals.widgetsArrange && slot.keyFocused
                                    radius: Theme.radiusRounded + Theme.spaceXs + Theme.spaceXxs
                                    color: "transparent"
                                    border.color: Theme.focusRing
                                    border.width: Theme.focusWidth
                                }
                                MouseArea {
                                    id: drag
                                    anchors.fill: parent
                                    enabled: Globals.widgetsArrange
                                    cursorShape: enabled ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
                                    property real ox: 0
                                    property real oy: 0
                                    onPressed: function (m) { ox = m.x; oy = m.y; stageRoot.focusIndex = slot.index }
                                    onPositionChanged: function (m) {
                                        if (!pressed) return
                                        slot.x = Math.max(0, Math.min(win.width - slot.width, slot.x + m.x - ox))
                                        slot.y = Math.max(0, Math.min(win.height - slot.height, slot.y + m.y - oy))
                                    }
                                    onReleased: PluginHost.placeWidget(slot.modelData.id, slot.x, slot.y)
                                }

                                // ── the chip row, spaceS + spaceXs above the card —
                                //    or below it when the bar would cover it (a
                                //    widget near the top edge; the default spot) ──
                                Row {
                                    id: chips
                                    visible: Globals.widgetsArrange
                                    anchors.left: parent.left
                                    readonly property int gap: Theme.spaceS + Theme.spaceXs
                                    readonly property bool below: slot.y - chips.height - chips.gap
                                                                  < (Globals.barVisible ? Theme.barHeight : 0)
                                    y: chips.below ? slot.height + chips.gap : -(chips.height + chips.gap)
                                    spacing: Theme.spaceXs
                                    // the widget's name: a solid accent chip
                                    Chip { label: slot.modelData.name; name: true }
                                    // Sticky keeps it above windows; accentSubtle while on
                                    Chip {
                                        glyph: Theme.icPin; label: "Sticky"
                                        on: win.layerName === "top"
                                        onAct: PluginHost.setWidgetLayer(slot.modelData.id, win.layerName === "top" ? "desktop" : "top")
                                    }
                                    Chip {
                                        glyph: Theme.icEyeOff; label: "Hide"
                                        onAct: PluginHost.setWidgetVisible(slot.modelData.id, false)
                                    }
                                }
                            }
                        }

                        // ── the mode's own hint: a Glass pill at the bottom,
                        //    once per screen (on the desktop layer), clear of
                        //    the dock (its strip + windowGap + spaceMd) ──
                        Item {
                            visible: Globals.widgetsArrange && win.layerName === "desktop"
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: (Globals.dockIconSize === "small" ? Theme.controlXl
                                                 : Globals.dockIconSize === "large" ? Theme.barHeightLg : Theme.control2xl)
                                                + 2 * Theme.spaceS + Theme.windowGap + Theme.spaceMd
                            width: pill.width; height: pill.height
                            // shadowFloat under the pill (.ewe-hintpill)
                            Rectangle { id: pillShadow; anchors.fill: parent; radius: Theme.radiusFull; color: Theme.black; visible: false }
                            Elevation { anchors.fill: pillShadow; source: pillShadow }
                            Rectangle {
                                id: pill
                                width: hint.implicitWidth + 2 * Theme.spaceMd
                                height: Theme.controlXl
                                radius: Theme.radiusFull
                                color: Theme.glassRaised
                                border.color: Theme.glassBorder; border.width: Theme.borderWidth1
                                Row {
                                    id: hint
                                    anchors.centerIn: parent; spacing: Theme.spaceS
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Drag to move · Sticky stays above windows ·"
                                        color: Theme.textSecondary
                                        font.family: Theme.type.label.family
                                        font.pixelSize: Theme.fontSizeS
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: escT.implicitWidth + 2 * Theme.spaceXs
                                        height: escT.implicitHeight + 2 * Theme.borderWidth2
                                        radius: Theme.radiusSlight
                                        color: Theme.surfaceRaised
                                        border.color: Theme.borderStrong; border.width: Theme.borderWidth1
                                        Text {
                                            id: escT; anchors.centerIn: parent; text: "Esc"
                                            color: Theme.textSecondary
                                            font.family: Theme.type.mono.family
                                            font.pixelSize: Theme.type.caption.size
                                            font.weight: Theme.fontWeightMedium
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Done"
                                        color: Theme.textSecondary
                                        font.family: Theme.type.label.family
                                        font.pixelSize: Theme.fontSizeS
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
