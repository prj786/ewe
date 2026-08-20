import QtQuick
import Quickshell
import Quickshell.Io

// Cast — "Cast to TV". The Quick Settings tile (and Super+Shift+C) flip
// Globals.casting; this Scope turns that bool into a running
// gnome-network-displays, the one app that does BOTH screen-mirroring
// protocols a smart TV may speak:
//
//   Miracast    Samsung "Screen Mirroring" (Tizen), most Android TVs. Wi-Fi
//               Direct (P2P) over NetworkManager + wpa_supplicant — the Wi-Fi
//               card must support P2P (cast-check.sh verifies with `iw list`).
//   Chromecast  Google TV / Chromecast built-in. Discovered over mDNS, so
//               avahi-daemon must be running (phase 30 enables it).
//
// The desktop is captured through the xdg-desktop-portal ScreenCast (the
// hyprland portal) — which pops OUR picker (SharePicker.qml) — so the app
// works outside GNOME. Its window lists the TVs it finds; closing that window
// ends the session.
//
//   casting → true   first time this session: run scripts/cast-check.sh (it
//                    notifies about anything missing — no binary, no avahi,
//                    no Wi-Fi Direct). A missing binary is fatal and resets the
//                    tile; everything else is a warning and the app still
//                    launches (a Chromecast-only setup is legitimate).
//   app exits        the tile follows: Globals.casting → false. `sh` exits 127
//                    when the binary is gone, which is the "Install …" toast.
//   casting → false  while the app runs: SIGTERM so it tears the Miracast /
//                    Chromecast session down cleanly, hard kill after 3 s.
//
// WHY the app's own errors aren't enough: when a connect fails it shows one
// line ("Connection failed") and nothing else. The real reason is in the
// system journal — NetworkManager drives the Wi-Fi Direct link and
// wpa_supplicant does the handshake, and both narrate every step. While
// casting we tail them and translate the failure into a toast that says what
// to DO (2026-08-21: a Samsung was found but never answered the P2P
// handshake → NM "supplicant-timeout" after 45 s; the app said nothing). The
// app's own debug output also goes to ~/.local/state/ewe/cast.log.
Scope {
    id: root

    property bool checked: false   // preflight has run once this shell session
    property string lastDiag: ""   // dedupe: same reason isn't toasted twice in one run
    readonly property string logPath: Quickshell.env("HOME") + "/.local/state/ewe/cast.log"

    function notify(urgency, title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Cast to TV", "-u", urgency,
                                 "-h", "string:x-canonical-private-synchronous:ewe-cast",
                                 title, body])
    }

    IpcHandler {
        target: "cast"
        function toggle(): void { Globals.casting = !Globals.casting }
        function start(): void  { Globals.casting = true }
        function stop(): void   { Globals.casting = false }
    }

    Connections {
        target: Globals
        function onCastingChanged() {
            if (Globals.casting) {
                if (gnd.running || preflight.running) return
                if (!root.checked) { root.checked = true; preflight.running = true }
                else gnd.running = true
            } else if (gnd.running) {
                gnd.signal(15)           // SIGTERM — let it end the session first
                hardKill.restart()
            }
        }
    }

    // One-time preflight. Exit 2 = gnome-network-displays missing (fatal, the
    // script already toasted the install command); 0/1 = go ahead. 127 = the
    // script itself is missing (dotfiles not deployed) — nothing to check with,
    // just launch and let the app's own exit code speak.
    Process {
        id: preflight
        command: ["sh", "-c", "exec \"$HOME/.config/hypr/scripts/cast-check.sh\""]
        onExited: (code, status) => {
            if (code === 2) { Globals.casting = false; return }
            if (Globals.casting) gnd.running = true
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
        onStarted: { root.lastDiag = ""; journal.running = true; castAudio.running = true }
        onExited: (code, status) => {
            hardKill.stop()
            journal.running = false
            castAudio.running = false
            if (code === 127)
                root.notify("critical", "Install gnome-network-displays",
                            "Cast to TV needs it:  paru -S gnome-network-displays")
            else if (code !== 0 && code !== 143 && Globals.casting)   // 143 = our SIGTERM
                root.notify("critical", "Cast to TV stopped unexpectedly",
                            "gnome-network-displays exited with code " + code + " — log: " + root.logPath)
            Globals.casting = false
        }
    }
    Timer { id: hardKill; interval: 3000; onTriggered: if (gnd.running) gnd.running = false }

    // ── the narrator: NetworkManager + wpa_supplicant, live, only while casting ──
    // Readable without root for wheel/adm/systemd-journal members (Arch's
    // default for the installing user); anyone else just gets no diagnosis.
    Process {
        id: journal
        command: ["journalctl", "-f", "-n", "0", "-o", "cat", "-u", "NetworkManager", "-u", "wpa_supplicant"]
        stdout: SplitParser { onRead: line => root.diagnose(line) }
    }

    // Audio follows the picture: while casting, cast-audio.sh makes the
    // gnome-network-displays null sink the default and moves live streams onto
    // it (GND streams that sink's monitor to the TV), restoring your speakers
    // when it exits. GND creates the sink but never redirects audio itself, so
    // without this the sound stays on the laptop.
    Process {
        id: castAudio
        command: ["sh", "-c", "exec \"$HOME/.config/hypr/scripts/cast-audio.sh\""]
    }
    function diag(key, urgency, title, body) {
        if (root.lastDiag === key) return
        root.lastDiag = key
        root.notify(urgency, title, body)
    }
    function diagnose(line) {
        var m
        if ((m = /P2P-DEVICE-FOUND .*name='([^']*)'/.exec(line))) {
            root.diag("found:" + m[1], "low", "TV found: " + m[1], "Pick it in the Cast window; the TV may ask you to allow the connection.")
        } else if (/P2P-GROUP-STARTED/.test(line)) {
            root.diag("linked", "low", "Wi-Fi Direct link up", "Handshake done — the picture should appear on the TV in a moment.")
        } else if (/connecting took too long|supplicant-timeout/.test(line)) {
            root.diag("timeout", "critical", "The TV never answered the Wi-Fi Direct handshake",
                      "It was discovered, but the pairing didn't complete within 45 s. On the TV open Source → Screen Mirroring "
                      + "(Samsung: Smart View / Screen Mirroring) so it is LISTENING, then pick it again in the Cast window and "
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
}
