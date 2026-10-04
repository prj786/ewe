import QtQuick
import Quickshell
import Quickshell.Wayland

// AnchoredPopup — a plugin's popup card (API 3, docs/PLUGINS.md). ONE
// PanelWindow on the anchor's screen, spanning it so a click outside
// closes; the card is a surfaceRaised, borderSubtle, radiusRounded panel
// centred on the anchor's x, above the dock (Shell.bottomInset) for a
// bottom anchor or spaceXs under the bar for a top one. Esc closes; the
// keyboard is OnDemand while open. Declare the card's content as children.
//
//   AnchoredPopup { id: pop; action: "acme.music.toggle"; implicitWidth: Theme.panelSm
//                   Column { anchors.fill: parent; anchors.margins: Theme.spaceS … } }
//   Shell.registerAction("acme.music.toggle", function (a) { pop.toggleAt(a) })
Scope {
    id: pop
    property bool open: false
    property string name: "popup"         // layer-shell namespace suffix: quickshell:<name>
    property string action: ""            // Shell.isActive(action) follows `open` (the dock item lights)
    property int implicitWidth: Theme.panelSm
    property int implicitHeight: Theme.panelSm
    property var anchor: null             // { screen, x, y, edge } from Shell.anchorFor()
    default property alias content: card.data
    signal opened()
    signal closed()

    function openAt(a) { if (a) pop.anchor = a; pop.open = true }
    function toggleAt(a) { if (pop.open) pop.close(); else pop.openAt(a) }
    function close() { pop.open = false }
    onOpenChanged: {
        if (pop.action !== "") Shell.setActive(pop.action, pop.open)
        if (pop.open) pop.opened(); else pop.closed()
    }

    PanelWindow {
        id: win
        visible: pop.open || win.held
        screen: (pop.anchor && pop.anchor.screen) ? pop.anchor.screen : Shell._focusedScreen()
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:" + pop.name
        WlrLayershell.keyboardFocus: pop.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }

        // `held` keeps the window mapped through the close fade (the same
        // idiom as the Quick settings panel)
        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durBase); onTriggered: win.held = false }
        Connections { target: pop; function onOpenChanged() {
            if (pop.open) { closeTimer.stop(); win.held = true; card.forceActiveFocus() }
            else closeTimer.restart()
        } }
        MouseArea { anchors.fill: parent; onClicked: pop.close() }

        Rectangle {
            id: card
            readonly property int edgeGap: Theme.spaceS + Theme.spaceXs
            readonly property bool fromBottom: !pop.anchor || pop.anchor.edge !== "top"
            readonly property real ax: pop.anchor ? pop.anchor.x : parent.width / 2
            x: Math.round(Math.max(edgeGap, Math.min(parent.width - width - edgeGap, ax - width / 2)))
            // bottom: the dock's inset plus the card's own gap; top: spaceXs
            // under the bar (the layer already sits below its exclusive zone)
            y: fromBottom ? Math.max(edgeGap, parent.height - height - (Shell.bottomInset + edgeGap)) : Theme.spaceXs
            width: Math.min(pop.implicitWidth, parent.width - 2 * edgeGap)
            height: Math.min(pop.implicitHeight, parent.height - Shell.bottomInset - 2 * edgeGap)
            radius: Theme.radiusRounded
            color: Theme.surfaceRaised
            border.color: Theme.borderSubtle
            border.width: Theme.borderWidth1
            clip: true
            focus: true
            Keys.onEscapePressed: pop.close()
            layer.enabled: true
            layer.effect: Elevation {}
            // a plain fade, like the dock's own panels
            opacity: pop.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.ease } }
            MouseArea { anchors.fill: parent }   // clicks inside stay inside
        }
    }
}
