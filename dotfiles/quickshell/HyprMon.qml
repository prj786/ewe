pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower

// HyprMon — the display manager behind Settings → Displays.
//
// Owns the known-good per-monitor configuration and re-asserts it whenever the
// world changes underneath us:
//   * one PROFILE per unique set of connected outputs, keyed by the sorted
//     monitor descriptions (fall back to connector name) — docking/undocking
//     picks the right profile automatically;
//   * profiles persist in ~/.config/quickshell/display-profiles.json and are
//     rendered to ~/.config/hypr/generated/monitors.lua (sourced by
//     hyprland.lua) so the exact mode/position/scale is applied at BOOT, before
//     the shell is even up — never `preferred`/`auto` for a configured monitor;
//   * re-asserts on Hyprland monitoradded/monitorremoved/configreloaded events
//     (hotplug) and on UPower AC↔battery transitions (the xe/Lunar Lake driver
//     can re-probe and blank the panel on charger plug/unplug — re-applying the
//     saved config recovers it; if the panel still blanks, that part is the
//     kernel driver (PSR), not the shell).
//
// Live changes go through `hyprctl eval 'hl.monitor{…}'` (this DE's Hyprland is
// Lua-configured; plain `hyprctl keyword` is rejected). Any non-`ok` reply
// lands in `lastError` for the Settings UI to surface — no silent failures.
QtObject {
    id: mgr

    readonly property string home: Quickshell.env("HOME")
    readonly property string profilesPath: home + "/.config/quickshell/display-profiles.json"
    readonly property string monitorsLua: home + "/.config/hypr/generated/monitors.lua"

    // ── state ─────────────────────────────────────────────────────────────────
    property var monitors: []          // hyprctl monitors all -j (includes disabled)
    property bool loading: false       // a monitors query is in flight
    property bool applying: false      // an apply batch is in flight
    property string lastError: ""      // last hyprctl / verify failure ("" = fine)
    property var profiles: ({})        // key → [spec…]
    property string lastKey: ""        // most recently committed profile key
    property bool _profLoaded: false
    property bool _monLoaded: false
    property bool _startupChecked: false

    // A spec is the app's canonical description of one output:
    // { desc, name, mode "WxH@Hz", x, y, scale, transform, vrr, bitdepth,
    //   disabled, mirror, primary }

    function start() { _profLoad.running = true; refresh() }
    function refresh() { loading = true; _monProc.running = false; _monProc.running = true }
    // re-read display-profiles.json after a settings restore rewrote it
    function reloadProfiles() { _profLoad.running = false; _profLoad.running = true }

    // ── spec helpers ──────────────────────────────────────────────────────────
    function specFromMonitor(m) {
        // a disabled output reports 0×0@0 — fall back to its first advertised
        // mode (or "preferred") so re-enabling never emits an invalid mode line
        var mode = (m.width || 0) + "x" + (m.height || 0) + "@" + Number(m.refreshRate || 60).toFixed(2)
        if (!(m.width > 0) || !(m.height > 0)) {
            var am = m.availableModes || []
            mode = am.length ? String(am[0]).replace(/Hz$/i, "") : "preferred"
        }
        return {
            desc: m.description || "", name: m.name,
            mode: mode,
            x: m.x || 0, y: m.y || 0,
            scale: Math.round(Number(m.scale || 1) * 10000) / 10000,
            transform: m.transform || 0,
            vrr: !!m.vrr,
            bitdepth: String(m.currentFormat || "").indexOf("2101010") >= 0 ? 10 : 8,
            disabled: !!m.disabled,
            mirror: (m.mirrorOf && m.mirrorOf !== "none") ? m.mirrorOf : "",
            primary: false
        }
    }
    // current state as a spec list, with the primary flag carried over from the
    // committed profile for this monitor set (primary is a shell concept —
    // Hyprland/Wayland have none; it anchors auto-arrange at 0,0).
    function snapshot() {
        var out = (monitors || []).map(specFromMonitor)
        var prof = profiles[keyFor(out)]
        if (prof) {
            for (var i = 0; i < out.length; i++)
                for (var j = 0; j < prof.length; j++)
                    if (matchId(out[i]) === matchId(prof[j])) { out[i].primary = !!prof[j].primary; break }
        }
        if (!out.some(function (s) { return s.primary }) && out.length) out[0].primary = true
        return out
    }
    function matchId(s) { return s.desc !== "" ? s.desc : s.name }
    function keyFor(specs) { return specs.map(matchId).sort().join(" || ") }
    function currentKey() { return keyFor((monitors || []).map(specFromMonitor)) }
    function modeRes(mode) { return String(mode).split("@")[0] }
    function modeHz(mode) { var p = String(mode).split("@"); return p.length > 1 ? parseFloat(p[1]) : 60 }

    // ── Lua generation ────────────────────────────────────────────────────────
    function luaEsc(s) { return String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') }
    // the argument table for hl.monitor{} — shared by live apply and monitors.lua
    function luaArgs(s) {
        var out = s.desc !== "" ? "desc:" + s.desc : s.name
        var L = '{ output = "' + luaEsc(out) + '"'
        if (s.disabled) return L + ", disabled = true }"
        L += ', mode = "' + s.mode + '", position = "' + s.x + "x" + s.y + '", scale = ' + s.scale
        if (s.transform) L += ", transform = " + s.transform
        L += ", vrr = " + (s.vrr ? 1 : 0)
        if (s.bitdepth === 10) L += ", bitdepth = 10"
        if (s.mirror !== "") L += ', mirror = "' + luaEsc(s.mirror) + '"'
        return L + " }"
    }

    // ── live apply (with error capture) ───────────────────────────────────────
    // runEvals is the ONE hyprctl-eval runner in the shell (Settings uses it
    // too): runs each single-line Lua statement, and any non-`ok` reply lands
    // in lastError. One batch in flight at a time.
    property var _applyDone: null
    function runEvals(stmts, done) {
        if (!stmts || !stmts.length) { if (done) done(false); return }
        var cmd = ["sh", "-c",
            'st=0; for s in "$@"; do out=$(hyprctl eval "$s" 2>&1); case "$out" in ok*) ;; *) echo "$out"; st=1;; esac; done; exit $st',
            "hyprmon"]
        for (var i = 0; i < stmts.length; i++) cmd.push(stmts[i])
        _applyDone = done || null
        applying = true
        _applyProc.command = cmd
        _applyProc.running = false; _applyProc.running = true
    }
    function applySpecs(specs, done) {
        if (!specs || !specs.length) { if (done) done(false); return }
        // clamshell: while the lid is closed the internal panel must STAY
        // off — a profile re-assert (hotplug/AC/idle events) would
        // otherwise relight the panel inside the closed lid
        var eff = specs.map(function (s) {
            return (mgr.lidClosed && mgr.isInternal(s.name)) ? { desc: s.desc, name: s.name, disabled: true } : s
        })
        // last-ditch guard: a profile that would turn off EVERY output leaves
        // no way to recover but a blind reboot — refuse it outright
        if (eff.every(function (s) { return s.disabled })) {
            mgr.lastError = "Refused to apply: profile would disable every display"
            if (done) done(false)
            return
        }
        runEvals(eff.map(function (s) { return "hl.monitor(" + luaArgs(s) + ")" }), done)
    }

    // ── clamshell (lid) state — lid.sh reports via `qs ipc call display lid …`
    property bool lidClosed: false
    function isInternal(name) { return /^(eDP|LVDS|DSI)/.test(String(name || "")) }
    function setLid(closed) {
        lidClosed = closed
        // reopened: the panel's enable event + this re-assert bring it back
        // with the saved mode/scale/position (no hardcoded geometry anywhere)
        if (!closed) _reassertT.restart()
    }
    property IpcHandler _displayIpc: IpcHandler {
        target: "display"
        function lid(state: string): void { mgr.setLid(state === "close" || state === "closed") }
        function reset(): void { mgr.resetDisplays() }
    }
    // shell (re)started with the lid already shut (docked boot) — sync from ACPI
    property Process _lidProbe: Process {
        running: true
        command: ["sh", "-c", "cat /proc/acpi/button/lid/*/state 2>/dev/null | head -1"]
        stdout: StdioCollector { onStreamFinished: { if (this.text.indexOf("closed") >= 0) mgr.lidClosed = true } }
    }

    // ── commit: save profile + regenerate monitors.lua + verify ──────────────
    property var _verifySpecs: null
    function commit(specs) {
        var key = keyFor(specs)
        var p = {}
        for (var k in profiles) p[k] = profiles[k]
        p[key] = specs
        profiles = p
        lastKey = key
        _saveProfiles()
        _writeMonitorsLua()
        _verifySpecs = specs
        _verifyT.restart()
    }
    function _saveProfiles() {
        var doc = { version: 1, lastKey: lastKey, profiles: profiles }
        atomicWrite(_profWriter, profilesPath, JSON.stringify(doc, null, 2))
    }
    function _writeMonitorsLua() {
        var s = "-- AUTO-GENERATED by Settings → Displays (Quickshell). Do not edit by hand.\n"
              + "-- Source of truth: ~/.config/quickshell/display-profiles.json — one profile\n"
              + "-- per connected-monitor set, keyed by the sorted output descriptions.\n"
              + "local profiles = {}\n"
        var keys = Object.keys(profiles).sort()
        for (var i = 0; i < keys.length; i++) {
            s += 'profiles["' + luaEsc(keys[i]) + '"] = {\n'
            var specs = profiles[keys[i]]
            for (var j = 0; j < specs.length; j++) s += "    " + luaArgs(specs[j]) + ",\n"
            s += "}\n"
        }
        s += '\n-- Fallback: at boot the monitor list may not be populated yet, so first\n'
           + '-- assert the last-committed profile unconditionally (desc: rules only bind\n'
           + '-- to outputs that are actually present)…\n'
           + 'local last = profiles["' + luaEsc(lastKey) + '"]\n'
           + "if last then for _, m in ipairs(last) do hl.monitor(m) end end\n"
           + "\n-- …then, when the connected set is known and a different profile matches it\n"
           + "-- (e.g. reload while undocked), let that profile win.\n"
           + "local names = {}\n"
           + "for _, m in ipairs(hl.get_monitors()) do\n"
           + '    local d = m.description\n'
           + '    if d == nil or d == "" then d = m.name end\n'
           + "    names[#names + 1] = d\n"
           + "end\n"
           + "table.sort(names)\n"
           + 'local prof = profiles[table.concat(names, " || ")]\n'
           + "if prof and prof ~= last then for _, m in ipairs(prof) do hl.monitor(m) end end\n"
        atomicWrite(_luaWriter, monitorsLua, s)
    }

    // ── verify: applied state must match the committed intent ────────────────
    function verifyAgainst(specs) {
        var bad = []
        for (var i = 0; i < specs.length; i++) {
            var s = specs[i]
            var m = null
            for (var j = 0; j < monitors.length; j++)
                if (matchId(specFromMonitor(monitors[j])) === matchId(s)) { m = monitors[j]; break }
            if (!m) { bad.push(matchId(s) + ": not present"); continue }
            if (s.disabled) { if (!m.disabled) bad.push(m.name + ": should be disabled"); continue }
            if (m.disabled) { bad.push(m.name + ": is disabled"); continue }
            var live = specFromMonitor(m)
            if (s.mirror !== "") { if (live.mirror !== s.mirror) bad.push(m.name + ": mirror not active"); continue }
            if (modeRes(live.mode) !== modeRes(s.mode)) bad.push(m.name + ": mode is " + modeRes(live.mode) + ", wanted " + modeRes(s.mode))
            else if (Math.abs(modeHz(live.mode) - modeHz(s.mode)) > 0.6) bad.push(m.name + ": " + modeHz(live.mode).toFixed(0) + "Hz, wanted " + modeHz(s.mode).toFixed(0) + "Hz")
            if (live.x !== s.x || live.y !== s.y) bad.push(m.name + ": position " + live.x + "," + live.y + ", wanted " + s.x + "," + s.y)
            if (Math.abs(live.scale - s.scale) > 0.011) bad.push(m.name + ": scale " + live.scale + ", wanted " + s.scale)
            if (live.transform !== s.transform) bad.push(m.name + ": rotation not applied")
        }
        return bad.join(" · ")
    }

    // ── re-assert (hotplug / AC transitions / escape hatch) ───────────────────
    // Apply the saved profile for the currently-connected set. `force` skips the
    // "already matches" check (used by Reset displays and power events, where a
    // blanked panel can still report healthy state).
    function applyMatching(force) {
        var key = currentKey()
        var prof = profiles[key]
        if (!prof) return
        if (!force && verifyAgainst(prof) === "") return
        applySpecs(prof)
    }
    // Re-assert against a FRESH monitor query. The hotplug/lid/AC handlers used
    // to call applyMatching() directly, but `monitors` is refreshed async — on
    // an unplug the stale list still contained the departed output, so the OLD
    // profile was re-applied, forcing a needless modeset on the panel (which
    // the xe driver's PSR path answers with a permanent black screen).
    property bool _assertPending: false
    property bool _assertForce: false
    function reassert(force) {
        _assertPending = true
        if (force) _assertForce = true
        refresh()
    }
    function resetDisplays() {
        // explicit escape hatch (screens are dark) — forcing dpms on is right
        // here; the dispatch arg must be Lua on this Hyprland (raw `dpms on`
        // errors — and used to fail silently, which is why Reset never worked)
        Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.dpms("on")'])
        reassert(true)
        _wallpaperReapply.restart()
    }
    // Wake only outputs that actually report dpms-off. NEVER dpms-cycle a
    // panel that is already on: on xe/Lunar Lake that alone can re-trigger the
    // PSR bug and black the screen (verified on hardware).
    property Process _dpmsGuard: Process {
        command: ["sh", "-c",
            "hyprctl monitors all -j 2>/dev/null | grep -q '\"dpmsStatus\": *false' && exec hyprctl dispatch 'hl.dsp.dpms(\"on\")'; exit 0"]
    }
    function wakeIfAsleep() { _dpmsGuard.running = false; _dpmsGuard.running = true }

    // ── plumbing ──────────────────────────────────────────────────────────────
    // The ONE atomic file writer (Settings uses it too): temp file + rename so a
    // crash mid-write can't corrupt config. The heredoc sentinel is distinctive
    // — no generated line (key=value, Lua code, indented JSON) can equal it.
    // Persistence is refused wholesale in a nested/test session: those share the
    // real $HOME, and a throwaway compositor's state must never overwrite the
    // user's config (live apply against the nested instance still works).
    function atomicWrite(proc, path, content) {
        if (_virtualSession()) { Log.info("display", "virtual session — skipped write to", path); return }
        proc.command = ["sh", "-c",
            'mkdir -p "$(dirname "$1")" && cat > "$1.tmp" <<\'HS_ATOMIC_EOF_7f3a\'\n' + content + '\nHS_ATOMIC_EOF_7f3a\nmv "$1.tmp" "$1"',
            "hyprmon", path]
        proc.running = false; proc.running = true
    }
    // a nested/headless test compositor (run-hypr-shell driver) exposes virtual
    // outputs — never let that session write the real user's config
    readonly property bool virtualSession: (monitors || []).some(function (m) { return /^(WAYLAND|HEADLESS)-/.test(m.name || "") })
    function _virtualSession() { return virtualSession }
    function _maybeStartupAssert() {
        if (_startupChecked || !_profLoaded || !_monLoaded) return
        _startupChecked = true
        if (_virtualSession()) return
        // first run (or migration from the old user.lua persistence): no saved
        // profiles yet → capture the current live layout as the initial
        // known-good profile so boot/hotplug re-assert has something to hold
        if (Object.keys(profiles).length === 0 && monitors.length > 0) { commit(snapshot()); return }
        applyMatching(false)   // correct any drift that happened before the shell was up
    }

    property Process _monProc: Process {
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { mgr.monitors = JSON.parse(this.text) } catch (e) { mgr.monitors = [] }
                mgr.loading = false
                mgr._monLoaded = true
                mgr._maybeStartupAssert()
                if (mgr._assertPending) {
                    mgr._assertPending = false
                    var f = mgr._assertForce; mgr._assertForce = false
                    mgr.applyMatching(f)
                    mgr._wallpaperReapply.restart()
                }
            }
        }
    }
    property Process _applyProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var err = this.text.trim()
                if (err !== "") mgr.lastError = err.split("\n")[0]
                mgr.applying = false
                var cb = mgr._applyDone; mgr._applyDone = null
                mgr._refreshT.restart()
                if (cb) cb(err === "")
            }
        }
    }
    property Process _profLoad: Process {
        command: ["sh", "-c", 'cat "$HOME/.config/quickshell/display-profiles.json" 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (j && j.profiles) mgr.profiles = j.profiles
                    if (j && j.lastKey) mgr.lastKey = j.lastKey
                } catch (e) {}
                mgr._profLoaded = true
                mgr._maybeStartupAssert()
            }
        }
    }
    property Process _profWriter: Process {}
    property Process _luaWriter: Process {}

    property Timer _refreshT: Timer { interval: 400; onTriggered: mgr.refresh() }
    property Timer _verifyT: Timer {
        interval: 900
        onTriggered: {
            if (!mgr._verifySpecs) return
            var bad = mgr.verifyAgainst(mgr._verifySpecs)
            mgr._verifySpecs = null
            if (bad !== "") mgr.lastError = "Applied state differs from requested: " + bad
        }
    }

    // hotplug: debounce, then re-assert the profile for the new set + give the
    // wallpaper backend a chance to cover a newly-added output.
    property Timer _hotplugT: Timer {
        interval: 800
        onTriggered: mgr.reassert(false)
    }
    property Timer _reassertT: Timer { interval: 500; onTriggered: mgr.reassert(false) }
    property Timer _wallpaperReapply: Timer {
        interval: 700
        // via Wallpaper so the freeze state is re-asserted afterwards — a hotplug
        // re-apply spawns a fresh, unpaused mpvpaper
        onTriggered: Wallpaper.reapply()
    }
    property Connections _hyprConn: Connections {
        target: Hyprland
        function onRawEvent(ev) {
            var n = ev.name
            if (n === "monitoradded" || n === "monitoraddedv2" || n === "monitorremoved") mgr._hotplugT.restart()
            else if (n === "configreloaded") mgr._refreshT.restart()
        }
    }
    // AC ↔ battery: the panel/driver may re-probe (and on xe/Lunar Lake, blank).
    // Wait out the re-probe, then RECOVER-ONLY: wake outputs that report
    // dpms-off and re-apply the profile only if the live state drifted from it.
    // (The old behaviour — unconditional dpms-cycle + forced re-apply on every
    // charger plug — was itself a blanking trigger on the xe PSR path.)
    property Timer _powerT: Timer {
        interval: 2500
        onTriggered: {
            mgr.wakeIfAsleep()
            mgr._powerAssertT.restart()
        }
    }
    property Timer _powerAssertT: Timer { interval: 600; onTriggered: mgr.reassert(false) }
    property Connections _powerConn: Connections {
        target: UPower
        function onOnBatteryChanged() { mgr._powerT.restart() }
    }
}
