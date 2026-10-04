import QtQuick
import Quickshell
import Quickshell.Io
import qs

// ewe.phone — the service: starts kdeconnectd when it is installed and not
// running (what the shell's autostart.sh did — Hyprland processes no XDG
// autostart, and the bridge can D-Bus-activate it on demand too), runs the
// D-Bus bridge from the plugin directory through the Phone singleton, and
// re-checks the bridge after a suspend (Shell.resumed) — a bridge whose bus
// connection died while asleep looks alive and reports nothing.
Scope {
    id: svc
    property string pluginId: ""
    property string pluginDir: ""        // injected after creation — the bridge lives here
    property var settings: ({})

    // the host injects pluginDir right after createObject(); start the bridge
    // from it. Should the injection never come (an older host), the singleton
    // resolves the script from its own directory a moment later.
    onPluginDirChanged: if (pluginDir !== "") Phone.start(pluginDir)
    Timer { interval: 1500; running: true; onTriggered: Phone.start("") }

    // autostart.sh's `run_once kdeconnectd kdeconnectd`: nothing when the
    // binary is missing or a daemon already runs, else start it detached.
    // `pgrep -x` (the process NAME), never `pgrep -f`: this `sh -c` wrapper's
    // own command line contains the word and an unanchored -f matched the
    // wrapper itself, so nothing ever started (the clipboard plugin's
    // 2026-09-20 lesson). EWE_PHONE_NO_DAEMON=1 (the nested test harness on
    // a private bus) keeps a test session from launching a daemon on the
    // real machine.
    Process {
        running: true
        command: ["sh", "-c",
            '[ -n "${EWE_PHONE_NO_DAEMON:-}" ] && exit 0; ' +
            'if command -v kdeconnectd >/dev/null 2>&1; then exe=kdeconnectd; ' +
            'elif [ -x /usr/lib/kdeconnectd ]; then exe=/usr/lib/kdeconnectd; else exit 0; fi; ' +
            'pgrep -x kdeconnectd >/dev/null 2>&1 && exit 0; ' +
            'setsid "$exe" >/dev/null 2>&1 </dev/null & exit 0']
        onExited: function (code) { if (code !== 0) Log.warn("ewe.phone", "kdeconnectd start helper exited", code) }
    }

    Connections {
        target: Shell
        function onResumed() { Phone.probeLiveness() }
    }

    Component.onCompleted: Log.info("ewe.phone", "service up")
}
