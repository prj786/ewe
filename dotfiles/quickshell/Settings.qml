import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Settings — the in-shell settings window (Super+, · the Quick settings gear
// · Launcher "Settings") for a machine without the ewe-settings app. A real
// toplevel window (movable/resizable/closable): the side navigation on the
// window's ground, the page in a raised pane (design system: App shell,
// Side navigation, Settings page, Look presets, Accessibility modes).
// Panes: System, Displays, Network, Default apps, Keyboard and mouse,
// Shortcuts, Layout, Appearance, Wallpaper, Screensaver, Power, Dock,
// Startup, User, Accessibility. Tokens only: every colour, size, radius and
// duration is a Theme role.
//
// Hyprland is Lua-configured, so live changes go through `hyprctl eval 'hl…'`
// (plain `hyprctl keyword` is rejected). Persistent changes are written to
// ~/.config/hypr/generated/user.lua (sourced last by hyprland.lua).
Scope {
    id: root

    function g(c) { return String.fromCodePoint(c) }
    readonly property string home: Quickshell.env("HOME")

    property int pane: 0
    // key is the stable identity: probe triggers and the pane component are
    // looked up by it, so inserting a nav item never silently renumbers others
    // `desc` is the page's one-line description (Settings page card). The
    // ORDER is public: `qs ipc call settings pane N` deep-links by index, so
    // a new page goes at the end (Accessibility did).
    readonly property var navItems: [
        { key: "system",    ic: 0xE0A9, label: "System",        desc: "Sound, desktop portals and the state of this machine." },
        { key: "displays",  ic: 0xE11D, label: "Displays",      desc: "Arrange your displays and choose how they look." },
        { key: "network",   ic: 0xE1AE, label: "Network",       desc: "Wired, Wi-Fi, VPN and SSH connections." },
        { key: "defaults",  ic: 0xE426, label: "Default apps",  desc: "The apps that open links, mail, text, pictures, video and folders." },
        { key: "input",     ic: 0xE284, label: "Keyboard and mouse", desc: "Layouts, typing, the pointer and the touchpad." },
        { key: "shortcuts", ic: 0xE09A, label: "Shortcuts",     desc: "Every keyboard shortcut on this desktop." },
        { key: "layout",    ic: 0xE1C1, label: "Layout",        desc: "Space between windows, their border and their corners." },
        { key: "theme",     ic: 0xE1DD, label: "Appearance",    desc: "Scheme, accent color, corners, density and the bar." },
        { key: "wallpaper", ic: 0xE0F6, label: "Wallpaper",     desc: "Pictures and videos behind your windows." },
        { key: "saver",     ic: 0xE410, label: "Screensaver",   desc: "What happens when you step away." },
        { key: "power",     ic: 0xE140, label: "Power",         desc: "The lid, the battery and what keeps this machine awake." },
        { key: "dock",      ic: 0xE4CF, label: "Dock",          desc: "The launcher, Overview and workspaces at the bottom." },
        { key: "startup",   ic: 0xE286, label: "Startup",       desc: "Apps that start when you sign in." },
        { key: "user",      ic: 0xE19F, label: "User",          desc: "Your name, your picture and your accounts." },
        { key: "accessibility", ic: 0xE297, label: "Accessibility", desc: "Motion, transparency, contrast and text size for the whole desktop." }
    ]
    readonly property string paneKey: navItems[pane].key
    // Run the active pane's probes. Called on pane change AND on window open —
    // reopening onto a remembered pane must re-probe too, or that pane shows
    // stale/never-loaded data forever ("Checking…", "—" session facts).
    function paneProbes() {
        var k = root.paneKey
        if (k === "displays") HyprMon.refresh()
        else if (k === "network") { wifiDevProbe.running = true; wifiState.running = true; wifiScan.running = true; vpnScan.running = true; netProc.running = true; sshProc.running = true }
        else if (k === "input") { inputProbe.running = true; devProbe.running = true; perWinProbe.running = true }
        else if (k === "shortcuts") scProc.running = true
        else if (k === "layout") layoutProc.running = true
        else if (k === "wallpaper") { wpBackendProbe.running = true; wpConfLoad.running = true; HyprMon.refresh(); if (root.wpDir === "") wpDirProbe.running = true; else root.wpList(root.wpDir) }
        else if (k === "saver") { saverToolProbe.running = false; saverToolProbe.running = true }
        else if (k === "power") { Power.refresh(); Logind.refreshBrightness(); Logind.refreshInhibitors() }
        else if (k === "startup") { saLoad.running = false; saLoad.running = true }
        else if (k === "user") { Globals.recheckFace(); userInfoProbe.running = false; userInfoProbe.running = true; Cloud.refresh(); Google.refresh(); Mail.probe(); Accounts.refresh() }
    }
    onPaneChanged: root.paneProbes()

    // ── startup applications (Settings → Startup; launched by autostart.sh) ────
    property var startupApps: []          // [{name, exec, icon, enabled}]
    property string startupQuery: ""
    property Process saWriter: Process {}
    property Process saLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/startup-apps.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { var j = JSON.parse(this.text); if (j && Array.isArray(j.apps)) root.startupApps = j.apps } catch (e) {}
            }
        }
    }
    function saveStartup() {
        // RFC-001: persist through ewe-conf (regenerates startup-apps.json)
        root.saWriter.command = [Globals.eweConf, "set", "--no-hooks", "apps.startup", JSON.stringify(root.startupApps)]
        root.saWriter.running = false; root.saWriter.running = true
    }
    function startupAdd(name, exec, icon) {
        var a = root.startupApps.slice()
        for (var i = 0; i < a.length; i++) if (a[i].exec === exec) return   // no dupes
        a.push({ name: name, exec: exec, icon: icon || "", enabled: true })
        root.startupApps = a; root.saveStartup()
    }
    function startupRemove(idx) {
        var a = root.startupApps.slice(); a.splice(idx, 1)
        root.startupApps = a; root.saveStartup()
    }
    function startupToggle(idx) {
        var a = JSON.parse(JSON.stringify(root.startupApps))
        a[idx].enabled = a[idx].enabled === false
        root.startupApps = a; root.saveStartup()
    }
    // desktop-entry Exec strings carry %-field codes (%U, %f…) — strip for sh -c
    function cleanExec(s) { return String(s || "").replace(/%[a-zA-Z]/g, "").trim() }

    // ── persisted override state ───────────────────────────────────────────────
    // hyprland.lua's shipped values (Window card): window-gap around the
    // screen, half of it between windows, a border-width-2 ring and the
    // `rounded` corner. The live values replace these once layoutProc runs.
    property int  gapsIn: Theme.spaceXs
    property int  gapsOut: Theme.windowGap
    property int  borderSize: Theme.borderWidth2
    property int  rounding: Theme.radiusRounded   // decoration.rounding (window corner radius)

    function hex6(c) { var s = String(c).replace("#", ""); return s.length === 8 ? s.slice(2) : s }

    // Tiling off = one catch-all float rule, so new windows behave the way they do
    // on a stacking desktop. Emitted only when off: absent means the Hyprland
    // default, which is what "tiling on" is.
    function tilingLua() {
        return Globals.tilingEnabled ? ""
             : 'hl.window_rule({ name = "float-all", match = { class = ".*" }, float = true })\n'
    }
    // A window rule cannot be withdrawn at runtime — `hyprctl keyword` only ever
    // ADDS one — so switching tiling back on has to go through a config reload.
    // Both directions reload, so the live state always matches the file.
    function setTiling(on) {
        Globals.tilingEnabled = on
        root.writePrefs()
        // Sync gaps/border/rounding from the LIVE compositor before rewriting
        // user.lua. This component's cached values are the shipped defaults
        // until its window has opened (layoutProc only runs on open) — and with
        // the standalone settings app installed it never opens, so an unsynced
        // write clobbered the user's layout on every tiling toggle.
        root.syncedWriteOverrides("hyprctl reload")
    }
    // run layoutProc first, then writeOverrides(after) once its values land
    property var _syncAfter: false
    function syncedWriteOverrides(after) { root._syncAfter = [after]; layoutProc.running = true }

    // RFC-001 Phase 4 (0.6): user.lua is an ewe-conf build artifact — the pane
    // sends only the four layout numbers; tint/accent/transparency/speed/
    // tiling flow in from their own conf domains. transparencyLua/
    // animLuaLines/tilingLua above remain for the live hyprctl eval only.
    function writeOverrides(after) {
        if (HyprMon.virtualSession) return   // same guard as atomicWrite
        var payload = JSON.stringify({ gaps_in: root.gapsIn, gaps_out: root.gapsOut,
                                       border_size: root.borderSize, rounding: root.rounding })
        luaWriter.command = ["sh", "-c",
            '"$HOME/.config/quickshell/../../bin/ewe-conf" set --no-hooks desktop.layout "$1"'
            + (after ? " && " + after : ""),
            "qs-settings", payload]
        luaWriter.running = false; luaWriter.running = true
    }
    // window transparency: hyprland.lua ships inactive_opacity 0.97; the toggle
    // forces full opacity. Always emitted so flipping it back re-applies 0.97.
    function transparencyLua() {
        return "hl.config({ decoration = { active_opacity = 1.0, inactive_opacity = "
             + (Globals.windowTransparency ? "0.97" : "1.0") + " } })"
    }
    function setTransparency(on) {
        Globals.windowTransparency = on
        root.writePrefs()
        root.syncedWriteOverrides()   // same stale-layout hazard as setTiling
        Quickshell.execDetached(["hyprctl", "eval", root.transparencyLua()])
    }
    Process { id: luaWriter }
    Process { id: jsonWriter }
    // Shape & density writer. Hooks stay ON here (unlike the panes that write
    // their own artifacts): `ewe-conf set desktop.theme.*` has to re-run
    // `ewe-theme build` and poke the shell, or the change sits in the file
    // and nothing on screen moves.
    Process { id: shapeWriter }
    function shapeWrite(argv) { shapeWriter.running = false; shapeWriter.command = argv; shapeWriter.running = true }
    // One ewe.conf key, hooks on (the theme hook rebuilds the tokens and the
    // shell follows): the look presets, the bar, Glass and the accessibility
    // modes, which live only in ewe.conf.
    function confSet(key, value) { root.shapeWrite([Globals.eweConf, "set", key, String(value)]) }
    // Schemes: the built-ins and the person's own, from `ewe-theme scheme
    // list`; picking one runs `scheme apply` (it writes ewe.conf through
    // ewe-conf with hooks, so the desktop follows).
    readonly property string eweTheme: Globals.eweConf.replace(/ewe-conf$/, "ewe-theme")
    property var schemeOptions: [{ label: "Ewe Dark", value: "ewe-dark" }, { label: "Ewe Light", value: "ewe-light" }]
    property Process _schemeList: Process {
        running: true
        command: [root.eweTheme, "scheme", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text), o = []
                    for (var i = 0; i < (j.schemes || []).length; i++)
                        o.push({ label: j.schemes[i].name + (j.schemes[i].variant === "light" ? " (light)" : " (dark)"), value: j.schemes[i].slug })
                    if (o.length) root.schemeOptions = o
                } catch (e) {}
            }
        }
    }
    function applyScheme(slug) { root.shapeWrite([root.eweTheme, "scheme", "apply", slug]); schemeRelist.restart() }
    Timer { id: schemeRelist; interval: 1500; onTriggered: { root._schemeList.running = false; root._schemeList.running = true } }
    // A key's current value, as the generator read it (theme-tokens.json).
    function tokIn(k, fb) { var v = Globals.tokInput ? Globals.tokInput[k] : undefined; return (v === undefined || v === null) ? fb : v }

    // ── Animations (speed multiplier → Hyprland animation overrides) ────────────
    // Scaling the per-leaf `speed` (duration in ds): higher multiplier → smaller
    // speed → faster. m=0 disables animations entirely.
    // Mirrors hyprland.lua's shipped block (and ANIM_BASE in ewe-settings'
    // hypr.js) — the three must change together.
    readonly property var animBase: [
        { leaf: "global",     s: 3,   bz: "snap" },
        { leaf: "border",     s: 3,   bz: "easeOutQuint" },
        { leaf: "windows",    s: 2.8, bz: "snap",  style: "popin 92%" },
        { leaf: "windowsOut", s: 1.8, bz: "quick", style: "popin 92%" },
        { leaf: "fade",       s: 1.8, bz: "quick" },
        { leaf: "layers",     s: 2,   bz: "quick", style: "fade" },
        { leaf: "workspaces", s: 2.8, bz: "snap",  style: "slide" }
    ]
    function animLuaLines(m) {
        var L = []
        if (m <= 0) { L.push("hl.config({ animations = { enabled = false } })"); return L }
        L.push("hl.config({ animations = { enabled = true } })")
        for (var i = 0; i < root.animBase.length; i++) {
            var a = root.animBase[i], sp = (a.s / m).toFixed(2)
            var s = 'hl.animation({ leaf = "' + a.leaf + '", enabled = true, speed = ' + sp
            if (a.spring) s += ', spring = "' + a.spring + '"'
            if (a.bz) s += ', bezier = "' + a.bz + '"'
            if (a.style) s += ', style = "' + a.style + '"'
            L.push(s + ' })')
        }
        return L
    }
    // persisted form: empty at default speed (let hyprland.lua's defaults stand)
    function animBlockPersist() {
        var m = Globals.animationSpeed
        return Math.abs(m - 1) < 0.001 ? "" : (root.animLuaLines(m).join("\n") + "\n")
    }
    // live-apply: one `hyprctl eval` per statement (the known-good single-call form)
    function applyAnimations() {
        var sh = root.animLuaLines(Globals.animationSpeed).map(function (c) { return "hyprctl eval '" + c + "'" }).join("; ")
        Quickshell.execDetached(["sh", "-c", sh])
        root.writeOverrides()
    }
    function setAnim(m) { Globals.animationSpeed = m; root.writePrefs(); root.applyAnimations() }

    // ── Layout (gaps/border/corner radius) — one hyprctl eval per statement
    //    (the known-good form; multi-statement evals don't apply) ────────────────
    function applyGaps() {
        var L = [
            "hl.config({ general = { gaps_in = " + root.gapsIn + ", gaps_out = " + root.gapsOut
                + ", border_size = " + root.borderSize + " } })",
            "hl.config({ decoration = { rounding = " + root.rounding + " } })"
        ]
        // NOTE: nothing to do for window groups here. Grouped windows are held
        // square by group-theme.lua and ungrouped ones are left on `unset`,
        // which means "follow decoration.rounding" — so this slider reaches
        // them on its own.
        Quickshell.execDetached(["sh", "-c", L.map(function (c) { return "hyprctl eval '" + c + "'" }).join("; ")])
        root.writeOverrides()
    }

    // ── shell prefs (accent + dock) persisted to user-theme.json ──────────────────
    // MERGED over whatever is already on disk, not written fresh. The standalone
    // Settings app writes this same file, and a newer one knows keys this shell
    // does not — emitting only our own keys would delete theirs on the next save.
    // JSON.stringify rather than string concatenation so a value containing a
    // quote produces valid JSON instead of a file nothing can parse.
    function writePrefs() {
        var o = {}
        var k
        for (k in Globals.prefsRaw) o[k] = Globals.prefsRaw[k]
        o.themeName = Globals.themeName
        o.accent = String(Globals.accentColor)
        o.tintBorders = Globals.tintBorders
        o.windowTransparency = Globals.windowTransparency
        o.dockEnabled = Globals.dockEnabled
        o.dockAutohide = Globals.dockAutohide
        o.dockIconSize = Globals.dockIconSize
        o.animationSpeed = Number(Globals.animationSpeed)
        o.colorScheme = Globals.colorScheme
        o.avatarShape = Globals.avatarShape
        o.lidDockedSuspend = Globals.lidDockedSuspend
        o.lowPowerEnabled = Globals.lowPowerEnabled
        o.tilingEnabled = Globals.tilingEnabled
        o.eventSounds = Globals.eventSounds
        // merge into any existing saver block for the same reason
        var sv = {}
        if (Globals.prefsRaw && Globals.prefsRaw.saver) for (k in Globals.prefsRaw.saver) sv[k] = Globals.prefsRaw.saver[k]
        sv.enabled = Globals.saverEnabled
        sv.min = Number(Globals.saverMin)
        sv.style = Globals.saverStyle
        sv.lock = Globals.saverLock
        sv.lockAfterMin = Number(Globals.saverLockAfterMin)
        o.saver = sv
        Globals.prefsRaw = o        // keep the cache in step with the file
        // RFC-001: persist through ewe-conf — `absorb user-theme` owns the
        // user-theme→ewe.conf key mapping and regenerates user-theme.json.
        jsonWriter.command = [Globals.eweConf, "absorb", "--no-hooks", "user-theme", JSON.stringify(o)]
        jsonWriter.running = false; jsonWriter.running = true
    }

    // ── Screensaver → generated hypridle.conf (hypridle owns all idle timing).
    // Mirrors the shipped dotfiles/hypr/hypridle.conf defaults, adds the saver
    // stage, then restarts hypridle on the new config. autostart.sh prefers the
    // generated file when it exists.
    // On battery every stage lands sooner — the point of the low-power setting is
    // that an unplugged machine should not sit lit and awake for the same five
    // minutes a docked one does. hypridle's config is static, so the timeline is
    // regenerated (and hypridle restarted) when the power source changes.
    readonly property real idleScale: Globals.lowPower ? 0.5 : 1.0
    readonly property int idleGraceSec: Globals.lowPower ? 10 : 20
    function idleAt(sec) { return Math.max(30, Math.round(sec * root.idleScale)) }
    // Describes the timeline the generator above actually produces. This used to
    // be a hardcoded string that lied the moment anyone touched the Screensaver
    // pane, and lied again once the battery timeline existed.
    function idlePolicyText() {
        var mins = function (m) { return Math.max(0.5, Math.round(m * root.idleScale * 10) / 10) }
        var parts = []
        if (Globals.saverEnabled && !Globals.saverLock) {
            parts.push("screensaver at " + mins(Globals.saverMin) + " min")
            parts.push(Globals.saverLockAfterMin > 0
                ? "lock at " + mins(Globals.saverMin + Globals.saverLockAfterMin) + " min"
                : "no automatic lock")
        } else if (Globals.saverEnabled) {
            parts.push("lock at " + mins(Globals.saverMin) + " min")
        } else {
            parts.push("lock at " + mins(5) + " min")
        }
        parts.push("suspend at 15 min on battery")
        parts.push("the display stays on")
        return parts.join(" · ") + (Globals.lowPower ? " (on battery)" : "")
    }
    property Connections _idlePowerHook: Connections {
        target: Globals
        function onLowPowerChanged() { root.writeIdleConf() }
    }

    function writeIdleConf() {
        var lockCmd = "qs ipc call lock lock"
        var undim = "qs ipc call saver undim"
        // before_sleep_cmd is kept as a FALLBACK only: the shell's logind delay
        // inhibitor (Logind.qml) is what actually locks before suspend now, and
        // it does so with a handshake rather than a race. Locking twice is
        // idempotent, so leaving hypridle's belt alongside our braces is free.
        var s = "# AUTO-GENERATED by the Quickshell Settings app (Screensaver pane). Do not edit by hand.\n"
              + "# Timeline is " + (Globals.lowPower ? "BATTERY (shortened)" : "AC") + ".\n"
              + "general {\n"
              + "    lock_cmd         = " + lockCmd + "\n"
              + "    before_sleep_cmd = " + lockCmd + "\n"
              + "    after_sleep_cmd  = hyprctl dispatch 'hl.dsp.dpms(\"on\")'\n"
              + "    ignore_dbus_inhibit = false\n"
              + "}\n"
        var saverSec = root.idleAt(Math.max(60, Math.round(Globals.saverMin * 60)))
        // first stage that actually takes the screen away — the dim leads it
        var firstSec = (Globals.saverEnabled ? saverSec : root.idleAt(300))
        var dimSec = Math.max(20, firstSec - root.idleGraceSec)
        s += "listener {\n    timeout    = " + dimSec + "\n    on-timeout = qs ipc call saver dim\n    on-resume  = " + undim + "\n}\n"
        if (Globals.saverEnabled && !Globals.saverLock) {
            s += "listener {\n    timeout    = " + saverSec + "\n    on-timeout = qs ipc call saver show\n    on-resume  = qs ipc call saver hide\n}\n"
            if (Globals.saverLockAfterMin > 0)
                s += "listener {\n    timeout    = " + (saverSec + root.idleAt(Globals.saverLockAfterMin * 60)) + "\n    on-timeout = " + lockCmd + "\n    on-resume  = " + undim + "\n}\n"
        } else if (Globals.saverEnabled && Globals.saverLock) {
            s += "listener {\n    timeout    = " + saverSec + "\n    on-timeout = " + lockCmd + "\n    on-resume  = " + undim + "\n}\n"
        } else {
            // saver off → the stock 5-minute auto-lock stays
            s += "listener {\n    timeout    = " + root.idleAt(300) + "\n    on-timeout = " + lockCmd + "\n    on-resume  = " + undim + "\n}\n"
        }
        // idle-suspend.sh still checks AC itself — belt and braces, because this
        // file can be stale for the moments between a plug event and the restart.
        // Deliberately NOT battery-shortened: suspend is the one stage the user
        // walks into blind (black screen, mouse can't wake s2idle — only keys
        // can), so it stays at the documented 15 min instead of a surprise 7.5.
        s += "listener {\n    timeout    = 900\n    on-timeout = ~/.config/hypr/scripts/idle-suspend.sh\n}\n"
        root.atomicWrite(idleWriter, root.home + "/.config/hypr/generated/hypridle.conf", s)
        if (!HyprMon.virtualSession) idleRestartDebounce.restart()
    }
    // Debounced: a dock plug/unplug flaps AC several times in seconds, and every
    // flap lands here via onLowPowerChanged. Two overlapping pkill+relaunch shells
    // race — the second pkill kills the first relaunch mid-sleep — which is how
    // hypridle ended up dead (no idle lock, all app inhibits ignored) on
    // 2026-08-13/14. Coalesce to one restart, and guard the start with pgrep so
    // it can never double-spawn.
    Timer {
        id: idleRestartDebounce
        interval: 2000
        onTriggered: {
            // restarting hypridle orphans any dim it fired (the new instance
            // never sends that on-resume) — clear it or the overlay sticks
            Globals.saverDimming = false
            // the small sleep lets the atomic temp+rename land before hypridle reads it
            Quickshell.execDetached(["sh", "-c", 'pkill -x hypridle; sleep 0.6; pgrep -x hypridle >/dev/null || exec hypridle -c "$HOME/.config/hypr/generated/hypridle.conf" >/dev/null 2>&1'])
        }
    }
    Process { id: idleWriter }
    function saverChanged() { root.writePrefs(); root.writeIdleConf() }
    property bool hypridleOk: true
    Process { id: saverToolProbe; command: ["sh", "-c", "command -v hypridle >/dev/null && echo yes || echo no"]; stdout: StdioCollector { onStreamFinished: root.hypridleOk = this.text.trim() === "yes" } }
    function setAccent(hex) {
        Globals.accentColor = hex
        root.writePrefs()
        if (Globals.tintBorders) root.applyBorder()
        root.applyAppColors()      // re-tint Qt/KDE apps to the new accent
    }
    // re-apply the GTK/Qt/KDE appearance (scheme + accent) to external apps
    function applyAppColors() {
        Quickshell.execDetached(["sh", "-c", "\"" + root.home + "/.config/quickshell/scripts/colorscheme.sh\" "
            + Globals.colorScheme + " " + String(Theme.accent).replace("#", "")])
    }
    // Live-only: the border COLOUR is theme state (ewe-conf's gen_user_lua
    // emits it from tint_borders + accent), not one of the four layout
    // numbers. This used to also call writeOverrides(), which wrote this
    // pane's CACHED gaps/border/rounding back into desktop.layout — and
    // right after a restore those were the pre-restore values (layoutProc
    // only runs on open), so the restored layout was clobbered on disk and
    // then auto-pushed to Drive. 0.9.16-2.
    function applyBorder() {
        if (Globals.tintBorders)
            Quickshell.execDetached(["hyprctl", "eval",
                "hl.config({ general = { col = { active_border = \"rgba(" + root.hex6(Theme.accent) + "ff)\" } } })"])
    }

    // ── Displays — state, apply, persistence and the hotplug/power guard all ──
    //    live in the HyprMon singleton; this is only the UI-side glue.
    function isLaptop(m) { return ((m && m.name) ? m.name : "").toLowerCase().indexOf("edp") >= 0 }
    // reactive snapshot of the current spec list (re-evaluates with HyprMon state)
    readonly property var dispSpecs: HyprMon.snapshot()
    property string errorMsg: ""        // inline error banner (dismissable)
    property string appliedMsg: ""      // transient "Applied" confirmation
    property var revertSpecs: null      // pre-change snapshot while confirm-or-revert is up
    property var keepSpecs: null
    property int revertLeft: 0

    function flashApplied(msg) { root.appliedMsg = msg || "Saved"; appliedClear.restart() }
    function clearError() { root.errorMsg = ""; HyprMon.lastError = "" }
    Timer { id: appliedClear; interval: 2200; onTriggered: root.appliedMsg = "" }
    Timer {
        id: revertCountdown; interval: 1000; repeat: true
        onTriggered: { root.revertLeft--; if (root.revertLeft <= 0) root.doRevert() }
    }
    Connections { target: HyprMon; function onLastErrorChanged() { if (HyprMon.lastError !== "") root.errorMsg = HyprMon.lastError } }

    // logical (scaled, rotation-aware) size of a spec
    function specW(s) { var p = HyprMon.modeRes(s.mode).split("x"); var w = (s.transform % 2) ? p[1] : p[0]; return Math.max(1, Math.round(w / s.scale)) }
    function specH(s) { var p = HyprMon.modeRes(s.mode).split("x"); var h = (s.transform % 2) ? p[0] : p[1]; return Math.max(1, Math.round(h / s.scale)) }
    function specsWith(name, patch) {
        var specs = HyprMon.snapshot()
        for (var i = 0; i < specs.length; i++) if (specs[i].name === name) for (var k in patch) specs[i][k] = patch[k]
        return specs
    }
    // resolution → refresh-rate map from a monitor's availableModes; the current
    // mode is seeded first so it is always selectable (virtual outputs report no
    // mode list at all)
    function modeMapFor(m, spec) {
        var am = (m && m.availableModes) ? m.availableModes.slice() : []
        if (spec && spec.mode) am.unshift(spec.mode)
        var byRes = {}, resList = []
        for (var i = 0; i < am.length; i++) {
            var s = String(am[i]).replace(/Hz$/i, "")
            var res = s.split("@")[0], hz = parseFloat(s.split("@")[1] || "60")
            if (!byRes[res]) { byRes[res] = []; resList.push(res) }
            var dup = false
            for (var j = 0; j < byRes[res].length; j++) if (Math.round(byRes[res][j].hz) === Math.round(hz)) { dup = true; break }
            if (!dup) byRes[res].push({ hz: hz, mode: res + "@" + hz.toFixed(2), label: Math.round(hz) + " Hz" })
        }
        resList.sort(function (a, b) { var pa = a.split("x"), pb = b.split("x"); return (pb[0] * pb[1]) - (pa[0] * pa[1]) })
        for (var r in byRes) byRes[r].sort(function (a, b) { return b.hz - a.hz })
        return { resList: resList, byRes: byRes }
    }

    // risky changes (mode / scale / rotate / mirror / enable): apply live, then a
    // 10 s confirm-or-revert dialog — timeout restores the previous known-good
    // state, so a blacked-out screen always comes back by itself.
    function riskyChange(name, patch) {
        var prev = HyprMon.snapshot()
        var next = root.specsWith(name, patch)
        root.revertSpecs = prev; root.keepSpecs = next; root.revertLeft = 10
        HyprMon.applySpecs(next, function (ok) {
            if (ok) revertCountdown.restart()
            else { root.revertSpecs = null; root.keepSpecs = null; HyprMon.applySpecs(prev) }
        })
    }
    function keepChange() {
        revertCountdown.stop()
        root.revertSpecs = null; root.keepSpecs = null
        // commit what is actually live (re-queried after the apply) rather than
        // the requested specs — so e.g. a "preferred" mode used to re-enable a
        // display is stored as the explicit mode the compositor picked
        HyprMon.commit(HyprMon.snapshot()); root.flashApplied("Display settings kept")
    }
    function doRevert() {
        revertCountdown.stop()
        var s = root.revertSpecs; root.revertSpecs = null; root.keepSpecs = null
        if (s) HyprMon.applySpecs(s)
    }
    // safe changes (VRR / bit depth): apply + persist straight away
    function directChange(name, patch) {
        var next = root.specsWith(name, patch)
        HyprMon.applySpecs(next, function (ok) { if (ok) { HyprMon.commit(next); root.flashApplied() } })
    }
    function applyPositions(specs) {
        HyprMon.applySpecs(specs, function (ok) { if (ok) { HyprMon.commit(specs); root.flashApplied("Layout saved") } })
    }
    function setPrimary(name) {
        var specs = HyprMon.snapshot()
        for (var i = 0; i < specs.length; i++) specs[i].primary = (specs[i].name === name)
        HyprMon.commit(specs); root.flashApplied("Primary display changed")
    }
    function autoArrange() {
        var all = HyprMon.snapshot()
        var specs = all.filter(function (s) { return !s.disabled })
        specs.sort(function (a, b) { return (b.primary - a.primary) || (a.x - b.x) })
        var x = 0
        for (var i = 0; i < specs.length; i++) { specs[i].x = x; specs[i].y = 0; x += root.specW(specs[i]) }
        root.applyPositions(all)
    }
    // drag-drop snapping: dock the dragged monitor to the nearest edge of another
    // rectangle, forbid overlaps and gaps, then normalise the layout to 0,0
    function snapDrop(name, dropX, dropY) {
        var all = HyprMon.snapshot()
        var specs = all.filter(function (s) { return !s.disabled })
        var d = null, others = []
        for (var i = 0; i < specs.length; i++) { if (specs[i].name === name) d = specs[i]; else others.push(specs[i]) }
        if (!d) return
        if (!others.length) { d.x = 0; d.y = 0; root.applyPositions(all); return }
        var dw = root.specW(d), dh = root.specH(d)
        function overlaps(x, y) {
            for (var j = 0; j < others.length; j++) {
                var o = others[j], ow = root.specW(o), oh = root.specH(o)
                if (x < o.x + ow && x + dw > o.x && y < o.y + oh && y + dh > o.y) return true
            }
            return false
        }
        function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
        var best = null, bestD = Infinity, minC = 48   // required shared-edge contact (logical px)
        for (var j = 0; j < others.length; j++) {
            var o = others[j], ow = root.specW(o), oh = root.specH(o)
            var cands = [
                { x: o.x + ow, y: clamp(dropY, o.y - dh + minC, o.y + oh - minC) },   // right of o
                { x: o.x - dw, y: clamp(dropY, o.y - dh + minC, o.y + oh - minC) },   // left of o
                { y: o.y + oh, x: clamp(dropX, o.x - dw + minC, o.x + ow - minC) },   // below o
                { y: o.y - dh, x: clamp(dropX, o.x - dw + minC, o.x + ow - minC) }    // above o
            ]
            for (var c = 0; c < cands.length; c++) {
                var p = cands[c]
                // magnetic edge alignment when close to the anchor's edges
                if (Math.abs(p.y - o.y) < 64) p.y = o.y
                else if (Math.abs((p.y + dh) - (o.y + oh)) < 64) p.y = o.y + oh - dh
                if (Math.abs(p.x - o.x) < 64) p.x = o.x
                else if (Math.abs((p.x + dw) - (o.x + ow)) < 64) p.x = o.x + ow - dw
                if (overlaps(p.x, p.y)) continue
                var dist = (p.x - dropX) * (p.x - dropX) + (p.y - dropY) * (p.y - dropY)
                if (dist < bestD) { bestD = dist; best = p }
            }
        }
        if (!best) return
        d.x = Math.round(best.x); d.y = Math.round(best.y)
        var mx = Infinity, my = Infinity
        for (i = 0; i < specs.length; i++) { mx = Math.min(mx, specs[i].x); my = Math.min(my, specs[i].y) }
        for (i = 0; i < specs.length; i++) { specs[i].x -= mx; specs[i].y -= my }
        root.applyPositions(all)
    }

    // ── Default apps ──────────────────────────────────────────────────────────
    property var defaults: ({})        // current default desktop-id per category
    property var appChoices: ({})      // category → [desktop-ids] that handle it (gio)
    readonly property var appCats: [
        { key: "Browser",      ic: 0xE0E8, mime: "x-scheme-handler/https", mimes: ["x-scheme-handler/https", "x-scheme-handler/http", "text/html"] },
        { key: "Mail",         ic: 0xE10F, mime: "x-scheme-handler/mailto", mimes: ["x-scheme-handler/mailto"] },
        { key: "Text Editor",  ic: 0xE0CC, mime: "text/plain", mimes: ["text/plain"] },
        { key: "Image Viewer", ic: 0xE0F6, mime: "image/png", mimes: ["image/png", "image/jpeg", "image/gif", "image/webp"] },
        { key: "Video Player", ic: 0xE0D0, mime: "video/mp4", mimes: ["video/mp4", "video/x-matroska", "video/webm"] },
        { key: "File Manager", ic: 0xE0D7, mime: "inode/directory", mimes: ["inode/directory"] }
    ]
    function entryForId(id) {
        var want = String(id || "").replace(/\.desktop$/, "")
        var apps = DesktopEntries.applications ? DesktopEntries.applications.values : []
        for (var i = 0; i < apps.length; i++) if (apps[i] && apps[i].id === want) return apps[i]
        return null
    }
    function appNameForId(id) { var e = root.entryForId(id); return e ? (e.name || e.id) : (id ? id.replace(/\.desktop$/, "") : "—") }
    function setDefaultApp(cat, deskId) {
        var c = null
        for (var i = 0; i < root.appCats.length; i++) if (root.appCats[i].key === cat) c = root.appCats[i]
        if (!c) return
        var cmd = ""
        for (var m = 0; m < c.mimes.length; m++) cmd += "xdg-mime default '" + deskId + "' '" + c.mimes[m] + "'; "
        if (cat === "Browser") cmd += "xdg-settings set default-web-browser '" + deskId + "'; "
        Quickshell.execDetached(["sh", "-c", cmd])
        defRefresh.restart()
    }

    // ── Networking ──────────────────────────────────────────────────────────────
    property var wifiList: []
    property bool wifiOn: true
    property bool hasWifi: true     // false when no wifi device exists (e.g. a VM)
    readonly property var wiredList: (root.netActive || []).filter(function (c) { return (c.type || "").indexOf("ethernet") >= 0 })
    property string pwTarget: ""
    property string pwText: ""
    property var vpnList: []
    property var netActive: []     // [{name,type,dev,state}]
    property var ipList: []        // ["wlo1: 192.168.x/24"]
    property var sshHosts: []
    function connectWifi(ssid, sec) {
        if (sec && sec !== "" && root.pwText === "") { root.pwTarget = (root.pwTarget === ssid) ? "" : ssid; return }
        var cmd = ["nmcli", "device", "wifi", "connect", ssid]
        if (root.pwText !== "") cmd = cmd.concat(["password", root.pwText])
        Quickshell.execDetached(cmd); root.pwTarget = ""; root.pwText = ""; wifiRescan.restart()
    }

    // ── refresh probes ────────────────────────────────────────────────────────
    function refresh() { diagProc.running = true; layoutProc.running = true; HyprMon.refresh(); defProc.running = true; choicesProc.running = true; root.paneProbes() }
    Connections { target: Globals; function onSettingsOpenChanged() { if (Globals.settingsOpen) root.refresh() } }
    // applyColorScheme() is already done by the reader itself; the border is not,
    // because it is Hyprland state rather than toolkit state. A prefs reload
    // usually means a restore/apply just rewrote the runtime files: re-read the
    // live layout numbers FIRST, so nothing in this pane can write stale ones.
    Connections { target: Globals; function onPrefsReloaded() { layoutProc.running = true; root.applyBorder() } }
    // Quick Settings toggles tiling by flipping the Globals bool (the in-shell
    // idiom); persisting and applying it belongs here, with the other generators.
    Connections {
        target: Globals
        function onTilingEnabledChanged() {
            // The prefs reader assigns this bool at startup too. Acting on that
            // would rewrite user.lua and `hyprctl reload` on every single login,
            // so only react when the value actually diverges from the file —
            // prefsRaw is assigned before the individual keys, so it is the
            // on-disk truth at this point.
            var onDisk = (Globals.prefsRaw && Globals.prefsRaw.tilingEnabled !== undefined)
                       ? Globals.prefsRaw.tilingEnabled : true
            if (Globals.tilingEnabled !== onDisk) root.setTiling(Globals.tilingEnabled)
        }
    }
    // IPC lives in IpcHub.qml (always resident — this panel is lazy-loaded).
    // Deep-links arrive through Globals.settingsPaneRequest.
    function _consumePaneRequest() {
        var n = Globals.settingsPaneRequest
        if (n === -1) return
        Globals.settingsPaneRequest = -1
        if (n === -2) {
            for (var i = 0; i < root.navItems.length; i++) if (root.navItems[i].key === "wallpaper") root.pane = i
            root.wallpaperBrowseRequested()
        } else
            root.pane = Math.max(0, Math.min(root.navItems.length - 1, n))
    }
    Component.onCompleted: root._consumePaneRequest()
    Connections { target: Globals; function onSettingsPaneRequestChanged() { root._consumePaneRequest() } }

    signal wallpaperBrowseRequested()

    // diagnostics (generic, app-agnostic)
    property var diag: ({})
    Process {
        id: diagProc
        command: ["sh", "-c",
            'echo "gsession=$(systemctl --user is-active graphical-session.target 2>/dev/null)";' +
            'echo "portal=$(systemctl --user is-active xdg-desktop-portal 2>/dev/null)";' +
            'echo "portal_hypr=$(systemctl --user is-active xdg-desktop-portal-hyprland 2>/dev/null)";' +
            'echo "portal_gtk=$(systemctl --user is-active xdg-desktop-portal-gtk 2>/dev/null)";' +
            'echo "handoff=$(busctl --user introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop org.freedesktop.portal.OpenURI >/dev/null 2>&1 && echo ok || echo fail)";' +
            'echo "browser=$(xdg-settings get default-web-browser 2>/dev/null)";' +
            'echo "gpu=$(lspci -k 2>/dev/null | grep -A3 -iE \"VGA|Display|3D\" | grep -i \"driver in use\" | head -1 | sed \"s/.*use: //\")";' +
            'echo "mem=$(free -m 2>/dev/null | awk \"/Mem:/{print \\$3\\\"/\\\"\\$2\\\" MB\\\"}\")";' +
            'echo "disk=$(df -h / 2>/dev/null | awk \"NR==2{print \\$3\\\"/\\\"\\$2\\\" (\\\"\\$5\\\")\\\"}\")"' ]
        stdout: StdioCollector { onStreamFinished: { var d = {}, ls = this.text.split("\n"); for (var i = 0; i < ls.length; i++) { var k = ls[i].indexOf("="); if (k > 0) d[ls[i].slice(0, k)] = ls[i].slice(k + 1) } root.diag = d } }
    }
    Process {
        id: layoutProc
        command: ["sh", "-c",
            'gi=$(hyprctl getoption general:gaps_in -j); go=$(hyprctl getoption general:gaps_out -j); bs=$(hyprctl getoption general:border_size -j); rd=$(hyprctl getoption decoration:rounding -j);' +
            'echo "in=$(echo \"$gi\" | grep -oE \"[0-9]+\" | head -1)";' +
            'echo "out=$(echo \"$go\" | grep -oE \"[0-9]+\" | head -1)";' +
            'echo "border=$(echo \"$bs\" | grep -oE \"\\\"int\\\": *[0-9]+\" | grep -oE \"[0-9]+\")";' +
            'echo "round=$(echo \"$rd\" | grep -oE \"\\\"int\\\": *[0-9]+\" | grep -oE \"[0-9]+\")"' ]
        stdout: StdioCollector { onStreamFinished: { var ls = this.text.split("\n"); for (var i = 0; i < ls.length; i++) { var p = ls[i].split("="); if (p[0] === "in" && p[1] !== "") root.gapsIn = parseInt(p[1]); else if (p[0] === "out" && p[1] !== "") root.gapsOut = parseInt(p[1]); else if (p[0] === "border" && p[1] !== "") root.borderSize = parseInt(p[1]); else if (p[0] === "round" && p[1] !== "") root.rounding = parseInt(p[1]) }; if (root._syncAfter !== false) { var a = root._syncAfter[0]; root._syncAfter = false; root.writeOverrides(a) } } }
    }
    Process {
        id: defProc
        command: ["sh", "-c",
            'echo "Browser=$(xdg-mime query default x-scheme-handler/https 2>/dev/null)";' +
            'echo "Mail=$(xdg-mime query default x-scheme-handler/mailto 2>/dev/null)";' +
            'echo "Text Editor=$(xdg-mime query default text/plain 2>/dev/null)";' +
            'echo "Image Viewer=$(xdg-mime query default image/png 2>/dev/null)";' +
            'echo "Video Player=$(xdg-mime query default video/mp4 2>/dev/null)";' +
            'echo "File Manager=$(xdg-mime query default inode/directory 2>/dev/null)"' ]
        stdout: StdioCollector { onStreamFinished: { var d = {}, ls = this.text.split("\n"); for (var i = 0; i < ls.length; i++) { var k = ls[i].indexOf("="); if (k > 0) d[ls[i].slice(0, k)] = ls[i].slice(k + 1) } root.defaults = d } }
    }
    Timer { id: defRefresh; interval: 400; onTriggered: { defProc.running = true; choicesProc.running = true } }
    // which apps handle each category (gio mime recommended/registered)
    Process {
        id: choicesProc
        command: ["sh", "-c",
            'for pair in "Browser:x-scheme-handler/https" "Mail:x-scheme-handler/mailto" "Text Editor:text/plain" "Image Viewer:image/png" "Video Player:video/mp4" "File Manager:inode/directory"; do ' +
            '  cat="${pair%%:*}"; mime="${pair#*:}"; ' +
            '  ids=$(gio mime "$mime" 2>/dev/null | awk "/Recommended applications:/{f=1;next} /^[^\\t]/{f=0} f{gsub(/^\\t/,\\\"\\\");print}"); ' +
            '  [ -z "$ids" ] && ids=$(gio mime "$mime" 2>/dev/null | awk "/Registered applications:/{f=1;next} /Recommended applications:/{f=0} /^[^\\t]/{f=0} f{gsub(/^\\t/,\\\"\\\");print}"); ' +
            '  for id in $ids; do printf "%s\\t%s\\n" "$cat" "$id"; done; ' +
            'done' ]
        stdout: StdioCollector { onStreamFinished: { var d = {}, ls = this.text.split("\n"); for (var i = 0; i < ls.length; i++) { var t = ls[i].split("\t"); if (t.length === 2 && t[1]) { if (!d[t[0]]) d[t[0]] = []; d[t[0]].push(t[1]) } } root.appChoices = d } }
    }
    // networking probes
    Process { id: wifiDevProbe; command: ["sh", "-c", "nmcli -t -f TYPE device status 2>/dev/null | grep -qx wifi && echo yes || echo no"]; stdout: StdioCollector { onStreamFinished: root.hasWifi = this.text.trim() === "yes" } }
    Process { id: wifiState; command: ["nmcli", "-t", "-f", "WIFI", "radio"]; stdout: StdioCollector { onStreamFinished: root.wifiOn = this.text.trim() === "enabled" } }
    Process {
        id: wifiScan; command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "device", "wifi", "list"]
        stdout: StdioCollector { onStreamFinished: { var ls = this.text.split("\n"), seen = {}, arr = []; for (var i = 0; i < ls.length; i++) { if (!ls[i]) continue; var p = ls[i].split(":"); var ssid = p.slice(3).join(":"); if (!ssid || seen[ssid]) continue; seen[ssid] = 1; arr.push({ ssid: ssid, signal: parseInt(p[1]) || 0, sec: p[2] || "", active: p[0] === "*" }) } arr.sort(function (a, b) { return (b.active - a.active) || (b.signal - a.signal) }); root.wifiList = arr } }
    }
    Timer { id: wifiRescan; interval: 2500; onTriggered: { wifiState.running = true; wifiScan.running = true } }
    Process {
        id: vpnScan; command: ["sh", "-c", "nmcli -t -f NAME,TYPE,ACTIVE connection show 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { var ls = this.text.split("\n"), arr = []; for (var i = 0; i < ls.length; i++) { if (!ls[i]) continue; var p = ls[i].split(":"); var type = p[p.length - 2], active = p[p.length - 1] === "yes"; var name = p.slice(0, p.length - 2).join(":"); if (type && (type.indexOf("vpn") >= 0 || type.indexOf("wireguard") >= 0)) arr.push({ name: name, active: active }) } root.vpnList = arr } }
    }
    Timer { id: vpnRescan; interval: 1500; onTriggered: vpnScan.running = true }
    Process {
        id: netProc
        command: ["sh", "-c", 'nmcli -t -f NAME,TYPE,DEVICE,STATE connection show --active 2>/dev/null; echo "==="; ip -4 -o addr show scope global 2>/dev/null | awk "{print \\$2\\\": \\\"\\$4}"' ]
        stdout: StdioCollector { onStreamFinished: { var parts = this.text.split("==="); var a = [], ip = []; var l1 = parts[0].split("\n"); for (var i = 0; i < l1.length; i++) { if (!l1[i]) continue; var p = l1[i].split(":"); a.push({ name: p[0], type: p[1], dev: p[2], state: p[3] }) } if (parts[1]) { var l2 = parts[1].split("\n"); for (var j = 0; j < l2.length; j++) if (l2[j].trim()) ip.push(l2[j].trim()) } root.netActive = a; root.ipList = ip } }
    }
    Process {
        id: sshProc; command: ["sh", "-c", "grep -iE '^[[:space:]]*Host[[:space:]]' \"$HOME/.ssh/config\" 2>/dev/null | awk '{for(i=2;i<=NF;i++)print $i}' | grep -v '[*?]' | sort -u"]
        stdout: StdioCollector { onStreamFinished: { var ls = this.text.split("\n"), arr = []; for (var i = 0; i < ls.length; i++) if (ls[i].trim()) arr.push(ls[i].trim()); root.sshHosts = arr } }
    }
    // ── Keyboard & Mouse — the whole input{} block (and per-device overrides),
    //    applied live via hyprctl eval and persisted to generated/input.lua ────
    property bool inpLoaded: false
    property var inp: ({ kb_layout: "us", kb_variant: "", kb_options: "", repeat_rate: 25, repeat_delay: 600,
                         numlock_by_default: false, sensitivity: 0, accel_profile: "", natural_scroll: false,
                         left_handed: false, scroll_factor: 1,
                         tp_natural_scroll: true, tp_tap: true, tp_dwt: true, tp_clickfinger: false,
                         tp_scroll_factor: 1, tp_mbe: false, tp_drag_lock: false, tp_tap_drag: true })
    property var mice: []
    property bool hasTouchpad: false
    property bool perWindowKb: false
    property var devOverrides: ({})    // device name → { sensitivity, natural_scroll, left_handed, accel_profile }
    property string devTarget: ""      // "" = all pointing devices (global input{})

    // eval runner + atomic writer live in HyprMon (the one copy each); these are
    // thin conveniences so pane code reads naturally
    function runEvals(stmts, done) { HyprMon.runEvals(stmts, done) }
    function atomicWrite(proc, path, content, after) { HyprMon.atomicWrite(proc, path, content, after) }
    Process { id: inputLuaWriter }

    function boolLua(b) { return b ? "true" : "false" }
    function esc(s) { return HyprMon.luaEsc(s) }
    function inputLua(p) {
        return 'hl.config({ input = { kb_layout = "' + root.esc(p.kb_layout) + '", kb_variant = "' + root.esc(p.kb_variant) + '", kb_options = "' + root.esc(p.kb_options) + '"'
             + ", repeat_rate = " + p.repeat_rate + ", repeat_delay = " + p.repeat_delay
             + ", numlock_by_default = " + root.boolLua(p.numlock_by_default)
             + ", sensitivity = " + p.sensitivity
             + (p.accel_profile !== "" ? ', accel_profile = "' + root.esc(p.accel_profile) + '"' : "")
             + ", natural_scroll = " + root.boolLua(p.natural_scroll) + ", left_handed = " + root.boolLua(p.left_handed)
             + ", scroll_factor = " + p.scroll_factor
             + ", touchpad = { natural_scroll = " + root.boolLua(p.tp_natural_scroll) + ", tap_to_click = " + root.boolLua(p.tp_tap)
             + ", disable_while_typing = " + root.boolLua(p.tp_dwt) + ", clickfinger_behavior = " + root.boolLua(p.tp_clickfinger)
             + ", scroll_factor = " + p.tp_scroll_factor + ", middle_button_emulation = " + root.boolLua(p.tp_mbe)
             + ", drag_lock = " + root.boolLua(p.tp_drag_lock) + ", tap_and_drag = " + root.boolLua(p.tp_tap_drag) + " } } })"
    }
    function deviceLua(name, o) {
        var L = 'hl.device({ name = "' + root.esc(name) + '"'
        if (o.sensitivity !== undefined) L += ", sensitivity = " + o.sensitivity
        if (o.natural_scroll !== undefined) L += ", natural_scroll = " + root.boolLua(o.natural_scroll)
        if (o.left_handed !== undefined) L += ", left_handed = " + root.boolLua(o.left_handed)
        if (o.accel_profile !== undefined && o.accel_profile !== "") L += ', accel_profile = "' + root.esc(o.accel_profile) + '"'
        return L + " })"
    }
    // RFC-001 Phase 4 (0.6): input.lua + input-devices.json are ewe-conf
    // build artifacts now — persistence is ONE `set desktop.input`, and the
    // inputLua/deviceLua strings above remain only for the live hyprctl eval.
    function writeInputLua() {
        if (HyprMon.virtualSession) return   // same guard as atomicWrite
        var payload = {}; for (var k in root.inp) payload[k] = root.inp[k]
        payload.devices = root.devOverrides
        inputLuaWriter.command = [root.home + "/.config/quickshell/../../bin/ewe-conf",
                                  "set", "--no-hooks", "desktop.input", JSON.stringify(payload)]
        inputLuaWriter.running = false; inputLuaWriter.running = true
    }
    function applyInput(patch) {
        var p = {}; for (var k in root.inp) p[k] = root.inp[k]
        for (k in patch) p[k] = patch[k]
        root.inp = p
        root.runEvals([root.inputLua(p)], function (ok) { if (ok) root.flashApplied() })
        root.writeInputLua()
    }
    function applyDevice(name, patch) {
        var all = {}; for (var d in root.devOverrides) all[d] = root.devOverrides[d]
        var o = {}; var cur = all[name] || {}
        for (var k in cur) o[k] = cur[k]
        for (k in patch) o[k] = patch[k]
        all[name] = o
        root.devOverrides = all
        root.runEvals([root.deviceLua(name, o)], function (ok) { if (ok) root.flashApplied() })
        root.writeInputLua()
    }
    // kb_options managed as a token set (grp:* switch shortcut + advanced extras)
    function kbOptToken(prefix) {
        var toks = String(root.inp.kb_options || "").split(",")
        for (var i = 0; i < toks.length; i++) if (toks[i].indexOf(prefix) === 0) return toks[i]
        return ""
    }
    function setKbOptPrefix(prefix, token) {
        var toks = String(root.inp.kb_options || "").split(",").filter(function (t) { return t !== "" && t.indexOf(prefix) !== 0 })
        if (token !== "") toks.push(token)
        root.applyInput({ kb_options: toks.join(",") })
    }
    function hasKbOpt(token) { return String(root.inp.kb_options || "").split(",").indexOf(token) >= 0 }
    function toggleKbOpt(token) {
        var toks = String(root.inp.kb_options || "").split(",").filter(function (t) { return t !== "" && t !== token })
        if (!root.hasKbOpt(token)) toks.push(token)
        root.applyInput({ kb_options: toks.join(",") })
    }
    // active layouts as [{code, variant}] (kb_layout / kb_variant are parallel lists)
    readonly property var kbActive: {
        var codes = String(root.inp.kb_layout).split(",").map(function (s) { return s.trim() }).filter(function (x) { return x !== "" })
        var vars = String(root.inp.kb_variant).split(",")
        return codes.map(function (c, i) { return { code: c, variant: (vars[i] || "").trim() } })
    }
    function applyLayouts(list) {
        if (!list.length) return
        var anyVar = list.some(function (l) { return l.variant !== "" })
        root.applyInput({
            kb_layout: list.map(function (l) { return l.code }).join(","),
            kb_variant: anyVar ? list.map(function (l) { return l.variant }).join(",") : ""
        })
        root.restartPerWindowKb()
    }
    function kbAdd(code) { var l = root.kbActive.slice(); l.push({ code: code, variant: "" }); root.applyLayouts(l) }
    function kbRemove(i) { var l = root.kbActive.slice(); if (l.length > 1) { l.splice(i, 1); root.applyLayouts(l) } }
    function kbMove(from, to) {
        var l = root.kbActive.slice()
        to = Math.max(0, Math.min(l.length - 1, to))
        if (from === to) return
        var it = l.splice(from, 1)[0]; l.splice(to, 0, it)
        root.applyLayouts(l)
    }
    function kbSetVariant(i, v) { var l = root.kbActive.slice(); l[i] = { code: l[i].code, variant: v }; root.applyLayouts(l) }
    // per-window layout memory = the kb-per-window.py daemon; the flag file tells
    // autostart.sh to skip it on the next login. Patterns use the [k] trick so
    // pgrep/pkill -f never match the wrapping `sh -c` (whose own cmdline would
    // otherwise contain the pattern and always "find" the daemon).
    function setPerWindowKb(on) {
        if (on) Quickshell.execDetached(["sh", "-c", 'rm -f "$HOME/.config/hypr/generated/kb-per-window.disabled"; pgrep -f "[k]b-per-window.py" >/dev/null || setsid python3 "$HOME/.config/hypr/scripts/kb-per-window.py" >/dev/null 2>&1 &'])
        else Quickshell.execDetached(["sh", "-c", 'mkdir -p "$HOME/.config/hypr/generated"; touch "$HOME/.config/hypr/generated/kb-per-window.disabled"; pkill -f "[k]b-per-window.py"'])
        perWinRecheck.restart()
    }
    // the daemon snapshots kb_layout at startup — restart it when the layout
    // list changes so its keymap-name→index map never goes stale
    function restartPerWindowKb() {
        Quickshell.execDetached(["sh", "-c", 'pgrep -f "[k]b-per-window.py" >/dev/null || exit 0; pkill -f "[k]b-per-window.py"; sleep 0.3; setsid python3 "$HOME/.config/hypr/scripts/kb-per-window.py" >/dev/null 2>&1 &'])
        perWinRecheck.restart()
    }

    // probes — one hyprctl --batch process for every option; replies come back
    // as blank-line-separated blocks in command order ("int: 25" / "str: us" /
    // "bool: false" / "float: 1.0")
    readonly property var inpOptions: [
        ["kb_layout", "kb_layout"], ["kb_variant", "kb_variant"], ["kb_options", "kb_options"],
        ["repeat_rate", "repeat_rate"], ["repeat_delay", "repeat_delay"], ["numlock_by_default", "numlock_by_default"],
        ["sensitivity", "sensitivity"], ["accel_profile", "accel_profile"], ["natural_scroll", "natural_scroll"],
        ["left_handed", "left_handed"], ["scroll_factor", "scroll_factor"],
        ["touchpad:natural_scroll", "tp_natural_scroll"], ["touchpad:tap-to-click", "tp_tap"],
        ["touchpad:disable_while_typing", "tp_dwt"], ["touchpad:clickfinger_behavior", "tp_clickfinger"],
        ["touchpad:scroll_factor", "tp_scroll_factor"], ["touchpad:middle_button_emulation", "tp_mbe"],
        ["touchpad:drag_lock", "tp_drag_lock"], ["touchpad:tap-and-drag", "tp_tap_drag"]
    ]
    Process {
        id: inputProbe
        command: ["hyprctl", "--batch", root.inpOptions.map(function (o) { return "getoption input:" + o[0] }).join("; ")]
        stdout: StdioCollector { onStreamFinished: root._parseInput(this.text) }
    }
    function _parseInput(text) {
        var blocks = text.split(/\n\s*\n/).filter(function (b) { return b.trim() !== "" })
        var p = {}; for (var k in root.inp) p[k] = root.inp[k]
        for (var i = 0; i < blocks.length && i < root.inpOptions.length; i++) {
            var m = blocks[i].split("\n")[0].match(/^(int|float|bool|str):\s?(.*)$/)
            if (!m) continue
            var v
            if (m[1] === "int") v = parseInt(m[2])
            else if (m[1] === "float") v = parseFloat(m[2])
            else if (m[1] === "bool") { var b = m[2].trim(); v = (b === "true" || b === "1") }
            else { v = m[2]; if (v === "[[EMPTY]]") v = "" }
            if (v !== undefined && !(typeof v === "number" && isNaN(v))) p[root.inpOptions[i][1]] = v
        }
        root.inp = p; root.inpLoaded = true
        // persist the live truth right away: covers first run and migration from
        // the days input settings lived in user.lua (idempotent, atomic)
        root.writeInputLua()
    }
    // best available heuristic: Hyprland exposes no device class, only names.
    // Covers the common touchpad name shapes (libinput/vendor) case-insensitively.
    function isTouchpadName(n) { return /touchpad|glidepoint|bcm5974|trackpad/i.test(n) }
    Process {
        id: devProbe; command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    var m = (j.mice || []).map(function (x) { return x.name })
                    root.mice = m
                    root.hasTouchpad = m.some(root.isTouchpadName)
                } catch (e) {}
            }
        }
    }
    Process { id: perWinProbe; command: ["sh", "-c", 'pgrep -f "[k]b-per-window.py" >/dev/null && echo yes || echo no']; stdout: StdioCollector { onStreamFinished: root.perWindowKb = this.text.trim() === "yes" } }
    Timer { id: perWinRecheck; interval: 600; onTriggered: perWinProbe.running = true }
    Process {
        id: devOvLoad; running: true
        command: ["sh", "-c", 'cat "$HOME/.config/quickshell/input-devices.json" 2>/dev/null']
        stdout: StdioCollector { onStreamFinished: { try { var j = JSON.parse(this.text); if (j && typeof j === "object") root.devOverrides = j } catch (e) {} } }
    }

    // The full system xkb registry replaces these curated arrays as soon as
    // base.lst parses (every layout + variant, same list other distros offer);
    // the curated set below remains only as a fallback for a missing file.
    property var kbVariantNames: ({})   // "layout/variant" → human description
    Process {
        id: xkbLoad; running: true
        command: ["sh", "-c", "cat /usr/share/X11/xkb/rules/base.lst 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n"), sec = "", ps = [], vs = ({}), vn = ({})
                for (var i = 0; i < lines.length; i++) {
                    var t = lines[i].trim()
                    if (t === "") continue
                    if (t[0] === "!") { sec = t.slice(1).trim(); continue }
                    var sp = t.search(/\s/); if (sp < 0) continue
                    var code = t.slice(0, sp), rest = t.slice(sp).trim()
                    if (sec === "layout") { ps.push({ c: code, n: rest }); vs[code] = [""] }
                    else if (sec === "variant") {
                        var ci = rest.indexOf(":"); if (ci < 0) continue
                        var lay = rest.slice(0, ci).trim(), desc = rest.slice(ci + 1).trim()
                        if (vs[lay]) { vs[lay].push(code); vn[lay + "/" + code] = desc }
                    }
                }
                if (ps.length) { root.kbPresets = ps; root.kbVariants = vs; root.kbVariantNames = vn }
            }
        }
    }
    // per-layout XKB variants (curated common set; Default = no variant)
    property var kbVariants: ({
        us: ["", "intl", "dvorak", "colemak", "mac"], gb: ["", "extd", "intl", "dvorak", "mac"],
        ge: ["", "qwerty", "mess", "ru"], ru: ["", "phonetic", "typewriter", "mac"], ua: ["", "phonetic", "typewriter"],
        de: ["", "nodeadkeys", "neo", "mac"], at: ["", "nodeadkeys"], ch: ["", "de_nodeadkeys", "fr"],
        fr: ["", "bepo", "oss", "mac"], be: ["", "oss"], ca: ["", "fr", "multix", "eng"],
        es: ["", "nodeadkeys", "winkeys", "mac"], latam: ["", "nodeadkeys"],
        it: ["", "nodeadkeys", "mac"], pt: ["", "nodeadkeys", "mac"], br: ["", "nodeadkeys", "thinkpad"],
        nl: ["", "mac"], tr: ["", "f", "alt"], gr: ["", "polytonic", "extended"],
        pl: ["", "qwertz", "dvorak"], cz: ["", "qwerty", "qwerty_bksl"], sk: ["", "qwerty"],
        hu: ["", "standard", "nodeadkeys"], ro: ["", "std"], bg: ["", "phonetic", "bas_phonetic"],
        se: ["", "nodeadkeys", "dvorak", "mac"], no: ["", "nodeadkeys", "dvorak", "mac"], fi: ["", "nodeadkeys", "mac"],
        dk: ["", "nodeadkeys", "mac"], is: ["", "mac"],
        lt: ["", "std"], lv: ["", "apostrophe"], ee: ["", "nodeadkeys"],
        rs: ["", "latin", "yz"], hr: ["", "unicode"], si: [""],
        by: ["", "latin"], kz: ["", "latin"], am: ["", "phonetic"], az: ["", "cyrillic"],
        il: ["", "phonetic", "biblical"], ara: ["", "azerty", "qwerty"], ir: ["", "pes_keypad"],
        "in": ["", "eng", "tam", "ben"], jp: ["", "kana", "mac"], kr: ["", "kr104"], cn: ["", "altgr-pinyin"],
        th: ["", "pat"], vn: [""]
    })
    // XKB group-toggle shortcut presets (kb_options grp:*). Super+Space is the
    // DE's own Hyprland bind (switchxkblayout) and always works in addition.
    readonly property var grpOptions: [
        { label: "Only Super+Space", value: "" },
        { label: "Alt+Shift", value: "grp:alt_shift_toggle" },
        { label: "Ctrl+Alt", value: "grp:ctrl_alt_toggle" },
        { label: "Ctrl+Shift", value: "grp:ctrl_shift_toggle" },
        { label: "Win+Space", value: "grp:win_space_toggle" },
        { label: "Caps Lock", value: "grp:caps_toggle" }
    ]
    property var kbPresets: [
        { c: "us", n: "English (US)" }, { c: "gb", n: "English (UK)" },
        { c: "ge", n: "Georgian" }, { c: "ru", n: "Russian" }, { c: "ua", n: "Ukrainian" },
        { c: "de", n: "German" }, { c: "at", n: "German (Austria)" }, { c: "ch", n: "Swiss" },
        { c: "fr", n: "French" }, { c: "be", n: "Belgian" }, { c: "ca", n: "French (Canada)" },
        { c: "es", n: "Spanish" }, { c: "latam", n: "Spanish (Latin America)" },
        { c: "it", n: "Italian" }, { c: "pt", n: "Portuguese" }, { c: "br", n: "Portuguese (Brazil)" },
        { c: "nl", n: "Dutch" }, { c: "tr", n: "Turkish" }, { c: "gr", n: "Greek" },
        { c: "pl", n: "Polish" }, { c: "cz", n: "Czech" }, { c: "sk", n: "Slovak" },
        { c: "hu", n: "Hungarian" }, { c: "ro", n: "Romanian" }, { c: "bg", n: "Bulgarian" },
        { c: "se", n: "Swedish" }, { c: "no", n: "Norwegian" }, { c: "fi", n: "Finnish" },
        { c: "dk", n: "Danish" }, { c: "is", n: "Icelandic" },
        { c: "lt", n: "Lithuanian" }, { c: "lv", n: "Latvian" }, { c: "ee", n: "Estonian" },
        { c: "rs", n: "Serbian" }, { c: "hr", n: "Croatian" }, { c: "si", n: "Slovenian" },
        { c: "by", n: "Belarusian" }, { c: "kz", n: "Kazakh" }, { c: "am", n: "Armenian" },
        { c: "az", n: "Azerbaijani" }, { c: "il", n: "Hebrew" }, { c: "ara", n: "Arabic" },
        { c: "ir", n: "Persian" }, { c: "in", n: "Indian" }, { c: "jp", n: "Japanese" },
        { c: "kr", n: "Korean" }, { c: "cn", n: "Chinese" }, { c: "th", n: "Thai" },
        { c: "vn", n: "Vietnamese" }
    ]
    // shortcuts (rendered from SHORTCUTS.md)
    property string shortcutsMd: ""
    Process { id: scProc; command: ["sh", "-c", "cat \"$HOME/.config/hypr/SHORTCUTS.md\" 2>/dev/null"]; stdout: StdioCollector { onStreamFinished: root.shortcutsMd = this.text } }
    function shortcutsModel() {
        var out = [], ls = root.shortcutsMd.split("\n")
        for (var i = 0; i < ls.length; i++) {
            var t = ls[i].trim()
            if (t.indexOf("## ") === 0) out.push({ h: true, a: t.slice(3), b: "" })
            else if (t.indexOf("|") === 0 && t.indexOf("---") < 0) {
                var cells = t.split("|").map(function (x) { return x.trim() }).filter(function (x) { return x !== "" })
                if (cells.length >= 2 && cells[0].toLowerCase() !== "shortcut")
                    out.push({ h: false, a: cells[0].replace(/`/g, ""), b: cells[1].replace(/\*\*/g, "").replace(/`/g, "") })
            }
        }
        return out
    }

    // ── Wallpaper — per-output assignments in generated/wallpapers.conf, applied
    //    by scripts/wallpaper.sh (backend: swww → hyprpaper → swaybg) ───────────
    property string wpImgBackend: ""   // what wallpaper.sh will drive images with (swww/awww/swaybg; "" = none)
    property string wpVideoBackend: "" // "mpvpaper" or "" (videos impossible without it)
    property bool wpMute: true         // video wallpapers muted (conf mute=)
    property var wpMap: ({})           // "*" or output name → file path
    property string wpMode: "fill"
    property string wpDir: ""          // folder shown in the thumbnail grid
    property var wpFiles: []
    property string wpTarget: "*"      // "*" = all displays
    readonly property string wpBackendLabel: wpImgBackend === "" && wpVideoBackend === "" ? "none"
        : wpImgBackend + (wpVideoBackend !== "" ? " + " + wpVideoBackend : "")
    function wpIsVideo(p) { return /\.(mp4|webm|mkv|mov|avi|m4v)$/i.test(p) }
    function wpIsGif(p) { return /\.gif$/i.test(p) }
    readonly property bool wpAnyAnimated: {
        for (var k in wpMap) if (wpIsVideo(wpMap[k]) || wpIsGif(wpMap[k])) return true
        return false
    }
    readonly property bool wpAnyVideo: {
        for (var k in wpMap) if (wpIsVideo(wpMap[k])) return true
        return false
    }
    // the backend mapping is wallpaper.sh's call (single authority) — ask it
    Process {
        id: wpBackendProbe
        command: ["sh", "-c", '"$HOME/.config/hypr/scripts/wallpaper.sh" --backend 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                var m = this.text.match(/img=(\S+)\s+video=(\S+)/)
                root.wpImgBackend = m && m[1] !== "none" ? m[1] : ""
                root.wpVideoBackend = m && m[2] !== "none" ? m[2] : ""
            }
        }
    }
    Process {
        id: wpConfLoad; command: ["sh", "-c", 'cat "$HOME/.config/hypr/generated/wallpapers.conf" 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                var m = {}, mode = "fill", mute = true, ls = this.text.split("\n")
                for (var i = 0; i < ls.length; i++) {
                    var l = ls[i]
                    if (l === "" || l[0] === "#") continue
                    var k = l.indexOf("="); if (k <= 0) continue
                    var key = l.slice(0, k), val = l.slice(k + 1)
                    if (key === "mode") mode = val
                    else if (key === "mute") mute = val === "1"
                    else if (key === "backend") continue   // power-user override, script-side only
                    else if (val !== "") m[key] = val
                }
                root.wpMap = m; root.wpMode = mode; root.wpMute = mute
            }
        }
    }
    // the shipped ewe set opens first (resolved through the config farm so
    // git checkouts, tarballs and the /usr/share/ewe package all find their
    // own copy); the user's own folders follow
    Process { id: wpDirProbe; command: ["sh", "-c", 'for d in "$(realpath "$HOME/.config/quickshell" 2>/dev/null)/../../system/branding/wallpapers" /usr/share/ewe/system/branding/wallpapers "$HOME/Pictures/Wallpapers" "$HOME/Pictures" "$HOME"; do d="$(realpath "$d" 2>/dev/null)"; [ -n "$d" ] && [ -d "$d" ] && { echo "$d"; exit; }; done']; stdout: StdioCollector { onStreamFinished: { var d = this.text.trim(); if (d !== "") root.wpList(d) } } }
    Process { id: wpLs; stdout: StdioCollector { onStreamFinished: root.wpFiles = this.text.split("\n").filter(function (x) { return x !== "" }) } }
    Process { id: wpWriter }
    // apply runs through a collecting Process so wallpaper.sh's error:/note:
    // lines land in the banner instead of vanishing into execDetached
    Timer { id: wpApply; interval: 250; onTriggered: { wpApplyProc.running = false; wpApplyProc.running = true } }
    Process {
        id: wpApplyProc
        command: ["sh", "-c", '"$HOME/.config/hypr/scripts/wallpaper.sh" --reapply 2>&1']
        stdout: StdioCollector {
            onStreamFinished: {
                var out = this.text.trim()
                if (out.indexOf("error:") >= 0) root.errorMsg = out.split("\n").filter(function (l) { return l.indexOf("error:") >= 0 })[0].replace(/^error:\s*/, "")
                else if (out !== "") root.flashApplied(out.split("\n")[0].replace(/^note:\s*/, ""))
                else root.flashApplied("Wallpaper applied")
                // a fresh mpvpaper is now running unpaused — re-assert the freeze
                Wallpaper.reapplied()
            }
        }
    }
    function wpList(dir) {
        root.wpDir = dir
        wpLs.command = ["sh", "-c", 'find "$1" -maxdepth 1 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.webm" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.m4v" \\) 2>/dev/null | sort', "qs-settings", dir]
        wpLs.running = false; wpLs.running = true
    }
    function wpWrite() {
        if (HyprMon.virtualSession) return   // test session: don't touch conf or the real backend
        // RFC-001: persist through ewe-conf (desktop.wallpapers) — it emits
        // generated/wallpapers.conf byte-identically to the old writer.
        var o = { mode: root.wpMode, mute: root.wpMute, outputs: ({}) }
        var keys = Object.keys(root.wpMap).sort()
        for (var i = 0; i < keys.length; i++) {
            if (keys[i] === "*") o["default"] = root.wpMap[keys[i]]
            else o.outputs[keys[i]] = root.wpMap[keys[i]]
        }
        wpWriter.command = [Globals.eweConf, "set", "--no-hooks", "desktop.wallpapers", JSON.stringify(o)]
        wpWriter.running = false; wpWriter.running = true
        wpApply.restart()
    }
    function wpAssign(path) {
        if (root.wpIsVideo(path) && root.wpVideoBackend === "") {
            root.errorMsg = "Video wallpapers need mpvpaper. Install it with sudo pacman -S mpvpaper."
            return
        }
        if (root.wpIsGif(path) && root.wpImgBackend === "swaybg")
            root.errorMsg = "GIFs stay still with swaybg. Install swww (sudo pacman -S awww) to animate them."
        var m
        if (root.wpTarget === "*") m = { "*": path }   // "all displays" replaces per-monitor picks
        else { m = {}; for (var k in root.wpMap) m[k] = root.wpMap[k]; m[root.wpTarget] = path }
        root.wpMap = m
        root.wpWrite()
        root.flashApplied("Wallpaper changed")
    }
    // file picking + drag-and-drop live in the shared FileDropTarget component
    // (instantiated by the Wallpaper and User panes)

    // accent presets: the Accent picker's colours, from the generator
    // ([{name, hex, ink}]) so this file carries none of its own
    readonly property var accents: Globals.tokAccentPresets

    // ── User: AccountsService identity + session facts ────────────────────────
    property string userRealName: ""
    property var sysFacts: ({})
    function fmtBytes(n) {
        n = Number(n || 0)
        if (n >= 1e12) return (n / 1e12).toFixed(1) + " TB"
        if (n >= 1e9) return (n / 1e9).toFixed(1) + " GB"
        if (n >= 1e6) return (n / 1e6).toFixed(0) + " MB"
        return (n / 1e3).toFixed(0) + " kB"
    }
    function fmtSyncTime(iso) {
        var d = new Date(iso)
        return isNaN(d.getTime()) ? (iso || "—") : Qt.formatDateTime(d, "d MMM · h:mm AP")
    }

    // (the packages-from-backup review surface retired in 0.6 — Komble's
    // For-you pane owns app restore; installs there enter its registry and
    // re-enter [apps.installed], which this side-channel never did)
    Process {
        id: userInfoProbe
        command: ["sh", "-c",
            'echo "real=$(getent passwd "$USER" | cut -d: -f5 | cut -d, -f1)";' +
            'echo "host=$(cat /etc/hostname 2>/dev/null || uname -n)";' +
            'echo "kernel=$(uname -r)";' +
            "echo \"up=$(uptime -p 2>/dev/null | sed 's/^up //')\";" +
            "echo \"hypr=$(hyprctl version 2>/dev/null | head -1 | cut -d' ' -f1-2)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var d = {}, ls = this.text.split("\n")
                for (var i = 0; i < ls.length; i++) { var k = ls[i].indexOf("="); if (k > 0) d[ls[i].slice(0, k)] = ls[i].slice(k + 1) }
                if (d.real) root.userRealName = d.real
                root.sysFacts = d
            }
        }
    }
    // AccountsService change-own-user-data is allowed for the active session, so
    // this normally succeeds without a polkit prompt; failures hit the banner
    Process {
        id: nameSetProc
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim()
                if (t !== "") root.errorMsg = "Couldn't change your name: " + t.split("\n")[0]
                else { root.flashApplied("Name changed"); userInfoProbe.running = false; userInfoProbe.running = true }
            }
        }
    }
    function setRealName(name) {
        nameSetProc.command = ["sh", "-c", 'busctl call org.freedesktop.Accounts "/org/freedesktop/Accounts/User$(id -u)" org.freedesktop.Accounts.User SetRealName s "$1" 2>&1', "qs-settings", name]
        nameSetProc.running = false; nameSetProc.running = true
    }
    // online-account provider → glyph (safe MDI codepoints only)
    function providerIcon(p) {
        p = String(p).toLowerCase()
        if (p.indexOf("google") >= 0) return 0xE461           // circle-user — Lucide ships no brand marks
        if (p.indexOf("imap") >= 0 || p.indexOf("smtp") >= 0) return 0xE10F  // mail
        return 0xE088                                         // cloud (exchange/nextcloud/webdav/…)
    }

    // ── avatar: pick → crop (pan/zoom) → 512² PNG to ~/.face + AccountsService ──
    property string avatarCropSrc: ""      // image being cropped ("" = dialog closed)
    function saveAvatar() {
        cropCanvas.grabToImage(function (res) {
            var tmp = root.home + "/.cache/ewe-avatar.png"
            if (!res.saveToFile(tmp)) { root.errorMsg = "Couldn't save the cropped picture."; root.avatarCropSrc = ""; return }
            avatarSave.command = ["sh", "-c",
                'if cp "$1" "$HOME/.face"; then busctl call org.freedesktop.Accounts /org/freedesktop/Accounts/User$(id -u) org.freedesktop.Accounts.User SetIconFile s "$HOME/.face" >/dev/null 2>&1 || echo ACCOUNTS-FAIL; else echo CP-FAIL; fi',
                "qs-settings", tmp]
            avatarSave.running = false; avatarSave.running = true
            root.avatarCropSrc = ""
        }, Qt.size(512, 512))
    }
    Process {
        id: avatarSave
        stdout: StdioCollector {
            onStreamFinished: {
                var out = this.text.trim()
                if (out.indexOf("CP-FAIL") >= 0) root.errorMsg = "Couldn't save ~/.face. Check its permissions."
                else if (out.indexOf("ACCOUNTS-FAIL") >= 0) { root.errorMsg = "Picture saved to ~/.face, but AccountsService refused it. The sign-in screen may keep the old one."; Globals.recheckFace() }
                else { root.flashApplied("Picture changed"); Globals.recheckFace() }
            }
        }
    }
    // Google profile photo → shell avatar: download at 512px (Google URLs end
    // in a =s<N>-c size suffix), then reuse the exact ~/.face + AccountsService
    // pipeline the crop flow uses. Google avatars are already square — no crop.
    function useGooglePhoto() {
        if (!Google.profile || !Google.profile.picture) return
        var url = String(Google.profile.picture)
        url = /=s\d+(-c)?$/.test(url) ? url.replace(/=s\d+(-c)?$/, "=s512-c") : url
        gPhotoFetch.command = ["sh", "-c",
            'tmp="$HOME/.cache/ewe-avatar.png"; if curl -fsSL --max-time 20 -o "$tmp" "$1"; then echo DL-OK; else echo DL-FAIL; fi',
            "qs-settings", url]
        gPhotoFetch.running = false; gPhotoFetch.running = true
    }
    Process {
        id: gPhotoFetch
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.indexOf("DL-OK") < 0) { root.errorMsg = "Couldn't download your Google profile photo. Check your connection and try again."; return }
                avatarSave.command = ["sh", "-c",
                    'if cp "$1" "$HOME/.face"; then busctl call org.freedesktop.Accounts /org/freedesktop/Accounts/User$(id -u) org.freedesktop.Accounts.User SetIconFile s "$HOME/.face" >/dev/null 2>&1 || echo ACCOUNTS-FAIL; else echo CP-FAIL; fi',
                    "qs-settings", root.home + "/.cache/ewe-avatar.png"]
                avatarSave.running = false; avatarSave.running = true
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // A real xdg-toplevel (FloatingWindow), NOT a layer surface. Layer surfaces
    // have no toplevel semantics, so the XDG portal file chooser had no valid
    // parent (dialogs never opened) and file drag-and-drop never routed here.
    // As a toplevel it is movable/closable like any app window; hyprland.lua has
    // a windowrule (match: title) that floats + centers it at 880×620, so it
    // still opens centered like the old overlay. Window animations come from
    // Hyprland's own popin animation — no hand-rolled fade needed.
    FloatingWindow {
        id: win
        visible: false
        // lazy-loaded: created AFTER settingsOpen flipped true, so the change
        // signal below already fired — sync the level at birth
        Component.onCompleted: if (Globals.settingsOpen) visible = true
        title: "ewe settings"
        // the size hyprland.lua's window rule opens it at; the floor is two
        // panels wide, so the rail never has to collapse (Side navigation)
        implicitWidth: Theme.panelLg + Theme.panelSm - Theme.spaceLg - Theme.spaceS
        implicitHeight: Theme.panelLg + Theme.control2xl + Theme.spaceMd - Theme.spaceXs
        minimumSize: Qt.size(2 * Theme.panelSm, Theme.panelLg - Theme.spaceXl - Theme.spaceMd)
        color: Theme.surfaceBase
        Connections {
            target: Globals
            function onSettingsOpenChanged() { if (win.visible !== Globals.settingsOpen) win.visible = Globals.settingsOpen }
        }
        onVisibleChanged: if (Globals.settingsOpen !== visible) Globals.settingsOpen = visible
        // Compositor-side close (Super+Q, the close button) does NOT flip the
        // proxy's `visible` — it fires `closed` and quietly unmaps the backing
        // window. Without this, Globals.settingsOpen stays true and the gear
        // (which sets it true again) is a no-change no-op: the window can never
        // be reopened. Drop visible to false ourselves so state resyncs and the
        // next open remaps a fresh backing window.
        onClosed: { win.visible = false; Globals.settingsOpen = false }

        Item {
            id: card
            anchors.fill: parent
            clip: true

            Item {
                id: keyGrab
                anchors.fill: parent; focus: true
                Keys.onEscapePressed: Globals.settingsOpen = false
                // Side navigation: Ctrl+1 … Ctrl+9 jump to the first nine pages
                Keys.onPressed: function (e) {
                    if ((e.modifiers & Qt.ControlModifier) && e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
                        var n = e.key - Qt.Key_1
                        if (n < root.navItems.length) root.pane = n
                        e.accepted = true
                    }
                }
                Connections { target: Globals; function onSettingsOpenChanged() { if (Globals.settingsOpen) keyGrab.forceActiveFocus() } }
            }

            // ════════ the page's parts (design system: Settings page) ════════
            // Text in the type styles. TBody is the body style in textPrimary,
            // TCaption the caption style in textMuted, TMono values that change
            // in place (tabular figures).
            component TBody: Text {
                color: Theme.textPrimary
                font.family: Theme.type.body.family
                font.pixelSize: Theme.type.body.size
                font.weight: Theme.type.body.weight
            }
            component TStrong: TBody { font.weight: Theme.type.bodyStrong.weight }
            component TCaption: Text {
                color: Theme.textMuted
                font.family: Theme.type.caption.family
                font.pixelSize: Theme.type.caption.size
                font.weight: Theme.type.caption.weight
            }
            component TMono: Text {
                color: Theme.textSecondary
                font.family: Theme.type.mono.family
                font.pixelSize: Theme.type.mono.size
                font.weight: Theme.type.mono.weight
                font.features: ({ "tnum": 1 })
            }
            // a paragraph under a list: what a setting does, where it is kept
            component Note: TCaption {
                width: parent ? parent.width : 0
                wrapMode: Text.WordWrap
            }
            // a status dot: ok · bad · info
            component Dot: Rectangle {
                property string state: "info"
                width: Theme.spaceS; height: Theme.spaceS; radius: Theme.radiusFull
                color: state === "ok" ? Theme.success : state === "bad" ? Theme.danger : Theme.textMuted
            }
            // the rule between two rows of a list well
            component Divider: Rectangle {
                width: parent ? parent.width : 0; height: Theme.borderWidth1
                color: Theme.borderSubtle
            }
            // The list well a group of rows sits in. Inside the raised pane,
            // lists take surfaceOverlay (App shell), with the borderSubtle
            // outline, the radiusRounded corner and spaceS + spaceXs inside.
            component Card: Rectangle {
                default property alias content: inner.data
                property alias spacing: inner.spacing
                width: parent ? parent.width : 0
                implicitHeight: inner.implicitHeight + 2 * (Theme.spaceS + Theme.spaceXs)
                radius: Theme.radiusRounded
                color: Theme.surfaceOverlay
                border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                Column {
                    id: inner
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: Theme.spaceS + Theme.spaceXs
                    spacing: Theme.spaceS
                }
            }
            // Inline alert (warning · danger · info · success · neutral): a
            // lasting state of the page, in the tone's -subtle ground.
            component Alert: Rectangle {
                id: al
                property string tone: "warning"
                property string title: ""
                property string text: ""
                readonly property color ink: al.tone === "danger" ? Theme.danger : al.tone === "info" ? Theme.info
                                           : al.tone === "success" ? Theme.success : al.tone === "neutral" ? Theme.textSecondary
                                           : Theme.warning
                width: parent ? parent.width : 0
                implicitHeight: alCol.implicitHeight + 2 * Theme.spaceS
                radius: Theme.radiusPrimary
                color: al.tone === "danger" ? Theme.dangerSubtle : al.tone === "info" ? Theme.infoSubtle
                     : al.tone === "success" ? Theme.successSubtle : al.tone === "neutral" ? Theme.surfaceRaised
                     : Theme.warningSubtle
                border.color: al.tone === "neutral" ? Theme.borderSubtle : "transparent"
                border.width: Theme.borderWidth1
                Text {
                    id: alIc
                    anchors.left: parent.left; anchors.leftMargin: Theme.spaceS + Theme.spaceXs
                    anchors.top: parent.top; anchors.topMargin: Theme.spaceS + Theme.borderWidth1
                    text: al.tone === "info" ? Theme.icBell : al.tone === "success" ? Theme.icCheck : Theme.icWarning
                    font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: al.ink
                }
                Column {
                    id: alCol
                    anchors.left: alIc.right; anchors.leftMargin: Theme.spaceS
                    anchors.right: parent.right; anchors.rightMargin: Theme.spaceS + Theme.spaceXs
                    anchors.top: parent.top; anchors.topMargin: Theme.spaceS
                    spacing: Theme.spaceXxs
                    TBody { visible: al.title !== ""; width: parent.width; text: al.title; color: al.ink; font.weight: Theme.fontWeightMedium; wrapMode: Text.WordWrap }
                    TBody { visible: al.text !== ""; width: parent.width; text: al.text; wrapMode: Text.WordWrap }
                }
            }
            // Button (design system: Button): secondary by default — the
            // surfaceRaised fill behind a borderStrong outline — `primary` is
            // the accent fill, `ghost` has neither. controlMd tall, or
            // controlSm with `size: "sm"`; spaceS + spaceXs of padding.
            component Pill: Rectangle {
                id: pb
                property string label: ""
                property string glyph: ""
                property bool primary: false
                property bool ghost: false
                property bool disabled: false
                property string size: "md"
                signal go()
                readonly property bool _sm: pb.size === "sm"
                width: pbRow.implicitWidth + 2 * (pb._sm ? Theme.spaceS : Theme.spaceS + Theme.spaceXs)
                height: pb._sm ? Theme.controlSm : Theme.controlMd
                radius: Theme.radiusPrimary
                color: pb.disabled ? (pb.ghost ? "transparent" : Theme.surfaceRaised)
                     : pb.primary ? (plMa.pressed ? Theme.accentPressed : plMa.containsMouse ? Theme.accentHover : Theme.accent)
                     : plMa.pressed ? Theme.surfacePressed : plMa.containsMouse ? Theme.surfaceHover
                     : pb.ghost ? "transparent" : Theme.surfaceRaised
                border.width: (pb.primary || pb.ghost) && !pb.disabled ? 0 : Theme.borderWidth1
                border.color: pb.disabled ? Theme.borderSubtle : Theme.borderStrong
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                activeFocusOnTab: !pb.disabled
                Keys.onSpacePressed: if (!pb.disabled) pb.go()
                Keys.onReturnPressed: if (!pb.disabled) pb.go()
                // the focus ring sits a border width outside the button
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -(Theme.borderWidth1 + Theme.focusWidth)
                    radius: Theme.radiusPrimary + Theme.borderWidth1 + Theme.focusWidth
                    color: "transparent"; visible: pb.activeFocus
                    border.color: Theme.focusRing; border.width: Theme.focusWidth
                }
                Row {
                    id: pbRow
                    anchors.centerIn: parent; spacing: Theme.spaceXs
                    Text {
                        visible: pb.glyph !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: pb.glyph; font.family: Theme.fontIcons
                        font.pixelSize: pb._sm ? Theme.iconSm : Theme.iconMd
                        color: pl.color
                    }
                    Text {
                        id: pl
                        anchors.verticalCenter: parent.verticalCenter
                        text: pb.label
                        color: pb.disabled ? Theme.textDisabled : pb.primary ? Theme.onAccent : Theme.textPrimary
                        font.family: Theme.type.body.family
                        font.pixelSize: pb._sm ? Theme.fontSizeS : Theme.fontSizeMd
                        font.weight: Theme.fontWeightMedium
                    }
                }
                MouseArea { id: plMa; anchors.fill: parent; enabled: !pb.disabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.go() }
            }
            // a ghost icon-only button (a row's remove ×)
            component IconBtn: Rectangle {
                id: ib
                property string glyph: Theme.icClose
                property bool danger: false
                signal go()
                width: Theme.controlSm; height: Theme.controlSm; radius: Theme.radiusPrimary
                color: ibMa.pressed ? Theme.surfacePressed : ibMa.containsMouse ? Theme.surfaceHover : "transparent"
                border.color: ib.activeFocus ? Theme.focusRing : "transparent"; border.width: Theme.focusWidth
                activeFocusOnTab: true
                Keys.onSpacePressed: ib.go()
                Keys.onReturnPressed: ib.go()
                Text {
                    anchors.centerIn: parent; text: ib.glyph
                    font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm
                    color: ib.danger && ibMa.containsMouse ? Theme.danger : Theme.textSecondary
                }
                MouseArea { id: ibMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.go() }
            }
            // a link-styled action beside a section header ("Add VPN…")
            component LinkBtn: TBody {
                id: lb
                signal go()
                color: Theme.accentText
                font.weight: Theme.fontWeightMedium
                font.underline: lbMa.containsMouse
                activeFocusOnTab: true
                Keys.onSpacePressed: lb.go()
                Keys.onReturnPressed: lb.go()
                MouseArea { id: lbMa; anchors.fill: parent; anchors.margins: -Theme.spaceXs; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lb.go() }
            }
            // Segmented control (design system: Segmented control): a sunken
            // well, the selected segment on surfaceSelected. `fill` splits the
            // row's width equally; `dim` disables every segment.
            component Seg: Rectangle {
                id: seg
                property var options: []           // [{ label, value }]
                property var value
                property bool dim: false
                property bool fill: false
                signal picked(var v)
                readonly property int _in: Theme.spaceXxs + Theme.borderWidth1
                implicitWidth: segRow.implicitWidth + 2 * seg._in
                width: seg.fill && parent ? parent.width : implicitWidth
                height: Theme.controlMd
                radius: Theme.radiusPrimary
                color: Theme.surfaceSunken
                border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                Row {
                    id: segRow
                    x: seg._in; y: seg._in
                    height: seg.height - 2 * seg._in
                    spacing: Theme.spaceXxs
                    Repeater {
                        model: seg.options
                        delegate: Rectangle {
                            id: sgi
                            required property var modelData
                            required property int index
                            readonly property bool sel: String(seg.value) === String(sgi.modelData.value)
                            width: seg.fill ? (seg.width - 2 * seg._in - (seg.options.length - 1) * segRow.spacing) / seg.options.length
                                            : sgl.implicitWidth + 2 * Theme.spaceS
                            height: segRow.height
                            radius: Theme.radiusSecondary
                            color: sgi.sel ? Theme.surfaceSelected : "transparent"
                            border.color: sgi.activeFocus ? Theme.focusRing : sgi.sel ? Theme.borderSubtle : "transparent"
                            border.width: sgi.activeFocus ? Theme.focusWidth : Theme.borderWidth1
                            activeFocusOnTab: !seg.dim
                            Keys.onSpacePressed: if (!seg.dim && !sgi.sel) seg.picked(sgi.modelData.value)
                            Keys.onReturnPressed: if (!seg.dim && !sgi.sel) seg.picked(sgi.modelData.value)
                            Text {
                                id: sgl
                                anchors.centerIn: parent
                                text: sgi.modelData.label
                                color: seg.dim ? Theme.textDisabled : (sgi.sel || sgMa.containsMouse) ? Theme.textPrimary : Theme.textSecondary
                                font.family: Theme.type.label.family
                                font.pixelSize: Theme.type.label.size
                                font.weight: Theme.type.label.weight
                            }
                            MouseArea {
                                id: sgMa; anchors.fill: parent; enabled: !seg.dim; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (!sgi.sel) seg.picked(sgi.modelData.value)
                            }
                        }
                    }
                }
            }
            // A setting row (Settings page, "Rows"): an optional controlLg icon
            // tile, the setting's name and what it does, and its control on
            // the right. The text wraps, so the row grows at a larger text
            // size instead of clipping.
            component SetRow: Item {
                id: sr
                property string glyph: ""
                property string title: ""
                property string desc: ""
                property bool dim: false
                default property alias control: srCtl.data
                width: parent ? parent.width : 0
                implicitHeight: Math.max(Theme.controlLg, srTexts.implicitHeight, srCtl.implicitHeight) + 2 * Theme.spaceXs
                Rectangle {
                    id: srTile
                    visible: sr.glyph !== ""
                    width: visible ? Theme.controlLg : 0; height: Theme.controlLg
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    radius: Theme.radiusPrimary
                    color: Theme.surfaceHover
                    Text {
                        anchors.centerIn: parent; text: sr.glyph
                        font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                        color: sr.dim ? Theme.textDisabled : Theme.textPrimary
                    }
                }
                Column {
                    id: srTexts
                    anchors.left: srTile.right; anchors.leftMargin: sr.glyph !== "" ? Theme.spaceS + Theme.spaceXs : 0
                    anchors.right: srCtl.left; anchors.rightMargin: Theme.spaceMd
                    anchors.verticalCenter: parent.verticalCenter
                    TBody { width: parent.width; text: sr.title; color: sr.dim ? Theme.textDisabled : Theme.textPrimary; wrapMode: Text.WordWrap }
                    TCaption { visible: sr.desc !== ""; width: parent.width; text: sr.desc; color: sr.dim ? Theme.textDisabled : Theme.textMuted; wrapMode: Text.WordWrap }
                }
                Row {
                    id: srCtl
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spaceS
                }
            }
            // a name and its value (a fact, not a setting), with an optional
            // status dot or one small action
            component KV: Item {
                id: kv
                property string k: ""; property string v: ""; property string dot: ""
                property bool action: false; property string actionLabel: ""
                signal act()
                width: parent ? parent.width : 0
                implicitHeight: Math.max(Theme.controlMd, kt.implicitHeight, kvRight.implicitHeight)
                TBody {
                    id: kt
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, kv.width / 2)
                    text: kv.k; elide: Text.ElideRight
                }
                Row {
                    id: kvRight
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spaceS
                    TBody {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !kv.action && kv.v !== ""
                        width: Math.min(implicitWidth, kv.width - kt.width - Theme.spaceMd - (kv.dot !== "" ? Theme.spaceMd : 0))
                        text: kv.v; color: Theme.textSecondary; elide: Text.ElideRight
                    }
                    Pill { visible: kv.action; anchors.verticalCenter: parent.verticalCenter; size: "sm"; label: kv.actionLabel; onGo: kv.act() }
                    Dot { anchors.verticalCenter: parent.verticalCenter; visible: kv.dot !== ""; state: kv.dot }
                }
            }
            // a switch row: name + optional description, the Switch at the
            // right. `dim` is the disabled state (a switch that can't apply).
            component ToggleRow: Item {
                id: tr
                property string title: ""; property string sub: ""; property bool on: false; property bool dim: false
                signal toggled()
                width: parent ? parent.width : 0
                implicitHeight: Math.max(Theme.controlLg, trTexts.implicitHeight + 2 * Theme.spaceXs)
                Column {
                    id: trTexts
                    anchors.left: parent.left; anchors.right: trTog.left; anchors.rightMargin: Theme.spaceMd
                    anchors.verticalCenter: parent.verticalCenter
                    TBody { width: parent.width; text: tr.title; color: tr.dim ? Theme.textDisabled : Theme.textPrimary; wrapMode: Text.WordWrap }
                    TCaption { visible: tr.sub !== ""; width: parent.width; text: tr.sub; color: tr.dim ? Theme.textDisabled : Theme.textMuted; wrapMode: Text.WordWrap }
                }
                Toggle { id: trTog; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; on: tr.on; disabled: tr.dim; onToggled: if (!tr.dim) tr.toggled() }
            }
            // a text field's box (Text field): surfaceSunken behind a
            // borderStrong outline; hover textMuted, focus focusRing. The
            // outline is fieldBorderWidth, so it survives `stroke = none`.
            component FieldBox: Rectangle {
                property bool focused: false
                property bool hovered: fbHov.hovered
                height: Theme.controlMd
                radius: Theme.radiusPrimary
                color: Theme.surfaceSunken
                border.width: Theme.fieldBorderWidth
                border.color: focused ? Theme.focusRing : hovered ? Theme.textMuted : Theme.borderStrong
                Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                HoverHandler { id: fbHov }
            }
            // DropRow, Slider, Toggle, ListRow and SectionTitle are the shared
            // qmldir components (Select, Slider, Switch, List row, Section header).

            // ════════ layout: side navigation + the page pane ════════
            // Side navigation: 196px (7 × controlMd) on the window's
            // surfaceBase, spaceS + spaceXs × spaceS padding, spaceMd between
            // groups; items controlMd tall on the radiusSecondary corner. The
            // selected item is an accentSubtle FILL (no edge bar), its label
            // textPrimary at medium weight and its icon accentText.
            Item {
                id: rail
                // 196px; wider in step with Text size, so labels keep fitting
                width: Theme.grow(7 * Theme.controlMd)
                anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
                Column {
                    id: railCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                    anchors.topMargin: Theme.spaceS + Theme.spaceXs
                    spacing: Theme.spaceMd
                    // brand: the sheep mark and the app name
                    Row {
                        height: Theme.controlLg; spacing: Theme.spaceS
                        leftPadding: Theme.spaceS
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.iconXl; height: Theme.iconXl
                            Image {
                                id: railMark
                                anchors.fill: parent
                                source: Qt.resolvedUrl("assets/sheep.svg")
                                sourceSize.width: 2 * Theme.iconXl; sourceSize.height: 2 * Theme.iconXl
                                visible: false
                            }
                            MultiEffect { anchors.fill: railMark; source: railMark; colorization: 1; colorizationColor: Theme.textPrimary }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Settings"; color: Theme.textPrimary
                            font.family: Theme.type.h4.family; font.pixelSize: Theme.type.h4.size; font.weight: Theme.type.h4.weight
                        }
                    }
                    Column {
                        width: parent.width; spacing: Theme.spaceXxs
                        Repeater {
                            model: root.navItems
                            delegate: Rectangle {
                                id: navItem
                                required property var modelData
                                required property int index
                                readonly property bool sel: root.pane === navItem.index
                                width: parent.width; height: Theme.controlMd; radius: Theme.radiusSecondary
                                color: navItem.sel ? Theme.accentSubtle : nMa.containsMouse ? Theme.surfaceHover : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } }
                                border.color: navItem.activeFocus ? Theme.focusRing : "transparent"
                                border.width: Theme.focusWidth
                                activeFocusOnTab: true
                                Keys.onSpacePressed: root.pane = navItem.index
                                Keys.onReturnPressed: root.pane = navItem.index
                                // Up and Down move between the items (focus; Enter opens)
                                Keys.onUpPressed: if (navItem.index > 0) navItem.nextItemInFocusChain(false).forceActiveFocus()
                                Keys.onDownPressed: if (navItem.index < root.navItems.length - 1) navItem.nextItemInFocusChain(true).forceActiveFocus()
                                Row {
                                    anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                                    anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                                    anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spaceS
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Theme.iconMd; horizontalAlignment: Text.AlignHCenter
                                        text: root.g(navItem.modelData.ic); font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd
                                        color: navItem.sel ? Theme.accentText : nMa.containsMouse ? Theme.textPrimary : Theme.textSecondary
                                    }
                                    TBody {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - Theme.iconMd - parent.spacing
                                        text: navItem.modelData.label; elide: Text.ElideRight
                                        color: (navItem.sel || nMa.containsMouse) ? Theme.textPrimary : Theme.textSecondary
                                        font.weight: navItem.sel ? Theme.fontWeightMedium : Theme.type.body.weight
                                    }
                                }
                                MouseArea { id: nMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pane = navItem.index }
                            }
                        }
                    }
                }
                // footer: close, and the version in the mono caption
                Column {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                    anchors.bottomMargin: Theme.spaceS + Theme.spaceXs
                    spacing: Theme.spaceXxs
                    Pill { ghost: true; glyph: Theme.icClose; label: "Close"; onGo: Globals.settingsOpen = false }
                    Text {
                        leftPadding: Theme.spaceS; topPadding: Theme.spaceXs
                        text: "ewe " + Globals.version
                        color: Theme.textMuted
                        font.family: Theme.fontMono; font.pixelSize: Theme.fontSizeXs
                    }
                }
            }
            // the pane (App shell): inset spaceS from the window's edges,
            // surfaceRaised with the borderSubtle outline and radiusRounded;
            // the page title and its description, then the page, spaceMd + spaceS
            // (24) from the sides.
            Rectangle {
                id: pagePane
                anchors.left: rail.right; anchors.right: parent.right
                anchors.top: parent.top; anchors.bottom: parent.bottom
                anchors.topMargin: Theme.spaceS; anchors.bottomMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                radius: Theme.radiusRounded
                color: Theme.surfaceRaised
                border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                Column {
                    id: pageHead
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.leftMargin: Theme.spaceMd + Theme.spaceS; anchors.rightMargin: Theme.spaceMd + Theme.spaceS
                    anchors.topMargin: Theme.spaceMd
                    spacing: Theme.spaceXxs
                    Text {
                        width: parent.width
                        text: root.navItems[root.pane].label; color: Theme.textPrimary
                        font.family: Theme.type.h2.family; font.pixelSize: Theme.type.h2.size
                        font.weight: Theme.type.h2.weight; font.letterSpacing: Theme.type.h2.letterSpacing
                        elide: Text.ElideRight
                    }
                    TBody { width: parent.width; text: root.navItems[root.pane].desc || ""; color: Theme.textSecondary; wrapMode: Text.WordWrap }
                }
                Flickable {
                    id: pageFlick
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: pageHead.bottom; anchors.bottom: parent.bottom
                    anchors.topMargin: Theme.spaceS + Theme.spaceXs
                    anchors.leftMargin: Theme.spaceMd + Theme.spaceS; anchors.rightMargin: Theme.spaceMd + Theme.spaceS
                    anchors.bottomMargin: Theme.borderWidth1
                    contentHeight: paneLoader.item ? paneLoader.item.implicitHeight + Theme.spaceMd : 0
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    Loader { id: paneLoader; width: parent.width; sourceComponent: ({ system: cSystem, displays: cDisplays, network: cNetwork, defaults: cDefaults, input: cKeyboard, shortcuts: cShortcuts, layout: cLayout, theme: cTheme, wallpaper: cWallpaper, saver: cSaver, power: cPower, dock: cDock, startup: cStartup, user: cUser, accessibility: cAccessibility })[root.paneKey] }
                }
            }

            // ════════ PANE 0 — System ════════
            Component {
                id: cSystem
                Column {
                    spacing: Theme.spaceS
                    SectionTitle { text: "Sound" }
                    Card {
                        id: audioCard
                        PwObjectTracker { objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : [] }
                        property var sink: Pipewire.defaultAudioSink
                        property bool muted: sink && sink.audio ? sink.audio.muted : false
                        KV { k: "Output"; v: audioCard.sink ? (audioCard.sink.description || audioCard.sink.nickname || audioCard.sink.name) : "—"; dot: audioCard.sink ? (audioCard.muted ? "bad" : "ok") : "bad" }
                        KV { k: "Volume"; v: (audioCard.sink && audioCard.sink.audio ? Math.round(audioCard.sink.audio.volume * 100) : 0) + "%" + (audioCard.muted ? " · muted" : "") }
                        KV { k: "Muted"; action: audioCard.muted; actionLabel: "Unmute"; v: audioCard.muted ? "" : "No"; dot: audioCard.muted ? "bad" : "ok"; onAct: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"]) }
                    }
                    SectionTitle { text: "Desktop portals" }
                    Note { text: "They let apps open links and files, and let the browser open apps back." }
                    Card {
                        KV { k: "graphical-session.target"; v: root.diag.gsession || "?"; dot: root.diag.gsession === "active" ? "ok" : "bad" }
                        KV { k: "xdg-desktop-portal"; v: root.diag.portal || "?"; dot: root.diag.portal === "active" ? "ok" : "bad" }
                        KV { k: "Portal: Hyprland"; v: root.diag.portal_hypr || "?"; dot: root.diag.portal_hypr === "active" ? "ok" : "bad" }
                        KV { k: "Portal: GTK"; v: root.diag.portal_gtk || "?"; dot: root.diag.portal_gtk === "active" ? "ok" : "bad" }
                        KV { k: "Opening links in apps (OpenURI)"; v: root.diag.handoff === "ok" ? "Working" : "Unavailable"; dot: root.diag.handoff === "ok" ? "ok" : "bad" }
                        KV { k: "Default browser"; v: root.appNameForId(root.diag.browser) }
                    }
                    SectionTitle { text: "System" }
                    Card {
                        KV { k: "Graphics driver"; v: root.diag.gpu || "?"; dot: "info" }
                        KV { k: "VPN"; v: Globals.vpnActive ? "Connected" : "Off"; dot: Globals.vpnActive ? "ok" : "info" }
                        KV { k: "When idle"; v: root.idlePolicyText(); dot: "info" }
                        KV { k: "Memory"; v: root.diag.mem || "?"; dot: "info" }
                        KV { k: "Disk /"; v: root.diag.disk || "?"; dot: "info" }
                    }
                    Pill { label: "Check again"; glyph: Theme.icRefresh; onGo: root.refresh() }
                }
            }

            // ════════ PANE 1 — Displays ════════
            Component {
                id: cDisplays
                Column {
                    spacing: Theme.spaceS
                    Card {
                        visible: HyprMon.monitors.length === 0
                        TBody { width: parent.width; text: HyprMon.loading ? "Looking for displays…" : "Hyprland reports no displays"; color: Theme.textSecondary }
                    }
                    SectionTitle { visible: HyprMon.monitors.length > 0; text: "Arrangement" }
                    Note { visible: HyprMon.monitors.length > 0; text: "Drag a display to move it; edges snap together." }
                    Card {
                        visible: HyprMon.monitors.length > 0
                        Item {
                            id: arena
                            width: parent.width; height: Theme.panelSm / 2 + Theme.spaceMd + Theme.spaceS
                            readonly property var specs: root.dispSpecs.filter(function (s) { return !s.disabled })
                            readonly property real pad: Theme.spaceS + Theme.spaceXs
                            readonly property real spanW: { var mx = 1; for (var i = 0; i < specs.length; i++) mx = Math.max(mx, specs[i].x + root.specW(specs[i])); return mx }
                            readonly property real spanH: { var mx = 1; for (var i = 0; i < specs.length; i++) mx = Math.max(mx, specs[i].y + root.specH(specs[i])); return mx }
                            readonly property real factor: Math.min((width - 2 * pad) / spanW, (height - 2 * pad) / spanH)
                            Repeater {
                                model: arena.specs
                                delegate: Rectangle {
                                    id: monBox
                                    required property var modelData
                                    width: root.specW(modelData) * arena.factor; height: root.specH(modelData) * arena.factor
                                    radius: Theme.radiusPrimary
                                    x: arena.pad + modelData.x * arena.factor
                                    y: arena.pad + modelData.y * arena.factor
                                    color: dragMa.drag.active ? Theme.accentSubtle : dragMa.containsMouse ? Theme.surfaceHover : Theme.surfaceRaised
                                    border.color: dragMa.drag.active ? Theme.accentText : Theme.borderStrong
                                    border.width: dragMa.drag.active ? Theme.borderWidth2 : Theme.borderWidth1
                                    Column { anchors.centerIn: parent; spacing: Theme.spaceXxs
                                        Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: Theme.spaceXs
                                            TStrong { anchors.verticalCenter: parent.verticalCenter; text: monBox.modelData.name }
                                            Text { anchors.verticalCenter: parent.verticalCenter; visible: monBox.modelData.primary; text: Theme.icStar; font.family: Theme.fontIcons; font.pixelSize: Theme.iconXs; color: Theme.accentText }
                                        }
                                        TCaption { anchors.horizontalCenter: parent.horizontalCenter; text: HyprMon.modeRes(monBox.modelData.mode).replace("x", " × ") + " · " + Math.round(HyprMon.modeHz(monBox.modelData.mode)) + " Hz" }
                                        TCaption { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(Number(monBox.modelData.scale) * 100) + "%" }
                                    }
                                    MouseArea {
                                        id: dragMa; anchors.fill: parent; cursorShape: Qt.SizeAllCursor; hoverEnabled: true
                                        drag.target: monBox; drag.axis: Drag.XAndYAxis
                                        drag.minimumX: 0; drag.maximumX: arena.width - monBox.width
                                        drag.minimumY: 0; drag.maximumY: arena.height - monBox.height
                                        onReleased: root.snapDrop(monBox.modelData.name, (monBox.x - arena.pad) / arena.factor, (monBox.y - arena.pad) / arena.factor)
                                    }
                                }
                            }
                        }
                        Row {
                            spacing: Theme.spaceS
                            Pill { label: "Arrange left to right"; onGo: root.autoArrange() }
                            Pill { label: "Reset displays"; onGo: { HyprMon.resetDisplays(); root.flashApplied("Saved profile applied again") } }
                        }
                        Note { visible: !HyprMon.profiles[HyprMon.currentKey()]; text: "This set of displays has no saved profile yet. Change any setting, or drag a display, to create one." }
                    }
                    SectionTitle { visible: HyprMon.monitors.length > 0; text: "Displays" }
                    Repeater {
                        model: root.dispSpecs
                        delegate: Card {
                            id: monCard
                            required property var modelData
                            readonly property var raw: { var ms = HyprMon.monitors; for (var i = 0; i < ms.length; i++) if (ms[i].name === modelData.name) return ms[i]; return null }
                            readonly property var mm: root.modeMapFor(raw, modelData)
                            readonly property string curRes: HyprMon.modeRes(modelData.mode)
                            readonly property var resOpts: mm.resList.map(function (r) { return { label: r.replace("x", " × "), value: r } })
                            readonly property var hzOpts: (mm.byRes[curRes] || []).map(function (o) { return { label: o.label, value: o.mode } })
                            readonly property var mirrorOpts: { var out = [{ label: "Off", value: "" }], ss = root.dispSpecs; for (var i = 0; i < ss.length; i++) if (ss[i].name !== modelData.name && !ss[i].disabled) out.push({ label: ss[i].name, value: ss[i].name }); return out }
                            readonly property int enabledCount: { var n = 0, ss = root.dispSpecs; for (var i = 0; i < ss.length; i++) if (!ss[i].disabled) n++; return n }
                            Item {
                                width: parent.width; height: Math.max(Theme.controlLg, monHead.implicitHeight)
                                Column {
                                    id: monHead
                                    anchors.left: parent.left; anchors.right: monToggle.left; anchors.rightMargin: Theme.spaceMd
                                    anchors.verticalCenter: parent.verticalCenter
                                    Row {
                                        spacing: Theme.spaceS
                                        TStrong { anchors.verticalCenter: parent.verticalCenter; text: monCard.modelData.name }
                                        Badge { anchors.verticalCenter: parent.verticalCenter; visible: root.isLaptop(monCard.modelData); label: "Built-in"; tone: "neutral"; solid: false }
                                        Badge { anchors.verticalCenter: parent.verticalCenter; visible: monCard.modelData.primary; label: "Primary"; tone: "accent"; solid: false }
                                    }
                                    TCaption { width: parent.width; text: monCard.modelData.desc; elide: Text.ElideRight }
                                }
                                Toggle {
                                    id: monToggle
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    on: !monCard.modelData.disabled
                                    onToggled: {
                                        if (!monCard.modelData.disabled && monCard.enabledCount <= 1) { root.errorMsg = "One display has to stay on."; return }
                                        root.riskyChange(monCard.modelData.name, { disabled: !monCard.modelData.disabled })
                                    }
                                }
                            }
                            Column {
                                width: parent.width; spacing: Theme.spaceXs; visible: !monCard.modelData.disabled
                                Divider {}
                                DropRow {
                                    label: "Resolution"; ddId: "res-" + monCard.modelData.name; options: monCard.resOpts; value: monCard.curRes
                                    onPicked: function (v) { var hzs = monCard.mm.byRes[v] || []; if (hzs.length) root.riskyChange(monCard.modelData.name, { mode: hzs[0].mode }) }
                                }
                                DropRow {
                                    label: "Refresh rate"; ddId: "hz-" + monCard.modelData.name; options: monCard.hzOpts; value: monCard.modelData.mode
                                    onPicked: function (v) { root.riskyChange(monCard.modelData.name, { mode: v }) }
                                }
                                SetRow {
                                    title: "Scale"
                                    desc: "Logical size " + root.specW(monCard.modelData) + " × " + root.specH(monCard.modelData)
                                    Seg {
                                        anchors.verticalCenter: parent.verticalCenter
                                        options: [1, 1.25, 1.5, 1.75, 2].map(function (x) { return { label: Math.round(x * 100) + "%", value: x } })
                                        value: [1, 1.25, 1.5, 1.75, 2].filter(function (x) { return Math.abs(monCard.modelData.scale - x) < 0.001 })[0]
                                        onPicked: function (v) { root.riskyChange(monCard.modelData.name, { scale: v }) }
                                    }
                                    FieldBox {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Theme.controlXl + Theme.spaceMd; focused: scIn.activeFocus
                                        TextInput {
                                            id: scIn
                                            anchors.fill: parent; anchors.leftMargin: Theme.spaceXs; anchors.rightMargin: Theme.spaceXs
                                            horizontalAlignment: TextInput.AlignHCenter; verticalAlignment: TextInput.AlignVCenter
                                            color: Theme.textPrimary; font.family: Theme.type.mono.family; font.pixelSize: Theme.type.mono.size
                                            text: Number(monCard.modelData.scale).toFixed(2)
                                            onAccepted: { var v = parseFloat(text); if (!isNaN(v) && v >= 0.5 && v <= 3) root.riskyChange(monCard.modelData.name, { scale: Math.round(v * 100) / 100 }) }
                                        }
                                    }
                                }
                                Note {
                                    readonly property var wh: HyprMon.modeRes(monCard.modelData.mode).split("x")
                                    readonly property bool frac: (wh[0] / monCard.modelData.scale) % 1 !== 0 || (wh[1] / monCard.modelData.scale) % 1 !== 0
                                    visible: frac
                                    color: Theme.warning
                                    text: "This scale doesn't divide the resolution evenly, so Hyprland rounds it to whole pixels."
                                }
                                DropRow {
                                    label: "Rotation"; ddId: "rot-" + monCard.modelData.name
                                    options: [{ label: "Normal", value: 0 }, { label: "90°", value: 1 }, { label: "180°", value: 2 }, { label: "270°", value: 3 }]
                                    value: monCard.modelData.transform
                                    onPicked: function (v) { root.riskyChange(monCard.modelData.name, { transform: Number(v) }) }
                                }
                                DropRow {
                                    visible: root.dispSpecs.length > 1
                                    label: "Mirror"; ddId: "mir-" + monCard.modelData.name
                                    options: monCard.mirrorOpts; value: monCard.modelData.mirror
                                    onPicked: function (v) { root.riskyChange(monCard.modelData.name, { mirror: v }) }
                                }
                                ToggleRow { title: "Variable refresh rate"; sub: "Smoother games and video"; on: monCard.modelData.vrr; onToggled: root.directChange(monCard.modelData.name, { vrr: !monCard.modelData.vrr }) }
                                ToggleRow { title: "10-bit color"; on: monCard.modelData.bitdepth === 10; onToggled: root.directChange(monCard.modelData.name, { bitdepth: monCard.modelData.bitdepth === 10 ? 8 : 10 }) }
                                KV { k: "Position"; v: monCard.modelData.x + ", " + monCard.modelData.y }
                                KV { visible: !monCard.modelData.primary; k: "Primary display"; action: true; actionLabel: "Make primary"; onAct: root.setPrimary(monCard.modelData.name) }
                            }
                            Note { visible: monCard.modelData.disabled; text: "This display is off. Switch it on to use it again." }
                        }
                    }
                    Note { text: "Changes apply at once. A change that can black out a display goes back on its own after 10 seconds unless you keep it. Each set of displays keeps its own profile, restored when you dock or undock and at startup." }
                    Note { text: "Screen goes black when you plug in the charger? The saved profile comes back a moment later. If the built-in panel stays black, that is the xe driver's panel self-refresh: use Reset displays, or start with xe.enable_psr=0." }
                }
            }

            // ════════ PANE 2 — Network ════════
            Component {
                id: cNetwork
                Column {
                    spacing: Theme.spaceS
                    // Wired / Ethernet
                    SectionTitle { text: "Wired" }
                    Card {
                        spacing: 0
                        TBody { width: parent.width; visible: root.wiredList.length === 0; text: "No wired connection"; color: Theme.textSecondary }
                        Repeater {
                            model: root.wiredList
                            delegate: ListRow {
                                required property var modelData
                                glyph: Theme.icEthernet
                                label: modelData.name
                                desc: modelData.dev
                                active: modelData.state === "activated"
                                selected: modelData.state === "activated"
                                kind: modelData.state === "activated" ? "Connected" : ""
                            }
                        }
                    }
                    // Wi-Fi
                    Item {
                        width: parent.width; height: Math.max(wifiTitle.implicitHeight, Theme.controlLg)
                        SectionTitle { id: wifiTitle; first: false; topPadding: 0; bottomPadding: 0; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Wi-Fi" }
                        Toggle { visible: root.hasWifi; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; on: root.wifiOn; onToggled: { Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiOn ? "off" : "on"]); wifiRescan.restart() } }
                        TCaption { visible: !root.hasWifi; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "Not available" }
                    }
                    Alert {
                        visible: !root.hasWifi; tone: "neutral"
                        title: "No Wi-Fi adapter"
                        text: "This machine has no wireless device, which is common in virtual machines. Use a wired connection or plug in a USB Wi-Fi adapter."
                    }
                    Card {
                        visible: root.hasWifi && root.wifiOn
                        spacing: 0
                        TBody { width: parent.width; visible: root.wifiList.length === 0; text: "Looking for networks…"; color: Theme.textSecondary }
                        Repeater {
                            model: root.wifiList.slice(0, 8)
                            delegate: Column {
                                id: wRow
                                required property var modelData
                                width: parent.width
                                ListRow {
                                    glyph: wRow.modelData.signal >= 66 ? Theme.icWifi : (wRow.modelData.signal >= 33 ? Theme.icWifiMed : Theme.icWifiLow)
                                    label: wRow.modelData.ssid
                                    active: wRow.modelData.active; selected: wRow.modelData.active; check: wRow.modelData.active
                                    onClicked: root.connectWifi(wRow.modelData.ssid, wRow.modelData.sec)
                                    Text { visible: wRow.modelData.sec !== ""; anchors.verticalCenter: parent.verticalCenter; text: Theme.icLock; font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm; color: Theme.textMuted }
                                }
                                Item {
                                    width: parent.width; visible: root.pwTarget === wRow.modelData.ssid
                                    height: visible ? Theme.controlMd + 2 * Theme.spaceXs : 0
                                    FieldBox {
                                        anchors.left: parent.left; anchors.right: joinBtn.left; anchors.rightMargin: Theme.spaceS
                                        anchors.verticalCenter: parent.verticalCenter
                                        focused: pwIn.activeFocus
                                        TextInput {
                                            id: pwIn
                                            anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                                            verticalAlignment: TextInput.AlignVCenter; echoMode: TextInput.Password; clip: true
                                            color: Theme.textPrimary; font.family: Theme.type.body.family; font.pixelSize: Theme.type.body.size
                                            onTextChanged: root.pwText = text; Component.onCompleted: forceActiveFocus(); onAccepted: root.connectWifi(wRow.modelData.ssid, wRow.modelData.sec)
                                            TBody { anchors.verticalCenter: parent.verticalCenter; visible: pwIn.text.length === 0; text: "Password"; color: Theme.textMuted }
                                        }
                                    }
                                    Pill { id: joinBtn; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; primary: true; label: "Join"; onGo: root.connectWifi(wRow.modelData.ssid, wRow.modelData.sec) }
                                }
                            }
                        }
                    }
                    // VPN
                    Item {
                        width: parent.width; height: Math.max(vpnTitle.implicitHeight, Theme.controlMd)
                        SectionTitle { id: vpnTitle; first: false; topPadding: 0; bottomPadding: 0; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "VPN" }
                        LinkBtn { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "Add VPN…"; onGo: Quickshell.execDetached(["nm-connection-editor"]) }
                    }
                    Card {
                        spacing: 0
                        Column {
                            width: parent.width; visible: root.vpnList.length === 0
                            TBody { text: "No VPN connections yet" }
                            TCaption { width: parent.width; text: "Add one with Add VPN…"; wrapMode: Text.WordWrap }
                        }
                        Repeater {
                            model: root.vpnList
                            delegate: ListRow {
                                required property var modelData
                                glyph: Theme.icVpn
                                label: modelData.name
                                active: modelData.active; selected: modelData.active
                                kind: modelData.active ? "Connected" : (hovered ? "Connect" : "")
                                onClicked: { Quickshell.execDetached(["nmcli", "connection", modelData.active ? "down" : "up", modelData.name]); vpnRescan.restart() }
                            }
                        }
                    }
                    // SSH
                    Item {
                        width: parent.width; height: Math.max(sshTitle.implicitHeight, Theme.controlMd)
                        SectionTitle { id: sshTitle; first: false; topPadding: 0; bottomPadding: 0; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "SSH hosts" }
                        LinkBtn { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "Edit config"; onGo: Quickshell.execDetached(["kitty", "-e", "sh", "-c", "${EDITOR:-micro} ~/.ssh/config"]) }
                    }
                    Card {
                        spacing: 0
                        Column {
                            width: parent.width; visible: root.sshHosts.length === 0
                            TBody { text: "No hosts in ~/.ssh/config" }
                            TCaption { width: parent.width; text: "Add one with Edit config."; wrapMode: Text.WordWrap }
                        }
                        Repeater {
                            model: root.sshHosts
                            delegate: ListRow {
                                required property var modelData
                                glyph: Theme.icSsh
                                label: modelData
                                kind: hovered ? "Connect" : ""
                                onClicked: Quickshell.execDetached(["kitty", "-e", "ssh", modelData])
                            }
                        }
                    }
                    // Status
                    SectionTitle { text: "Status" }
                    Card {
                        TBody { width: parent.width; visible: root.netActive.length === 0 && root.ipList.length === 0; text: "No active connections"; color: Theme.textSecondary }
                        Repeater {
                            model: root.netActive
                            delegate: KV { required property var modelData; k: modelData.name + " (" + modelData.type + ")"; v: modelData.dev + " · " + modelData.state; dot: modelData.state === "activated" ? "ok" : "info" }
                        }
                        Repeater { model: root.ipList; delegate: KV { required property var modelData; k: "IP address"; v: modelData } }
                    }
                }
            }

            // ════════ PANE 3 — Default apps ════════
            Component {
                id: cDefaults
                Column {
                    id: defCol
                    spacing: Theme.spaceS
                    property string openCat: ""
                    Repeater {
                        model: root.appCats
                        delegate: Card {
                            id: appCard
                            required property var modelData
                            readonly property string curId: root.defaults[modelData.key] || ""
                            readonly property var choices: root.appChoices[modelData.key] || []
                            readonly property bool open: defCol.openCat === modelData.key
                            // the keys are also the map keys: show them in sentence case
                            SetRow {
                                glyph: root.g(appCard.modelData.ic)
                                title: appCard.modelData.key.charAt(0) + appCard.modelData.key.slice(1).toLowerCase()
                                // the Select trigger (Select card)
                                FieldBox {
                                    id: defBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.panelSm / 2 + Theme.spaceLg; focused: appCard.open || activeFocus
                                    activeFocusOnTab: true
                                    Keys.onSpacePressed: defCol.openCat = appCard.open ? "" : appCard.modelData.key
                                    Keys.onReturnPressed: defCol.openCat = appCard.open ? "" : appCard.modelData.key
                                    TBody {
                                        anchors.left: parent.left; anchors.leftMargin: Theme.spaceS
                                        anchors.right: defChev.left; anchors.rightMargin: Theme.spaceXs
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.appNameForId(appCard.curId); elide: Text.ElideRight
                                    }
                                    Text {
                                        id: defChev
                                        anchors.right: parent.right; anchors.rightMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter
                                        text: appCard.open ? Theme.icChevronUp : Theme.icChevronDown
                                        font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: Theme.textSecondary
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: defCol.openCat = (appCard.open ? "" : appCard.modelData.key) }
                                }
                            }
                            Column {
                                width: parent.width; visible: appCard.open; spacing: 0
                                Divider {}
                                TBody { width: parent.width; topPadding: Theme.spaceS; visible: appCard.choices.length === 0; text: "No installed app opens this type"; color: Theme.textSecondary }
                                Repeater {
                                    model: appCard.choices
                                    delegate: Rectangle {
                                        id: choice
                                        required property var modelData
                                        readonly property var entry: root.entryForId(modelData)
                                        readonly property bool isCur: String(appCard.curId).replace(/\.desktop$/, "") === String(modelData).replace(/\.desktop$/, "")
                                        width: parent.width; height: Theme.controlLg; radius: Theme.radiusSecondary
                                        color: eMa.pressed ? Theme.surfacePressed : choice.isCur ? Theme.accentSubtle : eMa.containsMouse ? Theme.surfaceHover : "transparent"
                                        Row {
                                            anchors.left: parent.left; anchors.leftMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spaceS + Theme.spaceXs
                                            Image { anchors.verticalCenter: parent.verticalCenter; width: Theme.iconLg; height: Theme.iconLg; sourceSize.width: 2 * Theme.iconLg; sourceSize.height: 2 * Theme.iconLg; mipmap: true; source: choice.entry && choice.entry.icon ? Quickshell.iconPath(choice.entry.icon, "application-x-executable") : Quickshell.iconPath("application-x-executable") }
                                            TBody { anchors.verticalCenter: parent.verticalCenter; text: choice.entry ? (choice.entry.name || choice.modelData) : choice.modelData; font.weight: choice.isCur ? Theme.fontWeightMedium : Theme.type.body.weight }
                                        }
                                        Text { anchors.right: parent.right; anchors.rightMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter; visible: choice.isCur; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: Theme.accentText }
                                        MouseArea { id: eMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.setDefaultApp(appCard.modelData.key, choice.modelData); defCol.openCat = "" } }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ════════ PANE 4 — Keyboard and mouse ════════
            Component {
                id: cKeyboard
                Column {
                    id: kbPane
                    spacing: Theme.spaceS
                    property string kbQuery: ""
                    property bool advOpen: false
                    function nameOf(code) { for (var i = 0; i < root.kbPresets.length; i++) if (root.kbPresets[i].c === code) return root.kbPresets[i].n; return code }
                    function variantOpts(code) {
                        var vs = root.kbVariants[code] || [""]
                        return vs.map(function (v) { return { label: v === "" ? "Default" : (root.kbVariantNames[code + "/" + v] || v), value: v } })
                    }
                    // layouts not already active, matching the search query (name or code)
                    function filtered() {
                        var q = kbPane.kbQuery.trim().toLowerCase()
                        var act = root.kbActive.map(function (l) { return l.code })
                        var out = []
                        for (var i = 0; i < root.kbPresets.length; i++) {
                            var p = root.kbPresets[i]
                            if (act.indexOf(p.c) >= 0) continue
                            if (q === "" || p.n.toLowerCase().indexOf(q) >= 0 || p.c.toLowerCase().indexOf(q) >= 0) out.push(p)
                        }
                        return out
                    }
                    // effective mouse values for the selected device (override → global)
                    readonly property var devOv: root.devTarget !== "" ? (root.devOverrides[root.devTarget] || ({})) : ({})
                    readonly property real effSens: root.devTarget !== "" && devOv.sensitivity !== undefined ? devOv.sensitivity : root.inp.sensitivity
                    readonly property bool effNat: root.devTarget !== "" && devOv.natural_scroll !== undefined ? devOv.natural_scroll : (root.inp.natural_scroll === true)
                    readonly property bool effLeft: root.devTarget !== "" && devOv.left_handed !== undefined ? devOv.left_handed : (root.inp.left_handed === true)
                    readonly property string effAccel: root.devTarget !== "" && devOv.accel_profile !== undefined ? devOv.accel_profile : root.inp.accel_profile
                    function setMouse(patch) {
                        if (root.devTarget !== "") root.applyDevice(root.devTarget, patch)
                        else root.applyInput(patch)
                    }
                    // one layout row: controlLg + spaceXs, so a drag lands on a slot
                    readonly property int rowH: Theme.controlLg + Theme.spaceXs

                    Card {
                        visible: !root.inpLoaded
                        TBody { width: parent.width; text: "Reading your input settings…"; color: Theme.textSecondary }
                    }

                    SectionTitle { visible: root.inpLoaded; text: "Keyboard layouts" }
                    Note { visible: root.inpLoaded; text: "Drag a layout to reorder. The first one is the default." }
                    Card {
                        visible: root.inpLoaded
                        Item {
                            // when a variant menu is open its list must not be
                            // covered by the search field below — grow to fit
                            width: parent.width
                            height: {
                                var h = root.kbActive.length * kbPane.rowH
                                if (Globals.openDd.indexOf("kbvar-") === 0) {
                                    var idx = parseInt(Globals.openDd.slice(6)) || 0
                                    h = Math.max(h, idx * kbPane.rowH + Theme.controlLg + Theme.panelSm / 2)
                                }
                                return h
                            }
                            Repeater {
                                model: root.kbActive
                                delegate: Item {
                                    id: kbRow
                                    required property var modelData
                                    required property int index
                                    width: parent.width; height: kbPane.rowH
                                    y: index * kbPane.rowH
                                    z: rowDrag.drag.active || Globals.openDd === ("kbvar-" + index) ? 10 : 1
                                    Rectangle {
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                        height: Theme.controlLg; radius: Theme.radiusSecondary
                                        color: rowDrag.drag.active ? Theme.surfacePressed : rowDrag.containsMouse ? Theme.surfaceHover : "transparent"
                                        border.color: rowDrag.drag.active ? Theme.borderStrong : Theme.borderSubtle; border.width: Theme.borderWidth1
                                        Text { id: kbGlyph; anchors.left: parent.left; anchors.leftMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter; text: Theme.icKeyboard; font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: Theme.textSecondary }
                                        TBody {
                                            anchors.left: kbGlyph.right; anchors.leftMargin: Theme.spaceS + Theme.spaceXs
                                            anchors.right: kbRowRight.left; anchors.rightMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter
                                            text: kbPane.nameOf(kbRow.modelData.code) + " (" + kbRow.modelData.code + ")"
                                            font.weight: kbRow.index === 0 ? Theme.fontWeightMedium : Theme.type.body.weight; elide: Text.ElideRight
                                        }
                                        Row {
                                            id: kbRowRight
                                            anchors.right: parent.right; anchors.rightMargin: Theme.spaceXs; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spaceS
                                            Badge { anchors.verticalCenter: parent.verticalCenter; visible: kbRow.index === 0; label: "Default"; tone: "accent"; solid: false }
                                            FieldBox {
                                                visible: kbPane.variantOpts(kbRow.modelData.code).length > 1
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: Theme.panelSm / 3; height: Theme.controlSm
                                                focused: Globals.openDd === ("kbvar-" + kbRow.index)
                                                TCaption { anchors.left: parent.left; anchors.leftMargin: Theme.spaceS; anchors.right: kvChev.left; anchors.rightMargin: Theme.spaceXs; anchors.verticalCenter: parent.verticalCenter; text: kbRow.modelData.variant === "" ? "Default" : kbRow.modelData.variant; color: Theme.textPrimary; elide: Text.ElideRight }
                                                Text { id: kvChev; anchors.right: parent.right; anchors.rightMargin: Theme.spaceXs; anchors.verticalCenter: parent.verticalCenter; text: Theme.icChevronDown; font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm; color: Theme.textSecondary }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Globals.openDd = Globals.openDd === ("kbvar-" + kbRow.index) ? "" : ("kbvar-" + kbRow.index) }
                                            }
                                            IconBtn { visible: root.kbActive.length > 1; anchors.verticalCenter: parent.verticalCenter; danger: true; onGo: root.kbRemove(kbRow.index) }
                                        }
                                    }
                                    // the variant menu (Menu card) — over the rows below it
                                    Rectangle {
                                        visible: Globals.openDd === ("kbvar-" + kbRow.index)
                                        x: parent.width - width; y: Theme.controlLg; width: Theme.panelSm / 2; z: 30
                                        height: Math.min(kvCol.implicitHeight + 2 * Theme.spaceXs, Theme.panelSm / 2)
                                        radius: Theme.radiusRounded; color: Theme.surfaceOverlay
                                        border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                                        Flickable {
                                            anchors.fill: parent; anchors.margins: Theme.spaceXs; contentHeight: kvCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                                            Column {
                                                id: kvCol; width: parent.width
                                                Repeater {
                                                    model: kbPane.variantOpts(kbRow.modelData.code)
                                                    delegate: ListRow {
                                                        required property var modelData
                                                        density: "dense"
                                                        label: modelData.label
                                                        active: modelData.value === kbRow.modelData.variant
                                                        check: modelData.value === kbRow.modelData.variant
                                                        onClicked: { Globals.openDd = ""; root.kbSetVariant(kbRow.index, modelData.value) }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    MouseArea {
                                        id: rowDrag
                                        anchors.left: parent.left; width: Theme.controlLg; height: Theme.controlLg
                                        hoverEnabled: true
                                        drag.target: kbRow; drag.axis: Drag.YAxis
                                        drag.minimumY: 0; drag.maximumY: Math.max(0, (root.kbActive.length - 1) * kbPane.rowH)
                                        cursorShape: Qt.SizeVerCursor
                                        onReleased: {
                                            var to = Math.round(kbRow.y / kbPane.rowH)
                                            if (to !== kbRow.index) root.kbMove(kbRow.index, to)
                                            else kbRow.y = Qt.binding(function () { return kbRow.index * kbPane.rowH })
                                        }
                                    }
                                }
                            }
                        }
                        // add a layout: a search field over the full xkb list
                        FieldBox {
                            width: parent.width; focused: kbSearch.activeFocus
                            Text { id: kbSearchIc; anchors.left: parent.left; anchors.leftMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter; text: Theme.icSearch; font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: Theme.textMuted }
                            TextInput {
                                id: kbSearch
                                anchors.left: kbSearchIc.right; anchors.leftMargin: Theme.spaceXs; anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                                anchors.top: parent.top; anchors.bottom: parent.bottom
                                verticalAlignment: TextInput.AlignVCenter; clip: true
                                color: Theme.textPrimary; font.family: Theme.type.body.family; font.pixelSize: Theme.type.body.size
                                onTextChanged: kbPane.kbQuery = text
                                onAccepted: { var f = kbPane.filtered(); if (f.length) { root.kbAdd(f[0].c); text = "" } }
                                TBody { anchors.verticalCenter: parent.verticalCenter; visible: kbSearch.text.length === 0; text: "Search layouts to add"; color: Theme.textMuted }
                            }
                        }
                        Rectangle {
                            visible: kbSearch.activeFocus || kbPane.kbQuery !== ""
                            width: parent.width; height: Math.min(addCol.implicitHeight + 2 * Theme.spaceXs, Theme.panelSm / 2)
                            radius: Theme.radiusRounded; color: Theme.surfaceRaised
                            border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                            Flickable {
                                anchors.fill: parent; anchors.margins: Theme.spaceXs; contentHeight: addCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                                Column {
                                    id: addCol; width: parent.width
                                    TBody { visible: kbPane.filtered().length === 0; text: "No layout matches “" + kbPane.kbQuery.trim() + "”"; color: Theme.textSecondary; leftPadding: Theme.spaceS; topPadding: Theme.spaceXs; bottomPadding: Theme.spaceXs }
                                    Repeater {
                                        model: kbPane.filtered()
                                        delegate: ListRow {
                                            required property var modelData
                                            density: "dense"
                                            label: modelData.n + " (" + modelData.c + ")"
                                            kind: hovered ? "Add" : ""
                                            // on press, not click: fire before the search field loses focus
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onPressed: { root.kbAdd(modelData.c); kbSearch.text = "" } }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    SectionTitle { visible: root.inpLoaded; text: "Switching layouts" }
                    Card {
                        visible: root.inpLoaded
                        DropRow {
                            label: "Another shortcut"; ddId: "kb-grp"; buttonWidth: Theme.panelSm / 2 + Theme.spaceLg
                            options: root.grpOptions; value: root.kbOptToken("grp:")
                            onPicked: function (v) { root.setKbOptPrefix("grp:", v) }
                        }
                        ToggleRow {
                            title: "Remember the layout per window"
                            sub: "Each window keeps its own layout."
                            on: root.perWindowKb
                            onToggled: root.setPerWindowKb(!root.perWindowKb)
                        }
                    }

                    SectionTitle { visible: root.inpLoaded; text: "Typing" }
                    Card {
                        visible: root.inpLoaded
                        Slider { label: "Repeat rate (per second)"; value: root.inp.repeat_rate; from: 5; to: 80; onMoved: function (v) { root.applyInput({ repeat_rate: Math.round(v) }) } }
                        Slider { label: "Repeat delay (ms)"; value: root.inp.repeat_delay; from: 150; to: 1000; step: 10; onMoved: function (v) { root.applyInput({ repeat_delay: Math.round(v) }) } }
                        // Accordion: the rarely-changed keyboard options
                        Item {
                            width: parent.width; height: Theme.controlMd
                            activeFocusOnTab: true
                            Keys.onSpacePressed: kbPane.advOpen = !kbPane.advOpen
                            Keys.onReturnPressed: kbPane.advOpen = !kbPane.advOpen
                            Row {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spaceXs
                                Text { anchors.verticalCenter: parent.verticalCenter; text: Theme.icChevronRight; rotation: kbPane.advOpen ? 90 : 0; font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: Theme.textSecondary
                                    Behavior on rotation { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeFast } } }
                                TBody { anchors.verticalCenter: parent.verticalCenter; text: "Advanced"; font.weight: Theme.fontWeightMedium }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: kbPane.advOpen = !kbPane.advOpen }
                        }
                        Column {
                            width: parent.width; spacing: Theme.spaceXs; visible: kbPane.advOpen
                            ToggleRow { title: "Num Lock on at startup"; on: root.inp.numlock_by_default === true; onToggled: root.applyInput({ numlock_by_default: !(root.inp.numlock_by_default === true) }) }
                            ToggleRow { title: "Caps Lock acts as Ctrl"; on: root.hasKbOpt("ctrl:nocaps"); onToggled: root.toggleKbOpt("ctrl:nocaps") }
                            ToggleRow { title: "Caps Lock acts as Esc"; on: root.hasKbOpt("caps:escape"); onToggled: root.toggleKbOpt("caps:escape") }
                            ToggleRow { title: "Right Alt is Compose"; on: root.hasKbOpt("compose:ralt"); onToggled: root.toggleKbOpt("compose:ralt") }
                        }
                    }

                    SectionTitle { visible: root.inpLoaded; text: "Mouse" }
                    Card {
                        visible: root.inpLoaded
                        DropRow {
                            visible: root.mice.filter(function (n) { return !root.isTouchpadName(n) }).length > 1
                            label: "Device"; ddId: "mouse-dev"; buttonWidth: Theme.panelSm / 2 + Theme.spaceXl
                            options: { var o = [{ label: "All pointing devices", value: "" }]; var ms = root.mice; for (var i = 0; i < ms.length; i++) if (!root.isTouchpadName(ms[i])) o.push({ label: ms[i], value: ms[i] }); return o }
                            value: root.devTarget
                            onPicked: function (v) { root.devTarget = v }
                        }
                        Note { visible: root.devTarget !== ""; text: "These settings apply to this device only; the others keep the shared ones." }
                        Slider { label: "Pointer speed"; value: kbPane.effSens; from: -1; to: 1; step: 0.05; decimals: 2; onMoved: function (v) { kbPane.setMouse({ sensitivity: Math.round(v * 100) / 100 }) } }
                        SetRow {
                            title: "Acceleration"
                            Seg {
                                anchors.verticalCenter: parent.verticalCenter
                                options: [{ label: "Adaptive", value: "adaptive" }, { label: "Flat", value: "flat" }]
                                value: kbPane.effAccel === "" ? "adaptive" : kbPane.effAccel
                                onPicked: function (v) { kbPane.setMouse({ accel_profile: v }) }
                            }
                        }
                        ToggleRow { title: "Natural scrolling"; on: kbPane.effNat; onToggled: kbPane.setMouse({ natural_scroll: !kbPane.effNat }) }
                        ToggleRow { title: "Left-handed buttons"; on: kbPane.effLeft; onToggled: kbPane.setMouse({ left_handed: !kbPane.effLeft }) }
                        Slider { label: "Scroll speed"; value: Number(root.inp.scroll_factor); from: 0.1; to: 3; step: 0.1; decimals: 1; onMoved: function (v) { root.applyInput({ scroll_factor: Math.round(v * 10) / 10 }) } }
                    }

                    SectionTitle { visible: root.inpLoaded; text: "Touchpad" }
                    Card {
                        visible: root.inpLoaded && !root.hasTouchpad
                        TBody { width: parent.width; text: "No touchpad found"; color: Theme.textSecondary }
                    }
                    Card {
                        visible: root.inpLoaded && root.hasTouchpad
                        ToggleRow { title: "Tap to click"; on: root.inp.tp_tap === true; onToggled: root.applyInput({ tp_tap: !(root.inp.tp_tap === true) }) }
                        ToggleRow { title: "Natural scrolling"; on: root.inp.tp_natural_scroll === true; onToggled: root.applyInput({ tp_natural_scroll: !(root.inp.tp_natural_scroll === true) }) }
                        ToggleRow { title: "Off while typing"; on: root.inp.tp_dwt === true; onToggled: root.applyInput({ tp_dwt: !(root.inp.tp_dwt === true) }) }
                        ToggleRow { title: "Click with fingers"; sub: "Press with two fingers to right-click and three to middle-click, instead of using the corners."; on: root.inp.tp_clickfinger === true; onToggled: root.applyInput({ tp_clickfinger: !(root.inp.tp_clickfinger === true) }) }
                        ToggleRow { title: "Tap and drag"; on: root.inp.tp_tap_drag === true; onToggled: root.applyInput({ tp_tap_drag: !(root.inp.tp_tap_drag === true) }) }
                        ToggleRow { title: "Drag lock"; sub: "Keep dragging for a moment after you lift your finger."; on: root.inp.tp_drag_lock === true; onToggled: root.applyInput({ tp_drag_lock: !(root.inp.tp_drag_lock === true) }) }
                        ToggleRow { title: "Middle-click emulation"; sub: "Press left and right together to middle-click."; on: root.inp.tp_mbe === true; onToggled: root.applyInput({ tp_mbe: !(root.inp.tp_mbe === true) }) }
                        Slider { label: "Scroll speed"; value: Number(root.inp.tp_scroll_factor); from: 0.1; to: 3; step: 0.1; decimals: 1; onMoved: function (v) { root.applyInput({ tp_scroll_factor: Math.round(v * 10) / 10 }) } }
                    }
                    Note { text: "Everything here applies at once and is kept in generated/input.lua. Two-finger or edge scrolling follows the hardware's default, which Hyprland doesn't expose." }
                }
            }

            // ════════ PANE 5 — Shortcuts ════════
            Component {
                id: cShortcuts
                Column {
                    spacing: Theme.spaceS
                    TBody { visible: root.shortcutsMd === ""; width: parent.width; text: "No shortcut list found at ~/.config/hypr/SHORTCUTS.md"; color: Theme.textSecondary; wrapMode: Text.WordWrap }
                    Repeater {
                        model: root.shortcutsModel()
                        delegate: Item {
                            id: scRow
                            required property var modelData
                            width: parent.width
                            height: scRow.modelData.h ? scHead.implicitHeight : Math.max(Theme.controlMd, scDesc.implicitHeight)
                            SectionTitle { id: scHead; visible: scRow.modelData.h; first: false; anchors.left: parent.left; anchors.bottom: parent.bottom; text: scRow.modelData.a; bottomPadding: 0 }
                            TMono { id: scKeys; visible: !scRow.modelData.h; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: Theme.panelSm / 2; text: scRow.modelData.a; color: Theme.textPrimary; elide: Text.ElideRight }
                            TBody { id: scDesc; visible: !scRow.modelData.h; anchors.left: scKeys.right; anchors.leftMargin: Theme.spaceS; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: scRow.modelData.b; color: Theme.textSecondary; wrapMode: Text.WordWrap }
                        }
                    }
                }
            }

            // ════════ PANE 6 — Layout (gaps, border, corners) ════════
            Component {
                id: cLayout
                Column {
                    spacing: Theme.spaceS
                    SectionTitle { text: "Windows" }
                    Card {
                        Slider { label: "Gap between windows"; value: root.gapsIn; from: 0; to: 30
                            onMoved: function (v) { root.gapsIn = Math.round(v); root.applyGaps() } }
                        Slider { label: "Gap at the screen edges"; value: root.gapsOut; from: 0; to: 60
                            onMoved: function (v) { root.gapsOut = Math.round(v); root.applyGaps() } }
                        Slider { label: "Border width"; value: root.borderSize; from: 0; to: 6
                            onMoved: function (v) { root.borderSize = Math.round(v); root.applyGaps() } }
                        Slider { label: "Corner radius"; value: root.rounding; from: 0; to: 24
                            onMoved: function (v) { root.rounding = Math.round(v); root.applyGaps() } }
                    }
                    Pill { label: "Reset to defaults"; onGo: { root.gapsIn = Theme.spaceXs; root.gapsOut = Theme.windowGap; root.borderSize = Theme.borderWidth2; root.rounding = Theme.radiusRounded; root.applyGaps() } }
                    Note { text: "Sliders preview while you drag and apply when you let go. Changes are kept in generated/user.lua, so they last after a reload and the next sign-in." }
                }
            }

            // ════════ PANE 7 — Appearance ════════
            // Look presets (corner, density, stroke), the bar and Glass, the
            // accent, window chrome and motion. The presets, the bar size and
            // bar opacity live only in ewe.conf: they are written with hooks
            // on, so the generator rebuilds the tokens and the desktop follows.
            Component {
                id: cTheme
                Column {
                    id: lookPane
                    spacing: Theme.spaceS
                    readonly property int barOpacity: Number(root.tokIn("bar_opacity", 100))
                    property int opacityDrag: -1          // the slider's value while dragging
                    readonly property int opacityShown: lookPane.opacityDrag >= 0 ? lookPane.opacityDrag : lookPane.barOpacity

                    SectionTitle { text: "Scheme and accent" }
                    Card {
                        DropRow {
                            label: "Scheme"; ddId: "look-scheme"
                            options: root.schemeOptions
                            value: root.tokIn("scheme_slug", "ewe-dark")
                            onPicked: function (v) { root.applyScheme(v) }
                        }
                        Divider {}
                        TBody { text: "Accent color"; font.weight: Theme.fontWeightMedium }
                        // Accent picker: controlMd swatches spaceS apart, a
                        // borderSubtle ring so dark colours stay visible; the
                        // selected one wears a check in its own ink and a
                        // double ring (borderWidth2 of the surface, then
                        // borderWidth2 of textPrimary).
                        Flow {
                            width: parent.width; spacing: Theme.spaceS + Theme.spaceXs
                            Repeater {
                                model: root.accents
                                delegate: Item {
                                    id: sw
                                    required property var modelData
                                    readonly property bool sel: root.hex6(Theme.accent).toLowerCase() === root.hex6(sw.modelData.hex).toLowerCase()
                                    width: Theme.controlMd + 4 * Theme.borderWidth2; height: width
                                    Rectangle {
                                        anchors.fill: parent; radius: Theme.radiusFull
                                        color: "transparent"
                                        visible: sw.sel || swMa.containsMouse || sw.activeFocus
                                        border.width: sw.activeFocus && !sw.sel && !swMa.containsMouse ? Theme.focusWidth : Theme.borderWidth2
                                        border.color: sw.activeFocus && !sw.sel && !swMa.containsMouse ? Theme.focusRing : sw.sel ? Theme.textPrimary : Theme.borderStrong
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: Theme.controlMd; height: Theme.controlMd; radius: Theme.radiusFull
                                        color: sw.modelData.hex
                                        border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                                        Text { anchors.centerIn: parent; visible: sw.sel; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm; color: sw.modelData.ink }
                                    }
                                    activeFocusOnTab: true
                                    Keys.onSpacePressed: root.setAccent(sw.modelData.hex)
                                    Keys.onReturnPressed: root.setAccent(sw.modelData.hex)
                                    MouseArea { id: swMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setAccent(sw.modelData.hex) }
                                }
                            }
                        }
                        SetRow {
                            title: "Custom color"
                            desc: "Any color works; accent text is adjusted to stay readable."
                            FieldBox {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.panelSm / 3; focused: hexIn.activeFocus
                                Rectangle { id: hexChip; anchors.left: parent.left; anchors.leftMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter; width: Theme.iconMd; height: Theme.iconMd; radius: Theme.radiusSlight; color: Theme.accent; border.color: Theme.borderSubtle; border.width: Theme.borderWidth1 }
                                TextInput {
                                    id: hexIn
                                    anchors.left: hexChip.right; anchors.leftMargin: Theme.spaceS; anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                                    anchors.top: parent.top; anchors.bottom: parent.bottom
                                    verticalAlignment: TextInput.AlignVCenter; clip: true
                                    color: Theme.textPrimary; font.family: Theme.type.mono.family; font.pixelSize: Theme.type.mono.size
                                    text: String(Theme.accent)
                                    onAccepted: { var t = text.trim(); if (/^#?[0-9a-fA-F]{6}$/.test(t)) root.setAccent(t[0] === "#" ? t : "#" + t) }
                                }
                            }
                        }
                        Note { visible: Globals.schemeActive && root.tokIn("scheme_slug", "ewe-dark").indexOf("ewe-") !== 0; text: "This scheme brings its own accent; picking one here replaces it." }
                    }

                    SectionTitle { text: "Look" }
                    Card {
                        SetRow {
                            glyph: root.g(0xE648); title: "Corners"; desc: "How round windows, panels and controls are."
                            Seg {
                                anchors.verticalCenter: parent.verticalCenter
                                options: [{ label: "None", value: "none" }, { label: "Small", value: "small" }, { label: "Medium", value: "medium" }, { label: "Large", value: "large" }]
                                // the pre-v3 value `round` reads as large (the generator maps it)
                                value: root.tokIn("corner", "medium") === "round" ? "large" : root.tokIn("corner", "medium")
                                onPicked: function (v) { root.confSet("desktop.theme.corner", v) }
                            }
                        }
                        SetRow {
                            glyph: root.g(0xE58B); title: "Density"; desc: "How tall controls and rows are."
                            Seg {
                                anchors.verticalCenter: parent.verticalCenter
                                options: [{ label: "Compact", value: "compact" }, { label: "Comfortable", value: "comfortable" }, { label: "Roomy", value: "roomy" }]
                                value: root.tokIn("density", "comfortable")
                                onPicked: function (v) { root.confSet("desktop.theme.density", v) }
                            }
                        }
                        SetRow {
                            glyph: root.g(0xE167); title: "Outlines"; desc: "The line around cards, panels and buttons."
                            Seg {
                                anchors.verticalCenter: parent.verticalCenter
                                options: [{ label: "None", value: "none" }, { label: "Thin", value: "thin" }, { label: "Thick", value: "thick" }]
                                value: root.tokIn("stroke", "thin")
                                onPicked: function (v) { root.confSet("desktop.theme.stroke", v) }
                            }
                        }
                    }

                    SectionTitle { text: "Bar and dock" }
                    Card {
                        SetRow {
                            glyph: root.g(0xE435); title: "Bar size"
                            desc: Number(root.tokIn("text_scale", 100)) >= 130 ? "Text size 130% uses the large bar." : "Normal is 48 pixels tall, large 64."
                            dim: Number(root.tokIn("text_scale", 100)) >= 130
                            Seg {
                                anchors.verticalCenter: parent.verticalCenter
                                dim: Number(root.tokIn("text_scale", 100)) >= 130
                                options: [{ label: "Normal", value: "normal" }, { label: "Large", value: "large" }]
                                value: root.tokIn("bar_size", "normal")
                                onPicked: function (v) { root.confSet("desktop.bar.size", v) }
                            }
                        }
                        Divider {}
                        // Glass: bar opacity drives the bar, the dock and the
                        // lock card; the preset is 80, and below it Settings
                        // warns (Glass card). Nothing is blocked.
                        SetRow {
                            glyph: root.g(0xE59C); title: "Bar opacity"
                            desc: "The bar, the dock and the lock screen card. Below 100% the wallpaper shows through."
                            Pill {
                                anchors.verticalCenter: parent.verticalCenter
                                size: "sm"; label: "Glass"
                                disabled: lookPane.opacityShown === Math.round(Theme.opacityGlass * 100)
                                onGo: root.confSet("desktop.theme.bar_opacity", Math.round(Theme.opacityGlass * 100))
                            }
                        }
                        Slider {
                            from: 0; to: 100; step: 1; showValue: true
                            value: lookPane.barOpacity
                            valueText: lookPane.opacityShown + "%"
                            onDraggingChanged: lookPane.opacityDrag = dragging ? Math.round(dragVal) : -1
                            onDragValChanged: if (dragging) lookPane.opacityDrag = Math.round(dragVal)
                            onMoved: function (v) { lookPane.opacityDrag = -1; root.confSet("desktop.theme.bar_opacity", Math.round(v)) }
                        }
                        Alert {
                            visible: lookPane.opacityShown < Math.round(Theme.opacityGlass * 100)
                            tone: "warning"
                            text: "Text can be hard to read on bright wallpapers." + (Globals.noBlur ? " Blur isn't available on this machine, so 90% or more keeps it readable." : "")
                        }
                        Alert {
                            visible: Globals.noBlur && lookPane.opacityShown >= Math.round(Theme.opacityGlass * 100) && lookPane.opacityShown < 90
                            tone: "info"
                            text: "Blur isn't available on this machine, so the wallpaper shows through sharp. 90% or more keeps text easy to read."
                        }
                        Note { visible: root.tokIn("reduce_transparency", false) === true || root.tokIn("increase_contrast", false) === true; text: "Reduce transparency or Increase contrast is on (Accessibility), so the bar and dock stay solid." }
                    }

                    SectionTitle { text: "Windows" }
                    Card {
                        ToggleRow {
                            title: "Accent-colored borders"
                            sub: "The focused window's border follows your accent color."
                            on: Globals.tintBorders
                            onToggled: { Globals.tintBorders = !Globals.tintBorders; root.applyBorder(); root.setAccent(String(Globals.accentColor)) }
                        }
                        ToggleRow {
                            title: "Transparent windows in the background"
                            sub: "Windows without focus let a little of what is behind them through."
                            on: Globals.windowTransparency
                            onToggled: root.setTransparency(!Globals.windowTransparency)
                        }
                        ToggleRow {
                            title: "Blur behind apps"
                            sub: "Every window at 85% with the blurred desktop behind it. Full-screen windows stay solid."
                            on: root.tokIn("app_blur", false) === true
                            onToggled: root.confSet("desktop.theme.app_blur", root.tokIn("app_blur", false) === true ? "false" : "true")
                        }
                    }

                    SectionTitle { text: "Motion" }
                    Card {
                        SetRow {
                            glyph: Theme.icSpeed; title: "Animation speed"; desc: "Windows and the shell move at this speed."
                            Seg {
                                anchors.verticalCenter: parent.verticalCenter
                                // m divides every duration: Off 0 · Slow 0.6 · Normal 1 · Fast 2
                                options: [{ label: "Off", value: 0 }, { label: "Slow", value: 0.6 }, { label: "Normal", value: 1 }, { label: "Fast", value: 2 }]
                                value: [0, 0.6, 1, 2].filter(function (m) { return Math.abs(Globals.animationSpeed - m) < 0.001 })[0]
                                onPicked: function (v) { root.setAnim(v) }
                            }
                        }
                    }
                    Note { text: "Everything here applies at once and lives in ewe.conf, so it follows you to your other machines. Reduce motion is in Accessibility." }
                }
            }

            // ════════ PANE 8 — Wallpaper ════════
            Component {
                id: cWallpaper
                Column {
                    spacing: Theme.spaceS
                    Alert {
                        visible: root.wpBackendLabel === "none"; tone: "warning"
                        title: "No wallpaper backend"
                        text: "Install swww (packaged as awww) for pictures and animated GIFs, mpvpaper for videos, or swaybg for still pictures only."
                    }
                    SectionTitle { visible: root.wpBackendLabel !== "none"; text: "Wallpaper" }
                    Card {
                        visible: root.wpBackendLabel !== "none"
                        SetRow {
                            title: "Show on"
                            Seg {
                                anchors.verticalCenter: parent.verticalCenter
                                options: { var o = [{ label: "All displays", value: "*" }], ss = root.dispSpecs; for (var i = 0; i < ss.length; i++) if (!ss[i].disabled) o.push({ label: ss[i].name, value: ss[i].name }); return o }
                                value: root.wpTarget
                                onPicked: function (v) { root.wpTarget = v }
                            }
                        }
                        DropRow {
                            label: "Fit"; ddId: "wp-mode"
                            options: [{ label: "Fill", value: "fill" }, { label: "Fit", value: "fit" }, { label: "Stretch", value: "stretch" }, { label: "Tile", value: "tile" }, { label: "Center", value: "center" }]
                            value: root.wpMode
                            onPicked: function (v) { root.wpMode = v; if (Object.keys(root.wpMap).length) { root.wpWrite(); root.flashApplied() } }
                        }
                        ToggleRow {
                            visible: root.wpAnyVideo
                            title: "Mute video wallpaper"; sub: "Otherwise mpvpaper plays the video's sound."
                            on: root.wpMute
                            onToggled: { root.wpMute = !root.wpMute; root.wpWrite(); root.flashApplied() }
                        }
                        Divider {}
                        TBody { width: parent.width; visible: Object.keys(root.wpMap).length === 0; text: "No wallpaper yet. Pick one below."; color: Theme.textSecondary }
                        Repeater {
                            model: Object.keys(root.wpMap).sort()
                            delegate: KV { required property var modelData; k: modelData === "*" ? "All displays" : modelData; v: String(root.wpMap[modelData]).replace(/^.*\//, "") }
                        }
                        TCaption { width: parent.width; text: "Backend: " + root.wpBackendLabel }
                    }
                    SectionTitle { visible: root.wpBackendLabel !== "none"; text: "Choose" }
                    Note { visible: root.wpBackendLabel !== "none"; text: root.wpDir }
                    Card {
                        visible: root.wpBackendLabel !== "none"
                        FileDropTarget {
                            id: wpPicker
                            width: parent.width
                            acceptVideo: true
                            label: "Drop a picture, GIF or video here, or click to browse"
                            dialogTitle: "Choose a wallpaper"
                            onPicked: function (p) { root.wpAssign(p); root.wpList(p.replace(/\/[^/]*$/, "")) }
                            Connections { target: root; function onWallpaperBrowseRequested() { wpPicker.browse() } }
                        }
                        Row {
                            spacing: Theme.spaceS
                            Pill { label: "Browse files…"; onGo: wpPicker.browse() }
                            Pill { label: "Wallpapers folder"; onGo: root.wpList(root.home + "/Pictures/Wallpapers") }
                            Pill { label: "Pictures"; onGo: root.wpList(root.home + "/Pictures") }
                        }
                        Note { visible: root.wpFiles.length === 0; text: "No pictures in this folder. Use Browse files…, or put pictures in " + root.wpDir + "." }
                        // thumbnails: four to a row, 16:10, radiusPrimary; the
                        // current one wears a borderWidth2 accentText edge
                        Flow {
                            id: wpFlow
                            width: parent.width; spacing: Theme.spaceS
                            readonly property real tileW: (width - 3 * spacing) / 4
                            Repeater {
                                model: root.wpFiles
                                delegate: Rectangle {
                                    id: wpTile
                                    required property var modelData
                                    readonly property bool cur: root.wpMap[root.wpTarget] === modelData
                                    readonly property bool isVid: root.wpIsVideo(modelData)
                                    readonly property bool isGif: root.wpIsGif(modelData)
                                    width: wpFlow.tileW; height: width * 5 / 8; radius: Theme.radiusPrimary; clip: true
                                    color: Theme.surfaceSunken
                                    border.color: wpTile.cur ? Theme.accentText : wtMa.containsMouse ? Theme.textMuted : Theme.borderSubtle
                                    border.width: wpTile.cur ? Theme.borderWidth2 : Theme.borderWidth1
                                    Image { visible: !wpTile.isVid; anchors.fill: parent; anchors.margins: parent.border.width; source: wpTile.isVid ? "" : "file://" + wpTile.modelData; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 2 * wpTile.width; sourceSize.height: 2 * wpTile.height }
                                    // videos get a film tile — no thumbnail without a decode pass
                                    Column {
                                        visible: wpTile.isVid
                                        anchors.centerIn: parent; spacing: Theme.spaceXxs; width: parent.width - 2 * Theme.spaceS
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.g(0xE0D0); font.family: Theme.fontIcons; font.pixelSize: Theme.iconLg; color: Theme.textMuted }
                                        TCaption { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: String(wpTile.modelData).replace(/^.*\//, ""); elide: Text.ElideMiddle }
                                    }
                                    Badge {
                                        visible: wpTile.isVid || wpTile.isGif
                                        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.spaceXs
                                        label: wpTile.isVid ? "Video" : "GIF"; tone: "neutral"; solid: false
                                    }
                                    Rectangle {
                                        visible: wpTile.cur
                                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.spaceXs
                                        width: Theme.iconLg; height: Theme.iconLg; radius: Theme.radiusFull; color: Theme.accent
                                        Text { anchors.centerIn: parent; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: Theme.iconXs; color: Theme.onAccent }
                                    }
                                    MouseArea { id: wtMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.wpAssign(wpTile.modelData) }
                                }
                            }
                        }
                    }
                    Alert { visible: root.wpAnyAnimated; tone: "warning"; text: "Animated wallpapers keep the graphics card busy and use more battery." }
                    Note { text: "Applied at once and restored at every sign-in by wallpaper.sh; a display you plug in gets its wallpaper back. Pictures use " + (root.wpImgBackend || "no backend") + ", GIFs animate with swww and videos loop with mpvpaper." }
                }
            }

            // ════════ PANE — Screensaver ════════
            Component {
                id: cSaver
                Column {
                    spacing: Theme.spaceS
                    Alert {
                        visible: !root.hypridleOk; tone: "warning"
                        title: "The screensaver needs hypridle"
                        text: "Install it with sudo pacman -S hypridle. Locking when idle needs it too."
                    }
                    SectionTitle { text: "Screensaver" }
                    Card {
                        ToggleRow {
                            title: "Screensaver"
                            sub: "Covers every display when you have been away; any key, click or mouse move closes it."
                            on: Globals.saverEnabled
                            onToggled: { Globals.saverEnabled = !Globals.saverEnabled; root.saverChanged() }
                        }
                        DropRow {
                            label: "Start after"; ddId: "sv-timeout"; dim: !Globals.saverEnabled
                            options: [1, 3, 5, 10, 15, 30].map(function (m) { return { label: m + " min", value: m } })
                            value: Globals.saverMin
                            onPicked: function (v) { Globals.saverMin = v; root.saverChanged() }
                        }
                        Slider {
                            label: "Start after (minutes)"; from: 1; to: 60; step: 1; decimals: 0
                            value: Globals.saverMin
                            visible: Globals.saverEnabled
                            onMoved: function (v) { Globals.saverMin = Math.round(v); root.saverChanged() }
                        }
                        DropRow {
                            label: "Style"; ddId: "sv-style"; dim: !Globals.saverEnabled || Globals.saverLock
                            options: [{ label: "Clock", value: "clock" }, { label: "Blank", value: "blank" }]
                            value: Globals.saverStyle
                            onPicked: function (v) { Globals.saverStyle = v; root.saverChanged() }
                        }
                    }
                    SectionTitle { text: "Locking" }
                    Card {
                        ToggleRow {
                            title: "Require password"
                            sub: "When idle, go straight to the lock screen instead of the screensaver."
                            dim: !Globals.saverEnabled
                            on: Globals.saverLock
                            onToggled: { Globals.saverLock = !Globals.saverLock; root.saverChanged() }
                        }
                        DropRow {
                            label: "Lock after the screensaver starts"; ddId: "sv-lockafter"; dim: !Globals.saverEnabled || Globals.saverLock
                            options: [{ label: "Never", value: 0 }, { label: "1 min", value: 1 }, { label: "5 min", value: 5 }, { label: "10 min", value: 10 }, { label: "15 min", value: 15 }, { label: "30 min", value: 30 }]
                            value: Globals.saverLockAfterMin
                            onPicked: function (v) { Globals.saverLockAfterMin = v; root.saverChanged() }
                        }
                        Note { text: "With the screensaver off, the screen still locks after 5 minutes idle. On battery, the machine still suspends after 15 minutes." }
                    }
                    Row {
                        spacing: Theme.spaceS + Theme.spaceXs
                        Pill { label: "Preview"; primary: true; onGo: Globals.saverActive = true }
                        TCaption { anchors.verticalCenter: parent.verticalCenter; text: "Shows the screensaver now. Press any key to close it." }
                    }
                    Note { text: "Playing media, a full-screen window or Keep awake in Quick settings hold off the screensaver, the lock and suspend. hypridle keeps the time through generated/hypridle.conf; changes apply at once." }
                }
            }

            // ════════ PANE — Power / lid ════════
            Component {
                id: cPower
                Column {
                    spacing: Theme.spaceS
                    SectionTitle { text: "When the lid closes" }
                    Card {
                        ToggleRow {
                            title: "Suspend even when docked"
                            sub: "On: closing the lid always suspends. Off: with an external display, keep working with the panel dark."
                            on: Globals.lidDockedSuspend
                            onToggled: { Globals.lidDockedSuspend = !Globals.lidDockedSuspend; root.writePrefs() }
                        }
                        Divider {}
                        KV { k: "Right now"; v: Lid.docked ? (Lid.externals + " external display" + (Lid.externals === 1 ? "" : "s") + " connected")
                                                           : "No external display, so the lid always suspends" }
                    }
                    Note { text: "On its own, the laptop always suspends when you close the lid. The screen locks before it sleeps, so nothing shows when it wakes." }

                    SectionTitle { text: "Battery" }
                    Card {
                        KV { k: "Charge"; v: Power.capacity >= 0 ? Power.capacity + "% · " + Power.remainingText() : "—" }
                        KV { k: "Health"; v: Power.healthText() }
                        Divider { visible: Power.hasChargeLimit }
                        DropRow {
                            visible: Power.hasChargeLimit && Power.chargeLimitWritable
                            label: "Charge limit"; ddId: "chg-limit"
                            options: [{ label: "60% (longest life)", value: 60 },
                                      { label: "80% (balanced)", value: 80 },
                                      { label: "100% (full capacity)", value: 100 }]
                            value: Power.chargeLimit
                            onPicked: function (v) { Power.setChargeLimit(v) }
                        }
                        // present but root-only: say why rather than offering a
                        // control that would silently write into the void
                        Alert {
                            visible: Power.hasChargeLimit && !Power.chargeLimitWritable; tone: "warning"
                            text: "The charge limit is " + Power.chargeLimit + "%, but only root can change it here. Run install.sh again to add the udev rule, or use asusctl."
                        }
                        Note { visible: !Power.hasChargeLimit; text: "This battery has no charge limit to set." }
                    }

                    SectionTitle { visible: Logind.hasKbdBacklight; text: "Keyboard backlight" }
                    Card {
                        visible: Logind.hasKbdBacklight
                        DropRow {
                            label: "Level"; ddId: "kbd-bl"
                            options: [{ label: "Off", value: 0 }, { label: "Low", value: 1 },
                                      { label: "Medium", value: 2 }, { label: "High", value: 3 }]
                            value: Logind.hasKbdBacklight ? Logind.kbdBacklight.value : 0
                            onPicked: function (v) { Logind.setKbdStep(v) }
                        }
                        Note { text: "The keyboard's backlight keys change it too." }
                    }

                    SectionTitle { text: "Performance" }
                    Card {
                        KV { k: "Profiles from"; v: Power.ppdRunning ? "power-profiles-daemon" : (Power.platformProfile !== "" ? "The firmware profile" : "Kernel defaults") }
                        KV { visible: !Power.ppdRunning && Power.platformProfile !== ""
                             k: "Firmware profile"; v: Power.platformProfile + (Power.platformChoices.length ? " (" + Power.platformChoices.join(" · ") + ")" : "") }
                        Alert { visible: Power.degraded; tone: "warning"; text: "Performance is held back: " + Power.degradedReason + "." }
                        Note { visible: !Power.degraded && Power.ppdRunning; text: "Not held back by heat. Switch profiles in Quick settings." }
                    }

                    SectionTitle { text: "On battery" }
                    Card {
                        ToggleRow {
                            title: "Low-power mode"
                            sub: "Checks less often in the background while unplugged."
                            on: Globals.lowPowerEnabled
                            onToggled: { Globals.lowPowerEnabled = !Globals.lowPowerEnabled; root.writePrefs() }
                        }
                        Divider {}
                        KV { k: "Power source"; v: Globals.onBattery ? "Battery" + (Globals.lowPower ? " · low-power mode on" : "") : "Plugged in" }
                    }

                    SectionTitle { text: "Session" }
                    Card {
                        KV { k: "logind bridge"; v: Logind.bridgeUp ? "Connected" : (Logind.bridgeError !== "" ? Logind.bridgeError : "Starting…") }
                        KV { k: "Sleep inhibitor"; v: Logind.inhibited ? "Held (" + Logind.delayMs + " ms to lock)" : "Not held" }
                        KV { k: "Screen backlight"; v: Logind.hasBacklight ? Logind.backlight.name : "None found" }
                        KV { k: "Keyboard backlight"; v: Logind.hasKbdBacklight ? Logind.kbdBacklight.name : "None found" }
                    }

                    SectionTitle { text: "Keeping this machine awake" }
                    Card {
                        // We deliberately do not own org.freedesktop.ScreenSaver —
                        // hypridle implements it, and two owners would fight. This
                        // reports whether app inhibits are being heard at all.
                        KV { k: "Apps that keep it awake"; v: Logind.screensaverOwner !== ""
                                ? "Honored by " + Logind.screensaverOwner
                                : "Nothing owns org.freedesktop.ScreenSaver" }
                        KV { k: "Keep awake"; v: Globals.caffeine ? "On, idle is blocked" : "Off" }
                        Divider {}
                        Repeater {
                            model: Logind.blockingInhibitors()
                            delegate: KV {
                                required property var modelData
                                k: String(modelData.who)
                                v: String(modelData.why) + " · " + String(modelData.what)
                            }
                        }
                        Note { visible: Logind.blockingInhibitors().length === 0; text: "Nothing is keeping this machine awake right now." }
                    }
                }
            }

            // ════════ PANE — Dock ════════
            Component {
                id: cDock
                Column {
                    spacing: Theme.spaceS
                    SectionTitle { text: "Dock" }
                    Card {
                        ToggleRow {
                            title: "Show the dock"
                            sub: "The launcher, Overview and your workspaces at the bottom of the screen."
                            on: Globals.dockEnabled
                            onToggled: { Globals.dockEnabled = !Globals.dockEnabled; root.writePrefs() }
                        }
                        ToggleRow {
                            title: "Hide automatically"
                            sub: "Moves away when a window needs the space; point at the bottom edge to bring it back."
                            dim: !Globals.dockEnabled
                            on: Globals.dockAutohide
                            onToggled: { if (Globals.dockEnabled) { Globals.dockAutohide = !Globals.dockAutohide; root.writePrefs() } }
                        }
                        SetRow {
                            title: "Icon size"; desc: "Small is 40 pixels, medium 48, large 64."
                            dim: !Globals.dockEnabled
                            Seg {
                                anchors.verticalCenter: parent.verticalCenter
                                dim: !Globals.dockEnabled
                                options: [{ label: "Small", value: "small" }, { label: "Medium", value: "normal" }, { label: "Large", value: "large" }]
                                value: Globals.dockIconSize
                                onPicked: function (v) { Globals.dockIconSize = v; root.writePrefs() }
                            }
                        }
                    }
                }
            }

            // ════════ PANE — Startup apps ════════
            Component {
                id: cStartup
                Column {
                    spacing: Theme.spaceS
                    SectionTitle { text: "Start at sign-in" }
                    Card {
                        Column {
                            width: parent.width; visible: root.startupApps.length === 0
                            TBody { text: "Nothing starts at sign-in yet" }
                            TCaption { width: parent.width; text: "Search below to add an app."; wrapMode: Text.WordWrap }
                        }
                        Repeater {
                            model: root.startupApps
                            delegate: Item {
                                id: saRow
                                required property var modelData
                                required property int index
                                readonly property bool off: saRow.modelData.enabled === false
                                width: parent.width; height: Math.max(Theme.controlLg, saTexts.implicitHeight) + Theme.spaceXs
                                Image {
                                    id: saIcon
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.iconLg; height: Theme.iconLg
                                    visible: source !== ""
                                    source: saRow.modelData.icon ? Quickshell.iconPath(saRow.modelData.icon, true) : ""
                                    sourceSize.width: 2 * Theme.iconLg; sourceSize.height: 2 * Theme.iconLg; mipmap: true
                                }
                                Column {
                                    id: saTexts
                                    anchors.left: parent.left; anchors.leftMargin: Theme.iconLg + Theme.spaceS + Theme.spaceXs
                                    anchors.right: saCtl.left; anchors.rightMargin: Theme.spaceS
                                    anchors.verticalCenter: parent.verticalCenter
                                    TBody { width: parent.width; text: saRow.modelData.name || saRow.modelData.exec; color: saRow.off ? Theme.textDisabled : Theme.textPrimary; font.weight: Theme.fontWeightMedium; elide: Text.ElideRight }
                                    TMono { width: parent.width; text: saRow.modelData.exec; color: saRow.off ? Theme.textDisabled : Theme.textMuted; font.pixelSize: Theme.fontSizeXs; elide: Text.ElideRight }
                                }
                                Row {
                                    id: saCtl
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spaceS
                                    Toggle { anchors.verticalCenter: parent.verticalCenter; on: !saRow.off; onToggled: root.startupToggle(saRow.index) }
                                    IconBtn { anchors.verticalCenter: parent.verticalCenter; danger: true; onGo: root.startupRemove(saRow.index) }
                                }
                            }
                        }
                    }

                    SectionTitle { text: "Add an app" }
                    Card {
                        // search over installed desktop entries
                        FieldBox {
                            width: parent.width; focused: saSearch.activeFocus
                            Text { id: saSearchIc; anchors.left: parent.left; anchors.leftMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter; text: Theme.icSearch; font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: Theme.textMuted }
                            TextInput {
                                id: saSearch
                                anchors.left: saSearchIc.right; anchors.leftMargin: Theme.spaceXs; anchors.right: parent.right; anchors.rightMargin: Theme.spaceS
                                anchors.top: parent.top; anchors.bottom: parent.bottom
                                verticalAlignment: TextInput.AlignVCenter; clip: true
                                color: Theme.textPrimary; font.family: Theme.type.body.family; font.pixelSize: Theme.type.body.size
                                onTextChanged: root.startupQuery = text
                                TBody { anchors.verticalCenter: parent.verticalCenter; visible: saSearch.text.length === 0; text: "Search apps or type a command"; color: Theme.textMuted }
                            }
                        }
                        Column {
                            width: parent.width
                            visible: root.startupQuery.trim().length > 0
                            Repeater {
                                model: {
                                    var q = root.startupQuery.trim().toLowerCase()
                                    if (q === "") return []
                                    var out = [], a = DesktopEntries.applications.values
                                    for (var i = 0; i < a.length; i++) {
                                        var e = a[i]
                                        if (e && !e.noDisplay && (e.name || "").toLowerCase().indexOf(q) >= 0) out.push(e)
                                        if (out.length >= 8) break
                                    }
                                    return out
                                }
                                delegate: Rectangle {
                                    id: saRes
                                    required property var modelData
                                    width: parent.width; height: Theme.controlLg; radius: Theme.radiusSecondary
                                    color: saResMa.pressed ? Theme.surfacePressed : saResMa.containsMouse ? Theme.surfaceHover : "transparent"
                                    Image {
                                        id: saResIc
                                        anchors.left: parent.left; anchors.leftMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter
                                        width: Theme.iconLg; height: Theme.iconLg
                                        source: saRes.modelData.icon ? Quickshell.iconPath(saRes.modelData.icon, true) : ""
                                        sourceSize.width: 2 * Theme.iconLg; sourceSize.height: 2 * Theme.iconLg; mipmap: true
                                    }
                                    TBody {
                                        anchors.left: saResIc.right; anchors.leftMargin: Theme.spaceS + Theme.spaceXs; anchors.right: saAdd.left; anchors.rightMargin: Theme.spaceS
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: saRes.modelData.name; elide: Text.ElideRight
                                    }
                                    TBody { id: saAdd; anchors.right: parent.right; anchors.rightMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter; text: "Add"; color: Theme.accentText; font.weight: Theme.fontWeightMedium }
                                    MouseArea {
                                        id: saResMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.startupAdd(saRes.modelData.name, root.cleanExec(saRes.modelData.execString), saRes.modelData.icon); saSearch.text = "" }
                                    }
                                }
                            }
                            // raw command fallback — whatever was typed runs via sh -c
                            Rectangle {
                                width: parent.width; height: Theme.controlLg; radius: Theme.radiusSecondary
                                color: saCmdMa.pressed ? Theme.surfacePressed : saCmdMa.containsMouse ? Theme.surfaceHover : "transparent"
                                Text { id: saCmdIc; anchors.left: parent.left; anchors.leftMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter; width: Theme.iconLg; horizontalAlignment: Text.AlignHCenter; text: Theme.icSsh; font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: Theme.textSecondary }
                                TMono {
                                    anchors.left: saCmdIc.right; anchors.leftMargin: Theme.spaceS + Theme.spaceXs; anchors.right: saCmdAdd.left; anchors.rightMargin: Theme.spaceS
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Run “" + root.startupQuery.trim() + "”"; elide: Text.ElideRight
                                }
                                TBody { id: saCmdAdd; anchors.right: parent.right; anchors.rightMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter; text: "Add command"; color: Theme.accentText; font.weight: Theme.fontWeightMedium }
                                MouseArea {
                                    id: saCmdMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.startupAdd(root.startupQuery.trim(), root.startupQuery.trim(), ""); saSearch.text = "" }
                                }
                            }
                        }
                    }
                    Note { text: "These start once when you sign in, so changes take effect at the next sign-in. Switching one off keeps it in the list. The list is part of settings sync." }
                }
            }

            // an account's picture: the image in a circle, or its initial on
            // accentSubtle while there is none (Avatar card, initials)
            component AccountPic: Rectangle {
                id: ap
                property string src: ""
                property string initial: "?"
                width: Theme.controlXl; height: Theme.controlXl; radius: width / 2
                color: Theme.accentSubtle
                Text {
                    anchors.centerIn: parent; visible: apImg.status !== Image.Ready
                    text: ap.initial; color: Theme.accentText
                    font.family: Theme.type.bodyStrong.family; font.pixelSize: Theme.fontSizeLg; font.weight: Theme.fontWeightSemibold
                }
                Image {
                    id: apImg
                    anchors.fill: parent
                    source: ap.src
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                    layer.enabled: true
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: apMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                }
                Item { id: apMask; anchors.fill: parent; layer.enabled: true; visible: false; Rectangle { anchors.fill: parent; radius: Theme.radiusFull; antialiasing: true } }
            }

            // ════════ PANE — User ════════
            Component {
                id: cUser
                Column {
                    spacing: Theme.spaceS
                    SectionTitle { text: "Account" }
                    Card {
                        Row {
                            width: parent.width; spacing: Theme.spaceMd
                            Avatar { size: 2 * Theme.control2xl; initial: (root.userRealName || Quickshell.env("USER") || "").charAt(0).toUpperCase() }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spaceXs
                                // your name: click to change it (AccountsService)
                                FieldBox {
                                    width: Math.max(Theme.panelSm / 2 + Theme.spaceLg, nameIn.implicitWidth + Theme.spaceLg)
                                    height: Theme.controlLg
                                    color: nameIn.activeFocus ? Theme.surfaceSunken : "transparent"
                                    border.color: nameIn.activeFocus ? Theme.focusRing : hovered ? Theme.borderStrong : "transparent"
                                    TextInput {
                                        id: nameIn
                                        anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceLg - Theme.spaceS; verticalAlignment: TextInput.AlignVCenter
                                        text: root.userRealName !== "" ? root.userRealName : (Quickshell.env("USER") || "user")
                                        color: Theme.textPrimary
                                        font.family: Theme.type.h4.family; font.pixelSize: Theme.type.h4.size; font.weight: Theme.type.h4.weight
                                        selectByMouse: true; clip: true
                                        onAccepted: focus = false
                                        onActiveFocusChanged: if (!activeFocus && text.trim() !== "" && text.trim() !== root.userRealName) root.setRealName(text.trim())
                                    }
                                    Text { anchors.right: parent.right; anchors.rightMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter; visible: parent.hovered && !nameIn.activeFocus; text: Theme.icPencil; font.family: Theme.fontIcons; font.pixelSize: Theme.iconSm; color: Theme.textSecondary }
                                }
                                TBody { leftPadding: Theme.spaceS; text: "@" + (Quickshell.env("USER") || "user"); color: Theme.textSecondary }
                                Row {
                                    leftPadding: Theme.spaceS; topPadding: Theme.spaceXs
                                    spacing: Theme.spaceS
                                    Pill { label: "Change picture…"; onGo: avPicker.browse() }
                                    // shape: applies live everywhere via Globals.avatarShape
                                    Seg {
                                        anchors.verticalCenter: parent.verticalCenter
                                        options: [{ label: "Circle", value: "circle" }, { label: "Rounded", value: "rounded" }, { label: "Square", value: "square" }]
                                        value: Globals.avatarShape
                                        onPicked: function (v) { Globals.avatarShape = v; root.writePrefs() }
                                    }
                                }
                            }
                        }
                        FileDropTarget {
                            id: avPicker
                            width: parent.width; implicitHeight: 2 * Theme.control2xl
                            label: "Drop a picture here to use it"
                            dialogTitle: "Choose a picture"
                            onPicked: function (p) { root.avatarCropSrc = p }
                        }
                    }
                    Note { text: "Your picture is saved to ~/.face for the sign-in screen; the system account picture and your name change through AccountsService." }

                    SectionTitle { text: "Session" }
                    Card {
                        KV { k: "Host"; v: root.sysFacts.host || "—" }
                        KV { k: "Compositor"; v: root.sysFacts.hypr || "Hyprland" }
                        KV { k: "Session type"; v: "Wayland" }
                        KV { k: "Kernel"; v: root.sysFacts.kernel || "—" }
                        KV { k: "Up for"; v: root.sysFacts.up || "—" }
                    }

                    SectionTitle { text: "Nextcloud account" }
                    // signed out → the server field + sign in (RFC-005: the ewe
                    // account is the user's own Nextcloud; nothing is baked in)
                    Card {
                        visible: Cloud.probed && !Cloud.signedIn
                        TBody { width: parent.width; color: Theme.textSecondary; wrapMode: Text.WordWrap
                            text: "Sign in to your Nextcloud, a server you run or a hosted account (Murena, Disroot, Infomaniak…), and ewe works with it: this machine kept as one file, your apps restorable in Komble, your calendar in Quick settings and your files in ~/Nextcloud. ewe never sees your password: the server gives it an app password you can revoke at any time." }
                        Item {
                            width: parent.width; height: Theme.controlMd
                            FieldBox {
                                anchors.left: parent.left; anchors.right: ncBtns.left; anchors.rightMargin: Theme.spaceS
                                focused: ncSrv.activeFocus
                                TextInput {
                                    id: ncSrv
                                    anchors.fill: parent; anchors.leftMargin: Theme.spaceS; anchors.rightMargin: Theme.spaceS
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: Cloud.lastServer
                                    color: Theme.textPrimary; font.family: Theme.type.body.family; font.pixelSize: Theme.type.body.size
                                    clip: true; selectByMouse: true
                                    onAccepted: if (text.trim() !== "") Cloud.signIn(text)
                                    TBody { visible: ncSrv.text === "" && !ncSrv.activeFocus; anchors.verticalCenter: parent.verticalCenter; text: "https://cloud.example.org"; color: Theme.textMuted }
                                }
                            }
                            Row {
                                id: ncBtns
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                Pill { visible: Cloud.busy !== "signin"; label: "Sign in"; primary: true; onGo: Cloud.signIn(ncSrv.text) }
                                Pill { visible: Cloud.busy === "signin"; label: "Cancel"; onGo: Cloud.cancelSignIn() }
                            }
                        }
                        Row {
                            visible: Cloud.busy === "signin"; spacing: Theme.spaceS
                            Spinner { anchors.verticalCenter: parent.verticalCenter }
                            TBody { anchors.verticalCenter: parent.verticalCenter; text: "Waiting for the browser. Sign in on your server's page and allow ewe…" }
                        }
                        Row {
                            visible: Cloud.loginUrl !== ""; spacing: Theme.spaceS
                            Pill { label: "Open the sign-in page"; onGo: Cloud.openLoginUrl() }
                            Pill { label: "Copy the link"; onGo: Cloud.copyLoginUrl() }
                        }
                        Alert { visible: Cloud.reason === "revoked"; tone: "warning"; text: "This machine's access was revoked on the server. Sign in again." }
                        Note { visible: Cloud.keyringPromptExpected; text: Cloud.keyringState === "locked" ? "Your keyring is locked, so an “Unlock keyring” prompt appears during sign-in. Answer it with your sign-in password." : "A “Choose password for new keyring” prompt appears during sign-in. Use your sign-in password, so it unlocks by itself every time you sign in." }
                        Alert { visible: Google.legacyGoogleSync; tone: "warning"; text: "Settings sync now uses a Nextcloud account. Sign in to keep your backups going; your Google Drive backup stays where it is." }
                    }
                    // signed in → identity + what the account provides + sign out
                    Card {
                        visible: Cloud.signedIn
                        Item {
                            width: parent.width; height: Theme.controlXl
                            AccountPic { id: ncPic; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; src: Cloud.avatarPath !== "" ? "file://" + Cloud.avatarPath : ""; initial: (Cloud.displayName || "?").charAt(0).toUpperCase() }
                            Column {
                                anchors.left: ncPic.right; anchors.leftMargin: Theme.spaceS + Theme.spaceXs; anchors.right: ncOut.left; anchors.rightMargin: Theme.spaceS
                                anchors.verticalCenter: parent.verticalCenter
                                TStrong { width: parent.width; text: Cloud.displayName || "Nextcloud account"; elide: Text.ElideRight }
                                TCaption { width: parent.width; text: (Cloud.email !== "" ? Cloud.email + " · " : "") + Cloud.serverHost; elide: Text.ElideRight }
                            }
                            Pill { id: ncOut; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; label: "Sign out"; onGo: Cloud.signOut() }
                        }
                        Divider {}
                        KV { k: "Server"; v: Cloud.serverHost + (Cloud.offline ? " · can't be reached right now" : ""); dot: Cloud.offline ? "info" : "ok" }
                        KV { k: "Storage"; v: Cloud.quota && Cloud.quota.total > 0 ? (root.fmtBytes(Cloud.quota.used) + " of " + root.fmtBytes(Cloud.quota.total) + " · " + Math.round(Cloud.quota.relative || 0) + "%") : (Cloud.quota ? root.fmtBytes(Cloud.quota.used) + " used" : "—") }
                        KV { k: "Files"; v: Cloud.filesMounted ? "In " + Cloud.filesPath : "Not connected"; dot: Cloud.filesMounted ? "ok" : "info"; action: !Cloud.filesMounted; actionLabel: "Connect files"; onAct: Cloud.mountFiles() }
                        KV { k: "Calendar"; v: Cloud.calState === "offline" ? "Offline, showing events from the last sync" : (Cloud.events.length + " upcoming in Quick settings"); dot: Cloud.calState === "offline" ? "info" : "ok" }
                        KV { k: "Mail"; v: Mail.source === "imap" ? Mail.imapUser : (Mail.source === "gmail" ? "Gmail (Google)" : "None. Add an IMAP account in the Settings app"); dot: Mail.available ? "ok" : "info" }
                        // the account app (RFC-006) — the in-shell cards stay as the fallback
                        KV { visible: Globals.syncAppInstalled; k: "Your machines, folders and conflicts"; dot: "ok"; action: true; actionLabel: "Open ewe-sync"; onAct: Globals.openSync() }
                    }
                    Alert { visible: Cloud.error !== ""; tone: "danger"; text: Cloud.error }
                    // the keyring rejects the login password → replace it (PAM
                    // recreates `login` with the login password at the next login)
                    Card {
                        visible: !Cloud.signedIn && (Cloud.keyringTrouble || Cloud.keyringResetDone)
                        KV { visible: !Cloud.keyringResetDone; k: "Keyring"; v: Cloud.keyringState === "locked" ? "Locked; it couldn't be unlocked at sign-in" : "It refused the app password"; dot: "bad"; action: true; actionLabel: "Reset keyring"; onAct: Cloud.resetKeyring() }
                        KV { visible: Cloud.keyringResetDone; k: "Keyring"; v: "Reset. Sign out and in again, then sign in here"; dot: "info"; action: true; actionLabel: "Sign out now"; onAct: Cloud.logOut() }
                    }

                    SectionTitle { visible: Cloud.signedIn; text: "Settings sync" }
                    Card {
                        visible: Cloud.signedIn
                        // two facts, kept apart: who SAVED the backup, and when THIS
                        // machine last talked to it
                        KV { k: "Backup in your account"; v: Cloud.cloudInfo ? ("Saved by “" + Cloud.cloudInfo.device + "” · " + root.fmtSyncTime(Cloud.cloudInfo.updatedAt)) : "None yet" }
                        KV { k: "This machine last synced"; v: (Cloud.localSyncedAt !== "" ? root.fmtSyncTime(Cloud.localSyncedAt) : (Cloud.lastSync !== "" ? root.fmtSyncTime(Cloud.lastSync) : "Never. Nothing is uploaded until you back it up")) + (Cloud.inSync && Cloud.lastSync !== "" ? " · up to date" : "") }
                        ToggleRow {
                            title: "Sync automatically"
                            sub: Cloud.lastSync === "" ? "Starts after this machine's first backup. After that, every change (in Settings, Komble or the terminal) is uploaded about 20 s later." : "Every change, in Settings, Komble or the terminal, is uploaded about 20 s later."
                            on: Cloud.autoSync
                            onToggled: Cloud.setAutoSync(!Cloud.autoSync)
                        }
                        Row {
                            spacing: Theme.spaceS
                            // a never-synced machine never auto-pushes: its first upload is this button
                            Pill { label: Cloud.syncState === "syncing" ? "Syncing…" : (Cloud.lastSync === "" ? "Back up this machine" : "Sync now"); primary: true; onGo: Cloud.syncNow() }
                            Pill { label: "Restore from your account…"; onGo: Cloud.requestRestore() }
                            // only offered when the server refused a push
                            Pill { visible: Cloud.syncConflict; label: "Upload anyway"; onGo: Cloud.pushForce() }
                        }
                        Note { text: "The machine file (ewe.conf) lives in the ewe folder of your account: scheme and accent, dock, animations, power, display profiles, window rules, wallpapers, pinned and startup apps, places, VPN and SSH hosts, and Komble's list of installed apps (reinstalling from it is always your choice). Passwords and keys never sync." }
                        Alert { visible: Cloud.syncError !== ""; tone: "danger"; text: Cloud.syncError }
                        Alert { visible: Cloud.restoreSummary !== ""; tone: "success"; text: Cloud.restoreSummary }
                    }
                    // restore confirmation — explicit, says what will change
                    Card {
                        visible: Cloud.pendingRestore !== null
                        border.color: Theme.accentText
                        Text { width: parent.width; text: "Restore settings from your account?"; color: Theme.textPrimary; wrapMode: Text.WordWrap
                               font.family: Theme.type.h4.family; font.pixelSize: Theme.type.h4.size; font.weight: Theme.type.h4.weight }
                        KV { k: "Saved on"; v: Cloud.pendingRestore ? ("“" + (Cloud.pendingRestore.device || "?") + "” · " + root.fmtSyncTime(Cloud.pendingRestore.updatedAt || "")) : "" }
                        KV { k: "Restores"; v: "The machine file (ewe.conf); your current one is kept as a dated backup" }
                        KV { k: "Apps"; v: "Offered in Komble → For you, never installed on their own" }
                        Alert { tone: "warning"; text: "This machine's scheme, dock, wallpaper, window rules, display profiles and app list are replaced, then the shell reloads them." }
                        Row {
                            anchors.right: parent.right; spacing: Theme.spaceS
                            Pill { label: "Cancel"; ghost: true; onGo: Cloud.cancelRestore() }
                            Pill { label: "Restore settings"; primary: true; onGo: Cloud.applyRestore() }
                        }
                    }

                    SectionTitle { text: "Google (optional)" }
                    // ewe ships no Google client (RFC-005): the extra exists only
                    // for people who bring their own OAuth client file
                    Card {
                        visible: !Google.personalClient
                        TBody { width: parent.width; color: Theme.textSecondary; wrapMode: Text.WordWrap
                            text: "For Gmail in Quick settings and Google Drive as a folder. ewe ships no Google client: create your own OAuth client of type “Desktop app” (docs/GOOGLE-CLIENT.md) and save it as the file below; then this turns into Connect." }
                        TMono { width: parent.width; text: Google.clientPath; elide: Text.ElideMiddle }
                    }
                    Alert {
                        visible: Google.personalClient && Google.probed && !Google.configured; tone: "warning"
                        text: "The client file is there, but it has no client_id that could be read. docs/GOOGLE-CLIENT.md shows the JSON it expects."
                    }
                    Card {
                        visible: Google.probed && Google.configured && !Google.signedIn
                        TBody { width: parent.width; color: Theme.textSecondary; wrapMode: Text.WordWrap
                            text: "Your client file is in place. Connect for Gmail in Quick settings and ~/Google Drive in Files. Settings sync never goes through Google." }
                        Row {
                            spacing: Theme.spaceS
                            Pill { visible: Google.busy !== "signin"; label: "Connect Google"; primary: true; onGo: Google.signIn() }
                            Spinner { visible: Google.busy === "signin"; anchors.verticalCenter: parent.verticalCenter }
                            TBody { visible: Google.busy === "signin"; anchors.verticalCenter: parent.verticalCenter; text: "Waiting for the browser…" }
                            Pill { visible: Google.busy === "signin"; label: "Cancel"; onGo: Google.cancelSignIn() }
                        }
                        Row {
                            visible: Google.consentUrl !== ""; spacing: Theme.spaceS
                            Pill { label: "Open the sign-in page"; onGo: Google.openConsentUrl() }
                            Pill { label: "Copy the link"; onGo: Google.copyConsentUrl() }
                        }
                    }
                    Card {
                        visible: Google.signedIn
                        Item {
                            width: parent.width; height: Theme.controlXl
                            AccountPic { id: gPic; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; src: (Google.profile && Google.profile.picture) ? Google.profile.picture : ""; initial: ((Google.profile && Google.profile.name) || "?").charAt(0).toUpperCase() }
                            Column {
                                anchors.left: gPic.right; anchors.leftMargin: Theme.spaceS + Theme.spaceXs; anchors.right: gOut.left; anchors.rightMargin: Theme.spaceS
                                anchors.verticalCenter: parent.verticalCenter
                                TStrong { width: parent.width; text: (Google.profile && Google.profile.name) || "Google account"; elide: Text.ElideRight }
                                TCaption { width: parent.width; text: (Google.profile && Google.profile.email) || ""; elide: Text.ElideRight }
                            }
                            Pill { id: gOut; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; label: "Disconnect"; onGo: Google.signOut() }
                        }
                        Divider {}
                        KV { k: "Gmail"; v: Mail.source === "gmail" ? "In Quick settings" : "Your IMAP account is used instead"; dot: Mail.source === "gmail" ? "ok" : "info" }
                        KV { k: "Google Drive"; v: "~/Google Drive in Files"; dot: "ok" }
                        KV { visible: Google.profile && Google.profile.picture; k: "Google profile photo"; action: true; actionLabel: "Use as picture"; onAct: root.useGooglePhoto() }
                    }
                    Alert { visible: Google.error !== ""; tone: "danger"; text: Google.error }
                    Card {
                        visible: Google.configured && !Google.signedIn && (Google.keyringTrouble || Google.keyringResetDone)
                        KV { visible: !Google.keyringResetDone; k: "Keyring"; v: Google.keyringState === "locked" ? "Locked; it couldn't be unlocked at sign-in" : "It refused the token"; dot: "bad"; action: true; actionLabel: "Reset keyring"; onAct: Google.resetKeyring() }
                        KV { visible: Google.keyringResetDone; k: "Keyring"; v: "Reset. Sign out and in again, then connect here"; dot: "info"; action: true; actionLabel: "Sign out now"; onAct: Google.logOut() }
                    }

                    SectionTitle { visible: Accounts.contacts.length > 0; text: "Contacts (" + Accounts.contacts.length + ")" }
                    Card {
                        visible: Accounts.contacts.length > 0
                        spacing: 0
                        Repeater {
                            model: Accounts.contacts.slice(0, 25)
                            delegate: Item {
                                id: ctRow
                                required property var modelData
                                width: parent.width; height: Theme.control2xl - Theme.spaceS
                                AccountPic { id: ctPic; width: Theme.controlMd; height: Theme.controlMd; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; initial: (ctRow.modelData.name || "?").charAt(0).toUpperCase() }
                                Column {
                                    anchors.left: ctPic.right; anchors.leftMargin: Theme.spaceS + Theme.spaceXs; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    TBody { width: parent.width; text: ctRow.modelData.name; elide: Text.ElideRight }
                                    TCaption { width: parent.width; text: (ctRow.modelData.emails[0] || "") + (ctRow.modelData.phones && ctRow.modelData.phones.length ? " · " + ctRow.modelData.phones[0] : ""); elide: Text.ElideRight }
                                }
                            }
                        }
                        Note { visible: Accounts.contacts.length > 25; topPadding: Theme.spaceXs; text: "And " + (Accounts.contacts.length - 25) + " more" }
                    }
                }
            }

            // ════════ PANE — Accessibility (new, Accessibility modes) ════════
            // The four modes, stored in ewe.conf [desktop.accessibility] and
            // applied by the generator as remaps: nothing on this page (or
            // anywhere else) asks which mode is on to decide how to draw.
            Component {
                id: cAccessibility
                Column {
                    spacing: Theme.spaceS
                    Card {
                        SetRow {
                            glyph: root.g(0xE121); title: "Reduce motion"
                            desc: "Fades instead of slides; nothing moves more than it has to."
                            Toggle {
                                anchors.verticalCenter: parent.verticalCenter
                                on: root.tokIn("reduce_motion", false) === true
                                onToggled: root.confSet("desktop.accessibility.reduce_motion", on ? "false" : "true")
                            }
                        }
                        SetRow {
                            glyph: root.g(0xE59C); title: "Reduce transparency"
                            desc: "Solid bar, dock and lock screen card; no blur."
                            Toggle {
                                anchors.verticalCenter: parent.verticalCenter
                                on: root.tokIn("reduce_transparency", false) === true
                                onToggled: root.confSet("desktop.accessibility.reduce_transparency", on ? "false" : "true")
                            }
                        }
                        SetRow {
                            glyph: root.g(0xE09D); title: "Increase contrast"
                            desc: "Stronger outlines and text, and a thicker focus ring."
                            Toggle {
                                anchors.verticalCenter: parent.verticalCenter
                                on: root.tokIn("increase_contrast", false) === true
                                onToggled: root.confSet("desktop.accessibility.increase_contrast", on ? "false" : "true")
                            }
                        }
                        SetRow {
                            glyph: root.g(0xE198); title: "Text size"
                            desc: "Text grows, and controls grow with it. At 130% the bar uses its large size."
                            Seg {
                                anchors.verticalCenter: parent.verticalCenter
                                options: [{ label: "100%", value: 100 }, { label: "115%", value: 115 }, { label: "130%", value: 130 }]
                                value: Number(root.tokIn("text_scale", 100))
                                onPicked: function (v) { root.confSet("desktop.accessibility.text_scale", v) }
                            }
                        }
                    }
                    Note { text: "These work with every scheme and look, and apply to the whole desktop at once. Display scaling (125%, 150%) is separate, in Displays." }
                }
            }

            // ════════ overlays: error alert · saved confirmation · dialogs ════════
            // an error: a danger Inline alert along the bottom of the pane,
            // closed with its × (Inline alert card)
            Rectangle {
                visible: root.errorMsg !== ""
                anchors.horizontalCenter: pagePane.horizontalCenter; anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.spaceMd + Theme.spaceS
                width: Math.min(errText.implicitWidth + Theme.iconMd + Theme.controlSm + 2 * Theme.spaceMd + Theme.spaceS, pagePane.width - 2 * Theme.spaceMd)
                height: Math.max(Theme.controlLg, errText.implicitHeight + 2 * Theme.spaceS); z: 60
                radius: Theme.radiusPrimary
                color: Theme.dangerSubtle
                border.color: Theme.danger; border.width: Theme.borderWidth1
                Text { id: errIc; anchors.left: parent.left; anchors.leftMargin: Theme.spaceS + Theme.spaceXs; anchors.verticalCenter: parent.verticalCenter; text: Theme.icWarning; font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: Theme.danger }
                TBody { id: errText; anchors.left: errIc.right; anchors.leftMargin: Theme.spaceS; anchors.right: errX.left; anchors.rightMargin: Theme.spaceS; anchors.verticalCenter: parent.verticalCenter; text: root.errorMsg; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }
                IconBtn { id: errX; anchors.right: parent.right; anchors.rightMargin: Theme.spaceXs; anchors.verticalCenter: parent.verticalCenter; onGo: root.clearError() }
            }
            // a change applied and kept: a short confirmation at the pane's
            // bottom right (Toast card: past tense, names the thing)
            Rectangle {
                visible: root.appliedMsg !== "" && root.errorMsg === ""
                anchors.right: pagePane.right; anchors.bottom: parent.bottom
                anchors.rightMargin: Theme.spaceMd; anchors.bottomMargin: Theme.spaceMd + Theme.spaceS
                width: apRow.implicitWidth + 2 * (Theme.spaceS + Theme.spaceXs); height: Theme.controlLg; z: 60
                radius: Theme.radiusPrimary
                color: Theme.surfaceOverlay
                border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                Row {
                    id: apRow
                    anchors.centerIn: parent; spacing: Theme.spaceS
                    Text { anchors.verticalCenter: parent.verticalCenter; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: Theme.iconMd; color: Theme.success }
                    TBody { anchors.verticalCenter: parent.verticalCenter; text: root.appliedMsg; font.weight: Theme.fontWeightMedium }
                }
            }
            // avatar crop (Dialog card): pan by dragging, zoom with the slider,
            // inside a square; Save grabs it at 512×512 and writes ~/.face
            Rectangle {
                anchors.fill: parent; color: Theme.scrim; z: 65
                visible: root.avatarCropSrc !== ""
                MouseArea { anchors.fill: parent }   // swallow clicks
                Rectangle {
                    anchors.centerIn: parent; width: Theme.panelMd; height: cropCol.implicitHeight + 2 * Theme.spaceMd
                    radius: Theme.radiusRounded; color: Theme.surfaceRaised
                    border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                    Column {
                        id: cropCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.spaceMd; spacing: Theme.spaceMd
                        Text { text: "Crop your picture"; color: Theme.textPrimary
                               font.family: Theme.type.h3.family; font.pixelSize: Theme.type.h3.size; font.weight: Theme.type.h3.weight }
                        Item {
                            id: cropView
                            anchors.horizontalCenter: parent.horizontalCenter
                            // the crop square: four times the largest icon
                            readonly property real side: 4 * Theme.icon4xl
                            width: side; height: side
                            property real zoom: 1
                            onVisibleChanged: if (visible) zoom = 1
                            Item {
                                id: cropCanvas
                                anchors.fill: parent; clip: true
                                Image {
                                    id: cropImg
                                    source: root.avatarCropSrc === "" ? "" : "file://" + root.avatarCropSrc
                                    readonly property real baseScale: status === Image.Ready && implicitWidth > 0 && implicitHeight > 0 ? Math.max(cropView.side / implicitWidth, cropView.side / implicitHeight) : 1
                                    width: implicitWidth * baseScale * cropView.zoom
                                    height: implicitHeight * baseScale * cropView.zoom
                                    onStatusChanged: if (status === Image.Ready) { x = (cropView.side - width) / 2; y = (cropView.side - height) / 2 }
                                }
                            }
                            // overlay chrome lives OUTSIDE cropCanvas so the grab stays clean
                            Rectangle { anchors.fill: parent; color: "transparent"; border.color: Theme.borderSubtle; border.width: Theme.borderWidth1 }
                            Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.color: Theme.textPrimary; border.width: Theme.borderWidth1 }
                            MouseArea {
                                anchors.fill: parent
                                drag.target: cropImg
                                drag.minimumX: cropView.side - cropImg.width; drag.maximumX: 0
                                drag.minimumY: cropView.side - cropImg.height; drag.maximumY: 0
                                cursorShape: Qt.SizeAllCursor
                            }
                        }
                        Slider {
                            label: "Zoom"; value: cropView.zoom; from: 1; to: 3; step: 0.05; decimals: 2; live: true
                            onMoved: function (v) {
                                var s = cropView.side, h = s / 2
                                var cx = cropImg.width > 0 ? (h - cropImg.x) / cropImg.width : 0.5
                                var cy = cropImg.height > 0 ? (h - cropImg.y) / cropImg.height : 0.5
                                cropView.zoom = v
                                cropImg.x = Math.min(0, Math.max(s - cropImg.width, h - cx * cropImg.width))
                                cropImg.y = Math.min(0, Math.max(s - cropImg.height, h - cy * cropImg.height))
                            }
                        }
                        Row {
                            anchors.right: parent.right; spacing: Theme.spaceS
                            Pill { label: "Cancel"; ghost: true; onGo: root.avatarCropSrc = "" }
                            Pill { label: "Save picture"; primary: true; onGo: root.saveAvatar() }
                        }
                    }
                }
            }
            Rectangle {
                // confirm-or-revert (Dialog card): a change that can black out a
                // display was just applied; unless it is kept within 10 s, the
                // previous known-good configuration comes back by itself.
                anchors.fill: parent; color: Theme.scrim; z: 70
                visible: root.revertSpecs !== null
                MouseArea { anchors.fill: parent }   // swallow clicks
                Rectangle {
                    anchors.centerIn: parent; width: Theme.panelMd; height: revCol.implicitHeight + 2 * Theme.spaceMd
                    radius: Theme.radiusRounded; color: Theme.surfaceRaised
                    border.color: Theme.borderSubtle; border.width: Theme.borderWidth1
                    Column {
                        id: revCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.spaceMd; spacing: Theme.spaceMd
                        Column {
                            width: parent.width; spacing: Theme.spaceXs
                            Text { width: parent.width; text: "Keep these display settings?"; color: Theme.textPrimary; wrapMode: Text.WordWrap
                                   font.family: Theme.type.h3.family; font.pixelSize: Theme.type.h3.size; font.weight: Theme.type.h3.weight }
                            TBody { width: parent.width; text: "The previous settings come back in " + root.revertLeft + " s if you can't see this."; color: Theme.textSecondary; wrapMode: Text.WordWrap }
                        }
                        Row {
                            anchors.right: parent.right; spacing: Theme.spaceS
                            Pill { label: "Revert now"; ghost: true; onGo: root.doRevert() }
                            Pill { label: "Keep settings"; primary: true; onGo: root.keepChange() }
                        }
                    }
                }
            }
        }
    }
}
