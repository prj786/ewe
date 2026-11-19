import QtQuick
import QtQuick.Effects
import qs

// One system-tray icon (StatusNotifierItem image). Apps ship their tray
// icon for a dark panel — flat white glyphs (Nextcloud, GitHub Desktop,
// Steam, Discord…) — so on a light theme they vanish. A Canvas probes the
// pixels once per source: if every opaque pixel is grey (no hue), the icon
// is monochrome and is drawn through a colorization to the bar's own icon
// colour, in both themes — same weight as the Fluent glyphs beside it. A
// coloured icon (1Password, Slack, Telegram) is left exactly as the app
// drew it. Icons are iconLg (iconXl on the large bar) — Theme.barIcon.
Item {
    id: root
    property url source
    property int px: Theme.iconLg
    property color tint: Theme.textSecondary
    // "mono" is decided per source; until the probe returns the icon shows
    // untinted so nothing flashes
    property bool mono: false
    // an item that names no icon still gets a picture: the generic app
    // glyph (app-window, in the bar's icon colour) instead of a blank cell.
    // Quickshell hands an item with an empty IconName and no pixmap its
    // magenta-and-black "missing" checker (image://qspixmap/…), so the probe
    // also recognises that one.
    property bool missing: false
    readonly property bool blank: String(root.source) === "" || root.missing
    readonly property url shown: String(root.source) === "" ? "" : root.source
    width: px; height: px

    Text {
        anchors.centerIn: parent
        visible: root.blank
        text: Theme.icFloating
        font.family: Theme.fontIcons; font.pixelSize: root.px
        color: root.tint
    }
    Image {
        id: img
        anchors.fill: parent
        source: root.shown
        sourceSize.width: 2 * root.px; sourceSize.height: 2 * root.px; mipmap: true
        visible: !root.mono && !root.blank
        onSourceChanged: { root.mono = false; probe.reprobe() }
        onStatusChanged: if (status === Image.Ready) probe.reprobe()
    }
    MultiEffect {
        anchors.fill: parent
        source: img
        visible: root.mono && !root.blank
        colorization: 1.0
        colorizationColor: root.tint
    }
    Canvas {
        id: probe
        width: Theme.iconMd; height: Theme.iconMd   // the sampling grid
        visible: false
        renderStrategy: Canvas.Immediate
        property url loaded
        function reprobe() {
            if (String(root.shown) === "") return
            if (isImageLoaded(root.shown)) { probeIcon(); return }
            unloadImage(loaded); loaded = root.shown; loadImage(root.shown)
        }
        onImageLoaded: probeIcon()
        // A Canvas has no 2D context until its scene graph is up (a headless
        // or not-yet-exposed output hands back null — `getContext`/`clearRect`
        // TypeErrors). Wait for it, then probe; the icon shows untinted
        // meanwhile, which is the safe default.
        onAvailableChanged: if (available) reprobe()
        function probeIcon() {
            if (!available || !isImageLoaded(root.shown)) return
            var ctx = getContext("2d")
            if (!ctx) return
            ctx.clearRect(0, 0, width, height)
            ctx.drawImage(root.shown, 0, 0, width, height)
            var d = ctx.getImageData(0, 0, width, height).data
            var opaque = 0, chroma = 0, magenta = 0
            for (var i = 0; i < d.length; i += 4) {
                if (d[i + 3] < 96) continue
                opaque++
                var r = d[i], g = d[i + 1], b = d[i + 2]
                var spread = Math.max(r, g, b) - Math.min(r, g, b)
                if (spread > 28) chroma++
                if (r > 200 && b > 200 && g < 80) magenta++
            }
            // the "missing" checker is half pure magenta; no real icon is
            root.missing = opaque > 0 && magenta >= opaque * 0.3
            // a few anti-aliased edge pixels may pick up hue; the icon is
            // monochrome when almost nothing in it has one
            root.mono = opaque > 0 && chroma <= Math.max(1, opaque * 0.03)
        }
    }
}
