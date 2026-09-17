import QtQuick

// Spinner — "something is happening, and we don't know for how long"
// (design system: Spinner). A ring with a borderWidth2 stroke: the track is
// borderSubtle and a quarter arc in the tone colour turns once every 800 ms
// at a steady speed.
//
//   size   iconSm (14) · iconMd (16, default) · iconLg (20) · iconXl (24) ·
//          icon2xl (32)
//   tone   "accent" (default) · "neutral" (textSecondary, inside secondary
//          and ghost buttons) · "on-accent" (on a filled accent control)
//
// Reduce motion turns it three times slower rather than stopping it, so the
// busy state stays visible (the card's rule).
//
// The older API still works, because the shell and the plugins call it that
// way: `font.pixelSize` sizes the ring (it wins over `size`), `color` tints
// the arc (it wins over `tone`), and `ring` / `dot` name the track and the
// arc directly — AppStore draws a spinner on an accent fill with them.
Item {
    id: sp
    property int size: Theme.iconMd
    property string tone: "accent"
    property font font                       // compatibility: font.pixelSize
    property color color: sp.tone === "neutral" ? Theme.textSecondary
                        : sp.tone === "on-accent" ? Theme.onAccent : Theme.accent
    property color ring: sp.tone === "on-accent" ? Theme.withAlpha(Theme.onAccent, 0.2)
                                                 : Theme.borderSubtle
    property color dot: sp.color             // the arc; `color` feeds it

    readonly property int diameter: sp.font.pixelSize > 0 ? sp.font.pixelSize : sp.size
    readonly property int stroke: Theme.borderWidth2
    // The card's own period. The motion table has no spin period, so this is
    // the one duration that does not come from Theme — reported as a gap.
    readonly property int _period: Theme.reduceMotion ? 2400 : 800

    implicitWidth: diameter; implicitHeight: diameter
    width: diameter; height: diameter

    // the track: a full ring under the arc
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.color: sp.ring
        border.width: sp.stroke
        antialiasing: true
    }
    Canvas {
        id: arc
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var r = (width - sp.stroke) / 2
            if (r <= 0)
                return
            ctx.lineWidth = sp.stroke
            ctx.strokeStyle = sp.dot
            ctx.beginPath()
            // a quarter, starting at the top and running clockwise
            ctx.arc(width / 2, height / 2, r, -Math.PI / 2, 0, false)
            ctx.stroke()
        }
        onWidthChanged: requestPaint()
        Connections { target: sp; function onDotChanged() { arc.requestPaint() } }
        RotationAnimation on rotation {
            running: sp.visible
            from: 0; to: 360
            duration: sp._period
            loops: Animation.Infinite
        }
    }
}
