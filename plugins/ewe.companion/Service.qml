import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs

// ewe.companion — the shell's end of the ewe-companiond socket (RFC-007).
//
// The daemon thinks (cards, sessions, the chat, commands); this service
// mirrors its state into CompanionState for the notch to draw, and sends
// back what only the shell knows or can do:
//
//   env       locked, Do not disturb, the compositor's signature, the
//             Wayland display (for what Safe copies)
//   settings  who answers questions (the plugin's options; never a key)
//   do        Do not disturb, opening apps, screenshots, the browser (its
//             own command line when it has one), Safe's unlock prompt: the
//             things a daemon outside the shell should not do itself
//
// The daemon outlives shell restarts on purpose: an agent waiting on a card
// must not lose it because the shell restarted. We reconnect and re-learn
// everything from the `state` snapshot it sends every client. If the socket
// is missing we start the daemon: the user unit when installed,
// $EWE_COMPANIOND (or ewe-companiond on PATH) in dev. Nothing here ever
// answers a card for you: an answer is a click (C1).
//
// IPC: target `ewe.companion`: toggle · open · hide · status · ask <text>
Scope {
    id: root

    property string pluginId: ""
    property url pluginDir
    property string stateDir: ""
    property var settings: ({})

    onSettingsChanged: {
        var s = root.settings || {}
        CompanionState.peekMs = (s.peek_seconds !== undefined ? s.peek_seconds : 5) * 1000
        root.sendSettings()
    }

    // ── the screen cards and the home panel open on (setting `screen`) ───
    readonly property string screenSetting: (root.settings && root.settings.screen) || "primary"
    readonly property string focusedName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    // a name that is not a live output (a profile's primary that is
    // unplugged) falls back to the first screen, so the notch never vanishes
    function live(name) {
        var ss = Quickshell.screens
        for (var i = 0; i < ss.length; i++) if (ss[i].name === name) return name
        return ss.length > 0 ? ss[0].name : ""
    }
    Binding {
        target: CompanionState; property: "screenName"
        value: root.live(root.screenSetting === "primary" ? Shell.primaryScreenName
                         : (root.focusedName !== "" ? root.focusedName : Shell.primaryScreenName))
    }

    IpcHandler {
        target: "ewe.companion"
        function toggle(): void { CompanionState.dropOpen = !CompanionState.dropOpen }
        function open(): void { CompanionState.dropOpen = true }
        function hide(): void { CompanionState.dropOpen = false }
        // a question or a command, as if typed into the chat box
        function ask(text: string): void { CompanionState.dropOpen = true; CompanionState.ask(text) }
        function status(): string {
            return JSON.stringify({
                connected: CompanionState.connected,
                presence: CompanionState.presence,
                pending: CompanionState.pending.length,
                sessions: CompanionState.sessions.length,
                peek: CompanionState.peek ? CompanionState.peek.line : null,
                screen: CompanionState.screenName,
                open: CompanionState.dropOpen,
                provider: CompanionState.chat ? CompanionState.chat.provider : null
            })
        }
    }

    // ── the socket ───────────────────────────────────────────────────────
    function socketPath() {
        var o = Quickshell.env("EWE_COMPANION_SOCK")
        return o ? o : Quickshell.env("XDG_RUNTIME_DIR") + "/ewe-companion.sock"
    }

    Socket {
        id: sock
        path: root.socketPath()
        parser: SplitParser { onRead: line => root.onLine(line) }
        onConnectedChanged: {
            if (connected) {
                Log.info("ewe.companion", "connected to the daemon")
                retry.attempt = 0
                root.write({ type: "hello", client: "island", pid: 0 })
                root.sendEnv()
                root.sendSettings()
            } else {
                Log.info("ewe.companion", "daemon gone; reconnecting")
                CompanionState.connected = false
                CompanionState.pending = []
                CompanionState.thinking = false
                retry.restart()
            }
        }
    }

    function write(msg) {
        if (!sock.connected) return
        msg.v = 1
        sock.write(JSON.stringify(msg) + "\n")
        sock.flush()
    }
    Connections {
        target: CompanionState
        function onOutbound(msg) { root.write(msg) }
    }

    function onLine(line) {
        var m
        try { m = JSON.parse(line) } catch (e) { return }
        switch (m.type) {
        case "welcome":
            CompanionState.connected = true
            break
        case "state":
            CompanionState.presence = m.presence || "idle"
            CompanionState.pending = m.pending || []
            CompanionState.sessions = m.sessions || []
            CompanionState.glance = m.glance || {}
            CompanionState.usage = m.usage || null
            CompanionState.chat = m.chat || {}
            CompanionState.gameMode = !!m.game_mode
            break
        case "peek":
            CompanionState.showPeek(m)
            break
        case "card.close":
            CompanionState.pending = CompanionState.pending.filter(function (c) { return c.id !== m.id })
            break
        case "chat.reply":
            if (m.kind === "thinking") { CompanionState.thinking = true; break }
            CompanionState.thinking = false
            CompanionState.addMessage({ id: m.id, who: "companion", kind: m.kind, text: m.text || "", undo: m.undo || "",
                                        action: m.action || null, confirm: m.confirm || null, output: m.output || "",
                                        rows: m.rows || [] })
            // a command run from a button or a keybind, with the drop shut,
            // still says what it did
            if (!CompanionState.dropOpen && m.text)
                CompanionState.showPeek({ key: "chat", line: m.text, level: m.kind === "error" ? "danger" : "info",
                                          actions: m.undo ? [{ id: "undo:" + m.undo, label: "Undo" }] : [], ttl_ms: 0 })
            break
        case "do":
            root.perform(m.id, m.action, m.args || {})
            break
        }
    }

    // ── env and settings: what the daemon cannot see for itself ──────────
    function sendEnv() {
        root.write({
            type: "env",
            locked: Shell.locked,
            dnd: Shell.dnd,
            hypr: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "",
            wayland: Quickshell.env("WAYLAND_DISPLAY") || ""
        })
    }
    function sendSettings() {
        var s = root.settings || {}
        root.write({ type: "settings", provider: s.provider || "none", model: s.model || "", base_url: s.base_url || "" })
    }
    Connections {
        target: Shell
        function onLockedChanged() { root.sendEnv() }
        function onDndChanged() { root.sendEnv() }
    }

    // ── do: what only the shell can do, asked for by a command ───────────
    function done(id, ok, error, data) { root.write({ type: "do.result", id: id, ok: ok, error: error || null, data: data || null }) }
    function perform(id, action, a) {
        switch (action) {
        case "dnd":
            // Globals.dnd is the Quick settings switch itself; Plugin API 4
            // brings Shell.setDnd (PLAN §9) and this becomes that call
            Globals.dnd = !!a.on
            root.done(id, true)
            break
        case "open":
            // a page where the place has pages: a Settings page (Settings
            // 0.18 opens on Appearance whatever it is asked; the reply names
            // the page), a Komble page, a Quick settings tab
            var pg = String(a.page || "")
            var ok = a.what === "settings" ? (Shell.openSettings(pg), true)
                   : a.what === "komble" ? (Shell.openStore(pg), true)
                   : a.what === "quicksettings" ? (Shell.openQuickSettings(pg || "home"), true)
                   : a.what === "overview" ? ((Shell.overviewOpen || Shell.toggleOverview()), true)
                   : a.what === "sync" ? Shell.launch("io.github.prj786.ewe-sync")
                   : a.what === "terminal" ? Shell.launch("kitty")
                   : a.what === "files" ? Shell.launch("nemo") : false
            CompanionState.dropOpen = false
            root.done(id, ok !== false, ok === false ? "That app is not installed." : "")
            break
        case "launch":
            // any installed app, found by the words people use; with a path,
            // the app opens it (a terminal starts in it)
            var e = root.findApp(a.app)
            if (!e) { root.done(id, false, "not-found"); break }
            CompanionState.dropOpen = false
            root.done(id, root.startApp(e, a.path || "", a.dir || ""), "", { name: e.name || a.app })
            break
        case "term":
            // a proposed command the user chose to run in a terminal: kitty
            // shows it, runs it in their shell, and stays open on its result
            CompanionState.dropOpen = false
            Quickshell.execDetached({
                command: ["kitty", "--hold", "--directory", Quickshell.env("HOME"), "bash", "-c",
                          'printf "\\033[2m$ %s\\033[0m\\n" "$1"; bash -c "$1"; s=$?; ' +
                          'printf "\\n\\033[2m[exit %s — close this window when you are done]\\033[0m\\n" "$s"',
                          "ewe-companion", String(a.command || "")],
                workingDirectory: Quickshell.env("HOME")
            })
            root.done(id, true)
            break
        case "screenshot":
            // the drop shuts first, so the shot shows what you were looking at
            CompanionState.dropOpen = false
            shotTimer.mode = a.mode || "region"
            shotTimer.restart()
            root.done(id, true)
            break
        case "browse":
            browser.url = String(a.url || "")
            browser.reqId = id
            browser.running = true
            CompanionState.dropOpen = false
            break
        case "browser":
            // ewe browser's own command line (its docs/CLI.md): open,
            // search, play, a tab. Run here, not by the daemon, because it
            // may start the browser, which then belongs to the desktop. Only
            // ewe-browser, only as argv
            if (String(a.bin || "").split("/").pop() !== "ewe-browser") { root.done(id, false, "Not ewe browser."); break }
            if (bcli.running) { root.done(id, false, "ewe browser is busy."); break }
            bcli.reqId = id
            bcli.command = [String(a.bin)].concat((a.args || []).map(String))
            bcli.running = true
            bcliTimeout.restart()
            CompanionState.dropOpen = false
            break
        case "safe_unlock":
            // Safe's own prompt (`ewe-safe unlock --ask`): the master
            // password is typed there, never into the companion
            if (String(a.bin || "").split("/").pop() !== "ewe-safe") { root.done(id, false, "Not Safe."); break }
            CompanionState.dropOpen = false
            Quickshell.execDetached([String(a.bin), "unlock", "--ask"])
            root.done(id, true)
            break
        default:
            root.done(id, false, "The island cannot do " + action + ".")
        }
    }
    // ── apps: the launcher's index, matched like a person names an app ──
    // Its name ("Visual Studio Code"), its id or the id's last part
    // ("org.gnome.Nautilus" → nautilus), its program ("code"), whole words
    // of its name ("studio code"), whole words of its kind ("File
    // Manager"). Never a loose substring: "open the pod bay doors" must
    // find nothing. The shortest name wins a tie.
    function findApp(words) {
        var raw = String(words || "").trim(), n = raw.toLowerCase()
        if (n === "") return null
        // a desktop id (the daemon's answer for "the browser") is exact
        var direct = DesktopEntries.byId(raw) || DesktopEntries.byId(n)
        if (direct && !direct.noDisplay) return direct
        var all = DesktopEntries.applications.values, best = null, bestS = 0
        for (var i = 0; i < all.length; i++) {
            var e = all[i]
            if (e.noDisplay) continue
            var name = String(e.name || "").toLowerCase()
            var id = String(e.id || "").toLowerCase()
            var seg = id.split(".").pop()
            var cmd = e.command || []
            var bin = cmd.length > 0 ? String(cmd[0]).split("/").pop().toLowerCase() : ""
            var gen = String(e.genericName || "").toLowerCase()
            // whole words only: "code" finds Visual Studio Code, "cod" does not
            var s = name === n ? 100
                  : (id === n || seg === n) ? 95
                  : bin === n ? 90
                  : (" " + name + " ").indexOf(" " + n + " ") >= 0 ? 60
                  : (" " + gen + " ").indexOf(" " + n + " ") >= 0 ? 40 : 0
            if (s > bestS || (s > 0 && s === bestS && name.length < String(best.name || "").length)) { best = e; bestS = s }
        }
        return best
    }
    readonly property var terminals: ["kitty", "foot", "alacritty", "wezterm", "ghostty", "konsole", "gnome-terminal", "xterm", "kgx", "ptyxis"]
    function isTerminal(e) {
        var cats = e.categories || []
        for (var i = 0; i < cats.length; i++) if (String(cats[i]) === "TerminalEmulator") return true
        var cmd = e.command || []
        return cmd.length > 0 && root.terminals.indexOf(String(cmd[0]).split("/").pop()) >= 0
    }
    // No path: focus-or-launch, as a click in the launcher does. A path: a
    // fresh window on it: a terminal starts in its folder (kitty is told
    // so too), a console app runs in kitty there, anything else gets the
    // path as its argument.
    function startApp(e, path, dir) {
        if (path === "") return Shell.launch(e.id)
        var cmd = (e.command || []).slice()
        if (cmd.length === 0) return false
        var argv
        if (root.isTerminal(e)) {
            argv = cmd
            if (String(cmd[0]).split("/").pop() === "kitty") argv = argv.concat(["--directory", dir])
        } else if (e.runInTerminal) {
            argv = ["kitty", "--directory", dir, "-e"].concat(cmd)
        } else {
            argv = cmd.concat([path])
        }
        Quickshell.execDetached({ command: argv, workingDirectory: dir })
        return true
    }

    Timer {
        id: shotTimer
        property string mode: "region"
        interval: Math.max(1, Theme.durBase * 2)
        onTriggered: Quickshell.execDetached(["qs", "ipc", "call", "ewe.screenshot", "shoot", mode])
    }
    // ewe-browser when it is installed (it was built with the companion in
    // mind: its own CLI takes over search and play when it has one), else
    // $EWE_BROWSER, else the default browser. setsid: the page belongs to
    // the desktop, not to this script.
    Process {
        id: browser
        property string url: ""
        property string reqId: ""
        command: ["sh", "-c",
            'u="$1"; if [ -n "$EWE_BROWSER" ]; then echo "$EWE_BROWSER"; setsid "$EWE_BROWSER" "$u" >/dev/null 2>&1 & ' +
            'elif command -v ewe-browser >/dev/null 2>&1; then echo ewe-browser; setsid ewe-browser "$u" >/dev/null 2>&1 & ' +
            'else echo "your browser"; setsid xdg-open "$u" >/dev/null 2>&1 & fi', "sh", url]
        stdout: StdioCollector { id: via }
        onExited: (code) => root.done(browser.reqId, code === 0, code === 0 ? "" : "Could not open the browser.",
                                      { via: via.text.trim() })
    }

    // ewe browser's command line: one JSON object on its last line, which
    // goes back to the daemon as is (it reads `ok`, the line, the undo)
    Process {
        id: bcli
        property string reqId: ""
        stdout: StdioCollector { id: bout }
        onExited: (code) => {
            bcliTimeout.stop()
            var lines = bout.text.split("\n").filter(function (l) { return l.trim() !== "" })
            var reply = null
            try { reply = JSON.parse(lines[lines.length - 1]) } catch (e) {}
            if (reply) root.done(bcli.reqId, true, "", { reply: reply })
            else root.done(bcli.reqId, false, "ewe browser did not answer.")
        }
    }
    // the daemon waits 20 s (its browser.rs ACT); a command line that hangs
    // is stopped after that. A process deadline, not a motion: no token
    Timer {
        id: bcliTimeout
        interval: 25000
        onTriggered: bcli.running = false
    }

    // ── reconnect, starting the daemon when nobody answers ────────────────
    Timer {
        id: retry
        property int attempt: 0
        // 0.5 s, 1 s, 2 s … up to 30 s between tries
        interval: Math.min(30000, 500 * Math.pow(2, Math.min(attempt, 6)))
        running: true
        onTriggered: {
            if (sock.connected) return
            if (attempt === 1 || attempt % 6 === 5) root.ensureDaemon()
            attempt++
            sock.connected = true
            restart()
        }
    }
    function ensureDaemon() {
        // `sh` makes a missing binary a quiet no-op: the notch then says
        // the companion is off
        Quickshell.execDetached(["sh", "-c",
            "systemctl --user start ewe-companion.service 2>/dev/null || exec \"${EWE_COMPANIOND:-ewe-companiond}\""])
    }

    // ── the bar's material behind the notch ───────────────────────────────
    // With Glass on (bar_opacity < 100), ewe blurs only the bar's and the
    // dock's layers (user.lua's ewe-bar-blur, ^quickshell:(bar|dock)$). The
    // notch is the bar's own ground at the same opacity, so without that
    // blur it read as clear glass (owner, 2026-10-14). The plugin gives its
    // own namespace the same rule at runtime, again after every config
    // reload; nothing on disk changes, and with EWE_NO_BLUR (glassBlur
    // false) it adds nothing.
    //
    // xray: the bar sits on the wallpaper (its exclusive zone keeps windows
    // out), the notch hangs over windows. A plain blur showed the window
    // under the notch through the bar's ground, so the notch never matched
    // the bar: a shade darker over a terminal, grey over a light page,
    // worst in light mode (owner, 2026-10-17). With xray the notch blurs the
    // wallpaper, as the bar does, and the two are one material. (xray needs
    // decoration.blur.new_optimizations, which ewe turns on with the blur.)
    function applyBlur() {
        if (!Theme.glassBlur) return
        Quickshell.execDetached(["hyprctl", "eval",
            'hl.layer_rule({ name = "ewe-companion-blur", match = { namespace = "^quickshell:companion$" }, blur = true, ignore_alpha = 0.05, xray = true })'])
    }
    Connections {
        target: Hyprland
        function onRawEvent(ev) { if (ev.name === "configreloaded") root.applyBlur() }
    }
    Connections {
        target: Theme
        function onGlassBlurChanged() { root.applyBlur() }
    }

    Component.onCompleted: {
        Log.debug("ewe.companion", "service up; socket " + sock.path)
        root.applyBlur()
        sock.connected = true
    }
}
