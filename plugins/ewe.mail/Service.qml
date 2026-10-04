import QtQuick
import Quickshell
import Quickshell.Io
import qs

// ewe.mail — the service: brings the Inbox model up (IMAP polling through
// `ewe-mail`, Gmail through `ewe-auth token`, the new-mail notifications),
// answers the IPC the Settings app speaks, and refetches after a suspend.
//
// Two IPC targets, one set of verbs: `ewe.mail` (the add-on's own) and
// `mail` — the target the shell always had (ewe-settings calls
// `qs ipc call mail status` and `mail setNotify`; Rule 4: IPC verbs are
// public API). The `status` reply is byte-compatible with the shell's.
Scope {
    id: svc
    property string pluginId: ""
    property var settings: ({})

    IpcHandler {
        target: "ewe.mail"
        function refresh(): void { Inbox.refresh() }
        function fetch(): void { Inbox.fetch() }
        function setNotify(on: bool): void { Inbox.setNotify(on) }
        function status(): string { return Inbox.statusJson() }
    }
    IpcHandler {
        target: "mail"
        function refresh(): void { Inbox.refresh() }
        function fetch(): void { Inbox.fetch() }
        function setNotify(on: bool): void { Inbox.setNotify(on) }
        function status(): string { return Inbox.statusJson() }
    }

    Connections {
        target: Shell
        function onResumed() { Inbox.refreshAfterResume() }
    }

    // touching the singleton instantiates it: its status probes run at once
    Component.onCompleted: Log.info("ewe.mail", "service up — source:", Inbox.source || "none yet")
}
