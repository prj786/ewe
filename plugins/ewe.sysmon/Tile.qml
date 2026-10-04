import QtQuick
import qs

// ewe.sysmon — the CPU and memory meters on the Quick settings home grid
// (quickTile.span 2: the whole row). The card the shell drew for them: a
// surfaceOverlay well with a borderSubtle outline and radiusRounded corners,
// two Meters inside. Samples only while this tile is on screen (`panelOpen`).
Rectangle {
    id: root
    property string pluginId: ""
    property var settings: ({})
    property bool panelOpen: false
    readonly property int pad: Theme.spaceS + Theme.spaceXs

    implicitHeight: col.implicitHeight + 2 * root.pad
    radius: Theme.radiusRounded
    color: Theme.surfaceOverlay
    border.color: Theme.borderSubtle; border.width: Theme.borderWidth1

    onPanelOpenChanged: SysMon.hold(root, root.panelOpen)
    Component.onCompleted: SysMon.hold(root, root.panelOpen)
    Component.onDestruction: SysMon.hold(root, false)

    Column {
        id: col
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: root.pad
        spacing: Theme.spaceS + Theme.spaceXs
        Meter { label: "CPU"; glyph: Theme.icCpu; value: SysMon.cpuUsage }
        Meter { label: "Memory"; glyph: Theme.icMemory; value: SysMon.memUsage }
    }
}
