import QtQuick
import qs

// ewe.sysmon — the same numbers as a desktop widget (API 3
// `desktop-widget`). ewe draws the Glass card around it (glassRaised,
// glassBorder, radiusRounded, spaceS + spaceXs by spaceMd of padding) and
// owns the rest: where it sits, pinned or on the desktop, locked, shown —
// the hover toolbar's pin and grip, arrange mode (Super+Shift+W), Komble.
// Off until the user turns it on: the card's Show on desktop switch or
// Komble's Show on the desktop (both are `ewe-plugin place ewe.sysmon
// --visible on`), so the host only loads this while it is shown — and
// that is exactly when it samples.
//
//   head      the activity glyph in accentText + "System monitor" (overline)
//   CPU | Memory   two columns: the figure; a sparkline | a Level + "of 15.5 GB"
//   hairline
//   Internet  "Internet · Wi-Fi", ↓ download and ↑ upload, their sparklines
Item {
    id: w
    property string pluginId: ""
    property var settings: ({})
    readonly property bool inBits: SysMon.bits(w.settings)

    // a little under the card's panelSm, so it reads as a widget, not a panel
    implicitWidth: Theme.grow(Theme.panelSm) - Theme.spaceXl - 2 * Theme.spaceMd
    implicitHeight: col.implicitHeight

    Component.onCompleted: { SysMon.hold(w, true); SysMon.settleDefault() }
    Component.onDestruction: SysMon.hold(w, false)

    component Speed: Row {
        id: spd
        property string glyph: ""
        property color glyphColor: Theme.textMuted
        property real bps: -1
        readonly property var parts: SysMon.speedParts(spd.bps, w.inBits)
        spacing: Theme.spaceXs
        Glyph { anchors.verticalCenter: parent.verticalCenter; text: spd.glyph; color: spd.glyphColor; font.pixelSize: Theme.iconSm }
        Big { id: sbig; text: spd.parts[0] }
        Text {
            anchors.baseline: sbig.baseline
            visible: text !== ""
            text: spd.parts[1]
            color: Theme.textSecondary
            font.family: Theme.type.label.family
            font.pixelSize: Theme.fontSizeS
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: Theme.spaceS + Theme.spaceXs

        Row {
            spacing: Theme.spaceXs + Theme.spaceXxs
            Glyph { anchors.verticalCenter: parent.verticalCenter; text: SysMon.icActivity; color: Theme.accentText; font.pixelSize: Theme.iconSm }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "System monitor"
                color: Theme.textMuted
                font.family: Theme.type.overline.family
                font.pixelSize: Theme.type.overline.size
                font.weight: Theme.type.overline.weight
                font.letterSpacing: Theme.type.overline.letterSpacing
            }
        }

        Row {
            width: parent.width
            spacing: Theme.spaceS + Theme.spaceXs
            readonly property real colW: (width - spacing) / 2
            Column {
                width: parent.colW
                spacing: Theme.spaceXs
                TextCaption { text: "CPU" }
                Big { text: SysMon.cpuText }
                Spark {
                    width: parent.width
                    height: Theme.controlSm
                    samples: SysMon.history
                    keyA: "cpu"
                    max: 1
                    span: SysMon.windowMs
                }
            }
            Column {
                width: parent.colW
                spacing: Theme.spaceXs
                TextCaption { text: "Memory" }
                Big { text: SysMon.memUsedText }
                Item { width: parent.width; height: Theme.spaceXs }
                Level { width: parent.width; value: SysMon.memUsage }
                TextCaption { width: parent.width; text: SysMon.memTotalText }
            }
        }

        Rectangle { width: parent.width; height: Theme.borderWidth1; color: Theme.borderSubtle }

        Column {
            width: parent.width
            spacing: Theme.spaceXs
            TextCaption { width: parent.width; text: SysMon.netKnown ? "Internet · " + SysMon.kindText : "Internet" }
            Row {
                spacing: Theme.spaceMd
                Speed { glyph: SysMon.icDown; glyphColor: Theme.accentText; bps: SysMon.down }
                Speed { glyph: SysMon.icUp; glyphColor: Theme.textMuted; bps: SysMon.up }
            }
            Spark {
                width: parent.width
                height: Theme.controlSm
                samples: SysMon.history
                keyA: "down"
                keyB: "up"
                max: SysMon.netPeak
                span: SysMon.windowMs
            }
        }
    }
}
