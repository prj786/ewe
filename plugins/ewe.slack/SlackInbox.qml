pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// SlackInbox — the unread-DM model of the slack add-on, read by the bar glyph
// and the desktop widget. Polls slack-unread.py (which reads the token from the
// keyring itself — nothing secret ever passes through QML) and keeps the last
// good list while offline. Clicking a row opens that DM in Slack.
QtObject {
    id: si

    property string helper: ""
    property string stateDir: ""
    property var settings: ({})
    readonly property int pollSeconds: Math.max(30, Number(settings.poll_seconds) || 60)
    readonly property bool includeBots: settings.include_bots === true
    readonly property bool openInBrowser: settings.open_with === "browser"

    property bool probed: false
    property bool busy: false
    property string state: ""            // "" | "no-token" | "auth" | "offline" | "error"
    property string error: ""
    property string team: ""
    property var list: []
    property int unread: 0
    readonly property bool available: state !== "no-token" && state !== "auth"

    readonly property string hint: "Store a Slack user token (xoxp-…) in the keyring:\nsecret-tool store --label='Slack (ewe)' service ewe-slack account user-token\nthen refresh. See the README for the Slack app setup."

    function start(pluginDir, stateDir) {
        si.helper = String(pluginDir).replace(/^file:\/\//, "").replace(/\/$/, "") + "/slack-unread.py"
        si.stateDir = stateDir
        si.fetch()
    }

    function fetch() {
        if (si.helper === "" || si.stateDir === "" || si.busy) return
        si.busy = true
        var cmd = ["python3", si.helper, "--state-dir", si.stateDir]
        if (si.includeBots) cmd.push("--include-bots")
        _poll.command = cmd
        _poll.running = true
    }

    function open(row) {
        if (si.team === "" || !row) return
        var url = si.openInBrowser
            ? "https://app.slack.com/client/" + si.team + "/" + row.channel
            : "slack://channel?team=" + si.team + "&id=" + row.channel
        Quickshell.execDetached(["xdg-open", url])
        // reading it in Slack moves last_read; look again shortly after
        _afterOpen.restart()
    }

    function openSlack() {
        Quickshell.execDetached(["xdg-open", si.openInBrowser || si.team === ""
            ? "https://app.slack.com/client/" + si.team
            : "slack://open?team=" + si.team])
    }

    function statusJson() {
        return JSON.stringify({ probed: si.probed, state: si.state, error: si.error, unread: si.unread, conversations: si.list.length })
    }

    property Process _poll: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                si.busy = false
                si.probed = true
                try {
                    var j = JSON.parse(this.text)
                    if (j.ok) {
                        si.state = ""; si.error = ""
                        si.team = j.team
                        si.list = j.list || []
                        si.unread = j.total || 0
                    } else if (j.error === "no-token" || j.error === "auth") {
                        si.state = j.error
                        si.error = j.error === "auth" ? "Slack rejected the token — store a fresh one." : ""
                        si.list = []; si.unread = 0
                    } else if (j.error === "offline") {
                        si.state = "offline"; si.error = ""
                    } else {
                        si.state = "error"; si.error = "Slack: " + j.error
                    }
                } catch (e) {
                    si.state = "error"; si.error = "The Slack helper gave no answer."
                    Log.info("slack", "helper output unreadable:", this.text)
                }
            }
        }
        onExited: (code, status) => { if (code !== 0 && si.busy) { si.busy = false; si.state = "error"; si.error = "The Slack helper exited (" + code + ")." } }
    }

    property Timer _timer: Timer {
        interval: si.pollSeconds * (Shell.onBattery ? 2 : 1) * 1000
        running: si.helper !== "" && si.state !== "no-token"
        repeat: true
        onTriggered: si.fetch()
    }
    property Timer _afterOpen: Timer { interval: 15000; onTriggered: si.fetch() }
}
