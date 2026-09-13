import QtQuick

// Slider — THE slider (spec: 26 px tall, 8 px track r4 on bg2, accent fill,
// 14 px knob in fgOnBrand). Two call shapes, one file:
//
//     Slider { value: root.volumeVal; live: true; onMoved: v => ... }   bare, 0..1
//     Slider { label: "Gaps"; from: 0; to: 30; step: 1; onMoved: ... }  labelled, 40 tall
//
// With a label the value reads in the accent at 700 with tabular figures —
// the one place a number is coloured. `moved` fires per move only with
// `live`; otherwise exactly once, on release, so handlers that spawn
// processes (hyprctl, config writes) get one call.
Item {
    id: sld
    property string label: ""
    property string icon: ""
    property real value: 0
    property real from: 0
    property real to: 1
    property real step: 0            // 0 = continuous
    property int decimals: 0
    property bool live: false
    signal moved(real v)

    property real dragVal: 0
    property bool dragging: false
    readonly property real shown: dragging ? dragVal : value
    readonly property real frac: Math.max(0, Math.min(1, (shown - from) / Math.max(0.0001, to - from)))

    width: parent ? parent.width : 200
    height: sld.label !== "" ? 40 : 26

    Text {
        visible: sld.label !== ""
        anchors.left: parent.left; anchors.top: parent.top
        text: sld.label; color: Theme.fg1
        font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
    }
    Text {
        visible: sld.label !== ""
        anchors.right: parent.right; anchors.top: parent.top
        text: Number(sld.shown).toFixed(sld.decimals)
        color: Theme.accent
        font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.Bold
        font.features: ({ "tnum": 1 })
    }
    Text {
        id: sIco
        visible: sld.icon !== ""
        width: visible ? 20 : 0
        anchors.left: parent.left; anchors.verticalCenter: trk.verticalCenter
        text: sld.icon; font.family: Theme.fontIcons; font.pixelSize: 14; color: Theme.fg3
    }
    Rectangle {
        id: trk
        anchors.left: sIco.right; anchors.leftMargin: sld.icon !== "" ? 8 : 0
        anchors.right: parent.right
        // labelled: the track sits under the label row; bare: centred
        y: sld.label !== "" ? sld.height - 4 - height : Math.round((sld.height - height) / 2)
        height: 8; radius: 4; color: Theme.bg2
        Rectangle { height: parent.height; radius: 4; width: parent.width * sld.frac; color: Theme.accent }
        Rectangle {
            width: 14; height: 14; radius: 7; color: Theme.fgOnBrand
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(trk.width - width, trk.width * sld.frac - width / 2))
        }
        MouseArea {
            anchors.fill: parent; anchors.topMargin: -9; anchors.bottomMargin: -9
            function pick(mx) {
                var f = Math.max(0, Math.min(1, mx / trk.width))
                var v = sld.from + f * (sld.to - sld.from)
                if (sld.step > 0) v = Math.round(v / sld.step) * sld.step
                var lo = Math.min(sld.from, sld.to), hi = Math.max(sld.from, sld.to)
                return Math.max(lo, Math.min(hi, v))
            }
            onPressed: function (m) { sld.dragging = true; sld.dragVal = pick(m.x); if (sld.live) sld.moved(sld.dragVal) }
            onPositionChanged: function (m) { if (!pressed) return; sld.dragVal = pick(m.x); if (sld.live) sld.moved(sld.dragVal) }
            onReleased: { sld.dragging = false; if (!sld.live) sld.moved(sld.dragVal) }
        }
    }
}
