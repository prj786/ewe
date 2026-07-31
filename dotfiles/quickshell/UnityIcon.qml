import QtQuick

// UnityIcon — Unity 7 panel indicators, drawn rather than fetched.
//
// Unity's panel used ubuntu-mono-dark: flat, monochrome, thin-stroke glyphs in a
// single warm off-white — never coloured, never filled, no shadows. That icon
// theme is NOT packaged for Arch (only the Ubuntu fonts are, and the AUR has no
// ubuntu-mono icon set), so depending on it would leave most users with missing
// icons. These are drawn to the same rules instead: 1.5px strokes, no fills, no
// gradients.
//
// Used only under the Ambiance look. Graphite keeps the Nerd Font glyphs, so the
// two themes stay visually coherent with themselves.
//
// A Canvas paints once and only repaints when a property changes — nothing here
// animates, so it costs nothing at idle and does not defeat panel self-refresh.
Canvas {
    id: ic

    property string kind: ""              // wired | wifi | vpn | bluetooth
    property color tint: Theme.fgSecondary
    property int level: 3                 // wifi arcs lit, 0..3

    implicitWidth: 16
    implicitHeight: 16
    antialiasing: true

    onTintChanged: requestPaint()
    onKindChanged: requestPaint()
    onLevelChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()

    onPaint: {
        var c = getContext("2d")
        c.reset()
        c.clearRect(0, 0, width, height)
        c.strokeStyle = ic.tint
        c.fillStyle = ic.tint
        c.lineWidth = 1.5
        c.lineCap = "round"
        c.lineJoin = "round"
        if (ic.kind === "wifi") ic._wifi(c, width, height)
        else if (ic.kind === "wired") ic._wired(c, width, height)
        else if (ic.kind === "vpn") ic._vpn(c, width, height)
        else if (ic.kind === "bluetooth") ic._bluetooth(c, width, height)
    }

    // Concentric arcs over a dot — Unity's nm-signal-*. Unlit arcs are still
    // drawn, just faint, so the icon keeps its silhouette at low signal instead
    // of visibly changing size as the strength moves.
    function _wifi(c, w, h) {
        var cx = w / 2, cy = h * 0.80
        c.beginPath(); c.arc(cx, cy, 1.15, 0, Math.PI * 2); c.fill()
        for (var i = 0; i < 3; i++) {
            c.globalAlpha = (i < ic.level) ? 1.0 : 0.26
            c.beginPath()
            c.arc(cx, cy, 3.1 + i * 2.5, Math.PI * 1.25, Math.PI * 1.75)
            c.stroke()
        }
        c.globalAlpha = 1.0
    }

    // Two opposed arrows: the transmit/receive pair Unity showed for a wired
    // link. This is the one people remember as "the arrows".
    function _wired(c, w, h) {
        var y1 = h * 0.34, y2 = h * 0.66
        var x0 = w * 0.16, x1 = w * 0.84, head = 3.0, rise = 2.5
        c.beginPath(); c.moveTo(x0, y1); c.lineTo(x1, y1); c.stroke()
        c.beginPath()
        c.moveTo(x1 - head, y1 - rise); c.lineTo(x1, y1); c.lineTo(x1 - head, y1 + rise)
        c.stroke()
        c.beginPath(); c.moveTo(x1, y2); c.lineTo(x0, y2); c.stroke()
        c.beginPath()
        c.moveTo(x0 + head, y2 - rise); c.lineTo(x0, y2); c.lineTo(x0 + head, y2 + rise)
        c.stroke()
    }

    // Padlock — Unity badged the network area with one while a VPN was up.
    function _vpn(c, w, h) {
        var bw = w * 0.60, bh = h * 0.40
        var bx = (w - bw) / 2, by = h * 0.52
        c.beginPath(); c.rect(bx, by, bw, bh); c.stroke()
        c.beginPath(); c.arc(w / 2, by, bw * 0.34, Math.PI, 0); c.stroke()
    }

    // The ᛒ rune, stroked rather than filled.
    function _bluetooth(c, w, h) {
        var cx = w * 0.46, top = h * 0.14, bot = h * 0.86
        var dx = w * 0.24, q1 = h * 0.34, q3 = h * 0.66
        c.beginPath()
        c.moveTo(cx - dx, q1)
        c.lineTo(cx + dx, q3)
        c.lineTo(cx, bot)
        c.lineTo(cx, top)
        c.lineTo(cx + dx, q1)
        c.lineTo(cx - dx, q3)
        c.stroke()
    }
}
