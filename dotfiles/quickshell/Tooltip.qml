import QtQuick

// Tooltip — names an icon-only control on hover (design system: Tooltip).
// Declare it INSIDE the control (or point `target` at one): a HoverHandler
// on that item asks the shell's one TooltipHost to show `text` after the
// card's delay and to hide when the pointer leaves. It draws nothing itself
// and takes no input or layout space. Public to plugins (docs/PLUGINS.md).
//
//   QsIconButton { ic: Theme.icRefresh; Tooltip { text: "Refresh" } }
//   Tooltip { target: someItem; text: "Battery"; description: "82%, 2 h left" }
//
//   text         the label (a few words, sentence case, no period)
//   description  the second line of the two-line form (bar states)
//   shortcut     a Kbd combination after the text ("Super+V")
//   placement    "auto" (below in the top half of the screen, above in the
//                bottom half) · "above" · "below"
//   delay        ms before it shows; -1 = the card's 500
Item {
    id: tip
    property string text: ""
    property string description: ""
    property string shortcut: ""
    property string placement: "auto"
    property int delay: -1
    property Item target: null
    property bool enabled: true
    visible: false
    width: 0; height: 0
    readonly property Item _t: tip.target ? tip.target : tip.parent

    HoverHandler {
        id: hh
        parent: tip._t ? tip._t : tip
        enabled: tip.enabled && tip.text !== "" && tip._t !== null
        onHoveredChanged: {
            if (hovered) TooltipHost.show(tip._t, tip.text, tip.description, tip.shortcut, tip.placement, tip.delay)
            else TooltipHost.hide(tip._t)
        }
    }
    // a label that changes while the pointer rests (a state in it) follows
    onTextChanged: if (hh.hovered && TooltipHost.item === tip._t) TooltipHost.show(tip._t, tip.text, tip.description, tip.shortcut, tip.placement, tip.delay)
    onEnabledChanged: if (!tip.enabled) TooltipHost.hide(tip._t)
    Component.onDestruction: TooltipHost.hide(tip._t)
}
