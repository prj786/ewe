import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Settings — a universal, themed settings window (Super+, · Quick Settings gear ·
// Launcher "Settings"). A real toplevel window (movable/resizable/closable);
// sidebar nav + content. Panes: System/Diagnostics, Displays, Networking,
// Default Apps, Keyboard & Mouse, Shortcuts, Layout, Theme, Wallpaper, Dock,
// User. All colours from Theme.qml.
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
    readonly property var navItems: [
        { key: "system",    ic: 0xE610, label: "System" },
        { key: "displays",  ic: 0xE32E, label: "Displays" },
        { key: "network",   ic: 0xE4EA, label: "Networking" },
        { key: "defaults",  ic: 0xE5DA, label: "Default Apps" },
        { key: "input",     ic: 0xE2D8, label: "Keyboard & Mouse" },
        { key: "shortcuts", ic: 0xE1C4, label: "Shortcuts" },
        { key: "layout",    ic: 0xE6D6, label: "Layout" },
        { key: "theme",     ic: 0xE6C8, label: "Theme" },
        { key: "wallpaper", ic: 0xE2CA, label: "Wallpaper" },
        { key: "saver",     ic: 0xE58E, label: "Screensaver" },
        { key: "power",     ic: 0xE3DA, label: "Power" },
        { key: "dock",      ic: 0xEE50, label: "Dock" },
        { key: "startup",   ic: 0xE3FE, label: "Startup" },
        { key: "user",      ic: 0xE4C2, label: "User" }
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
        else if (k === "user") { Globals.recheckFace(); userInfoProbe.running = false; userInfoProbe.running = true; Google.refresh(); Accounts.refresh() }
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
    property int  gapsIn: 6
    property int  gapsOut: 14
    property int  borderSize: 1
    property int  rounding: 12      // decoration.rounding (window corner radius)

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

    function writeOverrides(after) {
        var s = "-- AUTO-GENERATED by the Quickshell Settings app. Do not edit by hand.\n"
        var gen = "hl.config({ general = { gaps_in = " + root.gapsIn
                + ", gaps_out = " + root.gapsOut + ", border_size = " + root.borderSize
        if (Globals.tintBorders)
            gen += ", col = { active_border = \"rgba(" + root.hex6(Theme.accent) + "ff)\" }"
        gen += " } })\n"
        s += gen
        s += "hl.config({ decoration = { rounding = " + root.rounding + " } })\n"
        s += root.transparencyLua() + "\n"
        s += root.animBlockPersist()
        s += root.tilingLua()
        root.atomicWrite(luaWriter, root.home + "/.config/hypr/generated/user.lua", s, after)
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
                : "no auto-lock")
        } else if (Globals.saverEnabled) {
            parts.push("lock at " + mins(Globals.saverMin) + " min")
        } else {
            parts.push("lock at " + mins(5) + " min")
        }
        parts.push("suspend at 15 min on battery")
        parts.push("no display power-off")
        return parts.join(" · ") + (Globals.lowPower ? "   (battery timeline)" : "")
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
    function applyBorder() {
        if (Globals.tintBorders)
            Quickshell.execDetached(["hyprctl", "eval",
                "hl.config({ general = { col = { active_border = \"rgba(" + root.hex6(Theme.accent) + "ff)\" } } })"])
        root.writeOverrides()
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

    function flashApplied(msg) { root.appliedMsg = msg || "Applied"; appliedClear.restart() }
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
        HyprMon.commit(HyprMon.snapshot()); root.flashApplied("Saved")
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
        HyprMon.commit(specs); root.flashApplied("Primary display saved")
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
        { key: "Browser",      ic: 0xE288, mime: "x-scheme-handler/https", mimes: ["x-scheme-handler/https", "x-scheme-handler/http", "text/html"] },
        { key: "Mail",         ic: 0xE214, mime: "x-scheme-handler/mailto", mimes: ["x-scheme-handler/mailto"] },
        { key: "Text Editor",  ic: 0xE23A, mime: "text/plain", mimes: ["text/plain"] },
        { key: "Image Viewer", ic: 0xE2CA, mime: "image/png", mimes: ["image/png", "image/jpeg", "image/gif", "image/webp"] },
        { key: "Video Player", ic: 0xE792, mime: "video/mp4", mimes: ["video/mp4", "video/x-matroska", "video/webm"] },
        { key: "File Manager", ic: 0xE24A, mime: "inode/directory", mimes: ["inode/directory"] }
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
    // because it is Hyprland state rather than toolkit state.
    Connections { target: Globals; function onPrefsReloaded() { root.applyBorder() } }
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
    Process { id: devOvWriter }

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
    function writeInputLua() {
        var s = "-- AUTO-GENERATED by Settings → Keyboard & Mouse. Do not edit by hand.\n" + root.inputLua(root.inp) + "\n"
        var devs = Object.keys(root.devOverrides).sort()
        for (var i = 0; i < devs.length; i++) s += root.deviceLua(devs[i], root.devOverrides[devs[i]]) + "\n"
        root.atomicWrite(inputLuaWriter, root.home + "/.config/hypr/generated/input.lua", s)
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
        root.atomicWrite(devOvWriter, root.home + "/.config/quickshell/input-devices.json", JSON.stringify(all, null, 2))
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
        { label: "Super+Space only (DE bind)", value: "" },
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
    Process { id: wpDirProbe; command: ["sh", "-c", 'for d in "$HOME/Pictures/Wallpapers" "$HOME/Pictures" "$HOME"; do [ -d "$d" ] && { echo "$d"; exit; }; done']; stdout: StdioCollector { onStreamFinished: { var d = this.text.trim(); if (d !== "") root.wpList(d) } } }
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
            root.errorMsg = "Video wallpapers need mpvpaper — install it with: sudo pacman -S mpvpaper"
            return
        }
        if (root.wpIsGif(path) && root.wpImgBackend === "swaybg")
            root.errorMsg = "GIFs will be static with swaybg — install swww (sudo pacman -S awww) for animation"
        var m
        if (root.wpTarget === "*") m = { "*": path }   // "all displays" replaces per-monitor picks
        else { m = {}; for (var k in root.wpMap) m[k] = root.wpMap[k]; m[root.wpTarget] = path }
        root.wpMap = m
        root.wpWrite()
        root.flashApplied("Wallpaper set")
    }
    // file picking + drag-and-drop live in the shared FileDropTarget component
    // (instantiated by the Wallpaper and User panes)

    // accent presets
    readonly property var accents: [
        { name: "Blue", hex: "#0a84ff" }, { name: "Indigo", hex: "#5e5ce6" }, { name: "Purple", hex: "#bf5af2" },
        { name: "Pink", hex: "#ff375f" }, { name: "Red", hex: "#ff453a" }, { name: "Orange", hex: "#ff9f0a" },
        { name: "Yellow", hex: "#ffd60a" }, { name: "Green", hex: "#30d158" }, { name: "Teal", hex: "#40c8e0" },
        { name: "Graphite", hex: "#8e8e93" }
    ]

    // ── User: AccountsService identity + session facts ────────────────────────
    property string userRealName: ""
    property var sysFacts: ({})
    function fmtSyncTime(iso) {
        var d = new Date(iso)
        return isNaN(d.getTime()) ? (iso || "—") : Qt.formatDateTime(d, "d MMM · h:mm AP")
    }

    // ── packages-from-backup review: diff the cloud bundle against pacman -Qq
    // and offer a checkbox install (runs visibly in kitty; AUR via paru) ───────
    property var pkgReview: null      // { repo: [{name,on}], aur: [{name,on}] } | null = closed
    property var _manifest: null
    function reviewPackages() {
        // RFC-002: the app list is ewe.conf's [apps.installed] (read through
        // ewe-conf, same source as Komble's For You)
        manifestProbe.running = false; manifestProbe.running = true
    }
    Process {
        id: manifestProbe
        command: [Globals.eweConf, "get", "apps.installed"]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = null
                try { m = JSON.parse(this.text) } catch (e) {}
                if (!m || !m.packages) { root.errorMsg = "No synced app list yet — restore the machine file first (or install something through Komble)."; return }
                root._manifest = m
                pkgProbe.running = false; pkgProbe.running = true
            }
        }
    }
    Process {
        id: pkgProbe
        command: ["pacman", "-Qq"]
        stdout: StdioCollector {
            onStreamFinished: {
                var installed = {}, ls = this.text.split("\n")
                for (var i = 0; i < ls.length; i++) if (ls[i] !== "") installed[ls[i]] = true
                var repo = [], aur = []
                var pk = (root._manifest && root._manifest.packages) || []
                for (var j = 0; j < pk.length; j++) {
                    if (!pk[j].package || installed[pk[j].package]) continue
                    (pk[j].source === "aur" ? aur : repo).push({ name: pk[j].package, on: true })
                }
                root.pkgReview = { repo: repo, aur: aur }
            }
        }
    }
    function pkgToggle(kind, idx) {
        var r = JSON.parse(JSON.stringify(root.pkgReview))
        r[kind][idx].on = !r[kind][idx].on
        root.pkgReview = r
    }
    function pkgSetAll(on) {
        var r = JSON.parse(JSON.stringify(root.pkgReview))
        for (var i = 0; i < r.repo.length; i++) r.repo[i].on = on
        for (var j = 0; j < r.aur.length; j++) r.aur[j].on = on
        root.pkgReview = r
    }
    function pkgSelectedCount() {
        if (!root.pkgReview) return 0
        var n = 0
        for (var i = 0; i < root.pkgReview.repo.length; i++) if (root.pkgReview.repo[i].on) n++
        for (var j = 0; j < root.pkgReview.aur.length; j++) if (root.pkgReview.aur[j].on) n++
        return n
    }
    function pkgInstallSelected() {
        var repo = [], aur = []
        for (var i = 0; i < root.pkgReview.repo.length; i++) if (root.pkgReview.repo[i].on) repo.push(root.pkgReview.repo[i].name)
        for (var j = 0; j < root.pkgReview.aur.length; j++) if (root.pkgReview.aur[j].on) aur.push(root.pkgReview.aur[j].name)
        if (repo.length === 0 && aur.length === 0) return
        var cmd = ""
        if (repo.length > 0) cmd += "sudo pacman -S --needed " + repo.join(" ")
        if (aur.length > 0) cmd += (cmd !== "" ? " && " : "") + "paru -S --needed " + aur.join(" ")
        Quickshell.execDetached(["kitty", "--title", "ewe package restore", "-e", "sh", "-c",
            cmd + '; s=$?; echo; if [ $s -eq 0 ]; then echo "── done ──"; else echo "── exited with status $s ──"; fi; read -n 1 -s -p "press any key to close"'])
    }
    // after a cloud restore lands, open the review so the user sees what's missing
    Connections {
        target: Google
        function onRestoreSummaryChanged() { if (Google.restoreSummary !== "" && Globals.settingsOpen) root.reviewPackages() }
    }
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
                if (t !== "") root.errorMsg = "Could not update the display name: " + t.split("\n")[0]
                else { root.flashApplied("Name updated"); userInfoProbe.running = false; userInfoProbe.running = true }
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
        if (p.indexOf("google") >= 0) return 0xE292           // google-logo
        if (p.indexOf("imap") >= 0 || p.indexOf("smtp") >= 0) return 0xE214  // envelope
        return 0xE1AA                                         // cloud (exchange/nextcloud/webdav/…)
    }

    // ── avatar: pick → crop (pan/zoom) → 512² PNG to ~/.face + AccountsService ──
    property string avatarCropSrc: ""      // image being cropped ("" = dialog closed)
    function saveAvatar() {
        cropCanvas.grabToImage(function (res) {
            var tmp = root.home + "/.cache/ewe-avatar.png"
            if (!res.saveToFile(tmp)) { root.errorMsg = "Could not write the cropped image."; root.avatarCropSrc = ""; return }
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
                if (out.indexOf("CP-FAIL") >= 0) root.errorMsg = "Could not save ~/.face (check permissions)."
                else if (out.indexOf("ACCOUNTS-FAIL") >= 0) { root.errorMsg = "Avatar saved to ~/.face, but AccountsService rejected the update — the login screen may keep the old icon."; Globals.recheckFace() }
                else { root.flashApplied("Avatar updated"); Globals.recheckFace() }
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
                if (this.text.indexOf("DL-OK") < 0) { root.errorMsg = "Could not download the Google profile photo."; return }
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
        implicitWidth: 880
        implicitHeight: 620
        minimumSize: Qt.size(720, 480)
        color: Theme.panel
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
                Connections { target: Globals; function onSettingsOpenChanged() { if (Globals.settingsOpen) keyGrab.forceActiveFocus() } }
            }

            // ════════ reusable bits ════════
            component Dot: Rectangle { property string state: "info"; width: 9; height: 9; radius: 5; color: state === "ok" ? Theme.success : state === "bad" ? Theme.danger : Theme.fgDim }
            component Card: Rectangle {
                default property alias content: inner.data
                width: parent ? parent.width : 0
                implicitHeight: inner.implicitHeight + 24
                radius: Theme.radiusInner; color: Theme.elevated
                Column { id: inner; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12; spacing: 8 }
            }
            component SectionTitle: Text { color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; bottomPadding: 2 }
            component KV: Item {
                property string k: ""; property string v: ""; property string dot: ""
                property bool action: false; property string actionLabel: ""
                signal act()
                width: parent ? parent.width : 0; height: 26
                Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: k; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: !action && v !== ""; text: v; color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; elide: Text.ElideRight; width: Math.min(implicitWidth, 340) }
                    Rectangle { visible: action; anchors.verticalCenter: parent.verticalCenter; width: alab.implicitWidth + 18; height: 22; radius: 7; color: aMa.containsMouse ? Theme.accent : Theme.hover; Behavior on color { ColorAnimation { duration: 120 } }
                        Text { id: alab; anchors.centerIn: parent; text: actionLabel; color: aMa.containsMouse ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                        MouseArea { id: aMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: act() } }
                    Dot { anchors.verticalCenter: parent.verticalCenter; visible: dot !== ""; state: dot }
                }
            }
            // Slider — the one slider, int or float (step/decimals). The label
            // previews live while dragging, but `moved` only fires per-move when
            // `live` is set — handlers that spawn processes (hyprctl + config
            // writes) get exactly one call, on release.
            component Slider: Item {
                id: sld
                property string label: ""; property real value: 0; property real from: 0; property real to: 30
                property real step: 1; property int decimals: 0; property bool live: false
                signal moved(real v)
                property real dragVal: 0
                property bool dragging: false
                readonly property real shown: dragging ? dragVal : value
                height: 40; width: parent ? parent.width : 0
                Text { anchors.left: parent.left; anchors.top: parent.top; text: sld.label; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                Text { anchors.right: parent.right; anchors.top: parent.top; text: Number(sld.shown).toFixed(sld.decimals); color: Theme.accent; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                Rectangle {
                    id: strk; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.bottomMargin: 4; height: 8; radius: 4; color: Theme.hover
                    Rectangle { height: parent.height; radius: 4; color: Theme.accent; width: parent.width * (sld.shown - sld.from) / Math.max(0.0001, sld.to - sld.from) }
                    Rectangle { width: 14; height: 14; radius: 7; color: "white"; anchors.verticalCenter: parent.verticalCenter; x: Math.max(0, Math.min(strk.width - width, strk.width * (sld.shown - sld.from) / Math.max(0.0001, sld.to - sld.from) - width / 2)) }
                    MouseArea {
                        anchors.fill: parent; anchors.topMargin: -8; anchors.bottomMargin: -8
                        function pick(mx) { var f = Math.max(0, Math.min(1, mx / strk.width)); var v = sld.from + f * (sld.to - sld.from); return Math.round(v / sld.step) * sld.step }
                        onPressed: function (m) { sld.dragging = true; sld.dragVal = pick(m.x); if (sld.live) sld.moved(sld.dragVal) }
                        onPositionChanged: function (m) { if (!pressed) return; sld.dragVal = pick(m.x); if (sld.live) sld.moved(sld.dragVal) }
                        onReleased: { sld.dragging = false; sld.moved(sld.dragVal) }
                    }
                }
            }
            component Toggle: Rectangle {
                property bool on: false
                signal toggled()
                width: 40; height: 24; radius: 12; color: on ? Theme.accent : Theme.hover; Behavior on color { ColorAnimation { duration: 150 } }
                activeFocusOnTab: true
                border.color: activeFocus ? Theme.fg : "transparent"; border.width: activeFocus ? 1 : 0
                Keys.onSpacePressed: toggled()
                Keys.onReturnPressed: toggled()
                Rectangle { width: 18; height: 18; radius: 9; color: "white"; anchors.verticalCenter: parent.verticalCenter; x: parent.on ? parent.width - width - 3 : 3; Behavior on x { NumberAnimation { duration: 150 } } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: toggled() }
            }
            component Pill: Rectangle {
                property string label: ""; property bool primary: false
                signal go()
                width: pl.implicitWidth + 22; height: 28; radius: 8
                color: plMa.containsMouse ? Theme.accent : (primary ? Theme.accent : Theme.elevated)
                Behavior on color { ColorAnimation { duration: 120 } }
                activeFocusOnTab: true
                border.color: activeFocus ? Theme.fg : "transparent"; border.width: activeFocus ? 1 : 0
                Keys.onSpacePressed: go()
                Keys.onReturnPressed: go()
                Text { id: pl; anchors.centerIn: parent; text: label; color: (plMa.containsMouse || primary) ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                MouseArea { id: plMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: go() }
            }
            // ToggleRow — label (+ optional sub-caption) left, Toggle right
            component ToggleRow: Item {
                property string title: ""; property string sub: ""; property bool on: false; property bool dim: false
                signal toggled()
                width: parent ? parent.width : 0; height: sub !== "" ? 34 : 28
                opacity: dim ? 0.45 : 1
                Column {
                    anchors.left: parent.left; anchors.right: trTog.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                    Text { text: title; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; elide: Text.ElideRight; width: parent.width }
                    Text { visible: sub !== ""; text: sub; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10; elide: Text.ElideRight; width: parent.width }
                }
                Toggle { id: trTog; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; on: parent.on; onToggled: if (!parent.dim) parent.toggled() }
            }
            // DropRow moved to the shared DropRow.qml (qmldir) so Quick Settings
            // uses the same dropdown; exclusive-open state lives in Globals.openDd.

            // ════════ layout: sidebar + content ════════
            Row {
                anchors.fill: parent; spacing: 0
                Rectangle {
                    width: 210; height: parent.height; color: Theme.bg
                    Column {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 14; spacing: 12
                        Text { text: "Settings"; color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge; font.weight: Font.Bold; bottomPadding: 2 }
                        Column {
                            width: parent.width; spacing: 2
                            Repeater {
                                model: root.navItems
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: parent.width; height: 36; radius: Theme.radiusInner
                                    readonly property bool sel: root.pane === index
                                    color: sel ? Theme.accent : (nMa.containsMouse ? Theme.hover : "transparent")
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Row {
                                        anchors.left: parent.left; anchors.leftMargin: 11; anchors.verticalCenter: parent.verticalCenter; spacing: 11
                                        Text { anchors.verticalCenter: parent.verticalCenter; width: 18; text: root.g(modelData.ic); font.family: Theme.fontIcons; font.pixelSize: 15; color: parent.parent.sel ? Theme.accentText : Theme.fg }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: parent.parent.sel ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: parent.parent.sel ? Font.DemiBold : Font.Medium }
                                    }
                                    MouseArea { id: nMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pane = index }
                                }
                            }
                        }
                    }
                    Rectangle {
                        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 14
                        width: 30; height: 30; radius: 15; color: xMa.containsMouse ? Theme.hover : Theme.elevated
                        Text { anchors.centerIn: parent; text: Theme.icClose; font.family: Theme.fontIcons; font.pixelSize: 14; color: Theme.fg }
                        MouseArea { id: xMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Globals.settingsOpen = false }
                    }
                    // version badge (bottom-right of the sidebar)
                    Text {
                        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 16
                        text: "ewe " + Globals.version
                        color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10
                    }
                }
                Rectangle { width: 1; height: parent.height; color: Theme.stroke }
                Item {
                    width: parent.width - 211; height: parent.height
                    Text { anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 20; text: root.navItems[root.pane].label; color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsTitle; font.weight: Font.Bold }
                    Flickable {
                        anchors.fill: parent; anchors.topMargin: 60; anchors.margins: 20
                        contentHeight: paneLoader.item ? paneLoader.item.implicitHeight : 0
                        clip: true; boundsBehavior: Flickable.StopAtBounds
                        Loader { id: paneLoader; width: parent.width; sourceComponent: ({ system: cSystem, displays: cDisplays, network: cNetwork, defaults: cDefaults, input: cKeyboard, shortcuts: cShortcuts, layout: cLayout, theme: cTheme, wallpaper: cWallpaper, saver: cSaver, power: cPower, dock: cDock, startup: cStartup, user: cUser })[root.paneKey] }
                    }
                }
            }

            // ════════ PANE 0 — System / Diagnostics ════════
            Component {
                id: cSystem
                Column {
                    spacing: 14
                    SectionTitle { text: "AUDIO" }
                    Card {
                        id: audioCard
                        PwObjectTracker { objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : [] }
                        property var sink: Pipewire.defaultAudioSink
                        property bool muted: sink && sink.audio ? sink.audio.muted : false
                        KV { k: "Output"; v: audioCard.sink ? (audioCard.sink.description || audioCard.sink.nickname || audioCard.sink.name) : "—"; dot: audioCard.sink ? (audioCard.muted ? "bad" : "ok") : "bad" }
                        KV { k: "Volume"; v: (audioCard.sink && audioCard.sink.audio ? Math.round(audioCard.sink.audio.volume * 100) : 0) + "%" + (audioCard.muted ? "  ·  muted" : "") }
                        KV { k: "Muted"; action: audioCard.muted; actionLabel: "Unmute"; v: audioCard.muted ? "" : "No"; dot: audioCard.muted ? "bad" : "ok"; onAct: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"]) }
                    }
                    SectionTitle { text: "DESKTOP PORTALS  ·  lets apps open links/files & the browser open apps back" }
                    Card {
                        KV { k: "graphical-session.target"; v: root.diag.gsession || "?"; dot: root.diag.gsession === "active" ? "ok" : "bad" }
                        KV { k: "xdg-desktop-portal"; v: root.diag.portal || "?"; dot: root.diag.portal === "active" ? "ok" : "bad" }
                        KV { k: "portal: hyprland"; v: root.diag.portal_hypr || "?"; dot: root.diag.portal_hypr === "active" ? "ok" : "bad" }
                        KV { k: "portal: gtk"; v: root.diag.portal_gtk || "?"; dot: root.diag.portal_gtk === "active" ? "ok" : "bad" }
                        KV { k: "App link handoff (OpenURI)"; v: root.diag.handoff === "ok" ? "working" : "unavailable"; dot: root.diag.handoff === "ok" ? "ok" : "bad" }
                        KV { k: "Default browser"; v: root.appNameForId(root.diag.browser) }
                    }
                    SectionTitle { text: "SYSTEM" }
                    Card {
                        KV { k: "GPU driver"; v: root.diag.gpu || "?"; dot: "info" }
                        KV { k: "VPN"; v: Globals.vpnActive ? "connected" : "off"; dot: Globals.vpnActive ? "ok" : "info" }
                        KV { k: "Idle policy"; v: root.idlePolicyText(); dot: "info" }
                        KV { k: "Memory"; v: root.diag.mem || "?"; dot: "info" }
                        KV { k: "Disk /"; v: root.diag.disk || "?"; dot: "info" }
                    }
                    Pill { label: "Re-run checks"; onGo: root.refresh() }
                    Item { width: 1; height: 8 }
                }
            }

            // ════════ PANE 1 — Displays ════════
            Component {
                id: cDisplays
                Column {
                    spacing: 14
                    Card {
                        visible: HyprMon.monitors.length === 0
                        Text { width: parent.width; text: HyprMon.loading ? "Querying displays…" : "No displays reported by Hyprland."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                    }
                    SectionTitle { visible: HyprMon.monitors.length > 0; text: "ARRANGEMENT  ·  drag a display; edges snap together" }
                    Card {
                        visible: HyprMon.monitors.length > 0
                        Item {
                            id: arena
                            width: parent.width; height: 200
                            readonly property var specs: root.dispSpecs.filter(function (s) { return !s.disabled })
                            readonly property real pad: 14
                            readonly property real spanW: { var mx = 1; for (var i = 0; i < specs.length; i++) mx = Math.max(mx, specs[i].x + root.specW(specs[i])); return mx }
                            readonly property real spanH: { var mx = 1; for (var i = 0; i < specs.length; i++) mx = Math.max(mx, specs[i].y + root.specH(specs[i])); return mx }
                            readonly property real factor: Math.min((width - 2 * pad) / spanW, (height - 2 * pad) / spanH)
                            Repeater {
                                model: arena.specs
                                delegate: Rectangle {
                                    id: monBox
                                    required property var modelData
                                    width: root.specW(modelData) * arena.factor; height: root.specH(modelData) * arena.factor; radius: 8
                                    x: arena.pad + modelData.x * arena.factor
                                    y: arena.pad + modelData.y * arena.factor
                                    color: dragMa.drag.active ? Theme.hover : (root.isLaptop(modelData) ? Theme.elevated : Theme.panel)
                                    border.color: dragMa.drag.active ? Theme.accent : Theme.stroke; border.width: dragMa.drag.active ? 2 : 1
                                    Column { anchors.centerIn: parent; spacing: 1
                                        Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 5
                                            Text { anchors.verticalCenter: parent.verticalCenter; text: monBox.modelData.name; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                            Text { anchors.verticalCenter: parent.verticalCenter; visible: monBox.modelData.primary; text: Theme.icStar; font.family: Theme.fontIcons; font.pixelSize: 10; color: Theme.accent }
                                        }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: HyprMon.modeRes(monBox.modelData.mode).replace("x", "×") + " @ " + Math.round(HyprMon.modeHz(monBox.modelData.mode)) + "Hz"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "scale " + Number(monBox.modelData.scale).toFixed(2) + "×"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }
                                    }
                                    MouseArea {
                                        id: dragMa; anchors.fill: parent; cursorShape: Qt.SizeAllCursor
                                        drag.target: monBox; drag.axis: Drag.XAndYAxis
                                        drag.minimumX: 0; drag.maximumX: arena.width - monBox.width
                                        drag.minimumY: 0; drag.maximumY: arena.height - monBox.height
                                        onReleased: root.snapDrop(monBox.modelData.name, (monBox.x - arena.pad) / arena.factor, (monBox.y - arena.pad) / arena.factor)
                                    }
                                }
                            }
                        }
                        Row {
                            spacing: 8
                            Pill { label: "Auto-arrange left → right"; onGo: root.autoArrange() }
                            Pill { label: "Reset displays"; onGo: { HyprMon.resetDisplays(); root.flashApplied("Saved profile re-applied") } }
                        }
                        Text { width: parent.width; visible: !HyprMon.profiles[HyprMon.currentKey()]; text: "No saved profile for this display set yet — change any setting (or drag a display) to create one."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    }
                    SectionTitle { visible: HyprMon.monitors.length > 0; text: "MONITORS" }
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
                                width: parent.width; height: 24
                                Row {
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: monCard.modelData.name; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold }
                                    Text { anchors.verticalCenter: parent.verticalCenter; visible: root.isLaptop(monCard.modelData); text: "built-in"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }
                                    Text { anchors.verticalCenter: parent.verticalCenter; visible: monCard.modelData.primary; text: Theme.icStar + " primary"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: 10; font.weight: Font.DemiBold }
                                }
                                Row {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: monCard.modelData.desc; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10; elide: Text.ElideRight; width: Math.min(implicitWidth, 190) }
                                    Toggle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        on: !monCard.modelData.disabled
                                        onToggled: {
                                            if (!monCard.modelData.disabled && monCard.enabledCount <= 1) { root.errorMsg = "At least one display must stay enabled."; return }
                                            root.riskyChange(monCard.modelData.name, { disabled: !monCard.modelData.disabled })
                                        }
                                    }
                                }
                            }
                            Column {
                                width: parent.width; spacing: 2; visible: !monCard.modelData.disabled
                                DropRow {
                                    label: "Resolution"; ddId: "res-" + monCard.modelData.name; options: monCard.resOpts; value: monCard.curRes
                                    onPicked: function (v) { var hzs = monCard.mm.byRes[v] || []; if (hzs.length) root.riskyChange(monCard.modelData.name, { mode: hzs[0].mode }) }
                                }
                                DropRow {
                                    label: "Refresh rate"; ddId: "hz-" + monCard.modelData.name; options: monCard.hzOpts; value: monCard.modelData.mode; buttonWidth: 110
                                    onPicked: function (v) { root.riskyChange(monCard.modelData.name, { mode: v }) }
                                }
                                Item {
                                    width: parent.width; height: 30
                                    Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Scale"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                    Row {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                                        Repeater {
                                            model: [1, 1.25, 1.5, 1.75, 2]
                                            delegate: Rectangle {
                                                required property var modelData
                                                readonly property bool sel: Math.abs(monCard.modelData.scale - modelData) < 0.001
                                                width: 37; height: 24; radius: 6
                                                color: sel ? Theme.accent : (spMa.containsMouse ? Theme.hover : Theme.panel)
                                                border.color: sel ? Theme.accent : Theme.stroke; border.width: 1
                                                Text { anchors.centerIn: parent; text: modelData === 1 || modelData === 2 ? modelData + "×" : String(modelData); color: sel ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: 10; font.weight: Font.DemiBold }
                                                MouseArea { id: spMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (!sel) root.riskyChange(monCard.modelData.name, { scale: modelData }) }
                                            }
                                        }
                                        Rectangle {
                                            width: 52; height: 24; radius: 6; color: Theme.panel
                                            border.color: scIn.activeFocus ? Theme.accent : Theme.stroke; border.width: 1
                                            TextInput {
                                                id: scIn
                                                anchors.fill: parent; horizontalAlignment: TextInput.AlignHCenter; verticalAlignment: TextInput.AlignVCenter
                                                color: Theme.fg; font.family: Theme.fontMono; font.pixelSize: 11
                                                text: Number(monCard.modelData.scale).toFixed(2)
                                                onAccepted: { var v = parseFloat(text); if (!isNaN(v) && v >= 0.5 && v <= 3) root.riskyChange(monCard.modelData.name, { scale: Math.round(v * 100) / 100 }) }
                                            }
                                        }
                                    }
                                }
                                Item {
                                    id: effRow
                                    width: parent.width; height: 16
                                    readonly property var wh: HyprMon.modeRes(monCard.modelData.mode).split("x")
                                    readonly property bool frac: (wh[0] / monCard.modelData.scale) % 1 !== 0 || (wh[1] / monCard.modelData.scale) % 1 !== 0
                                    Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "Logical size: " + root.specW(monCard.modelData) + " × " + root.specH(monCard.modelData) + (effRow.frac ? "  ·  fractional — Hyprland rounds to whole pixels" : ""); color: effRow.frac ? Theme.warning : Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }
                                }
                                DropRow {
                                    label: "Rotation"; ddId: "rot-" + monCard.modelData.name; buttonWidth: 110
                                    options: [{ label: "Normal", value: 0 }, { label: "90°", value: 1 }, { label: "180°", value: 2 }, { label: "270°", value: 3 }]
                                    value: monCard.modelData.transform
                                    onPicked: function (v) { root.riskyChange(monCard.modelData.name, { transform: Number(v) }) }
                                }
                                DropRow {
                                    visible: root.dispSpecs.length > 1
                                    label: "Mirror"; ddId: "mir-" + monCard.modelData.name; buttonWidth: 110
                                    options: monCard.mirrorOpts; value: monCard.modelData.mirror
                                    onPicked: function (v) { root.riskyChange(monCard.modelData.name, { mirror: v }) }
                                }
                                ToggleRow { title: "Variable refresh rate (VRR)"; on: monCard.modelData.vrr; onToggled: root.directChange(monCard.modelData.name, { vrr: !monCard.modelData.vrr }) }
                                ToggleRow { title: "10-bit colour"; on: monCard.modelData.bitdepth === 10; onToggled: root.directChange(monCard.modelData.name, { bitdepth: monCard.modelData.bitdepth === 10 ? 8 : 10 }) }
                                KV { k: "Position"; v: monCard.modelData.x + ", " + monCard.modelData.y + "  ·  drag in Arrangement to move" }
                                KV { visible: !monCard.modelData.primary; k: "Primary display"; action: true; actionLabel: "Make primary"; onAct: root.setPrimary(monCard.modelData.name) }
                            }
                            Text { visible: monCard.modelData.disabled; width: parent.width; text: "Display is disabled — flip the toggle to re-enable it."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11 }
                        }
                    }
                    Text { width: parent.width; text: "Changes apply live (with a 10-second revert safety net) and persist per display-set profile: docking or undocking restores the matching profile automatically, including at boot."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    Text { width: parent.width; text: "Screen goes black when (un)plugging the charger? The saved profile is re-asserted automatically a moment later. If the built-in panel still blanks, that's the xe graphics driver's panel self-refresh (kernel-side, not fixable from the shell) — use “Reset displays” to recover, or boot with xe.enable_psr=0."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    Item { width: 1; height: 8 }
                }
            }

            // ════════ PANE 2 — Networking ════════
            Component {
                id: cNetwork
                Column {
                    spacing: 14
                    // Wired / Ethernet
                    SectionTitle { text: "WIRED" }
                    Card {
                        Text { width: parent.width; visible: root.wiredList.length === 0; text: "No wired connection."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                        Repeater {
                            model: root.wiredList
                            delegate: Item {
                                required property var modelData
                                width: parent.width; height: 30
                                Text { anchors.left: parent.left; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: Theme.icEthernet; font.family: Theme.fontIcons; font.pixelSize: 13; color: modelData.state === "activated" ? Theme.accent : Theme.fgDim }
                                Text { anchors.left: parent.left; anchors.leftMargin: 28; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: modelData.name + "  ·  " + modelData.dev + (modelData.state === "activated" ? "  ·  connected" : ""); color: modelData.state === "activated" ? Theme.accent : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: modelData.state === "activated" ? Font.DemiBold : Font.Normal; elide: Text.ElideRight }
                            }
                        }
                    }
                    // Wi-Fi
                    Item {
                        width: parent.width; height: 30
                        SectionTitle { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "WI-FI" }
                        Toggle { visible: root.hasWifi; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; on: root.wifiOn; onToggled: { Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiOn ? "off" : "on"]); wifiRescan.restart() } }
                        Text { visible: !root.hasWifi; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "Not available"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                    }
                    Card {
                        visible: !root.hasWifi
                        Text { width: parent.width; text: Theme.icWifiOff + "  No Wi-Fi adapter detected — this machine has no wireless device (common in VMs). Use the wired connection above, or plug in a USB Wi-Fi dongle."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap }
                    }
                    Card {
                        visible: root.hasWifi && root.wifiOn
                        Repeater {
                            model: root.wifiList.slice(0, 8)
                            delegate: Column {
                                required property var modelData
                                width: parent.width
                                Item {
                                    width: parent.width; height: 30
                                    Rectangle { anchors.fill: parent; radius: 7; color: wMa.containsMouse ? Theme.hover : "transparent" }
                                    Text { anchors.left: parent.left; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: modelData.signal >= 66 ? Theme.icWifi : (modelData.signal >= 33 ? Theme.icWifiMed : Theme.icWifiLow); font.family: Theme.fontIcons; font.pixelSize: 13; color: modelData.active ? Theme.accent : Theme.fgDim }
                                    Text { anchors.left: parent.left; anchors.leftMargin: 28; anchors.right: parent.right; anchors.rightMargin: 22; anchors.verticalCenter: parent.verticalCenter; text: modelData.ssid; color: modelData.active ? Theme.accent : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: modelData.active ? Font.DemiBold : Font.Normal; elide: Text.ElideRight }
                                    Text { anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; visible: modelData.sec !== ""; text: Theme.icLock; font.family: Theme.fontIcons; font.pixelSize: 10; color: Theme.fgDim }
                                    MouseArea { id: wMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.connectWifi(modelData.ssid, modelData.sec) }
                                }
                                Item {
                                    width: parent.width; height: visible ? 34 : 0; visible: root.pwTarget === modelData.ssid
                                    Rectangle { anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 4; radius: 7; color: Theme.panel; border.color: Theme.accent; border.width: 1
                                        TextInput { id: pwIn; anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 52; verticalAlignment: TextInput.AlignVCenter; echoMode: TextInput.Password; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                            onTextChanged: root.pwText = text; Component.onCompleted: forceActiveFocus(); onAccepted: root.connectWifi(modelData.ssid, modelData.sec)
                                            Text { anchors.verticalCenter: parent.verticalCenter; visible: pwIn.text.length === 0; text: "Password"; color: Theme.fgDim; font: pwIn.font } }
                                        Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "Join"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.connectWifi(modelData.ssid, modelData.sec) } } }
                                }
                            }
                        }
                    }
                    // VPN
                    Item {
                        width: parent.width; height: 20
                        SectionTitle { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "VPN" }
                        Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "+ Add VPN"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["nm-connection-editor"]) } }
                    }
                    Card {
                        Text { width: parent.width; visible: root.vpnList.length === 0; text: "No VPN connections configured."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                        Repeater {
                            model: root.vpnList
                            delegate: Item {
                                required property var modelData
                                width: parent.width; height: 30
                                Rectangle { anchors.fill: parent; radius: 7; color: vMa.containsMouse ? Theme.hover : "transparent" }
                                Text { anchors.left: parent.left; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: Theme.icVpn; font.family: Theme.fontIcons; font.pixelSize: 12; color: modelData.active ? Theme.accent : Theme.fgDim }
                                Text { anchors.left: parent.left; anchors.leftMargin: 26; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: modelData.name + (modelData.active ? "  ·  connected" : ""); color: modelData.active ? Theme.accent : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: modelData.active ? Font.DemiBold : Font.Normal; elide: Text.ElideRight }
                                MouseArea { id: vMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Quickshell.execDetached(["nmcli", "connection", modelData.active ? "down" : "up", modelData.name]); vpnRescan.restart() } }
                            }
                        }
                    }
                    // SSH
                    Item {
                        width: parent.width; height: 20
                        SectionTitle { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "SSH HOSTS" }
                        Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "Edit config"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["kitty", "-e", "sh", "-c", "${EDITOR:-fresh} ~/.ssh/config"]) } }
                    }
                    Card {
                        Text { width: parent.width; visible: root.sshHosts.length === 0; text: "No hosts in ~/.ssh/config. Add one with “Edit config”."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap }
                        Repeater {
                            model: root.sshHosts
                            delegate: Item {
                                required property var modelData
                                width: parent.width; height: 30
                                Rectangle { anchors.fill: parent; radius: 7; color: sMa.containsMouse ? Theme.hover : "transparent" }
                                Text { anchors.left: parent.left; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: Theme.icLock; font.family: Theme.fontIcons; font.pixelSize: 12; color: Theme.fgDim }
                                Text { anchors.left: parent.left; anchors.leftMargin: 26; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                Text { anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; visible: sMa.containsMouse; text: "connect →"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: 11 }
                                MouseArea { id: sMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["kitty", "-e", "ssh", modelData]) }
                            }
                        }
                    }
                    // Status
                    SectionTitle { text: "STATUS" }
                    Card {
                        Repeater {
                            model: root.netActive
                            delegate: KV { required property var modelData; k: modelData.name + " (" + modelData.type + ")"; v: modelData.dev + " · " + modelData.state; dot: modelData.state === "activated" ? "ok" : "info" }
                        }
                        Repeater { model: root.ipList; delegate: KV { required property var modelData; k: "IP"; v: modelData } }
                    }
                    Item { width: 1; height: 8 }
                }
            }

            // ════════ PANE 3 — Default Apps ════════
            Component {
                id: cDefaults
                Column {
                    id: defCol
                    spacing: 10
                    property string openCat: ""
                    Repeater {
                        model: root.appCats
                        delegate: Card {
                            id: appCard
                            required property var modelData
                            readonly property string curId: root.defaults[modelData.key] || ""
                            readonly property var choices: root.appChoices[modelData.key] || []
                            Item {
                                width: parent.width; height: 30
                                Row {
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                    Text { anchors.verticalCenter: parent.verticalCenter; width: 18; text: root.g(appCard.modelData.ic); font.family: Theme.fontIcons; font.pixelSize: 15; color: Theme.fgDim }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: appCard.modelData.key; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                }
                                Rectangle {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    width: 210; height: 26; radius: 7; color: cMa.containsMouse ? Theme.hover : Theme.panel; border.color: Theme.stroke; border.width: 1
                                    Text { anchors.left: parent.left; anchors.leftMargin: 9; anchors.right: chev.left; anchors.verticalCenter: parent.verticalCenter; text: root.appNameForId(appCard.curId); color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; elide: Text.ElideRight }
                                    Text { id: chev; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: Theme.icChevronDown; font.family: Theme.fontIcons; font.pixelSize: 9; color: Theme.fgDim }
                                    MouseArea { id: cMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: defCol.openCat = (defCol.openCat === appCard.modelData.key ? "" : appCard.modelData.key) }
                                }
                            }
                            Column {
                                width: parent.width; visible: defCol.openCat === appCard.modelData.key; spacing: 1
                                Text { width: parent.width; visible: appCard.choices.length === 0; text: "No installed app handles this type."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11 }
                                Repeater {
                                    model: appCard.choices
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property var entry: root.entryForId(modelData)
                                        readonly property bool isCur: String(appCard.curId).replace(/\.desktop$/, "") === String(modelData).replace(/\.desktop$/, "")
                                        width: parent.width; height: 32; radius: 6; color: eMa.containsMouse ? Theme.hover : "transparent"
                                        Row {
                                            anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 9
                                            Image { anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; sourceSize.width: 36; sourceSize.height: 36; mipmap: true; source: parent.parent.entry && parent.parent.entry.icon ? Quickshell.iconPath(parent.parent.entry.icon, "application-x-executable") : Quickshell.iconPath("application-x-executable") }
                                            Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.entry ? (parent.parent.entry.name || modelData) : modelData; color: parent.parent.isCur ? Theme.accent : Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; font.weight: parent.parent.isCur ? Font.DemiBold : Font.Normal }
                                        }
                                        Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; visible: parent.isCur; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: 11; color: Theme.accent }
                                        MouseArea { id: eMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.setDefaultApp(appCard.modelData.key, modelData); defCol.openCat = "" } }
                                    }
                                }
                            }
                        }
                    }
                    Item { width: 1; height: 8 }
                }
            }

            // ════════ PANE 4 — Keyboard & Mouse ════════
            Component {
                id: cKeyboard
                Column {
                    id: kbPane
                    spacing: 14
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

                    Card {
                        visible: !root.inpLoaded
                        Text { width: parent.width; text: "Reading input configuration…"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                    }

                    SectionTitle { visible: root.inpLoaded; text: "KEYBOARD LAYOUTS  ·  drag to reorder — first is the default" }
                    Card {
                        visible: root.inpLoaded
                        Item {
                            // when a variant popup is open its ~150px list must not be
                            // occluded by the later search-box sibling — grow to fit
                            width: parent.width
                            height: {
                                var h = root.kbActive.length * 38
                                if (Globals.openDd.indexOf("kbvar-") === 0) {
                                    var idx = parseInt(Globals.openDd.slice(6)) || 0
                                    h = Math.max(h, idx * 38 + 30 + 155)
                                }
                                return h
                            }
                            Repeater {
                                model: root.kbActive
                                delegate: Item {
                                    id: kbRow
                                    required property var modelData
                                    required property int index
                                    width: parent.width; height: 38
                                    y: index * 38
                                    z: rowDrag.drag.active || Globals.openDd === ("kbvar-" + index) ? 10 : 1
                                    Rectangle {
                                        anchors.fill: parent; anchors.bottomMargin: 6; radius: 7
                                        color: rowDrag.drag.active ? Theme.hover : Theme.panel
                                        border.color: Theme.stroke; border.width: 1
                                        Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: Theme.icKeyboard; font.family: Theme.fontIcons; font.pixelSize: 13; color: Theme.fgDim }
                                        Text {
                                            anchors.left: parent.left; anchors.leftMargin: 32; anchors.right: kbRowRight.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                            text: kbPane.nameOf(kbRow.modelData.code) + "  (" + kbRow.modelData.code + ")" + (kbRow.index === 0 ? "  ·  default" : "")
                                            color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: kbRow.index === 0 ? Font.DemiBold : Font.Normal; elide: Text.ElideRight
                                        }
                                        Row {
                                            id: kbRowRight
                                            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                            Rectangle {
                                                visible: kbPane.variantOpts(kbRow.modelData.code).length > 1
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 118; height: 22; radius: 6
                                                color: kvMa.containsMouse ? Theme.hover : Theme.elevated
                                                border.color: Globals.openDd === ("kbvar-" + kbRow.index) ? Theme.accent : Theme.stroke; border.width: 1
                                                Text { anchors.left: parent.left; anchors.leftMargin: 7; anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter; text: kbRow.modelData.variant === "" ? "Default" : kbRow.modelData.variant; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 10; elide: Text.ElideRight }
                                                Text { anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; text: Theme.icChevronDown; font.family: Theme.fontIcons; font.pixelSize: 8; color: Theme.fgDim }
                                                MouseArea { id: kvMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Globals.openDd = Globals.openDd === ("kbvar-" + kbRow.index) ? "" : ("kbvar-" + kbRow.index) }
                                            }
                                            Text {
                                                visible: root.kbActive.length > 1
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Theme.icClose; font.family: Theme.fontIcons; font.pixelSize: 12; color: kxMa.containsMouse ? Theme.danger : Theme.fgDim
                                                MouseArea { id: kxMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.kbRemove(kbRow.index) }
                                            }
                                        }
                                    }
                                    // variant popup — overlays the rows below (z-stacked)
                                    Rectangle {
                                        visible: Globals.openDd === ("kbvar-" + kbRow.index)
                                        x: parent.width - 158; y: 30; width: 148; z: 30
                                        height: Math.min(kvCol.implicitHeight + 10, 150)
                                        radius: 7; color: Theme.bg; border.color: Theme.stroke; border.width: 1
                                        Flickable {
                                            anchors.fill: parent; anchors.margins: 5; contentHeight: kvCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                                            Column {
                                                id: kvCol; width: parent.width
                                                Repeater {
                                                    model: kbPane.variantOpts(kbRow.modelData.code)
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        readonly property bool sel: modelData.value === kbRow.modelData.variant
                                                        width: parent.width; height: 24; radius: 5; color: kvoMa.containsMouse ? Theme.hover : "transparent"
                                                        Text { anchors.left: parent.left; anchors.leftMargin: 7; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: sel ? Theme.accent : Theme.fg; font.family: Theme.fontText; font.pixelSize: 10; font.weight: sel ? Font.DemiBold : Font.Normal }
                                                        MouseArea { id: kvoMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Globals.openDd = ""; root.kbSetVariant(kbRow.index, modelData.value) } }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    MouseArea {
                                        id: rowDrag
                                        anchors.left: parent.left; width: 30; height: parent.height - 6
                                        drag.target: kbRow; drag.axis: Drag.YAxis
                                        drag.minimumY: 0; drag.maximumY: Math.max(0, (root.kbActive.length - 1) * 38)
                                        cursorShape: Qt.SizeVerCursor
                                        onReleased: {
                                            var to = Math.round(kbRow.y / 38)
                                            if (to !== kbRow.index) root.kbMove(kbRow.index, to)
                                            else kbRow.y = Qt.binding(function () { return kbRow.index * 38 })
                                        }
                                    }
                                }
                            }
                        }
                        // add a layout: searchable select
                        Rectangle {
                            width: parent.width; height: 34; radius: Theme.radiusInner
                            color: Theme.bg; border.color: kbSearch.activeFocus ? Theme.accent : Theme.stroke; border.width: 1
                            Text { anchors.left: parent.left; anchors.leftMargin: 11; anchors.verticalCenter: parent.verticalCenter; text: Theme.icSearch; font.family: Theme.fontIcons; font.pixelSize: 13; color: Theme.fgDim }
                            TextInput {
                                id: kbSearch
                                anchors.fill: parent; anchors.leftMargin: 34; anchors.rightMargin: 12; verticalAlignment: TextInput.AlignVCenter; clip: true
                                color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                onTextChanged: kbPane.kbQuery = text
                                onAccepted: { var f = kbPane.filtered(); if (f.length) { root.kbAdd(f[0].c); text = "" } }
                                Text { anchors.verticalCenter: parent.verticalCenter; visible: kbSearch.text.length === 0; text: "Add a layout — search by name or code…"; color: Theme.fgDim; font: kbSearch.font }
                            }
                        }
                        Rectangle {
                            visible: kbSearch.activeFocus || kbPane.kbQuery !== ""
                            width: parent.width; height: Math.min(addCol.implicitHeight + 10, 168)
                            radius: 7; color: Theme.bg; border.color: Theme.stroke; border.width: 1
                            Flickable {
                                anchors.fill: parent; anchors.margins: 5; contentHeight: addCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                                Column {
                                    id: addCol; width: parent.width
                                    Text { visible: kbPane.filtered().length === 0; text: "No matching layout."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; leftPadding: 8; topPadding: 4 }
                                    Repeater {
                                        model: kbPane.filtered()
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: parent.width; height: 26; radius: 6; color: kaMa.containsMouse ? Theme.hover : "transparent"
                                            Text { anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: modelData.n + "  (" + modelData.c + ")"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 11 }
                                            Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; visible: kaMa.containsMouse; text: "+ add"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: 10; font.weight: Font.DemiBold }
                                            // onPressed (not clicked): fire before the search field loses focus
                                            MouseArea { id: kaMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onPressed: { root.kbAdd(modelData.c); kbSearch.text = "" } }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    SectionTitle { visible: root.inpLoaded; text: "LAYOUT SWITCHING" }
                    Card {
                        visible: root.inpLoaded
                        DropRow {
                            label: "Extra switch shortcut"; ddId: "kb-grp"; buttonWidth: 210
                            options: root.grpOptions; value: root.kbOptToken("grp:")
                            onPicked: function (v) { root.setKbOptPrefix("grp:", v) }
                        }
                        ToggleRow {
                            title: "Remember layout per window"
                            sub: "GNOME-style: each window keeps its own layout (kb-per-window daemon)."
                            on: root.perWindowKb
                            onToggled: root.setPerWindowKb(!root.perWindowKb)
                        }
                    }

                    SectionTitle { visible: root.inpLoaded; text: "TYPING" }
                    Card {
                        visible: root.inpLoaded
                        Slider { label: "Key repeat rate (per second)"; value: root.inp.repeat_rate; from: 5; to: 80; onMoved: function (v) { root.applyInput({ repeat_rate: Math.round(v) }) } }
                        Slider { label: "Repeat delay (ms)"; value: root.inp.repeat_delay; from: 150; to: 1000; step: 10; onMoved: function (v) { root.applyInput({ repeat_delay: Math.round(v) }) } }
                        Item {
                            width: parent.width; height: 24
                            Row {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                Text { anchors.verticalCenter: parent.verticalCenter; text: (kbPane.advOpen ? Theme.icChevronUp : Theme.icChevronDown); font.family: Theme.fontIcons; font.pixelSize: 10; color: Theme.fgDim }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: "Advanced"; color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: kbPane.advOpen = !kbPane.advOpen }
                        }
                        Column {
                            width: parent.width; spacing: 2; visible: kbPane.advOpen
                            ToggleRow { title: "Num Lock on by default"; on: root.inp.numlock_by_default === true; onToggled: root.applyInput({ numlock_by_default: !(root.inp.numlock_by_default === true) }) }
                            ToggleRow { title: "Caps Lock acts as Ctrl"; on: root.hasKbOpt("ctrl:nocaps"); onToggled: root.toggleKbOpt("ctrl:nocaps") }
                            ToggleRow { title: "Caps Lock acts as Escape"; on: root.hasKbOpt("caps:escape"); onToggled: root.toggleKbOpt("caps:escape") }
                            ToggleRow { title: "Right Alt is Compose"; on: root.hasKbOpt("compose:ralt"); onToggled: root.toggleKbOpt("compose:ralt") }
                        }
                    }

                    SectionTitle { visible: root.inpLoaded; text: "MOUSE" }
                    Card {
                        visible: root.inpLoaded
                        DropRow {
                            visible: root.mice.filter(function (n) { return !root.isTouchpadName(n) }).length > 1
                            label: "Device"; ddId: "mouse-dev"; buttonWidth: 250
                            options: { var o = [{ label: "All pointing devices", value: "" }]; var ms = root.mice; for (var i = 0; i < ms.length; i++) if (!root.isTouchpadName(ms[i])) o.push({ label: ms[i], value: ms[i] }); return o }
                            value: root.devTarget
                            onPicked: function (v) { root.devTarget = v }
                        }
                        Text { visible: root.devTarget !== ""; width: parent.width; text: "Overriding this device only — everything else keeps the global values."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10; wrapMode: Text.Wrap }
                        Slider { label: "Pointer speed"; value: kbPane.effSens; from: -1; to: 1; step: 0.05; decimals: 2; onMoved: function (v) { kbPane.setMouse({ sensitivity: Math.round(v * 100) / 100 }) } }
                        Item {
                            width: parent.width; height: 30
                            Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Acceleration profile"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                            Row {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                                Repeater {
                                    model: [{ n: "Adaptive", v: "adaptive" }, { n: "Flat", v: "flat" }]
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool sel: kbPane.effAccel === modelData.v || (kbPane.effAccel === "" && modelData.v === "adaptive")
                                        width: 76; height: 24; radius: 6
                                        color: sel ? Theme.accent : (apMa.containsMouse ? Theme.hover : Theme.panel)
                                        border.color: sel ? Theme.accent : Theme.stroke; border.width: 1
                                        Text { anchors.centerIn: parent; text: modelData.n; color: sel ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: 10; font.weight: Font.DemiBold }
                                        MouseArea { id: apMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: kbPane.setMouse({ accel_profile: modelData.v }) }
                                    }
                                }
                            }
                        }
                        ToggleRow { title: "Natural scrolling"; on: kbPane.effNat; onToggled: kbPane.setMouse({ natural_scroll: !kbPane.effNat }) }
                        ToggleRow { title: "Left-handed buttons"; on: kbPane.effLeft; onToggled: kbPane.setMouse({ left_handed: !kbPane.effLeft }) }
                        Slider { label: "Scroll speed"; value: Number(root.inp.scroll_factor); from: 0.1; to: 3; step: 0.1; decimals: 1; onMoved: function (v) { root.applyInput({ scroll_factor: Math.round(v * 10) / 10 }) } }
                    }

                    SectionTitle { visible: root.inpLoaded; text: "TOUCHPAD" }
                    Card {
                        visible: root.inpLoaded && !root.hasTouchpad
                        Text { width: parent.width; text: "No touchpad detected."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                    }
                    Card {
                        visible: root.inpLoaded && root.hasTouchpad
                        ToggleRow { title: "Tap to click"; on: root.inp.tp_tap === true; onToggled: root.applyInput({ tp_tap: !(root.inp.tp_tap === true) }) }
                        ToggleRow { title: "Natural scrolling"; on: root.inp.tp_natural_scroll === true; onToggled: root.applyInput({ tp_natural_scroll: !(root.inp.tp_natural_scroll === true) }) }
                        ToggleRow { title: "Disable while typing"; on: root.inp.tp_dwt === true; onToggled: root.applyInput({ tp_dwt: !(root.inp.tp_dwt === true) }) }
                        ToggleRow { title: "Clickfinger behaviour"; sub: "Two-finger press = right-click, three-finger = middle-click (instead of corner zones)."; on: root.inp.tp_clickfinger === true; onToggled: root.applyInput({ tp_clickfinger: !(root.inp.tp_clickfinger === true) }) }
                        ToggleRow { title: "Tap and drag"; on: root.inp.tp_tap_drag === true; onToggled: root.applyInput({ tp_tap_drag: !(root.inp.tp_tap_drag === true) }) }
                        ToggleRow { title: "Drag lock"; sub: "Keep dragging briefly after lifting the finger."; on: root.inp.tp_drag_lock === true; onToggled: root.applyInput({ tp_drag_lock: !(root.inp.tp_drag_lock === true) }) }
                        ToggleRow { title: "Middle-click emulation"; sub: "Left+right button together = middle click."; on: root.inp.tp_mbe === true; onToggled: root.applyInput({ tp_mbe: !(root.inp.tp_mbe === true) }) }
                        Slider { label: "Scroll speed"; value: Number(root.inp.tp_scroll_factor); from: 0.1; to: 3; step: 0.1; decimals: 1; onMoved: function (v) { root.applyInput({ tp_scroll_factor: Math.round(v * 10) / 10 }) } }
                    }
                    Text { width: parent.width; text: "Everything here applies live and persists to generated/input.lua. Two-finger vs edge scrolling follows the hardware default (libinput); Hyprland doesn't expose it."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    Item { width: 1; height: 8 }
                }
            }

            // ════════ PANE 5 — Shortcuts ════════
            Component {
                id: cShortcuts
                Column {
                    spacing: 6
                    Repeater {
                        model: root.shortcutsModel()
                        delegate: Item {
                            required property var modelData
                            width: parent.width
                            height: modelData.h ? 30 : 24
                            SectionTitle { visible: modelData.h; anchors.left: parent.left; anchors.bottom: parent.bottom; text: modelData.a; font.pixelSize: Theme.fsBody; color: Theme.fg }
                            Text { visible: !modelData.h; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: 180; text: modelData.a; color: Theme.accent; font.family: Theme.fontMono; font.pixelSize: 11 }
                            Text { visible: !modelData.h; anchors.left: parent.left; anchors.leftMargin: 190; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: modelData.b; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; elide: Text.ElideRight }
                        }
                    }
                    Item { width: 1; height: 8 }
                }
            }

            // ════════ PANE 6 — Layout (gaps & border) ════════
            Component {
                id: cLayout
                Column {
                    spacing: 14
                    SectionTitle { text: "WINDOW GAPS, BORDER & CORNERS  ·  applied live, persisted to generated/user.lua" }
                    Card {
                        Slider { label: "Inner gap"; value: root.gapsIn; from: 0; to: 30
                            onMoved: function (v) { root.gapsIn = Math.round(v); root.applyGaps() } }
                        Slider { label: "Outer gap"; value: root.gapsOut; from: 0; to: 60
                            onMoved: function (v) { root.gapsOut = Math.round(v); root.applyGaps() } }
                        Slider { label: "Border width"; value: root.borderSize; from: 0; to: 6
                            onMoved: function (v) { root.borderSize = Math.round(v); root.applyGaps() } }
                        Slider { label: "Corner radius"; value: root.rounding; from: 0; to: 24
                            onMoved: function (v) { root.rounding = Math.round(v); root.applyGaps() } }
                    }
                    Pill { label: "Reset to defaults"; onGo: { root.gapsIn = 6; root.gapsOut = 14; root.borderSize = 1; root.rounding = 12; root.applyGaps() } }
                    Text { width: parent.width; text: "Sliders preview while dragging and apply on release — live via hyprctl, persisted to generated/user.lua so they survive reloads and relogin."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    Item { width: 1; height: 8 }
                }
            }

            // ════════ PANE 7 — Theme & Accent ════════
            Component {
                id: cTheme
                Column {
                    spacing: 14
                    SectionTitle { text: "SHELL STYLE" }
                    Card {
                        Row {
                            width: parent.width; spacing: 8
                            Repeater {
                                model: [{ n: "Flock", m: "flock" }, { n: "Black Sheep", m: "blacksheep" }]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: Globals.themeName === modelData.m
                                    width: (parent.width - 8) / 2; height: 38; radius: Theme.radiusInner
                                    color: sel ? Theme.accent : Theme.panel
                                    border.color: sel ? Theme.accent : Theme.stroke; border.width: 1
                                    Text { anchors.centerIn: parent; text: modelData.n; color: parent.sel ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { Globals.themeName = modelData.m; root.writePrefs() } }
                                }
                            }
                        }
                        Text {
                            width: parent.width; wrapMode: Text.Wrap
                            text: "Flock — the ewe look in soft dark greys. Black Sheep — the same look on absolute black (#020202) surfaces: bar, dock, panels. Shape, icons and your accent stay identical; applies instantly."
                            color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11
                        }
                    }
                    // (Light mode is parked until it is actually fully light —
                    // the DE is dark-only for now, so no Light/Dark toggle.)
                    SectionTitle { text: "ACCENT COLOUR" }
                    Card {
                        Flow {
                            width: parent.width; spacing: 10
                            Repeater {
                                model: root.accents
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 46; height: 46; radius: 23; color: modelData.hex
                                    readonly property bool sel: root.hex6(Globals.accentColor).toLowerCase() === root.hex6(modelData.hex).toLowerCase()
                                    border.color: sel ? Theme.fg : Qt.rgba(1, 1, 1, 0.15); border.width: sel ? 3 : 1
                                    // accentText, not white: a white check vanishes on yellow/light swatches
                                    Text { anchors.centerIn: parent; visible: parent.sel; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: 18; color: Theme.accentText }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setAccent(modelData.hex) }
                                }
                            }
                        }
                        Item {
                            width: parent.width; height: 30
                            Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Custom hex"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                            Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 130; height: 26; radius: 7; color: Theme.panel; border.color: hexIn.activeFocus ? Theme.accent : Theme.stroke; border.width: 1
                                TextInput { id: hexIn; anchors.fill: parent; anchors.leftMargin: 9; anchors.rightMargin: 9; verticalAlignment: TextInput.AlignVCenter; color: Theme.fg; font.family: Theme.fontMono; font.pixelSize: 12; text: String(Globals.accentColor)
                                    onAccepted: { var t = text.trim(); if (/^#?[0-9a-fA-F]{6}$/.test(t)) root.setAccent(t[0] === "#" ? t : "#" + t) } } }
                        }
                    }
                    SectionTitle { text: "WINDOW BORDERS" }
                    Card {
                        ToggleRow {
                            title: "Tint window borders with accent"
                            sub: "Replaces the default border colour with your accent."
                            on: Globals.tintBorders
                            onToggled: { Globals.tintBorders = !Globals.tintBorders; root.applyBorder(); root.setAccent(String(Globals.accentColor)) }
                        }
                    }
                    SectionTitle { text: "WINDOW TRANSPARENCY" }
                    Card {
                        ToggleRow {
                            title: "Transparent unfocused windows"
                            sub: "Slight see-through on windows without focus. Off = every window fully opaque."
                            on: Globals.windowTransparency
                            onToggled: root.setTransparency(!Globals.windowTransparency)
                        }
                    }
                    SectionTitle { text: "ANIMATIONS" }
                    Card {
                        Row {
                            width: parent.width; spacing: 8
                            Repeater {
                                // m divides the base durations (shell base = 300 ms):
                                // Off 0 · Fast 150 ms · Normal 300 ms · Slow 500 ms —
                                // steps far enough apart to actually feel different
                                model: [{ n: "Off", m: 0 }, { n: "Fast", m: 2 }, { n: "Normal", m: 1 }, { n: "Slow", m: 0.6 }]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: Math.abs(Globals.animationSpeed - modelData.m) < 0.001
                                    width: (parent.width - 24) / 4; height: 32; radius: Theme.radiusInner
                                    color: sel ? Theme.accent : Theme.panel
                                    border.color: sel ? Theme.accent : Theme.stroke; border.width: 1
                                    Text { anchors.centerIn: parent; text: modelData.n; color: parent.sel ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setAnim(modelData.m) }
                                }
                            }
                        }
                    }
                    Text { width: parent.width; text: "Animation speed drives window + shell motion (shell: Fast 150 ms · Normal 300 ms · Slow 500 ms; window animations scale along); applies live and persists to user-theme.json + generated/user.lua."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    Text { width: parent.width; text: "Accent recolours the whole shell instantly and persists in user-theme.json."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    Item { width: 1; height: 8 }
                }
            }

            // ════════ PANE 8 — Wallpaper ════════
            Component {
                id: cWallpaper
                Column {
                    spacing: 14
                    Card {
                        visible: root.wpBackendLabel === "none"
                        Text { width: parent.width; text: "No wallpaper backend found. Install swww (packaged as “awww”) for images and animated GIFs, mpvpaper for video wallpapers — or swaybg for static images only."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap }
                    }
                    SectionTitle { visible: root.wpBackendLabel !== "none"; text: "WALLPAPER  ·  backend: " + root.wpBackendLabel }
                    Card {
                        visible: root.wpBackendLabel !== "none"
                        Item {
                            width: parent.width; height: 30
                            Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Apply to"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                            Row {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                                Repeater {
                                    model: { var o = [{ label: "All displays", value: "*" }], ss = root.dispSpecs; for (var i = 0; i < ss.length; i++) if (!ss[i].disabled) o.push({ label: ss[i].name, value: ss[i].name }); return o }
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool sel: root.wpTarget === modelData.value
                                        width: wptLbl.implicitWidth + 18; height: 24; radius: 6
                                        color: sel ? Theme.accent : (wptMa.containsMouse ? Theme.hover : Theme.panel)
                                        border.color: sel ? Theme.accent : Theme.stroke; border.width: 1
                                        Text { id: wptLbl; anchors.centerIn: parent; text: modelData.label; color: sel ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: 10; font.weight: Font.DemiBold }
                                        MouseArea { id: wptMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.wpTarget = modelData.value }
                                    }
                                }
                            }
                        }
                        DropRow {
                            label: "Fit"; ddId: "wp-mode"; buttonWidth: 110
                            options: [{ label: "Fill", value: "fill" }, { label: "Fit", value: "fit" }, { label: "Stretch", value: "stretch" }, { label: "Tile", value: "tile" }, { label: "Centre", value: "center" }]
                            value: root.wpMode
                            onPicked: function (v) { root.wpMode = v; if (Object.keys(root.wpMap).length) { root.wpWrite(); root.flashApplied() } }
                        }
                        ToggleRow {
                            visible: root.wpAnyVideo
                            title: "Mute video wallpaper"; sub: "mpvpaper plays the file's audio track otherwise."
                            on: root.wpMute
                            onToggled: { root.wpMute = !root.wpMute; root.wpWrite(); root.flashApplied() }
                        }
                        Text { width: parent.width; visible: Object.keys(root.wpMap).length === 0; text: "No wallpaper set yet — pick one below."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11 }
                        Repeater {
                            model: Object.keys(root.wpMap).sort()
                            delegate: KV { required property var modelData; k: modelData === "*" ? "All displays" : modelData; v: String(root.wpMap[modelData]).replace(/^.*\//, "") }
                        }
                    }
                    SectionTitle { visible: root.wpBackendLabel !== "none"; text: "CHOOSE  ·  " + root.wpDir }
                    Card {
                        visible: root.wpBackendLabel !== "none"
                        FileDropTarget {
                            id: wpPicker
                            width: parent.width
                            acceptVideo: true
                            label: "Drop an image, GIF or video here — or click to browse"
                            dialogTitle: "Choose wallpaper"
                            onPicked: function (p) { root.wpAssign(p); root.wpList(p.replace(/\/[^/]*$/, "")) }
                            Connections { target: root; function onWallpaperBrowseRequested() { wpPicker.browse() } }
                        }
                        Row {
                            spacing: 8
                            Pill { label: "Browse files…"; onGo: wpPicker.browse() }
                            Pill { label: "Wallpapers folder"; onGo: root.wpList(root.home + "/Pictures/Wallpapers") }
                            Pill { label: "Pictures"; onGo: root.wpList(root.home + "/Pictures") }
                        }
                        Text { width: parent.width; visible: root.wpFiles.length === 0; text: "No images in this folder — use “Browse files…” or drop images into " + root.wpDir + "."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                        Flow {
                            width: parent.width; spacing: 8
                            Repeater {
                                model: root.wpFiles
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool cur: root.wpMap[root.wpTarget] === modelData
                                    readonly property bool isVid: root.wpIsVideo(modelData)
                                    readonly property bool isGif: root.wpIsGif(modelData)
                                    width: 122; height: 76; radius: 7; clip: true
                                    color: Theme.bg
                                    border.color: cur ? Theme.accent : (wtMa.containsMouse ? Theme.fgDim : Theme.stroke); border.width: cur ? 2 : 1
                                    Image { visible: !parent.isVid; anchors.fill: parent; anchors.margins: 1; source: parent.isVid ? "" : "file://" + modelData; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 244; sourceSize.height: 152 }
                                    // videos get a film tile — no thumbnail without a decode pass
                                    Column {
                                        visible: parent.isVid
                                        anchors.centerIn: parent; spacing: 3; width: parent.width - 14
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.g(0xE792); font.family: Theme.fontIcons; font.pixelSize: 20; color: Theme.fgDim }
                                        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: String(modelData).replace(/^.*\//, ""); color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 9; elide: Text.ElideMiddle }
                                    }
                                    Rectangle {
                                        visible: parent.isVid || parent.isGif
                                        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 4
                                        width: badgeT.implicitWidth + 10; height: 16; radius: 5
                                        color: Qt.rgba(0, 0, 0, 0.62)
                                        Text { id: badgeT; anchors.centerIn: parent; text: parent.parent.isVid ? "▶ video" : "GIF"; color: "white"; font.family: Theme.fontText; font.pixelSize: 9; font.weight: Font.DemiBold }
                                    }
                                    Text { anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 4; visible: cur; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: 12; color: Theme.accent; style: Text.Outline; styleColor: "black" }
                                    MouseArea { id: wtMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.wpAssign(modelData) }
                                }
                            }
                        }
                    }
                    Text { width: parent.width; text: "Applied live and restored at every login by wallpaper.sh; when a monitor is plugged in, its wallpaper is re-applied automatically. Static images → " + (root.wpImgBackend || "no backend") + ", GIFs animate via swww, video plays via mpvpaper (always looped)."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    Text { visible: root.wpAnyAnimated; width: parent.width; text: "Animated wallpapers keep the GPU decoding continuously — expect measurable battery drain on the laptop."; color: Theme.warning; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    Item { width: 1; height: 8 }
                }
            }

            // ════════ PANE — Screensaver ════════
            Component {
                id: cSaver
                Column {
                    spacing: 14
                    SectionTitle { text: "SCREENSAVER" }
                    Card {
                        visible: !root.hypridleOk
                        Text { width: parent.width; text: "hypridle is not installed — the screensaver (and idle auto-lock) needs it:  sudo pacman -S hypridle"; color: Theme.warning; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap }
                    }
                    Card {
                        ToggleRow {
                            title: "Enable screensaver"
                            sub: "Covers every display after the idle timeout; any key, click or mouse move dismisses it."
                            on: Globals.saverEnabled
                            onToggled: { Globals.saverEnabled = !Globals.saverEnabled; root.saverChanged() }
                        }
                        DropRow {
                            label: "Idle timeout"; ddId: "sv-timeout"; dim: !Globals.saverEnabled
                            options: [1, 3, 5, 10, 15, 30].map(function (m) { return { label: m + " min", value: m } })
                            value: Globals.saverMin
                            onPicked: function (v) { Globals.saverMin = v; root.saverChanged() }
                        }
                        Slider {
                            label: "Custom timeout (minutes)"; from: 1; to: 60; step: 1; decimals: 0
                            value: Globals.saverMin
                            visible: Globals.saverEnabled
                            onMoved: function (v) { Globals.saverMin = Math.round(v); root.saverChanged() }
                        }
                        DropRow {
                            label: "Style"; ddId: "sv-style"; dim: !Globals.saverEnabled || Globals.saverLock
                            options: [{ label: "Clock", value: "clock" }, { label: "Blank (black)", value: "blank" }]
                            value: Globals.saverStyle
                            onPicked: function (v) { Globals.saverStyle = v; root.saverChanged() }
                        }
                    }
                    SectionTitle { text: "LOCKING" }
                    Card {
                        ToggleRow {
                            title: "Require password"
                            sub: "Idle goes straight to the session lock screen instead of the dismissable saver."
                            dim: !Globals.saverEnabled
                            on: Globals.saverLock
                            onToggled: { Globals.saverLock = !Globals.saverLock; root.saverChanged() }
                        }
                        DropRow {
                            label: "Lock after the saver starts"; ddId: "sv-lockafter"; dim: !Globals.saverEnabled || Globals.saverLock
                            options: [{ label: "Never", value: 0 }, { label: "1 min", value: 1 }, { label: "5 min", value: 5 }, { label: "10 min", value: 10 }, { label: "15 min", value: 15 }, { label: "30 min", value: 30 }]
                            value: Globals.saverLockAfterMin
                            onPicked: function (v) { Globals.saverLockAfterMin = v; root.saverChanged() }
                        }
                        Text { width: parent.width; text: "With the saver disabled the stock behaviour stays: auto-lock after 5 minutes idle. Idle-suspend on battery (15 min) is always kept."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    }
                    Row {
                        spacing: 10
                        Pill { label: "Preview"; primary: true; onGo: Globals.saverActive = true }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Shows the saver now — press any key to dismiss."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11 }
                    }
                    Text { width: parent.width; text: "Playing media, a fullscreen window, or the bar's Insomnia toggle keep the screensaver (and auto-lock/suspend) away. Timing is enforced by hypridle via generated/hypridle.conf — settings apply immediately, no restart needed."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    Item { width: 1; height: 8 }
                }
            }

            // ════════ PANE — Dock ════════
            // ════════ PANE — Power / lid ════════
            Component {
                id: cPower
                Column {
                    spacing: 14
                    SectionTitle { text: "WHEN THE LID CLOSES" }
                    Card {
                        Item {
                            width: parent.width; height: 34
                            Column { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                Text { text: "Suspend even when docked"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                Text { text: "On: closing the lid always suspends. Off (default): with an external monitor, keep working with the panel dark."
                                       color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }
                            }
                            Toggle {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                on: Globals.lidDockedSuspend
                                onToggled: { Globals.lidDockedSuspend = !Globals.lidDockedSuspend; root.writePrefs() }
                            }
                        }
                        Rectangle { width: parent.width; height: 1; color: Theme.stroke; opacity: 0.5 }
                        KV { k: "Right now"; v: Lid.docked ? (Lid.externals + " external display" + (Lid.externals === 1 ? "" : "s") + " connected")
                                                           : "no external display — the lid always suspends" }
                    }
                    Text { width: parent.width
                           text: "With the laptop alone, closing the lid always suspends. The session is locked on the way down through a logind delay inhibitor, so the lock is up before the machine sleeps rather than racing it."
                           color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }

                    SectionTitle { text: "BATTERY" }
                    Card {
                        KV { k: "Charge"; v: Power.capacity >= 0 ? Power.capacity + "%  ·  " + Power.remainingText() : "—" }
                        KV { k: "Health"; v: Power.healthText() }
                        Rectangle { visible: Power.hasChargeLimit; width: parent.width; height: 1; color: Theme.stroke; opacity: 0.5 }
                        DropRow {
                            visible: Power.hasChargeLimit && Power.chargeLimitWritable
                            label: "Charge ceiling"; ddId: "chg-limit"; buttonWidth: 120
                            options: [{ label: "60%  (longest life)", value: 60 },
                                      { label: "80%  (balanced)", value: 80 },
                                      { label: "100%  (full capacity)", value: 100 }]
                            value: Power.chargeLimit
                            onPicked: function (v) { Power.setChargeLimit(v) }
                        }
                        // present but root-only: say why rather than offering a
                        // control that would silently write into the void
                        Text {
                            visible: Power.hasChargeLimit && !Power.chargeLimitWritable
                            width: parent.width; wrapMode: Text.Wrap
                            text: "Charge ceiling is " + Power.chargeLimit + "%, but this attribute is root-only here. Re-run install.sh to add the udev rule, or manage it with asusctl."
                            color: Theme.warning; font.family: Theme.fontText; font.pixelSize: 11
                        }
                        Text {
                            visible: !Power.hasChargeLimit
                            width: parent.width; wrapMode: Text.Wrap
                            text: "This machine's battery exposes no charge-ceiling control."
                            color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11
                        }
                    }

                    SectionTitle { visible: Logind.hasKbdBacklight; text: "KEYBOARD BACKLIGHT" }
                    Card {
                        visible: Logind.hasKbdBacklight
                        DropRow {
                            label: "Level"; ddId: "kbd-bl"; buttonWidth: 120
                            options: [{ label: "Off", value: 0 }, { label: "Low", value: 1 },
                                      { label: "Medium", value: 2 }, { label: "High", value: 3 }]
                            value: Logind.hasKbdBacklight ? Logind.kbdBacklight.value : 0
                            onPicked: function (v) { Logind.setKbdStep(v) }
                        }
                        KV { k: "Hotkeys"; v: "the keyboard-backlight keys step this too" }
                    }

                    SectionTitle { text: "PERFORMANCE" }
                    Card {
                        KV { k: "Profile daemon"; v: Power.ppdRunning ? "power-profiles-daemon" : "none — using " + (Power.platformProfile !== "" ? "the firmware profile" : "kernel defaults") }
                        KV { visible: !Power.ppdRunning && Power.platformProfile !== ""
                             k: "Firmware profile"; v: Power.platformProfile + (Power.platformChoices.length ? "  (" + Power.platformChoices.join(" · ") + ")" : "") }
                        Text {
                            visible: Power.degraded
                            width: parent.width; wrapMode: Text.Wrap
                            text: "Performance is being held back: " + Power.degradedReason + "."
                            color: Theme.warning; font.family: Theme.fontText; font.pixelSize: 11
                        }
                        Text {
                            visible: !Power.degraded && Power.ppdRunning
                            width: parent.width
                            text: "Not thermally limited. Switch profiles from Quick Settings."
                            color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11
                        }
                    }

                    SectionTitle { text: "ON BATTERY" }
                    Card {
                        Item {
                            width: parent.width; height: 34
                            Column { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                Text { text: "Low-power mode"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                Text { text: "Slow background polling down while unplugged."
                                       color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }
                            }
                            Toggle {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                on: Globals.lowPowerEnabled
                                onToggled: { Globals.lowPowerEnabled = !Globals.lowPowerEnabled; root.writePrefs() }
                            }
                        }
                        Rectangle { width: parent.width; height: 1; color: Theme.stroke; opacity: 0.5 }
                        KV { k: "Power source"; v: Globals.onBattery ? "battery" + (Globals.lowPower ? " · low-power active" : "") : "mains" }
                    }

                    SectionTitle { text: "SESSION" }
                    Card {
                        KV { k: "logind bridge"; v: Logind.bridgeUp ? "connected" : (Logind.bridgeError !== "" ? Logind.bridgeError : "starting…") }
                        KV { k: "Sleep inhibitor"; v: Logind.inhibited ? "held (" + Logind.delayMs + " ms to lock)" : "not held" }
                        KV { k: "Panel backlight"; v: Logind.hasBacklight ? Logind.backlight.name : "none detected" }
                        KV { k: "Keyboard backlight"; v: Logind.hasKbdBacklight ? Logind.kbdBacklight.name : "none detected" }
                    }

                    SectionTitle { text: "KEEPING THIS MACHINE AWAKE" }
                    Card {
                        // We deliberately do not own org.freedesktop.ScreenSaver —
                        // hypridle implements it, and two owners would fight. This
                        // reports whether app inhibits are being heard at all.
                        KV { k: "App inhibits"; v: Logind.screensaverOwner !== ""
                                ? "honoured by " + Logind.screensaverOwner
                                : "nothing owns org.freedesktop.ScreenSaver" }
                        KV { k: "Insomnia"; v: Globals.caffeine ? "on — idle is blocked" : "off" }
                        Rectangle { width: parent.width; height: 1; color: Theme.stroke; opacity: 0.5 }
                        Repeater {
                            model: Logind.blockingInhibitors()
                            delegate: KV {
                                required property var modelData
                                k: String(modelData.who)
                                v: String(modelData.why) + "  ·  " + String(modelData.what)
                            }
                        }
                        Text {
                            visible: Logind.blockingInhibitors().length === 0
                            width: parent.width; wrapMode: Text.Wrap
                            text: "Nothing is blocking idle or sleep right now."
                            color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11
                        }
                    }
                    Item { width: 1; height: 8 }
                }
            }

            Component {
                id: cDock
                Column {
                    spacing: 14
                    SectionTitle { text: "BOTTOM DOCK" }
                    Card {
                        Item {
                            width: parent.width; height: 30
                            Column { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                Text { text: "Show dock"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                Text { text: "Launcher · overview · workspace switcher at the bottom."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }
                            }
                            Toggle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; on: Globals.dockEnabled; onToggled: { Globals.dockEnabled = !Globals.dockEnabled; root.writePrefs() } }
                        }
                        Rectangle { width: parent.width; height: 1; color: Theme.stroke; opacity: 0.5 }
                        Item {
                            width: parent.width; height: 30
                            opacity: Globals.dockEnabled ? 1 : 0.4
                            Column { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                Text { text: "Intelligent hide"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                Text { text: "Auto-hide; reveal by moving the cursor to the bottom edge."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }
                            }
                            Toggle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; on: Globals.dockAutohide; onToggled: { if (Globals.dockEnabled) { Globals.dockAutohide = !Globals.dockAutohide; root.writePrefs() } } }
                        }
                        Rectangle { width: parent.width; height: 1; color: Theme.stroke; opacity: 0.5 }
                        Item {
                            width: parent.width; height: 30
                            opacity: Globals.dockEnabled ? 1 : 0.4
                            Column { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                Text { text: "Icon size"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                Text { text: "How big the dock buttons and workspace boxes are."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }
                            }
                            Row {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                Repeater {
                                    model: [{ n: "Small", v: "small" }, { n: "Normal", v: "normal" }, { n: "Large", v: "large" }]
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool sel: Globals.dockIconSize === modelData.v
                                        width: 60; height: 26; radius: Theme.radiusPill
                                        color: sel ? Theme.accent : Theme.panel
                                        border.color: sel ? Theme.accent : Theme.stroke; border.width: 1
                                        Text { anchors.centerIn: parent; text: modelData.n; color: parent.sel ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (Globals.dockEnabled) { Globals.dockIconSize = modelData.v; root.writePrefs() } } }
                                    }
                                }
                            }
                        }
                    }
                    Text { width: parent.width; text: "The dock replaces the workspace row that used to be in the top bar."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    Item { width: 1; height: 8 }
                }
            }

            // ════════ PANE — Startup applications ════════
            Component {
                id: cStartup
                Column {
                    spacing: 14
                    SectionTitle { text: "LAUNCH AT LOGIN" }

                    Card {
                        Text {
                            visible: root.startupApps.length === 0
                            width: parent.width; wrapMode: Text.Wrap
                            text: "Nothing starts automatically yet. Search below to add an application."
                            color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                        }
                        Repeater {
                            model: root.startupApps
                            delegate: Item {
                                id: saRow
                                required property var modelData
                                required property int index
                                width: parent.width; height: 36
                                opacity: saRow.modelData.enabled === false ? 0.45 : 1
                                Image {
                                    id: saIcon
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    width: 20; height: 20
                                    visible: source !== ""
                                    source: saRow.modelData.icon ? Quickshell.iconPath(saRow.modelData.icon, true) : ""
                                    sourceSize.width: 40; sourceSize.height: 40; mipmap: true
                                }
                                Column {
                                    anchors.left: parent.left; anchors.leftMargin: 30
                                    anchors.right: saCtl.left; anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1
                                    Text { width: parent.width; text: saRow.modelData.name || saRow.modelData.exec; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                    Text { width: parent.width; text: saRow.modelData.exec; color: Theme.fgDim; font.family: Theme.fontMono; font.pixelSize: 10; elide: Text.ElideRight }
                                }
                                Row {
                                    id: saCtl
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                    Toggle { anchors.verticalCenter: parent.verticalCenter; on: saRow.modelData.enabled !== false; onToggled: root.startupToggle(saRow.index) }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 22; height: 22; radius: 6
                                        color: saDelMa.containsMouse ? Theme.danger : "transparent"
                                        Text { anchors.centerIn: parent; text: Theme.icClose; font.family: Theme.fontIcons; font.pixelSize: 11; color: saDelMa.containsMouse ? Theme.accentText : Theme.fgDim }
                                        MouseArea { id: saDelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.startupRemove(saRow.index) }
                                    }
                                }
                            }
                        }
                    }

                    SectionTitle { text: "ADD APPLICATION" }
                    Card {
                        // search over installed desktop entries
                        Rectangle {
                            width: parent.width; height: 32; radius: 8
                            color: Theme.bg; border.color: saSearch.activeFocus ? Theme.accent : Theme.stroke; border.width: 1
                            Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: Theme.icSearch; font.family: Theme.fontIcons; font.pixelSize: 13; color: Theme.fgDim }
                            TextInput {
                                id: saSearch
                                anchors.fill: parent; anchors.leftMargin: 30; anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                onTextChanged: root.startupQuery = text
                                Text { anchors.verticalCenter: parent.verticalCenter; visible: saSearch.text.length === 0; text: "Search apps — or type any command…"; color: Theme.fgDim; font: saSearch.font }
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
                                delegate: Item {
                                    id: saRes
                                    required property var modelData
                                    width: parent.width; height: 30
                                    Rectangle { anchors.fill: parent; radius: 6; color: saResMa.containsMouse ? Theme.hover : "transparent" }
                                    Image {
                                        anchors.left: parent.left; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter
                                        width: 18; height: 18
                                        source: saRes.modelData.icon ? Quickshell.iconPath(saRes.modelData.icon, true) : ""
                                        sourceSize.width: 36; sourceSize.height: 36; mipmap: true
                                    }
                                    Text {
                                        anchors.left: parent.left; anchors.leftMargin: 30; anchors.right: parent.right; anchors.rightMargin: 60
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: saRes.modelData.name; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; elide: Text.ElideRight
                                    }
                                    Text {
                                        anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                        text: "Add"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold
                                    }
                                    MouseArea {
                                        id: saResMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.startupAdd(saRes.modelData.name, root.cleanExec(saRes.modelData.execString), saRes.modelData.icon); saSearch.text = "" }
                                    }
                                }
                            }
                            // raw command fallback — whatever was typed runs via sh -c
                            Item {
                                width: parent.width; height: 30
                                Rectangle { anchors.fill: parent; radius: 6; color: saCmdMa.containsMouse ? Theme.hover : "transparent" }
                                Text { anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: Theme.icSsh; font.family: Theme.fontIcons; font.pixelSize: 12; color: Theme.fgDim }
                                Text {
                                    anchors.left: parent.left; anchors.leftMargin: 30; anchors.right: parent.right; anchors.rightMargin: 90
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Run command: " + root.startupQuery.trim()
                                    color: Theme.fgSecondary; font.family: Theme.fontMono; font.pixelSize: 11; elide: Text.ElideRight
                                }
                                Text {
                                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                    text: "Add command"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold
                                }
                                MouseArea {
                                    id: saCmdMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.startupAdd(root.startupQuery.trim(), root.startupQuery.trim(), ""); saSearch.text = "" }
                                }
                            }
                        }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.Wrap
                        text: "Entries launch once at login (autostart). Changes apply at the next login — the toggle disables an entry without removing it. This list is included in Settings sync."
                        color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11
                    }
                    Item { width: 1; height: 8 }
                }
            }

            // ════════ PANE — User ════════
            Component {
                id: cUser
                Column {
                    spacing: 14
                    SectionTitle { text: "ACCOUNT" }
                    Card {
                        Row {
                            width: parent.width; spacing: 16
                            Avatar { size: 72; initial: (root.userRealName || Quickshell.env("USER") || "").charAt(0).toUpperCase() }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                // display name — click to edit, saved to AccountsService
                                Rectangle {
                                    width: Math.max(220, nameIn.implicitWidth + 26); height: 32; radius: 6
                                    color: nameIn.activeFocus ? Theme.bg : "transparent"
                                    border.color: nameIn.activeFocus ? Theme.accent : (nameHov.hovered ? Theme.stroke : "transparent"); border.width: 1
                                    HoverHandler { id: nameHov }
                                    TextInput {
                                        id: nameIn
                                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 24; verticalAlignment: TextInput.AlignVCenter
                                        text: root.userRealName !== "" ? root.userRealName : (Quickshell.env("USER") || "user")
                                        color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge; font.weight: Font.Bold
                                        selectByMouse: true; clip: true
                                        onAccepted: focus = false
                                        onActiveFocusChanged: if (!activeFocus && text.trim() !== "" && text.trim() !== root.userRealName) root.setRealName(text.trim())
                                    }
                                    Text { anchors.right: parent.right; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter; visible: nameHov.hovered && !nameIn.activeFocus; text: Theme.icPencil; font.family: Theme.fontMono; font.pixelSize: 11; color: Theme.fgDim }
                                }
                                Text { leftPadding: 9; text: "@" + (Quickshell.env("USER") || "user"); color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                Item { width: 1; height: 3 }
                                Row {
                                    spacing: 8
                                    Pill { label: "Change avatar…"; onGo: avPicker.browse() }
                                    // shape picker — applies live everywhere via Globals.avatarShape
                                    Repeater {
                                        model: [{ l: "Circle", v: "circle" }, { l: "Rounded", v: "rounded" }, { l: "Square", v: "square" }]
                                        delegate: Pill {
                                            required property var modelData
                                            label: modelData.l; primary: Globals.avatarShape === modelData.v
                                            onGo: { Globals.avatarShape = modelData.v; root.writePrefs() }
                                        }
                                    }
                                }
                            }
                        }
                        FileDropTarget {
                            id: avPicker
                            width: parent.width; implicitHeight: 44
                            label: "Drop an image here to change your avatar"
                            dialogTitle: "Choose avatar image"
                            onPicked: function (p) { root.avatarCropSrc = p }
                        }
                    }
                    Text { width: parent.width; text: "Avatar is saved to ~/.face (used by login/greeters); the system account icon and display name update via AccountsService."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }

                    SectionTitle { text: "SESSION" }
                    Card {
                        KV { k: "Host"; v: root.sysFacts.host || "—" }
                        KV { k: "Compositor"; v: root.sysFacts.hypr || "Hyprland" }
                        KV { k: "Session type"; v: "Wayland" }
                        KV { k: "Kernel"; v: root.sysFacts.kernel || "—" }
                        KV { k: "Uptime"; v: root.sysFacts.up || "—" }
                    }

                    SectionTitle { text: "GOOGLE ACCOUNT" }
                    // not configured yet — actionable, never a spinner
                    Card {
                        visible: Google.probed && !Google.configured
                        Text { width: parent.width; text: "Google client ID not configured. Create a Google Cloud OAuth client of type “Desktop app” (enable the Calendar and Drive APIs) and save it as ~/.config/quickshell/google-oauth.json:"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap }
                        Text { width: parent.width; text: '{ "client_id": "…apps.googleusercontent.com", "client_secret": "…" }'; color: Theme.fgSecondary; font.family: Theme.fontMono; font.pixelSize: 11 }
                        Text { width: parent.width; text: "The file is gitignored; tokens end up only in the system keyring. Full steps: README → Google account."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    }
                    Card {
                        visible: Google.probed && Google.configured && !Google.keyringOk
                        Text { width: parent.width; text: "No Secret Service keyring found — the refresh token has nowhere safe to live. Install and enable gnome-keyring, then retry."; color: Theme.warning; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap }
                    }
                    // configured, signed out → connect
                    Card {
                        visible: Google.probed && Google.configured && !Google.signedIn
                        Text { width: parent.width; text: "Connect your Google account and ewe lights up around it: calendar in Quick Settings, your machine synced as one file, app restore through Komble — and, if you choose, your Drive as a folder in Files. Until then, nothing Google appears anywhere: this button is the only trace."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap }
                        Row {
                            spacing: 10
                            Pill { visible: Google.busy !== "signin"; label: "Connect Google account"; primary: true; onGo: Google.signIn() }
                            Text { visible: Google.busy === "signin"; anchors.verticalCenter: parent.verticalCenter; text: "Waiting for the browser sign-in…"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                            Pill { visible: Google.busy === "signin"; label: "Cancel"; onGo: Google.cancelSignIn() }
                        }
                    }
                    // signed in → profile + services + sign out
                    Card {
                        visible: Google.signedIn
                        Item {
                            width: parent.width; height: 46
                            Rectangle {
                                id: gAvBox
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                width: 40; height: 40; radius: 20; color: Theme.hover
                                Text { anchors.centerIn: parent; visible: gAv.status !== Image.Ready; text: ((Google.profile && Google.profile.name) || "?").charAt(0).toUpperCase(); color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 16; font.weight: Font.DemiBold }
                                Image {
                                    id: gAv
                                    anchors.fill: parent
                                    source: (Google.profile && Google.profile.picture) ? Google.profile.picture : ""
                                    fillMode: Image.PreserveAspectCrop
                                    visible: status === Image.Ready
                                    layer.enabled: true
                                    layer.effect: MultiEffect { maskEnabled: true; maskSource: gAvMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                                }
                                Item { id: gAvMask; anchors.fill: parent; layer.enabled: true; visible: false; Rectangle { anchors.fill: parent; radius: 20; antialiasing: true } }
                            }
                            Column {
                                anchors.left: parent.left; anchors.leftMargin: 52; anchors.right: gOut.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                Text { width: parent.width; text: (Google.profile && Google.profile.name) || "Google account"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                Text { width: parent.width; text: (Google.profile && Google.profile.email) || ""; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; elide: Text.ElideRight }
                            }
                            Pill { id: gOut; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; label: "Sign out"; onGo: Google.signOut() }
                        }
                        KV { k: "Calendar"; v: "connected · read-only"; dot: "ok" }
                        KV { k: "Settings sync (Drive app data)"; v: "connected"; dot: "ok" }
                        KV { visible: Google.profile && Google.profile.picture; k: "Google profile photo"; action: true; actionLabel: "Use as avatar"; onAct: root.useGooglePhoto() }
                    }
                    Text {
                        visible: Google.error !== ""
                        width: parent.width; text: Google.error; color: Theme.danger; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap
                    }

                    SectionTitle { visible: Google.signedIn; text: "SETTINGS SYNC" }
                    Card {
                        visible: Google.signedIn
                        KV { k: "Cloud backup"; v: Google.cloudInfo ? ("saved on “" + Google.cloudInfo.device + "” · " + root.fmtSyncTime(Google.cloudInfo.updatedAt)) : "none yet" }
                        KV { k: "Last synced from this device"; v: Google.lastSync !== "" ? root.fmtSyncTime(Google.lastSync) : "never" }
                        ToggleRow {
                            title: "Auto-sync"
                            sub: "Pushes ~20 s after closing Settings whenever something changed."
                            on: Google.autoSync
                            onToggled: Google.setAutoSync(!Google.autoSync)
                        }
                        Row {
                            spacing: 10
                            Pill { label: Google.syncState === "syncing" ? "Syncing…" : "Sync now"; primary: true; onGo: Google.syncNow() }
                            Pill { label: "Restore from cloud…"; onGo: Google.requestRestore() }
                            Pill { label: "Packages from backup…"; onGo: root.reviewPackages() }
                        }
                        Text { width: parent.width; text: "Theme, keyboard, dock, wallpaper, shortcuts, screensaver, avatar (picture + shape), startup applications, display profiles, SSH hosts + browse tunnels (never keys) — one bundle in Drive's hidden app storage. VPN profiles hold secrets, so only their names are captured. The installed-package list is captured too; reinstalling from it is always opt-in."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                        Text { visible: Google.syncError !== ""; width: parent.width; text: Google.syncError; color: Theme.danger; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                        Text { visible: Google.restoreSummary !== ""; width: parent.width; text: Google.restoreSummary; color: Theme.success; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    }
                    // restore confirmation — explicit, summarises what will change
                    Rectangle {
                        visible: Google.pendingRestore !== null
                        width: parent.width
                        implicitHeight: restCol.implicitHeight + 24
                        radius: Theme.radiusInner; color: Theme.elevated
                        border.color: Theme.accent; border.width: 1
                        Column {
                            id: restCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12; spacing: 8
                            Text { text: "Restore settings from the cloud backup?"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold }
                            KV { k: "Saved on"; v: Google.pendingRestore ? ("“" + (Google.pendingRestore.device || "?") + "” · " + root.fmtSyncTime(Google.pendingRestore.updatedAt || "")) : "" }
                            KV { k: "Restores"; v: "the machine file (ewe.conf) — theme, dock, displays, rules, apps list; your current file is kept as a timestamped backup" }
                            KV { k: "Applications"; v: "reinstall offers appear in Komble → For you (never auto-installed)" }
                            Text { width: parent.width; text: "Overwrites this machine's theme, keyboard, dock, wallpaper, screensaver, SSH-host and display-profile settings, then reloads the shell config live."; color: Theme.warning; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                            Row {
                                spacing: 10
                                Pill { label: "Restore"; primary: true; onGo: Google.applyRestore() }
                                Pill { label: "Cancel"; onGo: Google.cancelRestore() }
                            }
                        }
                    }

                    // packages-from-backup — checkbox picker for what's not installed here
                    Rectangle {
                        visible: root.pkgReview !== null
                        width: parent.width
                        implicitHeight: pkgCol.implicitHeight + 24
                        radius: Theme.radiusInner; color: Theme.elevated
                        border.color: Theme.accent; border.width: 1
                        Column {
                            id: pkgCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12; spacing: 8
                            Text { text: "Packages from the backup"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold }
                            Text {
                                width: parent.width
                                readonly property int missing: root.pkgReview ? (root.pkgReview.repo.length + root.pkgReview.aur.length) : 0
                                text: missing === 0 ? "Everything from the backup is already installed on this machine."
                                                    : missing + " captured packages are not installed here — pick what to install:"
                                color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap
                            }
                            component PkgRow: Item {
                                property string kind: "repo"
                                property int idx: 0
                                property var entry: null
                                width: parent ? parent.width : 0; height: 26
                                Rectangle {
                                    id: pkBox
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    width: 16; height: 16; radius: 4
                                    color: entry && entry.on ? Theme.accent : "transparent"
                                    border.color: entry && entry.on ? Theme.accent : Theme.stroke; border.width: 1
                                    Text { anchors.centerIn: parent; visible: entry && entry.on; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: 10; color: Theme.accentText }
                                }
                                Text { anchors.left: pkBox.right; anchors.leftMargin: 9; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: (entry ? entry.name : "") + (kind === "aur" ? "   · AUR" : ""); color: Theme.fg; font.family: Theme.fontMono; font.pixelSize: 11; elide: Text.ElideRight }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.pkgToggle(kind, idx) }
                            }
                            Rectangle {
                                width: parent.width
                                visible: root.pkgReview !== null && (root.pkgReview.repo.length + root.pkgReview.aur.length) > 0
                                height: visible ? Math.min(pkgListCol.implicitHeight + 10, 240) : 0
                                radius: 7; color: Theme.bg; border.color: Theme.stroke; border.width: 1
                                Flickable {
                                    anchors.fill: parent; anchors.margins: 5
                                    contentHeight: pkgListCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                                    Column {
                                        id: pkgListCol; width: parent.width
                                        Repeater {
                                            model: root.pkgReview ? root.pkgReview.repo : []
                                            delegate: PkgRow { required property var modelData; required property int index; kind: "repo"; idx: index; entry: modelData }
                                        }
                                        Repeater {
                                            model: root.pkgReview ? root.pkgReview.aur : []
                                            delegate: PkgRow { required property var modelData; required property int index; kind: "aur"; idx: index; entry: modelData }
                                        }
                                    }
                                }
                            }
                            Row {
                                spacing: 10
                                Pill { visible: root.pkgSelectedCount() > 0; label: "Install selected (" + root.pkgSelectedCount() + ") in terminal"; primary: true; onGo: root.pkgInstallSelected() }
                                Pill { visible: root.pkgReview !== null && (root.pkgReview.repo.length + root.pkgReview.aur.length) > 0; label: "All"; onGo: root.pkgSetAll(true) }
                                Pill { visible: root.pkgReview !== null && (root.pkgReview.repo.length + root.pkgReview.aur.length) > 0; label: "None"; onGo: root.pkgSetAll(false) }
                                Pill { label: "Close"; onGo: root.pkgReview = null }
                            }
                            Text { visible: root.pkgReview !== null && (root.pkgReview.repo.length + root.pkgReview.aur.length) > 0; width: parent.width; text: "Opens a terminal running sudo pacman -S --needed (AUR entries via paru) — you authenticate there and watch it happen. Nothing installs silently."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap }
                        }
                    }

                    SectionTitle { visible: Accounts.contacts.length > 0; text: "CONTACTS  ·  " + Accounts.contacts.length }
                    Card {
                        visible: Accounts.contacts.length > 0
                        Repeater {
                            model: Accounts.contacts.slice(0, 25)
                            delegate: Item {
                                required property var modelData
                                width: parent.width; height: 36
                                Rectangle {
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    width: 26; height: 26; radius: 13; color: Theme.hover
                                    Text { anchors.centerIn: parent; text: (modelData.name || "?").charAt(0).toUpperCase(); color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 12; font.weight: Font.DemiBold }
                                }
                                Column {
                                    anchors.left: parent.left; anchors.leftMargin: 36; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                    Text { width: parent.width; text: modelData.name; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; elide: Text.ElideRight }
                                    Text { width: parent.width; text: (modelData.emails[0] || "") + (modelData.phones && modelData.phones.length ? "  ·  " + modelData.phones[0] : ""); color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10; elide: Text.ElideRight }
                                }
                            }
                        }
                        Text { visible: Accounts.contacts.length > 25; text: "…and " + (Accounts.contacts.length - 25) + " more"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11 }
                    }
                    Item { width: 1; height: 8 }
                }
            }

            // ════════ overlays: error banner · applied flash · confirm-or-revert ════════
            Rectangle {
                visible: root.errorMsg !== ""
                anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 14
                width: Math.min(errText.implicitWidth + 66, card.width - 40); height: 36; radius: 10; z: 60
                color: Theme.elevated; border.color: Theme.danger; border.width: 1
                Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: Theme.icWarning; font.family: Theme.fontIcons; font.pixelSize: 13; color: Theme.danger }
                Text { id: errText; anchors.left: parent.left; anchors.leftMargin: 34; anchors.right: parent.right; anchors.rightMargin: 32; anchors.verticalCenter: parent.verticalCenter; text: root.errorMsg; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; elide: Text.ElideRight }
                Text { anchors.right: parent.right; anchors.rightMargin: 11; anchors.verticalCenter: parent.verticalCenter; text: Theme.icClose; font.family: Theme.fontIcons; font.pixelSize: 12; color: Theme.fgDim
                    MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: root.clearError() } }
            }
            Rectangle {
                visible: root.appliedMsg !== "" && root.errorMsg === ""
                anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 14
                width: apText.implicitWidth + 40; height: 30; radius: 9; z: 60
                color: Theme.elevated; border.color: Theme.stroke; border.width: 1
                Text { anchors.left: parent.left; anchors.leftMargin: 11; anchors.verticalCenter: parent.verticalCenter; text: Theme.icCheck; font.family: Theme.fontIcons; font.pixelSize: 12; color: Theme.success }
                Text { id: apText; anchors.right: parent.right; anchors.rightMargin: 11; anchors.verticalCenter: parent.verticalCenter; text: root.appliedMsg; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
            }
            Rectangle {
                // avatar crop: pan (drag) + zoom (slider) inside a square viewport;
                // Save grabs the viewport at 512×512 and writes it to ~/.face.
                anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45); z: 65
                visible: root.avatarCropSrc !== ""
                MouseArea { anchors.fill: parent }   // swallow clicks
                Rectangle {
                    anchors.centerIn: parent; width: 340; height: cropCol.implicitHeight + 40
                    radius: Theme.radius; color: Theme.panel; border.color: Theme.stroke; border.width: 1
                    Column {
                        id: cropCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 20; spacing: 12
                        Text { text: "Crop avatar"; color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge; font.weight: Font.Bold }
                        Item {
                            id: cropView
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 256; height: 256
                            property real zoom: 1
                            onVisibleChanged: if (visible) zoom = 1
                            Item {
                                id: cropCanvas
                                anchors.fill: parent; clip: true
                                Image {
                                    id: cropImg
                                    source: root.avatarCropSrc === "" ? "" : "file://" + root.avatarCropSrc
                                    readonly property real baseScale: status === Image.Ready && implicitWidth > 0 && implicitHeight > 0 ? Math.max(256 / implicitWidth, 256 / implicitHeight) : 1
                                    width: implicitWidth * baseScale * cropView.zoom
                                    height: implicitHeight * baseScale * cropView.zoom
                                    onStatusChanged: if (status === Image.Ready) { x = (256 - width) / 2; y = (256 - height) / 2 }
                                }
                            }
                            // overlay chrome lives OUTSIDE cropCanvas so the grab stays clean
                            Rectangle { anchors.fill: parent; color: "transparent"; border.color: Theme.stroke; border.width: 1 }
                            Rectangle { anchors.fill: parent; radius: 128; color: "transparent"; border.color: Qt.rgba(1, 1, 1, 0.4); border.width: 1 }
                            MouseArea {
                                anchors.fill: parent
                                drag.target: cropImg
                                drag.minimumX: 256 - cropImg.width; drag.maximumX: 0
                                drag.minimumY: 256 - cropImg.height; drag.maximumY: 0
                                cursorShape: Qt.SizeAllCursor
                            }
                        }
                        Slider {
                            label: "Zoom"; value: cropView.zoom; from: 1; to: 3; step: 0.05; decimals: 2; live: true
                            onMoved: function (v) {
                                var cx = cropImg.width > 0 ? (128 - cropImg.x) / cropImg.width : 0.5
                                var cy = cropImg.height > 0 ? (128 - cropImg.y) / cropImg.height : 0.5
                                cropView.zoom = v
                                cropImg.x = Math.min(0, Math.max(256 - cropImg.width, 128 - cx * cropImg.width))
                                cropImg.y = Math.min(0, Math.max(256 - cropImg.height, 128 - cy * cropImg.height))
                            }
                        }
                        Row {
                            anchors.right: parent.right; spacing: 8
                            Pill { label: "Cancel"; onGo: root.avatarCropSrc = "" }
                            Pill { label: "Save avatar"; primary: true; onGo: root.saveAvatar() }
                        }
                    }
                }
            }
            Rectangle {
                // confirm-or-revert: a change that can black out a display was just
                // applied; unless the user confirms within 10 s, the previous
                // known-good configuration is restored automatically.
                anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45); z: 70
                visible: root.revertSpecs !== null
                MouseArea { anchors.fill: parent }   // swallow clicks
                Rectangle {
                    anchors.centerIn: parent; width: 380; height: revCol.implicitHeight + 40
                    radius: Theme.radius; color: Theme.panel; border.color: Theme.stroke; border.width: 1
                    Column {
                        id: revCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 20; spacing: 10
                        Text { text: "Keep these display settings?"; color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge; font.weight: Font.Bold }
                        Text { width: parent.width; text: "Reverting to the previous configuration in " + root.revertLeft + " s if you can't see this."; color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap }
                        Row {
                            anchors.right: parent.right; spacing: 8
                            Pill { label: "Revert now"; onGo: root.doRevert() }
                            Pill { label: "Keep (" + root.revertLeft + ")"; primary: true; onGo: root.keepChange() }
                        }
                    }
                }
            }
        }
    }
}
