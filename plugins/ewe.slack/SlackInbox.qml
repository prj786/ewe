pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// SlackInbox — the unread-DM model of the slack add-on, read by the bar glyph
// and the desktop widget. Polls slack-unread.py (which reads the token from the
// keyring itself) and keeps the last good list while offline. Clicking a row
// opens that DM in Slack. The one moment a token is in QML is the Connect
// window: it goes straight to `slack-unread.py --connect` on stdin, which
// checks it with Slack before storing it in the keyring.
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
    property string teamName: ""
    property string userName: ""
    property var list: []
    property int unread: 0
    readonly property bool available: state !== "no-token" && state !== "auth"

    readonly property bool connected: probed && available

    // the Connect window (Setup.qml)
    property bool setupOpen: false
    property bool connecting: false
    property string connectError: ""
    readonly property string appManifest: JSON.stringify({
        display_information: { name: "ewe Slack unread", description: "Shows your unread Slack DMs on the ewe desktop." },
        oauth_config: { scopes: { user: ["im:read", "im:history", "mpim:read", "mpim:history", "users:read"] } },
        settings: { org_deploy_enabled: false, socket_mode_enabled: false, token_rotation_enabled: false }
    })
    function createApp() {
        Quickshell.execDetached(["xdg-open", "https://api.slack.com/apps?new_app=1&manifest_json=" + encodeURIComponent(si.appManifest)])
    }
    function openSetup() { si.connectError = ""; si.setupOpen = true }

    function connect(tok) {
        if (si.helper === "" || si.connecting) return
        si.connecting = true; si.connectError = ""
        si._pendingToken = String(tok).trim()
        _connect.command = ["python3", si.helper, "--state-dir", si.stateDir, "--connect"]
        _connect.running = true
    }
    property string _pendingToken: ""
    property Process _connect: Process {
        stdinEnabled: true
        onStarted: { _connect.write(si._pendingToken + "\n"); si._pendingToken = "" }
        stdout: StdioCollector {
            onStreamFinished: {
                si.connecting = false
                try {
                    var j = JSON.parse(this.text)
                    if (j.ok) {
                        si.setupOpen = false
                        si.state = ""; si.error = ""; si.list = []; si.unread = 0
                        si.fetch()
                    } else si.connectError = j.error || "Couldn't connect."
                } catch (e) { si.connectError = "The Slack helper gave no answer." }
            }
        }
    }
    function disconnect() {
        if (si.helper === "") return
        _disconnect.command = ["python3", si.helper, "--state-dir", si.stateDir, "--disconnect"]
        _disconnect.running = true
    }
    property Process _disconnect: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                si.list = []; si.unread = 0; si.team = ""; si.teamName = ""; si.userName = ""
                si.state = "no-token"; si.error = ""
            }
        }
    }

    // first start without a token: offer the Connect window once (the marker
    // in the state dir remembers that it was offered)
    property Process _offer: Process {
        stdout: StdioCollector { onStreamFinished: if (this.text.trim() === "first") si.openSetup() }
    }
    onStateChanged: if (si.state === "no-token" && si.stateDir !== "") {
        _offer.command = ["sh", "-c", 'test -e "$1" || { touch "$1" && echo first; }', "ewe-slack", si.stateDir + "/setup-offered"]
        _offer.running = true
    }

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
                        si.teamName = j.teamName || ""
                        si.userName = j.user || ""
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
