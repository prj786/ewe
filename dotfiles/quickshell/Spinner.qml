import QtQuick

// Small rotating progress glyph — the "something is happening" cue used by
// the bar and Quick Settings while a Wi-Fi/VPN connection attempt runs.
Text {
    id: sp
    text: Theme.icRefresh
    font.family: Theme.fontIcons
    font.pixelSize: 13
    color: Theme.accent
    RotationAnimation on rotation {
        running: sp.visible
        from: 0; to: 360
        duration: 900
        loops: Animation.Infinite
    }
}
