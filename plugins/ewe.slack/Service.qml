import QtQuick
import Quickshell
import Quickshell.Io
import qs

// ewe.slack — the service: hands the SlackInbox model its helper path,
// state dir and settings, answers IPC, and refetches after a suspend.
//   qs ipc call ewe.slack refresh | status | open | connect
Scope {
    id: svc
    property string pluginId: ""
    property string pluginDir: ""
    property string stateDir: ""
    property var settings: ({})

    // the host injects after creation: start once both paths have arrived
    function _go() { if (svc.pluginDir !== "" && svc.stateDir !== "") SlackInbox.start(svc.pluginDir, svc.stateDir) }
    onPluginDirChanged: _go()
    onStateDirChanged: _go()
    onSettingsChanged: SlackInbox.settings = svc.settings

    IpcHandler {
        target: "ewe.slack"
        function refresh(): void { SlackInbox.fetch() }
        function status(): string { return SlackInbox.statusJson() }
        function open(): void { SlackInbox.openSlack() }
        function connect(): void { SlackInbox.openSetup() }
    }

    Connections {
        target: Shell
        function onResumed() { SlackInbox.fetch() }
    }

    Component.onCompleted: Log.info("ewe.slack", "service up")
}
