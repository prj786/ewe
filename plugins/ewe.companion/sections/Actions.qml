import QtQuick
import qs
import ".."

// Actions — one click across ewe. Each button runs a catalog command
// through the daemon (the same path as typing it), so its result and its
// Undo arrive in the chat like any other.
Column {
    id: qa
    spacing: Theme.spaceXxs
    property string hint: ""

    readonly property var buttons: [
        { ic: Theme.icDnd, label: "Do not disturb", on: Shell.dnd, cmd: "dnd", args: { on: !Shell.dnd } },
        { ic: Theme.icGamepad, label: "Game mode", on: CompanionState.gameMode, cmd: "game_mode", args: { on: !CompanionState.gameMode } },
        { ic: Theme.icCamera, label: "Screenshot", on: false, cmd: "screenshot", args: { mode: "region" } },
        { ic: Theme.icCog, label: "Settings", on: false, cmd: "open", args: { what: "settings" } },
        { ic: Theme.icStore, label: "Komble", on: false, cmd: "open", args: { what: "komble" } },
        { ic: Theme.icLock, label: "Lock", on: false, cmd: "lock", args: {} }
    ]

    Row {
        spacing: Theme.spaceXs
        Repeater {
            model: qa.buttons
            QsIconButton {
                required property var modelData
                ic: modelData.ic
                size: "md"
                selected: modelData.on
                Accessible.name: modelData.label
                // moving from one icon to the next, the new one's enter can
                // come before the old one's leave: only clear our own hint
                readonly property string hintText: modelData.label + (modelData.on ? " (on)" : "")
                onHoveredChanged: {
                    if (hovered) qa.hint = hintText
                    else if (qa.hint === hintText) qa.hint = ""
                }
                onGo: CompanionState.run(modelData.cmd, modelData.args)
            }
        }
    }
    // a fixed slot: a Column skips a child of zero width, and an empty
    // caption is zero wide, so without the width the notch grew on hover
    // (owner, 2026-10-14)
    TextCaption { text: qa.hint; width: qa.width; height: Theme.lineHeightXs }
}
