import QtQuick
import qs
import ".."

// Agents — every live session: project, state, its last steps, files
// changed. A click brings its terminal forward. Hidden with no sessions.
Column {
    id: ag
    spacing: Theme.spaceXs
    visible: CompanionState.sessions.length > 0

    function word(st) {
        return st === "working" ? "Working" : st === "waiting" ? "Needs you" : st === "done" ? "Done"
             : st === "failed" ? "Stopped" : "Idle"
    }
    function ink(st) {
        return st === "working" ? Theme.accent : st === "waiting" ? Theme.warning : st === "done" ? Theme.success
             : st === "failed" ? Theme.danger : Theme.textMuted
    }

    SectionLabel { text: "AGENTS" }
    Repeater {
        model: CompanionState.sessions.slice(0, 3)
        Rectangle {
            id: row
            required property var modelData
            width: ag.width
            height: col.implicitHeight + 2 * Theme.spaceXs
            radius: Theme.radiusPrimary
            color: ma.pressed ? Theme.surfacePressed : ma.containsMouse ? Theme.surfaceHover : "transparent"
            Column {
                id: col
                x: Theme.spaceS; y: Theme.spaceXs
                width: parent.width - 2 * Theme.spaceS
                spacing: Theme.spaceXxs
                Item {
                    width: parent.width
                    height: head.implicitHeight
                    Row {
                        id: head
                        spacing: Theme.spaceS
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.spaceS; height: width; radius: width / 2
                            color: ag.ink(row.modelData.state)
                        }
                        TextStrong { text: "Claude · " + row.modelData.project + "/" }
                    }
                    TextCaption {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: ag.word(row.modelData.state)
                              + (row.modelData.files_changed > 0
                                 ? " · " + row.modelData.files_changed + (row.modelData.files_changed === 1 ? " file" : " files") : "")
                    }
                }
                Repeater {
                    model: (row.modelData.steps || []).slice(-3)
                    TextCaption {
                        required property var modelData
                        width: col.width
                        text: modelData
                        font.family: Theme.type.mono.family
                    }
                }
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { CompanionState.jump(row.modelData.id); CompanionState.dropOpen = false }
            }
        }
    }
}
