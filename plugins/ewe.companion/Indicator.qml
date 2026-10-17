import QtQuick
import qs

// Indicator — the notch's one line (the owner, 2026-10-14: agent state,
// waiting count, live activity, Claude plan usage).
//
//   compact  ● Working  Claude · Edit Bar.qml             5h ▮▮▯  wk ▮▯▯
//   open     ● Working  2                         5h ▮▮▯ 42%  wk ▮▯▯ 13%
//
// It fills the width the notch gives it and never asks for more: the notch
// is one fixed size, and the line elides inside it (the owner, 2026-10-14:
// "it should be always same size"). Nothing here follows the pointer.
//
// The dot takes the state colour, and the word says the same thing, so
// colour is never the only signal. A peek (a finished agent, a command's
// result) takes the word's place for a few seconds.
Item {
    id: ind
    property var settings: ({})
    // open, the Agents section shows the activity: the line keeps to state,
    // count and usage
    property bool open: false

    readonly property var peek: CompanionState.peek
    readonly property var lead: CompanionState.lead
    readonly property string mood: !CompanionState.connected ? "off"
                                  : CompanionState.asking > 0 || (ind.lead && ind.lead.state === "waiting") ? "waiting"
                                  : ind.lead && ind.lead.state === "working" ? "working"
                                  : CompanionState.thinking ? "thinking"
                                  : CompanionState.presence === "error" ? "error"
                                  : CompanionState.gameMode ? "game"
                                  : "idle"
    readonly property string word: ind.peek ? ind.peek.line
                                  : ind.mood === "off" ? "Shaun is off"
                                  : ind.mood === "waiting" ? "Needs you"
                                  : ind.mood === "working" ? "Working"
                                  : ind.mood === "thinking" ? "Thinking"
                                  : ind.mood === "error" ? "Stopped"
                                  : ind.mood === "game" ? "Game mode"
                                  : "Shaun"
    readonly property color ink: ind.peek ? (ind.peek.level === "success" ? Theme.success
                                           : ind.peek.level === "danger" ? Theme.danger
                                           : ind.peek.level === "warning" ? Theme.warning : Theme.accent)
                               : ind.mood === "waiting" ? Theme.warning
                               : ind.mood === "working" || ind.mood === "thinking" ? Theme.accent
                               : ind.mood === "error" ? Theme.danger
                               : ind.mood === "game" ? Theme.info
                               : ind.mood === "off" ? Theme.textDisabled
                               : Theme.textMuted
    readonly property string activity: !ind.open && !ind.peek && ind.lead && ind.lead.last ? "Claude · " + ind.lead.last : ""
    readonly property var usage: (ind.settings.show_usage !== false) ? CompanionState.usage : null
    readonly property var windows: ind.usage ? [["5h", ind.usage.five_hour], ["wk", ind.usage.seven_day]].filter(function (u) { return !!u[1] }) : []

    // the room left of the usage bars, and what the word must leave for
    // the badge and the peek's action
    readonly property real room: ind.width - (usageRow.visible ? usageRow.implicitWidth + Theme.spaceMd : 0)
    readonly property real tailW: (badge.visible ? badge.width + Theme.spaceS : 0)
                                + (act.visible ? act.implicitWidth + Theme.spaceS : 0)

    Rectangle {
        id: dot
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.spaceS
        height: width
        radius: width / 2          // a true circle: geometry, not a radius token
        color: ind.ink
        Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
    }
    TextStrong {
        id: wordT
        x: dot.width + Theme.spaceS
        anchors.verticalCenter: parent.verticalCenter
        text: ind.word
        width: Math.max(0, Math.min(implicitWidth, ind.room - x - ind.tailW))
        color: ind.mood === "idle" && !ind.peek ? Theme.textMuted : Theme.textPrimary
    }
    Badge {
        id: badge
        visible: CompanionState.asking > 0
        x: wordT.x + wordT.width + Theme.spaceS
        anchors.verticalCenter: parent.verticalCenter
        count: CompanionState.asking
        tone: "warning"
    }
    Text {
        // the action a click runs during a peek, as a quiet label
        id: act
        visible: !!(ind.peek && ind.peek.actions && ind.peek.actions.length > 0)
        x: (badge.visible ? badge.x + badge.width : wordT.x + wordT.width) + Theme.spaceS
        anchors.verticalCenter: parent.verticalCenter
        text: visible ? ind.peek.actions[0].label : ""
        color: Theme.accentText
        font.family: Theme.type.label.family
        font.pixelSize: Theme.type.label.size
        font.weight: Theme.type.label.weight
    }
    TextCaption {
        id: activityT
        x: (act.visible ? act.x + act.implicitWidth : badge.visible ? badge.x + badge.width : wordT.x + wordT.width) + Theme.spaceS
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, ind.room - x)
        visible: ind.activity !== "" && width >= Theme.spaceLg
        text: ind.activity
    }

    Row {
        id: usageRow
        visible: ind.windows.length > 0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spaceS
        Repeater {
            model: ind.windows
            Row {
                required property var modelData
                spacing: Theme.spaceXxs
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                TextCaption { text: modelData[0]; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    // a Meter-like track: the fill turns warning past 80 %
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.spaceLg
                    height: Theme.spaceXs
                    radius: height / 2
                    color: Theme.surfaceSunken
                    Rectangle {
                        width: parent.width * Math.min(1, Math.max(0, modelData[1].pct / 100))
                        height: parent.height
                        radius: parent.radius
                        color: modelData[1].pct >= 80 ? Theme.warning : Theme.accent
                    }
                }
                // the number only when open: the compact line keeps its room
                TextCaption {
                    visible: ind.open
                    text: Math.round(modelData[1].pct) + "%"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
