import QtQuick
import qs

// ewe.safe — Safe's glyph in the bar's Quick settings pill: a lock, open
// while the safe is unlocked, shown once a safe exists on this machine (or
// its daemon is missing, which needs saying). A dot on its corner when
// something wants the user — a sync error, an older copy from the server, a
// master password changed elsewhere, the daemon not running. Its own click
// opens Quick Access instead of Quick settings (the pill's ewe-sync glyph
// does the same for ewe-sync).
BarStatusGlyph {
    id: glyph
    property string pluginId: ""
    property var settings: ({})
    property var screen: null
    property var barWindow: null

    readonly property bool dot: SafeState.attention !== ""
    // the dot hangs off the glyph's corner: reserve its overhang so the next
    // glyph in the pill doesn't run into it (BarIcon's rule)
    width: implicitWidth + (glyph.dot ? Math.max(0, badge.width - Theme.spaceXxs) : 0)
    text: SafeState.unlocked ? Theme.icLockOpen : Theme.icLock
    shown: SafeState.phase === "locked" || SafeState.phase === "unlocked" || SafeState.phase === "down"

    Badge {
        id: badge
        visible: glyph.dot
        dot: true
        tone: SafeState.attention === "danger" ? "danger" : "warning"
        solid: true
        ring: !Theme.glass
        ringColor: Theme.barGround
        x: glyph.font.pixelSize - Theme.spaceXxs
        y: -Theme.borderWidth1
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: Shell.runAction("ewe.safe.toggle", Shell.anchorFor(glyph, glyph.barWindow))
    }
}
