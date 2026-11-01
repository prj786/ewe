import QtQuick
import qs

// ewe.sysmon — the readout in the top bar: CPU · memory · download as three
// glyph + figure pairs in one bar module ("7%  39%  1.2 MB/s"); the setting
// `bar_shows` keeps CPU + memory, or only the speed (then ↓ and ↑). Shown by
// default (`barWidget.defaultShown: true`) — Show in bar is the host's
// switch (Komble → Plugins → System monitor; `ewe-plugin bar ewe.sysmon
// on|off`), so the host loads this only while it is on. A click opens the
// card (Panel.qml) under it on this very screen.
//
// Figures are mono with tabular digits at the clock's size (fontSizeMd,
// fontSizeLg on the large bar), and each takes the width of its widest form
// ("00%", "000 KB/s"), so the bar does not shuffle on every tick.
Item {
    id: root
    property string pluginId: ""
    property var settings: ({})
    property var screen: null
    property var barWindow: null

    readonly property string shows: root.settings && typeof root.settings.bar_shows === "string" ? root.settings.bar_shows : "All three"
    readonly property bool showLoad: root.shows !== "Speed"
    readonly property bool showSpeed: root.shows !== "CPU + memory"
    readonly property bool speedOnly: root.shows === "Speed"
    readonly property bool inBits: SysMon.bits(root.settings)
    // sample while this bar is up (Super+Shift+B hides it)
    readonly property bool barUp: !root.barWindow || root.barWindow.visible !== false

    implicitWidth: mod.implicitWidth
    implicitHeight: mod.implicitHeight

    onBarUpChanged: SysMon.hold(root, root.barUp)
    Component.onCompleted: { SysMon.hold(root, root.barUp); SysMon.addBar(root, mod, root.barWindow) }
    onBarWindowChanged: SysMon.addBar(root, mod, root.barWindow)
    Component.onDestruction: { SysMon.hold(root, false); SysMon.removeBar(root) }

    readonly property int figPx: Theme.barLarge ? Theme.fontSizeLg : Theme.fontSizeMd
    readonly property int glyphPx: Theme.barLarge ? Theme.iconLg : Theme.iconMd
    TextMetrics { id: pctW; font.family: Theme.type.mono.family; font.pixelSize: root.figPx; text: "00%" }
    TextMetrics { id: spdW; font.family: Theme.type.mono.family; font.pixelSize: root.figPx; text: root.inBits ? "000 kbit/s" : "000 KB/s" }

    // one glyph + figure pair
    component Pair: Row {
        id: pr
        property string glyph: ""
        property string value: ""
        property real minW: 0
        spacing: Theme.spaceXs + Theme.spaceXxs
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pr.glyph
            color: mod.ink
            font.family: Theme.fontIcons
            font.pixelSize: root.glyphPx
            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(pr.minW, implicitWidth)
            text: pr.value
            color: mod.ink
            font.family: Theme.type.mono.family
            font.pixelSize: root.figPx
            font.features: ({ "tnum": 1 })
            Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
        }
    }

    BarModule {
        id: mod
        anchors.centerIn: parent
        active: Shell.isActive("ewe.sysmon.toggle")
        readonly property color ink: mod.hovered || mod.active ? Theme.textPrimary : Theme.textSecondary
        a11yName: "System monitor — "
                  + [root.showLoad ? "CPU " + SysMon.cpuText + ", memory " + SysMon.memText : "",
                     root.showSpeed ? "download " + SysMon.speedText(SysMon.down, root.inBits) : "",
                     root.speedOnly ? "upload " + SysMon.speedText(SysMon.up, root.inBits) : ""]
                    .filter(function (s) { return s !== "" }).join(", ")
        onActivated: Shell.runAction("ewe.sysmon.toggle", Shell.anchorFor(mod, root.barWindow))

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spaceS + Theme.spaceXxs
            Pair { visible: root.showLoad; glyph: Theme.icCpu; value: SysMon.cpuText; minW: pctW.width }
            Pair { visible: root.showLoad; glyph: Theme.icMemory; value: SysMon.memText; minW: pctW.width }
            Pair { visible: root.showSpeed; glyph: SysMon.icDown; value: SysMon.speedText(SysMon.down, root.inBits); minW: spdW.width }
            Pair { visible: root.speedOnly; glyph: SysMon.icUp; value: SysMon.speedText(SysMon.up, root.inBits); minW: spdW.width }
        }
    }
}
