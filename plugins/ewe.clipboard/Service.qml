import QtQuick
import Quickshell
import Quickshell.Io
import qs

// ewe.clipboard — the recorder. Two wl-paste watchers feed cliphist; text
// goes through clip-store.sh, which drops passwords (the KDE password-manager
// hint, a focused password manager, ewe-pass's own copy marker). The
// processes die with the shell, so a disabled plugin records nothing.
// The double-start guard is anchored ("^wl-paste …") on purpose: the `sh -c`
// wrapper's own command line contains the watcher text (the exec line), and
// an unanchored `pgrep -f "wl-paste …"` matched THAT, took the `exit 0`
// branch and never started a watcher — clipboard history recorded nothing
// (2026-09-20). A real watcher's command line STARTS with wl-paste (exec
// replaces the shell); the wrapper's starts with sh.
QtObject {
    id: svc
    property var settings: ({})
    readonly property string gate: Qt.resolvedUrl("clip-store.sh").toString().replace(/^file:\/\//, "")

    property Process text: Process {
        command: ["sh", "-c", 'pgrep -f "^wl-paste --type text --watch" >/dev/null && exit 0; exec wl-paste --type text --watch "$1"', "_", svc.gate]
        running: true
        onExited: function (code) { if (code !== 0) Log.warn("ewe.clipboard", "text watcher exited", code) }
    }
    property Process image: Process {
        command: ["sh", "-c", 'pgrep -f "^wl-paste --type image --watch" >/dev/null && exit 0; exec wl-paste --type image --watch cliphist store']
        running: true
    }
    Component.onCompleted: Log.info("ewe.clipboard", "recording copies into cliphist")
}
