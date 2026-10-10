import QtQuick
import qs

// ewe.sysmon — the compact readout in the top bar: "cpu 12%  mem 48%" as
// two glyphs with mono-numeric figures, one bar module. Opt-in: the
// manifest says `defaultShown: false`, so the host loads it only once Show in
// bar is on (Komble → Plugins → System monitor → Options; `ewe-plugin bar
// ewe.sysmon on`) — a bar widget polls for the whole session. A click opens
// Quick settings, where the full meters live. (1.0's own `show_in_bar`
// setting is gone; a value it stored still counts as the Show in bar state.)
Item {
    id: root
    property string pluginId: ""
    property var settings: ({})
    property var screen: null
    property var barWindow: null
    readonly property bool on: !(root.settings && root.settings.show_in_bar === false)

    implicitWidth: root.on ? mod.implicitWidth : 0
    implicitHeight: root.on ? mod.implicitHeight : 0
    visible: root.on

    onOnChanged: SysMon.hold(root, root.on)
    Component.onCompleted: SysMon.hold(root, root.on)
    Component.onDestruction: SysMon.hold(root, false)

    BarModule {
        id: mod
        anchors.centerIn: parent
        a11yName: "System monitor, CPU " + SysMon.cpuPct + "%, memory " + SysMon.memPct + "%"
        onActivated: Shell.openQuickSettings("home")
        readonly property color ink: mod.hovered ? Theme.textPrimary : Theme.textSecondary
        Glyph { anchors.verticalCenter: parent.verticalCenter; text: Theme.icCpu; font.pixelSize: Theme.barIcon; color: mod.ink }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: SysMon.cpuPct + "%"
            color: mod.ink
            font.family: Theme.type.label.family
            font.pixelSize: Theme.barLarge ? Theme.fontSizeMd : Theme.fontSizeS
            font.features: ({ "tnum": 1 })
        }
        Glyph { anchors.verticalCenter: parent.verticalCenter; text: Theme.icMemory; font.pixelSize: Theme.barIcon; color: mod.ink }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: SysMon.memPct + "%"
            color: mod.ink
            font.family: Theme.type.label.family
            font.pixelSize: Theme.barLarge ? Theme.fontSizeMd : Theme.fontSizeS
            font.features: ({ "tnum": 1 })
        }
    }
}
