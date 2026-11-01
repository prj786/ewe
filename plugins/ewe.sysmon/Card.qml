import QtQuick
import QtQuick.Layouts
import qs

// Card — what the bar readout opens (Panel.qml puts it in an AnchoredPopup):
//
//   head      the activity glyph in accentText, "System monitor" semibold,
//             the options cog (Komble → Plugins) on the right
//   CPU       a well: the figure, the last minute as a sparkline, "8 cores ·
//             last 60 seconds"
//   Memory    a well: "6.1 GB of 15.5 GB", a Level, "39% in use · swap empty"
//   Internet  a well: the link it uses ("Wi-Fi · home-5G", "Ethernet",
//             "Offline"), ↓ download (accent) and ↑ upload (muted), their
//             sparklines
//   switch    Show on desktop — the host's widget visibility, the same switch
//             as Komble's Show on the desktop
//
// Wells are spaceS + spaceXs (12) apart, like the card's padding.
Column {
    id: card
    property bool inBits: false
    signal options()

    spacing: Theme.spaceS + Theme.spaceXs

    // a section's label: an iconSm glyph and the small text in textSecondary
    component Label: Row {
        property alias glyph: lg.text
        property alias text: lt.text
        spacing: Theme.spaceXs + Theme.spaceXxs
        Glyph { id: lg; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Theme.iconSm }
        Text {
            id: lt
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.textSecondary
            font.family: Theme.type.label.family
            font.pixelSize: Theme.fontSizeS
        }
    }
    // one speed: the arrow, the figure, its unit; the caption under it
    component Speed: Column {
        id: spd
        property string glyph: ""
        property color glyphColor: Theme.textMuted
        property real bps: -1
        property string caption: ""
        readonly property var parts: SysMon.speedParts(spd.bps, card.inBits)
        Row {
            spacing: Theme.spaceXs
            Glyph { anchors.verticalCenter: parent.verticalCenter; text: spd.glyph; color: spd.glyphColor }
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
        TextCaption { text: spd.caption }
    }

    // ── head ──
    RowLayout {
        width: parent.width
        spacing: Theme.spaceS
        Glyph { text: SysMon.icActivity; color: Theme.accentText; Layout.alignment: Qt.AlignVCenter }
        TextStrong {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: "System monitor"
            font.weight: Theme.fontWeightSemibold
        }
        QsIconButton {
            Layout.alignment: Qt.AlignVCenter
            ic: Theme.icCog
            Accessible.name: "System monitor options"
            onGo: card.options()
        }
    }

    // ── CPU ──
    Well {
        width: parent.width
        RowLayout {
            width: parent.width
            spacing: Theme.spaceS
            Label { glyph: Theme.icCpu; text: "CPU"; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
            Big { text: SysMon.cpuText; Layout.alignment: Qt.AlignVCenter }
        }
        Spark {
            width: parent.width
            height: Theme.controlLg
            samples: SysMon.history
            keyA: "cpu"
            max: 1
            span: SysMon.windowMs
        }
        TextCaption { width: parent.width; text: SysMon.cpuCaption }
    }

    // ── Memory ──
    Well {
        width: parent.width
        RowLayout {
            width: parent.width
            spacing: Theme.spaceS
            Label { glyph: Theme.icMemory; text: "Memory"; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
            Big { text: SysMon.memUsedText; Layout.alignment: Qt.AlignVCenter }
            TextCaption { text: SysMon.memTotalText; visible: text !== ""; Layout.alignment: Qt.AlignVCenter }
        }
        Level { width: parent.width; value: SysMon.memUsage }
        TextCaption { width: parent.width; text: SysMon.memCaption }
    }

    // ── Internet ──
    Well {
        width: parent.width
        RowLayout {
            width: parent.width
            spacing: Theme.spaceS
            Label { glyph: Theme.icWeb; text: "Internet"; Layout.alignment: Qt.AlignVCenter }
            TextCaption {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignRight
                text: SysMon.linkText
            }
        }
        Row {
            width: parent.width
            spacing: Theme.spaceS
            Speed { width: (parent.width - parent.spacing) / 2; glyph: SysMon.icDown; glyphColor: Theme.accentText; bps: SysMon.down; caption: "Download" }
            Speed { width: (parent.width - parent.spacing) / 2; glyph: SysMon.icUp; glyphColor: Theme.textMuted; bps: SysMon.up; caption: "Upload" }
        }
        Spark {
            width: parent.width
            height: Theme.controlLg
            samples: SysMon.history
            keyA: "down"
            keyB: "up"
            max: SysMon.netPeak
            span: SysMon.windowMs
        }
    }

    // ── on the desktop ──
    QsSwitchRow {
        width: parent.width
        label: "Show on desktop"
        desc: "The same card as a widget you can place anywhere"
        on: SysMon.widgetShown
        onToggled: SysMon.setWidgetShown(!SysMon.widgetShown)
    }
}
