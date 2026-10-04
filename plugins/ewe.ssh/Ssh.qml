pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// ewe.ssh — THE state behind the tile, the page and the bar glyph: the hosts
// parsed from ~/.ssh/config (+ config.d/*), which of them has a background
// tunnel we started alive, which has a saved browse script, and every action
// the page offers. The three entry points are pure consumers (the qmldir
// beside this file makes it a singleton of this plugin's own directory).
//
// Each host entry: { host, tunnel (bool), script (bool) }
//   "tunnel" = a background `ssh -f -N` we started is alive for that host;
//   "script" = the user saved a browse script (ssh-browse/<host>.sh, below).
//
// The browse scripts stay where the shell kept them —
// ~/.config/quickshell/ssh-browse/<host>.sh — so nobody's saved launcher is
// lost when the feature moves out of the shell (user data is never moved
// silently). It is not synced and not in ewe.conf.
QtObject {
    id: ssh

    property var hosts: []
    property bool tunnelUp: false       // any background ssh -f -N tunnel is up (the bar glyph)
    property string scriptTarget: ""    // host whose browse-script editor is open
    property string scriptText: ""      // editor prefill (existing script when editing)

    // what is on screen — the tile (Quick settings home) and the page (tab
    // ssh). The host injects panelOpen into each entry point; they mirror it
    // here so the scan runs when something that shows the result appears
    // (the shell scanned on every panel open: the tile's sub-label needs
    // the host count) and the 6 s poll runs only while the page is open.
    property bool tileOpen: false
    property bool pageOpen: false
    onTileOpenChanged: if (ssh.tileOpen) ssh.scan()
    onPageOpenChanged: if (ssh.pageOpen) ssh.scan()

    readonly property string scriptDir: "$HOME/.config/quickshell/ssh-browse"

    function sq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }   // shell single-quote
    function scriptPath(host) { return "\"" + ssh.scriptDir + "/" + host + ".sh\"" }

    function scan() { scanProc.running = true }
    function rescanSoon() { rescan.restart() }

    // ── actions ──
    // Open a terminal already ssh'd into the host (kitty runs the command directly).
    function term(host) {
        Quickshell.execDetached(["kitty", "ssh", host])
        Shell.closeQuickSettings()
    }
    // Browse: run the user's saved per-host script (a proxied-browser launcher,
    // pasted once via the inline editor and kept forever in ssh-browse/). Before
    // the script runs, a background SOCKS5 tunnel `ssh -f -N -D $SOCKS_PORT` to
    // the host is brought up if none is alive (BatchMode: needs key/agent auth —
    // there is no terminal to type a password into), and SSH_HOST + SOCKS_PORT
    // (default 1080) are exported so the script can point a browser at
    // socks5://127.0.0.1:$SOCKS_PORT. No saved script yet → open the editor.
    function browse(host, hasScript) {
        if (!hasScript) {
            ssh.scriptText = ""
            ssh.scriptTarget = ssh.scriptTarget === host ? "" : host
            return
        }
        Quickshell.execDetached(["sh", "-c", ssh.runCmd(host)])
        ssh.rescanSoon()
        Shell.closeQuickSettings()
    }
    // The tunnel-then-script shell command (shared by browse and Save & Run).
    function runCmd(host) {
        var pat = ssh.sq("^ssh -f -N .*" + host + "$")
        return "export SSH_HOST=" + ssh.sq(host) + " SOCKS_PORT=\"${SOCKS_PORT:-1080}\"; " +
               "if ! pgrep -f " + pat + " >/dev/null 2>&1; then " +
               "ssh -f -N -D \"$SOCKS_PORT\" -o BatchMode=yes -o ConnectTimeout=5 -o ExitOnForwardFailure=yes " + ssh.sq(host) +
               " || { notify-send -u critical -a SSH " + ssh.sq("Tunnel to " + host + " failed") +
               " 'Needs key/agent auth (no password prompt in the background).'; exit 1; }; fi; " +
               "exec " + ssh.scriptPath(host)
    }
    // Save the pasted script (quoted heredoc: content lands verbatim), mark it
    // executable, then immediately run it via the same tunnel-first path.
    function saveScript(host, text) {
        var p = ssh.scriptPath(host)
        var cmd = "mkdir -p \"" + ssh.scriptDir + "\" && cat > " + p +
                  " <<'QS_EOF'\n" + text.replace(/\n+$/, "") + "\nQS_EOF\nchmod +x " + p + " && " + ssh.runCmd(host)
        Quickshell.execDetached(["sh", "-c", cmd])
        ssh.scriptTarget = ""
        ssh.rescanSoon()
        Shell.closeQuickSettings()
    }
    // Pencil button: load the saved script into the editor (or close it again).
    function editScript(host) {
        if (ssh.scriptTarget === host) { ssh.scriptTarget = ""; return }
        scriptLoad.host = host
        scriptLoad.command = ["sh", "-c", "cat " + ssh.scriptPath(host) + " 2>/dev/null"]
        scriptLoad.running = false; scriptLoad.running = true
    }
    function deleteScript(host) {
        Quickshell.execDetached(["sh", "-c", "rm -f " + ssh.scriptPath(host)])
        ssh.scriptTarget = ""
        ssh.rescanSoon()
    }
    function stopTunnel(host) {
        Quickshell.execDetached(["sh", "-c", "pkill -f " + ssh.sq("^ssh -f -N .*" + host + "$")])
        ssh.rescanSoon()
    }

    // ── the scan: ~/.ssh/config (+ config.d/*) + live tunnels + scripts ──
    // One process emits the config, then (behind marker lines) `pgrep -af` of the
    // background tunnels we start (they all match "^ssh -f -N") and the saved
    // browse scripts (ssh-browse/<host>.sh).
    property Process scanProc: Process {
        command: ["sh", "-c", "cat \"$HOME/.ssh/config\" \"$HOME/.ssh/config.d\"/* 2>/dev/null; printf '\\n@TUNNELS@\\n'; pgrep -af '^ssh -f -N' 2>/dev/null; printf '@SCRIPTS@\\n'; ls \"" + ssh.scriptDir + "\" 2>/dev/null; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var ls = this.text.split("\n"), sec = 0   // 0 config · 1 tunnels · 2 scripts
                var hosts = [], seen = {}, tunHosts = {}, scripts = {}
                for (var i = 0; i < ls.length; i++) {
                    var ln = ls[i].trim()
                    if (ln === "@TUNNELS@") { sec = 1; continue }
                    if (ln === "@SCRIPTS@") { sec = 2; continue }
                    if (!ln || (sec === 0 && ln.charAt(0) === "#")) continue
                    if (sec === 1) {
                        // "PID ssh -f -N [-o …] [-D …] host" — host is the last token
                        var tk = ln.split(/\s+/)
                        tunHosts[tk[tk.length - 1]] = true
                        continue
                    }
                    if (sec === 2) {
                        if (/\.sh$/.test(ln)) scripts[ln.slice(0, -3)] = true
                        continue
                    }
                    var mh = ln.match(/^Host\s+(.+)$/i)
                    if (mh) {
                        var names = mh[1].split(/\s+/)
                        for (var n = 0; n < names.length; n++) {
                            var h = names[n]
                            if (!h || /[*?!]/.test(h)) continue   // skip wildcard/negated patterns
                            if (!seen[h]) { seen[h] = true; hosts.push(h) }
                        }
                    }
                }
                var arr = [], anyTun = false
                for (var k = 0; k < hosts.length; k++) {
                    var t = tunHosts[hosts[k]] === true
                    if (t) anyTun = true
                    arr.push({ host: hosts[k], tunnel: t, script: scripts[hosts[k]] === true })
                }
                ssh.hosts = arr
                ssh.tunnelUp = anyTun
            }
        }
    }
    // cat's an existing browse script into the editor, then opens it
    property Process scriptLoad: Process {
        property string host: ""
        stdout: StdioCollector {
            onStreamFinished: {
                ssh.scriptText = this.text
                ssh.scriptTarget = scriptLoad.host
            }
        }
    }
    // after an action: the tunnel takes a moment to appear or go
    property Timer rescan: Timer { interval: 1500; onTriggered: ssh.scan() }
    // while the page is open, keep the tunnel marks fresh (the shell's 6 s poll)
    property Timer poll: Timer { interval: 6000; running: ssh.pageOpen; repeat: true; onTriggered: ssh.scan() }
    // one read at start so the bar glyph knows about a tunnel that outlived a
    // shell restart, and one after wake (a tunnel rarely survives a suspend)
    property Connections wake: Connections { target: Shell; function onResumed() { ssh.scan() } }
    Component.onCompleted: ssh.scan()
}
