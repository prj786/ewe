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
//     (hotplug), on UPower AC↔battery transitions (the xe/Lunar Lake driver
//     can re-probe and blank the panel on charger plug/unplug — re-applying the
//     saved config recovers it; if the panel still blanks, that part is the
//     kernel driver (PSR), not the shell) and on resume — and a re-assert
//     touches ONLY the outputs whose live state differs from the profile
//     (applyMatching): every hl.monitor() is a potential modeset, and on xe a
//     modeset of a healthy panel is a blink at best.
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
    // One monitors query in flight at a time. A refresh() while one is running
    // does NOT restart the process (that would kill it, and a killed process
    // may never deliver its stream — every callback waiting on it would be
    // lost); it marks the result stale, and a second query runs when the first
    // lands, so callers always get data at least as fresh as their request.
    property bool _refreshAgain: false
    property var _queryCbs: []
    function refresh() {
        if (loading) { _refreshAgain = true; return }
        loading = true
        _monProc.running = false; _monProc.running = true
    }
    // query(cb): refresh, then cb(monitors) once the fresh list is in. This is
    // how anything that must act on LIVE state (Lid._open, the re-assert) asks
    // — `monitors` alone is whatever the last query returned, which after a
    // suspend or an unplug is a lie.
    function query(cb) { if (cb) _queryCbs = _queryCbs.concat([cb]); refresh() }
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
    // Name of the primary output (a shell concept — see snapshot()). The dock
    // pins itself to this screen. Re-evaluates when monitors/profiles change.
    readonly property string primaryName: {
        var s = snapshot()
        for (var i = 0; i < s.length; i++) if (s[i].primary && !s[i].disabled) return s[i].name
        return s.length ? s[0].name : ""
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
        // always explicit: omitting bitdepth would leave a live 10-bit output at 10
        L += ", bitdepth = " + (s.bitdepth === 10 ? 10 : 8)
        if (s.mirror !== "") L += ', mirror = "' + luaEsc(s.mirror) + '"'
        return L + " }"
    }

    // ── live apply (with error capture) ───────────────────────────────────────
    // runEvals is the ONE hyprctl-eval runner in the shell (Settings uses it
    // too): runs each single-line Lua statement, and any non-`ok` reply lands
    // in lastError. One batch in flight at a time; a batch that arrives while
    // another runs is QUEUED, not substituted — restarting the Process killed
    // the running `sh` mid-loop, and a half-applied batch is a half-set layout.
    property var _applyDone: null
    property var _evalQueue: []
    property var _running: []           // the statements of the batch in flight
    function runEvals(stmts, done) {
        if (!stmts || !stmts.length) { if (done) done(false); return }
        if (applying) {
            // Identical statements already running or queued are dropped: the
            // resume re-assert and Lid._open can both decide to re-enable the
            // same blanked panel with the same saved spec in the same tick,
            // and issuing one hl.monitor() twice is one modeset too many.
            var seen = _running.slice()
            for (var q = 0; q < _evalQueue.length; q++) seen = seen.concat(_evalQueue[q].stmts)
            var fresh = stmts.filter(function (s) { return seen.indexOf(s) < 0 })
            if (!fresh.length) { if (done) done(true); return }
            _evalQueue = _evalQueue.concat([{ stmts: fresh, done: done || null }])
            return
        }
        var cmd = ["sh", "-c",
            'st=0; for s in "$@"; do out=$(hyprctl eval "$s" 2>&1); case "$out" in ok*) ;; *) echo "$out"; st=1;; esac; done; exit $st',
            "hyprmon"]
        for (var i = 0; i < stmts.length; i++) cmd.push(stmts[i])
        _applyDone = done || null
        _running = stmts.slice()
        applying = true
        _applyProc.command = cmd
        _applyProc.running = false; _applyProc.running = true
    }
    // clamshell: while the lid is closed the internal panel must STAY off — a
    // profile re-assert (hotplug/AC/idle events) would otherwise relight the
    // panel inside the closed lid. This is the one place that rule lives.
    function effectiveSpecs(specs) {
        return specs.map(function (s) {
            return (mgr.lidClosed && mgr.isInternal(s.name)) ? { desc: s.desc, name: s.name, disabled: true } : s
        })
    }
    // last-ditch guard: a profile that would turn off EVERY output leaves no
    // way to recover but a blind reboot — refuse it outright
    function _refuseAllDark(eff, done) {
        if (!eff.every(function (s) { return s.disabled })) return false
        mgr.lastError = "Refused to apply: profile would disable every display"
        if (done) done(false)
        return true
    }
    // Apply a whole layout (Settings → Displays: the user asked for exactly
    // this). The re-assert paths do NOT use this — see applyMatching.
    function applySpecs(specs, done) {
        if (!specs || !specs.length) { if (done) done(false); return }
        var eff = effectiveSpecs(specs)
        if (_refuseAllDark(eff, done)) return
        runEvals(eff.map(function (s) { return "hl.monitor(" + luaArgs(s) + ")" }), done)
    }

    // ── clamshell (lid) state — lid.sh reports via `qs ipc call display lid …`
    property bool lidClosed: false
    function isInternal(name) { return /^(eDP|LVDS|DSI)/.test(String(name || "")) }
    function setLid(closed) {
        lidClosed = closed
        // Reopened: Lid._open() re-enables the panel — only if it is actually
        // off, and with its SAVED spec. There is no blanket re-assert here any
        // more: the one that used to fire 500 ms later existed to repair the
        // preferred/auto geometry _open used to issue, and on a laptop that
        // slept alone it re-applied a layout nothing had changed — one more
        // modeset, one more blink of the lock screen (2026-10-04).
    }
    property IpcHandler _displayIpc: IpcHandler {
        target: "display"
        function lid(state: string): void { mgr.setLid(state === "close" || state === "closed") }
        function reset(): void { mgr.resetDisplays() }
    }
    // The lid switch, from ACPI — the one source that cannot be stale. lid.sh
    // reports EVENTS, and events get missed: the shell is restarted with the
    // lid shut (docked boot), or the machine hibernates and resumes with the
    // lid open while `lidClosed` still says closed from before the sleep. That
    // stale flag is how 4 of 7 hibernate resumes went straight back to sleep
    // (Lid's grace timers fired instantly after the resume and believed it).
    // So: re-runnable, sets the state BOTH ways, and every path that acts on
    // lid state (the re-assert, Lid's grace timers, the resume routine) asks
    // it first — probeLid(cb) → cb(closed). No lid file (desktop) = no change.
    property var _lidCbs: []
    property bool _lidProbing: true     // the startup run below is in flight
    function probeLid(cb) {
        if (cb) _lidCbs = _lidCbs.concat([cb])
        if (_lidProbing) return
        _lidProbing = true
        _lidProbe.running = false; _lidProbe.running = true
    }
    property Process _lidProbe: Process {
        running: true
        command: ["sh", "-c", "cat /proc/acpi/button/lid/*/state 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text
                if (t.indexOf("closed") >= 0) mgr.lidClosed = true
                else if (t.indexOf("open") >= 0) mgr.lidClosed = false
                mgr._lidProbing = false
                var cbs = mgr._lidCbs; mgr._lidCbs = []
                for (var i = 0; i < cbs.length; i++) cbs[i](mgr.lidClosed)
            }
        }
    }
    // The saved profile's entry for a LIVE monitor (null when this monitor
    // set has no profile, or the entry is missing) — the exact mode, scale and
    // position to bring an output back with. Never preferred/auto for a
    // configured output: on the 1.8-scaled eDP that is a visible re-layout.
    function savedSpecFor(m) {
        var prof = profiles[currentKey()]
        if (!prof) return null
        var id = matchId(specFromMonitor(m))
        for (var i = 0; i < prof.length; i++) if (matchId(prof[i]) === id) return prof[i]
        return null
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
        // RFC-001: persist through ewe-conf (desktop.displays) — it
        // regenerates display-profiles.json for every reader of that file.
        _profWriter.command = [Globals.eweConf, "set", "--no-hooks", "desktop.displays", JSON.stringify(doc)]
        _profWriter.running = false; _profWriter.running = true
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
    // verifyOne(spec) → "" when the live output matches, else what differs.
    // `s.mirror`/`s.mode` may be absent on a lid-mapped {disabled:true} stub,
    // which is why the disabled checks come first.
    function verifyOne(s) {
        var m = null
        for (var j = 0; j < monitors.length; j++)
            if (matchId(specFromMonitor(monitors[j])) === matchId(s)) { m = monitors[j]; break }
        if (!m) return matchId(s) + ": not present"
        if (s.disabled) return m.disabled ? "" : m.name + ": should be disabled"
        if (m.disabled) return m.name + ": is disabled"
        var live = specFromMonitor(m), bad = []
        if (s.mirror !== "") return live.mirror !== s.mirror ? m.name + ": mirror not active" : ""
        if (modeRes(live.mode) !== modeRes(s.mode)) bad.push(m.name + ": mode is " + modeRes(live.mode) + ", wanted " + modeRes(s.mode))
        else if (Math.abs(modeHz(live.mode) - modeHz(s.mode)) > 0.6) bad.push(m.name + ": " + modeHz(live.mode).toFixed(0) + "Hz, wanted " + modeHz(s.mode).toFixed(0) + "Hz")
        if (live.x !== s.x || live.y !== s.y) bad.push(m.name + ": position " + live.x + "," + live.y + ", wanted " + s.x + "," + s.y)
        if (Math.abs(live.scale - s.scale) > 0.011) bad.push(m.name + ": scale " + live.scale + ", wanted " + s.scale)
        if (live.transform !== s.transform) bad.push(m.name + ": rotation not applied")
        return bad.join(" · ")
    }
    function verifyAgainst(specs) {
        var bad = []
        for (var i = 0; i < specs.length; i++) { var b = verifyOne(specs[i]); if (b !== "") bad.push(b) }
        return bad.join(" · ")
    }

    // ── re-assert (hotplug / AC transitions / escape hatch) ───────────────────
    // Bring the saved profile for the currently-connected set back — touching
    // ONLY the outputs whose live state differs from it. Every hl.monitor() is
    // a potential modeset, and on xe/Lunar Lake a modeset of a healthy panel is
    // a blink at best (the lock screen re-lays out) and the PSR black screen at
    // worst; re-issuing the whole profile because ONE output drifted (DP-1
    // re-enumerating after every resume) was exactly that. `force` applies
    // every output regardless (Reset displays: a blanked panel can still
    // report healthy state, and the user pressed the button for a reason).
    function applyMatching(force) {
        var prof = profiles[currentKey()]
        if (!prof) return
        var eff = effectiveSpecs(prof)
        if (_refuseAllDark(eff, null)) return
        var todo = force ? eff : eff.filter(function (s) { return verifyOne(s) !== "" })
        if (!todo.length) { Log.debug("display", "re-assert: every output matches the saved profile — nothing to apply"); return }
        Log.info("display", "re-assert:", todo.map(function (s) { return s.name + (force ? "" : " (" + verifyOne(s) + ")") }).join(", "))
        runEvals(todo.map(function (s) { return "hl.monitor(" + luaArgs(s) + ")" }), null)
    }
    // Re-assert against a FRESH lid state and a FRESH monitor query. The
    // hotplug/lid/AC handlers used to call applyMatching() directly, but
    // `monitors` is refreshed async — on an unplug the stale list still
    // contained the departed output, so the OLD profile was re-applied,
    // forcing a needless modeset on the panel (which the xe driver's PSR path
    // answers with a permanent black screen). The lid is re-read first because
    // the profile's EFFECTIVE shape depends on it: a resume with `lidClosed`
    // stale-true disabled the panel the user had just opened, and Lid._open
    // re-enabled it a moment later — two modesets instead of none.
    property bool _assertPending: false
    property bool _assertForce: false
    function reassert(force) {
        _assertPending = true
        if (force) _assertForce = true
        probeLid(function () { mgr.refresh() })
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
    // `after` (optional) is a shell command run once the file is in place. It runs
    // in the SAME sh as the write because there is no completion signal to hang a
    // second Process off — two processes would race, and `hyprctl reload` losing
    // that race re-reads the old file and silently discards the change.
    function atomicWrite(proc, path, content, after) {
        if (_virtualSession()) { Log.info("display", "virtual session — skipped write to", path); return }
        proc.command = ["sh", "-c",
            'mkdir -p "$(dirname "$1")" && cat > "$1.tmp" <<\'HS_ATOMIC_EOF_7f3a\'\n' + content + '\nHS_ATOMIC_EOF_7f3a\nmv "$1.tmp" "$1"'
            + (after ? " && " + after : ""),
            "hyprmon", path]
        proc.running = false; proc.running = true
    }
    // a nested/headless test compositor (run-ewe driver) exposes virtual
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
                // a refresh() landed while this query ran: its result is
                // already stale — run once more and deliver THAT one
                if (mgr._refreshAgain) { mgr._refreshAgain = false; mgr.refresh(); return }
                mgr._monLoaded = true
                mgr._maybeStartupAssert()
                if (mgr._assertPending) {
                    mgr._assertPending = false
                    var f = mgr._assertForce; mgr._assertForce = false
                    mgr.applyMatching(f)
                    mgr._wallpaperReapply.restart()
                }
                var cbs = mgr._queryCbs; mgr._queryCbs = []
                for (var i = 0; i < cbs.length; i++) cbs[i](mgr.monitors)
            }
        }
    }
    property Process _applyProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var err = this.text.trim()
                if (err !== "") mgr.lastError = err.split("\n")[0]
                mgr.applying = false
                mgr._running = []
                var cb = mgr._applyDone; mgr._applyDone = null
                mgr._refreshT.restart()
                if (cb) cb(err === "")
                if (mgr._evalQueue.length) { var q = mgr._evalQueue; mgr._evalQueue = q.slice(1); mgr.runEvals(q[0].stmts, q[0].done) }
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
