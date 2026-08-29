import QtQuick
import Quickshell
import Quickshell.Io

// Cast — "Cast to TV", the ewe-castd client (RFC-004).
//
// The protocols live in the ewe-castd daemon (Miracast/WFD as a real-time
// RTSP source, Chromecast via cast-channel; discovery over avahi + NM Wi-Fi
// P2P). This scope is only the shell's end of its control socket: it mirrors
// the daemon's state machine into Globals (castState/castDetail/castSinks),
// relays the Quick Settings card's commands, and narrates the P2P handshake
// from the system journal — NetworkManager and wpa_supplicant tell the truth
// about Wi-Fi Direct failures, the sink rarely does.
//
// The daemon outlives shell restarts on purpose (a hot-reload must not drop
// a presentation); we reconnect and re-learn its state from the greeting it
// sends every client. If the socket is missing we start the daemon: the user
// unit when installed, $EWE_CASTD/ewe-castd directly in dev.
//
// gnome-network-displays remains as `qs ipc call cast legacy` — the escape
// hatch until ewe-castd's WFD path has survived a real Samsung (its window
// picks the TV; closing it ends the session). Same babysitting as before:
// preflight, log capture, audio-follow, journal diagnosis.
Scope {
    id: root

    property bool wantDaemon: false        // something asked for cast this session
    property string lastDiag: ""           // dedupe: same reason isn't toasted twice in one run
    readonly property string logPath: Quickshell.env("HOME") + "/.local/state/ewe/cast.log"

    function notify(urgency, title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Cast to TV", "-u", urgency,
                                 "-h", "string:x-canonical-private-synchronous:ewe-cast",
                                 title, body])
    }

    IpcHandler {
        target: "cast"
        // toggle = the Super+Shift+C meaning: stop when live, otherwise open
        // Control Center on the sink list (picking a TV needs eyes anyway)
        function toggle(): void {
            if (Globals.casting) root.command("stop", "")
            else { root.ensureDaemon(); Globals.quickSettingsOpen = true }
        }
        function start(sink: string): void { root.command("start", sink) }
        function stop(): void  { root.command("stop", ""); Globals.castLegacy = false }
        function scan(): void  { root.command("scan", "") }
        function legacy(): void { root.legacyStart() }
    }

    Connections {
        target: Globals
        function onCastCommand(cmd, arg) { root.command(cmd, arg) }
    }

    // ── the daemon's socket ──────────────────────────────────────────────
    Socket {
        id: ctl
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/ewe-cast.sock"
        parser: SplitParser {
            onRead: line => {
                var msg
                try { msg = JSON.parse(line) } catch (e) { return }
                if (msg.event !== "status") return
                var was = Globals.castState
                Globals.castState = msg.state
                Globals.castDetail = msg.detail || ""
                Globals.castSinkName = msg.sink ? msg.sink.name : ""
                Globals.castSinks = msg.sinks || []
                if (msg.state === "error" && msg.detail && was !== "error")
                    root.notify("critical", "Cast to TV", msg.detail)
                journal.running = (msg.state === "connecting" || msg.state === "waiting")
                                  || Globals.castLegacy
            }
        }
        onConnectedChanged: {
            if (!connected) {
                Globals.castState = "idle"
                Globals.castSinks = []
                if (root.wantDaemon) retry.restart()
            }
        }
    }
    Timer { id: retry; interval: 1500; onTriggered: root.ensureDaemon() }

    function ensureDaemon() {
        root.wantDaemon = true
        if (ctl.connected) return
        // installed: the user unit (survives shell restarts); dev: straight
        // spawn — `sh` makes a missing binary a quiet no-op, the card shows
        // "engine not installed" from the socket never appearing
        Quickshell.execDetached(["sh", "-c",
            "systemctl --user start ewe-cast.service 2>/dev/null || exec ${EWE_CASTD:-ewe-castd}"])
        reconnect.restart()
    }
    Timer { id: reconnect; interval: 800; repeat: true
        property int tries: 0
        onRunningChanged: if (running) tries = 0
        onTriggered: {
            if (ctl.connected) { stop(); return }
            if (++tries > 10) {          // ~8 s of nothing: the engine isn't there
                stop()
                Globals.castDetail = "cast engine not installed (ewe-cast package)"
                return
            }
            ctl.connected = true
        } }

    function command(cmd, arg) {
        if (cmd === "start" || cmd === "scan") root.ensureDaemon()
        if (!ctl.connected) { pendingCmd = JSON.stringify({cmd: cmd, sink: arg}); return }
        ctl.write(JSON.stringify(cmd === "start" ? {cmd: "start", sink: arg} : {cmd: cmd}) + "\n")
        ctl.flush()
    }
    property string pendingCmd: ""
    Connections {
        target: ctl
        function onConnectedChanged() {
            if (ctl.connected && root.pendingCmd) {
                ctl.write(root.pendingCmd + "\n"); ctl.flush()
                root.pendingCmd = ""
            }
        }
    }

    // ── the narrator: NetworkManager + wpa_supplicant, live, only while a
    //    Wi-Fi Direct attempt is in flight (daemon or legacy) ─────────────
    // Readable without root for wheel/adm/systemd-journal members (Arch's
    // default for the installing user); anyone else just gets no diagnosis.
    Process {
        id: journal
        command: ["journalctl", "-f", "-n", "0", "-o", "cat", "-u", "NetworkManager", "-u", "wpa_supplicant"]
        stdout: SplitParser { onRead: line => root.diagnose(line) }
    }
    function diag(key, urgency, title, body) {
        if (root.lastDiag === key) return
        root.lastDiag = key
        root.notify(urgency, title, body)
    }
    function diagnose(line) {
        var m
        if ((m = /P2P-DEVICE-FOUND .*name='([^']*)'/.exec(line))) {
            root.diag("found:" + m[1], "low", "TV found: " + m[1], "The TV may ask you to allow the connection.")
        } else if (/P2P-GROUP-STARTED/.test(line)) {
            root.diag("linked", "low", "Wi-Fi Direct link up", "Handshake done — the picture should appear on the TV in a moment.")
        } else if (/connecting took too long|supplicant-timeout/.test(line)) {
            root.diag("timeout", "critical", "The TV never answered the Wi-Fi Direct handshake",
                      "It was discovered, but the pairing didn't complete within 45 s. On the TV open Source → Screen Mirroring "
                      + "(Samsung: Smart View / Screen Mirroring) so it is LISTENING, then pick it again and "
                      + "accept the prompt the TV shows. Keep the laptop close to the TV.")
        } else if (/peer-not-found/.test(line)) {
            // The TV joined the Wi-Fi Direct group, got an address, and left
            // ~10 s later: it never received a usable stream. 2026-08-21 this
            // was xdph's screencopy freeze (no frames → TV gives up); a choked
            // 2.4 GHz link does the same. cast-check.sh names which.
            root.diag("dropped", "critical", "The TV connected, then dropped the link",
                      "It joined and got an address but received no usable picture within ~10 s. Run "
                      + "~/.config/hypr/scripts/cast-check.sh — it flags a freezing portal (xdg-desktop-portal-hyprland < 1.4.1-1.1) "
                      + "and a 2.4 GHz-only link. Log: " + root.logPath)
        } else if (/P2P-GO-NEG-FAILURE|P2P-GROUP-FORMATION-FAILURE|WPS-FAIL|P2P-PROV-DISC-FAILURE/.test(line)) {
            root.diag("refused", "critical", "The TV refused the Wi-Fi Direct pairing",
                      "Either the prompt on the TV was declined, or the TV remembers a stale pairing. On the TV forget this "
                      + "computer in Screen Mirroring → Device manager, then try again.")
        } else if ((m = /\(p2p-dev-[^)]*\): state change: .* -> failed \(reason '([^']+)'/.exec(line)) && m[1] !== "supplicant-timeout" && m[1] !== "peer-not-found") {
            root.diag("failed:" + m[1], "critical", "Wi-Fi Direct connection failed", "NetworkManager reason: " + m[1] + " — details in " + root.logPath)
        }
    }

    // ══ LEGACY ANNEX: gnome-network-displays, until ewe-castd meets a real
    //    Samsung. `qs ipc call cast legacy` is the only door in. ══════════
    property bool legacyChecked: false

    function legacyStart() {
        if (gnd.running || preflight.running) return
        if (!root.legacyChecked) { root.legacyChecked = true; preflight.running = true }
        else gnd.running = true
    }

    Connections {
        target: Globals
        function onCastLegacyChanged() {
            if (!Globals.castLegacy && gnd.running) {
                gnd.signal(15)           // SIGTERM — let it end the session first
                hardKill.restart()
            }
        }
    }

    // One-time preflight. Exit 2 = gnome-network-displays missing (fatal, the
    // script already toasted the install command); 0/1 = go ahead. 127 = the
    // script itself is missing (dotfiles not deployed) — just launch.
    Process {
        id: preflight
        command: ["sh", "-c", "exec \"$HOME/.config/hypr/scripts/cast-check.sh\""]
        onExited: (code, status) => {
            if (code === 2) return
            gnd.running = true
        }
    }

    Process {
        id: gnd
        // via sh so a missing binary is a clean 127 rather than a failed spawn;
        // G_MESSAGES_DEBUG=all because the UI shows one-line errors — the
        // debug log is where "Connection failed" gets a reason. stdbuf: GLib
        // writes debug lines to STDOUT, which is block-buffered into a file,
        // so a SIGTERM'd app lost everything after its first 4 KB (2026-08-21:
        // the log stopped right before the RTSP handshake we needed to see).
        command: ["sh", "-c",
                  'mkdir -p "$HOME/.local/state/ewe"; '
                  + 'exec stdbuf -oL -eL env G_MESSAGES_DEBUG=all gnome-network-displays >"$HOME/.local/state/ewe/cast.log" 2>&1']
        onStarted: { root.lastDiag = ""; Globals.castLegacy = true; journal.running = true; castAudio.running = true }
        onExited: (code, status) => {
            hardKill.stop()
            journal.running = false
            castAudio.running = false
            if (code === 127)
                root.notify("critical", "Install gnome-network-displays",
                            "The legacy cast path needs it:  paru -S gnome-network-displays")
            else if (code !== 0 && code !== 143 && Globals.castLegacy)   // 143 = our SIGTERM
                root.notify("critical", "Cast to TV stopped unexpectedly",
                            "gnome-network-displays exited with code " + code + " — log: " + root.logPath)
            Globals.castLegacy = false
        }
    }
    Timer { id: hardKill; interval: 3000; onTriggered: if (gnd.running) gnd.running = false }

    // Audio follows the picture: while the legacy app casts, cast-audio.sh
    // makes its null sink the default and moves live streams onto it,
    // restoring your speakers when it exits. (ewe-castd does this itself.)
    Process {
        id: castAudio
        command: ["sh", "-c", "exec \"$HOME/.config/hypr/scripts/cast-audio.sh\""]
    }
}
