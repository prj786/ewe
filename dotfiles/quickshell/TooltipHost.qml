pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland

// TooltipHost — the ONE tooltip of the shell (design system: Tooltip).
// `Tooltip {}` (the promoted component) asks it to show after the card's
// hover delay and to hide when the pointer leaves; every tooltip in the
// bar, the dock, the panels and the plugins shares this window, so a
// hundred icon buttons cost one hidden layer surface, not a hundred.
//
//   container  surfaceOverlay, a borderWidth1 borderSubtle outline, the
//              radiusSlight corner, shadowSm; spaceXxs × spaceS of padding
//              (spaceXs × spaceS for the two-line form); at most 10 ×
//              controlSm (240) wide
//   text       the label style in textPrimary; the two-line form has the
//              title at weight medium and the description in textSecondary
//   shortcut   a Kbd combination spaceS after the text (caption, textMuted)
//
// Placed spaceXs from its target, centred on it: below a target in the top
// half of the screen (the bar), above one in the bottom half (the dock) —
// `placement` "above" / "below" forces it; never covering the target. No
// arrow. Appears after the hover delay (2 × durSlow, the card's 500 ms at
// Normal speed); once one is showing, the neighbours' appear at once.
// Takes no input (an empty mask) and never the keyboard.
Scope {
    id: host

    property Item item: null            // the target showing (or waiting)
    property string label: ""
    property string description: ""
    property string shortcut: ""
    property string placement: "auto"
    property bool shown: false
    property var screen: null
    property real tipX: 0
    property real tipY: 0

    readonly property int delay: 2 * Theme.durSlow

    Timer { id: delayTimer; interval: Math.max(1, host.delay); onTriggered: host.place() }
    Timer { id: warm; interval: Math.max(1, host.delay) }     // a neighbour opens without the delay

    function show(item, label, description, shortcut, placement, delay) {
        if (!item || !label) return
        host.item = item
        host.label = String(label)
        host.description = description ? String(description) : ""
        host.shortcut = shortcut ? String(shortcut) : ""
        host.placement = placement ? String(placement) : "auto"
        if (host.shown || warm.running) host.place()
        else { delayTimer.interval = Math.max(1, (delay !== undefined && delay !== null && delay >= 0) ? delay : host.delay); delayTimer.restart() }
    }
    // hide(item): only when that item's tooltip is the one showing or
    // waiting; hide() with nothing hides whatever shows (a menu opening)
    function hide(item) {
        if (item && host.item !== item) return
        delayTimer.stop()
        if (host.shown) { host.shown = false; warm.restart() }
        host.item = null
    }
    function place() {
        var it = host.item
        if (!it || !it.visible || host.label === "") { host.shown = false; return }
        var top = Shell.screenPoint(it, it.width / 2, 0)
        var bottom = Shell.screenPoint(it, it.width / 2, it.height)
        if (!top || !top.screen) { host.shown = false; return }
        host.screen = top.screen
        var sw = top.screen.width, sh = top.screen.height
        var w = box.width, h = box.height
        var below = host.placement === "below" || (host.placement !== "above" && top.y < sh / 2)
        host.tipX = Math.round(Math.max(Theme.spaceXs, Math.min(sw - w - Theme.spaceXs, top.x - w / 2)))
        host.tipY = Math.round(below ? Math.min(sh - h - Theme.spaceXs, bottom.y + Theme.spaceXs)
                                     : Math.max(Theme.spaceXs, top.y - Theme.spaceXs - h))
        host.shown = true
    }

    PanelWindow {
        id: win
        visible: host.shown || win.held
        screen: host.screen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell:tooltip"
        anchors { top: true; bottom: true; left: true; right: true }
        // an empty input region: the pointer never sees this window
        mask: Region {}

        // `held` keeps the window mapped through the fade out
        property bool held: false
        Timer { id: closeTimer; interval: Math.max(1, Theme.durFast + 60); onTriggered: win.held = false }
        Connections { target: host; function onShownChanged() {
            if (host.shown) { closeTimer.stop(); win.held = true }
            else closeTimer.restart()
        } }

        Rectangle {
            id: box
            readonly property bool twoLine: host.description !== ""
            readonly property int maxW: 10 * Theme.controlSm
            readonly property int padV: box.twoLine ? Theme.spaceXs : Theme.spaceXxs
            x: host.tipX; y: host.tipY
            width: Math.min(box.maxW, body.implicitWidth + 2 * Theme.spaceS)
            height: body.implicitHeight + 2 * box.padV
            radius: Theme.radiusSlight
            color: Theme.surfaceOverlay
            border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
            layer.enabled: true
            // the short shadow: shadowSm, not the panels' shadowFloat
            layer.effect: Elevation { shadowColor: Theme.shadowSm.color; shadowHorizontalOffset: Theme.shadowSm.x; shadowVerticalOffset: Theme.shadowSm.y; blurMax: Theme.shadowSm.blur }
            opacity: host.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }

            Row {
                id: body
                anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spaceS
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: host.label
                        color: Theme.textPrimary
                        font.family: Theme.type.label.family
                        font.pixelSize: Theme.type.label.size
                        font.weight: box.twoLine ? Theme.fontWeightMedium : Theme.type.label.weight
                        lineHeight: Theme.type.label.lineHeight; lineHeightMode: Text.FixedHeight
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, box.maxW - 2 * Theme.spaceS - (host.shortcut !== "" ? kbd.implicitWidth + Theme.spaceS : 0))
                    }
                    Text {
                        visible: box.twoLine
                        text: host.description
                        color: Theme.textSecondary
                        font.family: Theme.type.label.family
                        font.pixelSize: Theme.type.label.size
                        lineHeight: Theme.type.label.lineHeight; lineHeightMode: Text.FixedHeight
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, box.maxW - 2 * Theme.spaceS)
                    }
                }
                Text {
                    id: kbd
                    visible: host.shortcut !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: host.shortcut
                    color: Theme.textMuted
                    font.family: Theme.type.caption.family
                    font.pixelSize: Theme.type.caption.size
                }
            }
        }
    }
}
