import QtQuick
import Quickshell

// BarPopup — the card a bar button opens (0.45, additive to plugin API 3 —
// docs/PLUGINS.md). Every bar card looks the same: the System monitor's.
// It is an AnchoredPopup (placement, surface, radius, elevation, the fade,
// Esc, click-outside, one popup at a time) with the layout filled in:
//
//   width     Theme.grow(Theme.panelSm) — one width for every bar card
//   padding   spaceS + spaceXs (12) around, and between head, body, footer
//   head      PopupHead: `glyph` in accentText, `title` semibold, an
//             optional `subtitle`, `headActions` on the right
//   body      your content (default property), a Column at the card's
//             inner width, `pad` between children. `scrollable: true`
//             puts it in a Flickable no taller than `maxBodyHeight`
//             (80 % of the screen less the bar, the head, the footer);
//             a ListView body scrolls itself — size it with maxBodyHeight
//   footer    `footer` children, under the body (a switch, Clear all)
//
//   BarPopup { id: pop; owner: "acme.music"; action: "acme.music.toggle"
//              name: "music"; title: "Now playing"; glyph: Theme.icMusic
//              headActions: QsIconButton { ic: Theme.icCog; onGo: … }
//              Text { width: parent.width; text: "…" } }
//   Shell.registerAction("acme.music.toggle", function (a) { pop.toggleAt(a) })
Scope {
    id: bp
    property string name: "popup"          // layer namespace quickshell:<name>
    property string owner: ""              // plugin id (Shell.closePopups spares it)
    property string action: ""             // Shell.isActive(action) follows `open`
    property string title: ""
    property string glyph: ""
    property string subtitle: ""
    property bool scrollable: false
    property bool exclusiveKeyboard: false  // AnchoredPopup's: a card you type into first
    property int implicitWidth: Theme.grow(Theme.panelSm)
    readonly property int pad: Theme.spaceS + Theme.spaceXs
    readonly property alias open: ap.open
    readonly property alias anchor: ap.anchor
    default property alias content: bodyCol.data
    property alias headActions: head.actions
    property alias footer: foot.data
    signal opened()
    signal closed()

    function openAt(a) { ap.openAt(a) }
    function toggleAt(a) { ap.toggleAt(a) }
    function close() { ap.close() }

    // the tallest the body may be: 80 % of the screen (the Quick settings
    // rule) less the bar, the head, the footer and the paddings
    readonly property real _screenH: {
        var s = (ap.anchor && ap.anchor.screen) ? ap.anchor.screen : Shell._focusedScreen()
        return s ? s.height : Theme.panelLg * 2
    }
    readonly property real maxBodyHeight: Math.max(Theme.control2xl,
        bp._screenH * 0.8 - Theme.barHeight - head.height - (foot.visible ? foot.height + bp.pad : 0) - 3 * bp.pad)
    readonly property real _bodyH: bp.scrollable ? Math.min(bodyCol.implicitHeight, bp.maxBodyHeight) : bodyCol.implicitHeight

    AnchoredPopup {
        id: ap
        name: bp.name
        owner: bp.owner
        action: bp.action
        exclusiveKeyboard: bp.exclusiveKeyboard
        implicitWidth: bp.implicitWidth
        implicitHeight: col.implicitHeight + 2 * bp.pad
        onOpened: bp.opened()
        onClosed: bp.closed()

        Column {
            id: col
            x: bp.pad; y: bp.pad
            width: parent.width - 2 * bp.pad
            spacing: bp.pad
            PopupHead {
                id: head
                width: parent.width
                visible: bp.title !== "" || bp.glyph !== ""
                glyph: bp.glyph
                title: bp.title
                subtitle: bp.subtitle
            }
            Flickable {
                id: flick
                width: parent.width
                height: bp._bodyH
                visible: bodyCol.implicitHeight > 0
                interactive: bp.scrollable && bodyCol.implicitHeight > height
                clip: bp.scrollable
                contentWidth: width
                contentHeight: bodyCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: bodyCol
                    width: flick.width
                    spacing: bp.pad
                }
            }
            Item {
                id: foot
                width: parent.width
                visible: children.length > 0
                height: childrenRect.height
            }
        }
    }
}
