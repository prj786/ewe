import QtQuick
import qs

// Spark — the last minute as a sparkline: `keyA` in the accent with an
// accentSubtle area under it, `keyB` (optional) as a textMuted line over it
// — download and upload. The x axis is real time: the newest sample sits on
// the right edge and a sample `span` ms older on the left, so a pause in
// sampling shows as a gap, never as a line drawn across it. A value below 0
// is "no reading" and breaks the line. `max` is the top of the scale. With
// nothing to plot (the first tick, offline) it draws a borderSubtle baseline.
//
// The stroke is half-way between borderWidth1 and borderWidth2 (the
// mockup's 1.5), drawn inside the box so nothing clips.
Canvas {
    id: sp
    property var samples: []
    property string keyA: ""
    property string keyB: ""
    property real max: 1
    property int span: 60000
    property color lineA: Theme.accent
    property color areaA: Theme.accentSubtle
    property color lineB: Theme.textMuted
    property color base: Theme.borderSubtle
    readonly property real stroke: (Theme.borderWidth1 + Theme.borderWidth2) / 2

    implicitHeight: Theme.controlLg
    onSamplesChanged: requestPaint()
    onMaxChanged: requestPaint()
    onLineAChanged: requestPaint()
    onAreaAChanged: requestPaint()
    onLineBChanged: requestPaint()
    onBaseChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    // runs of consecutive readings: [[{x, y}, …], …]
    function runs(key) {
        var s = sp.samples || [], out = [], cur = []
        if (s.length === 0 || key === "") return out
        var tEnd = s[s.length - 1].t, top = Math.max(sp.max, 1e-9)
        var h = sp.height - sp.stroke
        for (var i = 0; i < s.length; i++) {
            var v = s[i][key]
            if (typeof v !== "number" || v < 0) { if (cur.length > 1) out.push(cur); cur = []; continue }
            cur.push({ x: sp.width - (tEnd - s[i].t) / sp.span * sp.width,
                       y: sp.stroke / 2 + h - Math.min(1, v / top) * h })
        }
        if (cur.length > 1) out.push(cur)
        return out
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.lineWidth = sp.stroke
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        var a = sp.runs(sp.keyA), b = sp.runs(sp.keyB), r, i
        // nothing to plot: the chart reads as empty rather than missing
        if (a.length === 0 && b.length === 0) {
            ctx.beginPath()
            ctx.moveTo(0, sp.height - sp.stroke / 2)
            ctx.lineTo(sp.width, sp.height - sp.stroke / 2)
            ctx.strokeStyle = sp.base
            ctx.stroke()
            return
        }
        for (r = 0; r < a.length; r++) {
            var run = a[r]
            ctx.beginPath()
            ctx.moveTo(run[0].x, sp.height)
            for (i = 0; i < run.length; i++) ctx.lineTo(run[i].x, run[i].y)
            ctx.lineTo(run[run.length - 1].x, sp.height)
            ctx.closePath()
            ctx.fillStyle = sp.areaA
            ctx.fill()
        }
        function line(runsOf, colour) {
            for (var q = 0; q < runsOf.length; q++) {
                var rn = runsOf[q]
                ctx.beginPath()
                ctx.moveTo(rn[0].x, rn[0].y)
                for (var k = 1; k < rn.length; k++) ctx.lineTo(rn[k].x, rn[k].y)
                ctx.strokeStyle = colour
                ctx.stroke()
            }
        }
        line(b, sp.lineB)
        line(a, sp.lineA)
    }
}
