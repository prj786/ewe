import QtQuick

// InvertedCorner — a small concave ("reverse-rounded") fillet that joins a
// dropdown's top corner up to the bar, so the panel looks like it flares out of
// the topbar. Place to the LEFT of a panel's top-left corner (right:false) or to
// the RIGHT of its top-right corner (right:true), flush with the bar's bottom.
Canvas {
    id: c
    property color fillColor: Theme.bg3
    property bool rightSide: false
    property int r: 12
    width: r
    height: r

    onFillColorChanged: requestPaint()
    onRightSideChanged: requestPaint()
    onRChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.fillStyle = c.fillColor
        ctx.beginPath()
        if (!c.rightSide) {
            // top-left fillet: filled along the top (bar) + right (panel) edges,
            // concave arc scooped out of the bottom-left.
            ctx.moveTo(width, 0)
            ctx.lineTo(0, 0)
            ctx.arc(width, 0, width, Math.PI, Math.PI / 2, false)
        } else {
            // top-right fillet: top (bar) + left (panel) edges, concave bottom-right.
            ctx.moveTo(0, 0)
            ctx.lineTo(width, 0)
            ctx.arc(0, 0, width, 0, Math.PI / 2, false)
        }
        ctx.closePath()
        ctx.fill()
    }
}
