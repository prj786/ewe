import QtQuick

// Slider — THE slider (design system: Slider): a value from a range where
// the position matters more than the number, and the result shows at once.
//
//   md (default)  spaceXs (4) track, iconXs (12) thumb, iconMd icons
//   lg            spaceS (8) track, iconMd (16) thumb, iconLg icons —
//                 the volume and brightness popups
//
//   track  surfaceHover, radiusFull · fill accent · thumb textPrimary
//   hover  a spaceXs surfaceHover halo around the thumb
//   focus  a focusWidth focusRing, focusWidth outside the thumb
//   value  the mono-numeric style in textSecondary, right-aligned in a
//          spaceLg + spaceXs (36) column so it never shifts
//   steps  borderWidth1 × spaceXs ticks in borderStrong under the track,
//          with caption labels
//
// Two call shapes, one file:
//
//     Slider { value: root.volumeVal; live: true; onMoved: v => … }   bare, 0..1
//     Slider { label: "Gaps"; from: 0; to: 30; step: 1; onMoved: … }  labelled
//
// `moved` fires per move only with `live`; otherwise exactly once, on
// release, so handlers that spawn processes (hyprctl, config writes) get one
// call. Arrow keys move by one step, Page Up / Page Down by ten.
Item {
    id: sld
    property string label: ""
    property string icon: ""             // leading icon (low end)
    property string endIcon: ""          // trailing icon (high end)
    property real value: 0
    property real from: 0
    property real to: 1
    property real step: 0                // 0 = continuous
    property int decimals: 0
    property bool live: false
    property bool disabled: false
    property bool showValue: sld.label !== ""
    property string valueText: ""        // overrides the formatted number
    property var ticks: []               // labels under the track; [] = none
    property string size: "md"           // md · lg
    signal moved(real v)

    property real dragVal: 0
    property bool dragging: false
    readonly property real shown: dragging ? dragVal : value
    readonly property real frac: Math.max(0, Math.min(1, (shown - from) / Math.max(0.0001, to - from)))
    readonly property string shownText: sld.valueText !== "" ? sld.valueText
                                                             : Number(sld.shown).toFixed(sld.decimals)

    readonly property bool _lg: sld.size === "lg"
    readonly property int _trackH: sld._lg ? Theme.spaceS : Theme.spaceXs
    readonly property int _thumb: sld._lg ? Theme.iconMd : Theme.iconXs
    readonly property int _iconPx: sld._lg ? Theme.iconLg : Theme.iconMd
    readonly property color _fill: sld.disabled ? Theme.textDisabled : Theme.accent
    readonly property int _step1: sld.step > 0 ? sld.step : (sld.to - sld.from) / 100

    width: parent ? parent.width : Theme.panelSm
    height: (sld.label !== "" ? Theme.controlXl : Theme.controlMd)
            + (sld.ticks.length > 0 ? Theme.spaceMd : 0)

    activeFocusOnTab: !sld.disabled
    function _commit(v) {
        var lo = Math.min(sld.from, sld.to), hi = Math.max(sld.from, sld.to)
        sld.dragVal = Math.max(lo, Math.min(hi, v))
        sld.moved(sld.dragVal)
    }
    Keys.onLeftPressed:  if (!sld.disabled) _commit(sld.shown - sld._step1)
    Keys.onRightPressed: if (!sld.disabled) _commit(sld.shown + sld._step1)
    Keys.onDownPressed:  if (!sld.disabled) _commit(sld.shown - sld._step1)
    Keys.onUpPressed:    if (!sld.disabled) _commit(sld.shown + sld._step1)
    Keys.onPressed: function (e) {
        if (sld.disabled)
            return
        if (e.key === Qt.Key_PageDown) { _commit(sld.shown - 10 * sld._step1); e.accepted = true }
        else if (e.key === Qt.Key_PageUp) { _commit(sld.shown + 10 * sld._step1); e.accepted = true }
    }

    // ── the label row (only with a label) ─────────────────────────────────
    Text {
        id: lbl
        visible: sld.label !== ""
        anchors.left: parent.left; anchors.top: parent.top
        text: sld.label
        color: sld.disabled ? Theme.textDisabled : Theme.textPrimary
        font.family: Theme.type.label.family
        font.pixelSize: Theme.type.label.size
        font.weight: Theme.type.label.weight
    }
    Text {
        visible: sld.showValue && sld.label !== ""
        anchors.right: parent.right; anchors.top: parent.top
        width: Theme.spaceLg + Theme.spaceXs
        horizontalAlignment: Text.AlignRight
        text: sld.shownText
        color: sld.disabled ? Theme.textDisabled : Theme.textSecondary
        font.family: Theme.type.monoNumeric.family
        font.pixelSize: Theme.type.monoNumeric.size
        font.weight: Theme.type.monoNumeric.weight
        font.features: ({ "tnum": 1 })
    }

    // ── icons, track, value ───────────────────────────────────────────────
    Text {
        id: sIco
        visible: sld.icon !== ""
        width: visible ? sld._iconPx : 0
        anchors.left: parent.left; anchors.verticalCenter: trk.verticalCenter
        text: sld.icon; font.family: Theme.fontIcons; font.pixelSize: sld._iconPx
        color: sld.disabled ? Theme.textDisabled : Theme.textSecondary
    }
    Text {
        id: eIco
        visible: sld.endIcon !== ""
        width: visible ? sld._iconPx : 0
        anchors.right: val.visible ? val.left : parent.right
        anchors.rightMargin: visible ? Theme.spaceS : 0
        anchors.verticalCenter: trk.verticalCenter
        text: sld.endIcon; font.family: Theme.fontIcons; font.pixelSize: sld._iconPx
        color: sld.disabled ? Theme.textDisabled : Theme.textSecondary
    }
    Text {
        id: val
        visible: sld.showValue && sld.label === ""
        width: visible ? Theme.spaceLg + Theme.spaceXs : 0
        horizontalAlignment: Text.AlignRight
        anchors.right: parent.right; anchors.verticalCenter: trk.verticalCenter
        text: sld.shownText
        color: sld.disabled ? Theme.textDisabled : Theme.textSecondary
        font.family: Theme.type.monoNumeric.family
        font.pixelSize: Theme.type.monoNumeric.size
        font.weight: Theme.type.monoNumeric.weight
        font.features: ({ "tnum": 1 })
    }
    Rectangle {
        id: trk
        anchors.left: sIco.right; anchors.leftMargin: sld.icon !== "" ? Theme.spaceS : 0
        anchors.right: eIco.visible ? eIco.left : (val.visible ? val.left : parent.right)
        anchors.rightMargin: (eIco.visible || val.visible) ? Theme.spaceS : 0
        // labelled: the track sits under the label row; bare: centred
        y: sld.label !== "" ? Theme.controlXl - Theme.spaceXs - height
                            : Math.round((Theme.controlMd - height) / 2)
        height: sld._trackH
        radius: Theme.radiusFull
        color: Theme.surfaceHover

        Rectangle {
            height: parent.height; radius: Theme.radiusFull
            width: parent.width * sld.frac
            color: sld._fill
        }
        // hover halo — a spaceXs ring of surfaceHover behind the thumb
        Rectangle {
            visible: (tMa.containsMouse || sld.dragging) && !sld.disabled
            width: sld._thumb + 2 * Theme.spaceXs; height: width
            radius: Theme.radiusFull
            color: Theme.surfaceHover
            anchors.verticalCenter: parent.verticalCenter
            x: knob.x + (knob.width - width) / 2
        }
        Rectangle {
            id: knob
            width: sld._thumb; height: sld._thumb
            radius: Theme.radiusFull
            color: sld.disabled ? Theme.textDisabled : Theme.textPrimary
            antialiasing: true
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(trk.width - width, trk.width * sld.frac - width / 2))
            // the focus ring rides focusWidth outside the thumb
            Rectangle {
                anchors.fill: parent
                anchors.margins: -Theme.focusWidth * 2
                radius: Theme.radiusFull
                color: "transparent"
                visible: sld.activeFocus
                border.color: Theme.focusRing
                border.width: Theme.focusWidth
                antialiasing: true
            }
        }
        // the steps, under the track
        Repeater {
            model: sld.ticks.length
            delegate: Rectangle {
                required property int index
                width: Theme.borderWidth1; height: Theme.spaceXs
                color: Theme.borderStrong
                y: trk.height + Theme.spaceXs
                x: sld.ticks.length > 1
                   ? Math.round(index * (trk.width - width) / (sld.ticks.length - 1)) : 0
            }
        }
        MouseArea {
            id: tMa
            anchors.fill: parent
            anchors.topMargin: -Theme.spaceS - Theme.spaceXs
            anchors.bottomMargin: -Theme.spaceS - Theme.spaceXs
            enabled: !sld.disabled
            hoverEnabled: true
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
    // the step labels, under the ticks
    Repeater {
        model: sld.ticks.length > 0 ? sld.ticks : []
        delegate: Text {
            required property int index
            required property var modelData
            text: String(modelData)
            color: Theme.textMuted
            font.family: Theme.type.caption.family
            font.pixelSize: Theme.type.caption.size
            y: trk.y + trk.height + Theme.spaceS
            x: Math.max(0, Math.min(sld.width - width,
                        trk.x + (sld.ticks.length > 1
                                 ? index * trk.width / (sld.ticks.length - 1) : 0) - width / 2))
        }
    }
}
