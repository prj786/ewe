pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower

// Globals — shared, instant shell state (no IPC round-trip for in-shell toggles).
QtObject {
    id: g

    // ── power state — the hook every battery-aware behaviour hangs off ─────────
    // On this hardware (Lunar Lake) the display controller can stop reading from
    // memory entirely while the screen is static (Panel Self Refresh), so a timer
    // that wakes for nothing is not free — it costs real battery. Anything that
    // can be lazier on battery reads `lowPower`.
    readonly property bool onBattery: UPower.onBattery
    // plug/unplug feedback — guarded so the initial binding can't chime at login
    property bool _powerSoundReady: false
    property Timer _powerSoundArm: Timer { interval: 4000; running: true; onTriggered: g._powerSoundReady = true }
    onOnBatteryChanged: if (g._powerSoundReady) g.playSound(g.onBattery ? "power-unplug" : "power-plug")
    property bool lowPowerEnabled: true
    readonly property bool lowPower: onBattery && lowPowerEnabled

    // Lid policy (Lid.qml). Default: with an external monitor connected,
    // closing the lid keeps the session running and just blanks the built-in
    // panel — the Ubuntu/GNOME docked behaviour. Turn on to suspend anyway.
    property bool lidDockedSuspend: false

    // Project version — the shell's runtime copy. Keep in sync with the repo-root
    // VERSION file (the canonical source used for git tags / releases). Semver, with
    // an -alpha/-beta pre-release suffix until the first stable cut.
    readonly property string version: "0.9.10"

    // ── event sounds (GNOME-style; the freedesktop sound theme, one toggle) ──
    // playSound("message-new-instant") etc — names are theme event ids from
    // /usr/share/sounds/freedesktop/stereo. Missing theme = silent no-op.
    property bool eventSounds: true
    function playSound(name) {
        if (!g.eventSounds) return
        Quickshell.execDetached(["sh", "-c",
            'f="/usr/share/sounds/freedesktop/stereo/' + name + '.oga"; [ -r "$f" ] || exit 0; pw-play "$f" 2>/dev/null || paplay "$f" 2>/dev/null'])
    }

    property bool barVisible: true          // the top bar (Super+Shift+B toggles)
    property bool quickSettingsOpen: false  // the Quick Settings panel
    property bool dnd: false               // Do Not Disturb (suppresses toasts)
    property var server: null              // set by Notifications.qml (the live NotificationServer)
    property bool vpnActive: false         // any VPN connection up (bar shows a VPN glyph)
    property string netBusy: ""            // "wifi" | "vpn" while a connection attempt runs (bar spinner)
    property bool sshTunnelUp: false       // any background ssh -f -N tunnel from Quick Settings is up (bar shows a console glyph)
    property bool caffeine: false          // keep-awake: holds a wayland idle inhibitor (no lock/blank/sleep)
    // ── Cast to TV (RFC-004: ewe-castd owns the protocols, Cast.qml owns the
    //    socket, this is the shared truth the tile/bar/card all render) ──
    property string castState: "idle"      // idle·picking·connecting·waiting·negotiating·starting·streaming·error
    property string castDetail: ""         // one narrated line for the current state
    property string castSinkName: ""       // who we're casting to, while active
    property var castSinks: []             // [{id, name, kind}] — displays in range
    property bool castLegacy: false        // the gnome-network-displays fallback is up
    signal castCommand(string cmd, string arg)   // QS card → Cast.qml → daemon socket
    // derived: anything that makes the bar glyph and the tile light up
    readonly property bool casting: castLegacy || (castState !== "idle" && castState !== "error")
    property bool overviewOpen: false      // GNOME-style window overview (Super tapped alone)
    property bool clipboardOpen: false     // the clipboard-history / emoji popup (scissors icon)
    property bool settingsOpen: false      // the Quickshell Settings window (Super+, or the CC gear)
    // deep-link for the LAZY-loaded fallback panel: pane index, or -2 =
    // wallpaper pane + file chooser; the panel consumes and resets to -1
    property int settingsPaneRequest: -1
    property string openDd: ""             // ddId of the one open DropRow, shell-wide ("" = none)
    property real clipAnchorX: 40           // screen-local x of the scissors icon (clipboard opens under it)

    // ── Standalone first-party apps ───────────────────────────────────────────
    // Komble (the software manager) and ewe-settings (the Settings app) are
    // separate Tauri binaries installed by phase 20. When present they ARE the
    // store/settings UX — every entry point routes through openStore()/
    // openSettings() below — and the QML panels are only the fallback for a
    // machine where the build failed, so the desktop is never unconfigurable.
    // Probed once at startup: an install/removal is followed by a shell restart
    // (ewe.service) anyway, so a per-click probe would only add latency.
    // The settings binary was `hypr-settings` before the rename; keep launching
    // it on machines that still have the old package.
    property bool kombleInstalled: false
    property bool settingsAppInstalled: false
    property string settingsAppBin: "ewe-settings"
    // an already-open Settings/Komble window is FOCUSED, never doubled —
    // clicking the gear twice should land you on the window you had
    function focusWindowByClass(klass) {
        var tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (var i = 0; i < tls.length; i++) {
            var t = tls[i]
            var o = t.lastIpcObject
            var c = (o && (o.class || o.initialClass)) || (t.wayland && t.wayland.appId) || ""
            if (c.toLowerCase() !== klass) continue
            if (t.wayland) t.wayland.activate()
            else if (o && o.address) Hyprland.dispatch('hl.dsp.focus({ window = "address:' + o.address + '" })')
            return true
        }
        return false
    }
    function openSettings() {
        if (g.focusWindowByClass("ewe-settings") || g.focusWindowByClass("hypr-settings")) return
        if (g.settingsAppInstalled) Quickshell.execDetached([g.settingsAppBin])
        else g.settingsOpen = true
    }
    function openStore() {
        if (g.focusWindowByClass("komble")) return
        if (g.kombleInstalled) Quickshell.execDetached(["komble"])
        else g.storeOpen = true
    }
    // ── Focus-or-launch ────────────────────────────────────────────────────
    // Clicking an app that already has a window JUMPS to it (activate = focus
    // + workspace switch) instead of spawning a second instance — for
    // single-instance apps (Slack, Komble, browsers) a relaunch just pings the
    // existing process and looks like "nothing happened". Both launchers call
    // this first; middle-click still forces a fresh instance. Prefers the
    // window that was most recently active when an app has several.
    function activateAppWindow(entry) {
        if (!entry) return false
        var tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
        var best = null
        for (var i = 0; i < tls.length; i++) {
            var t = tls[i]
            var o = t.lastIpcObject
            var c = (o && (o.class || o.initialClass)) || (t.wayland && t.wayland.appId) || ""
            if (c === "") continue
            var e = DesktopEntries.heuristicLookup(c)
            if (!e || e.id !== entry.id) continue
            if (!best || t.activated) best = t
        }
        if (!best) return false
        if (best.wayland) best.wayland.activate()
        else if (best.address) Hyprland.dispatch('hl.dsp.focus({ window = "address:' + best.address + '" })')
        return true
    }

    property Process _standaloneProbe: Process {
        running: true
        command: ["sh", "-c", "command -v komble >/dev/null && printf k; command -v ewe-settings >/dev/null && printf s; command -v hypr-settings >/dev/null && printf o"]
        stdout: StdioCollector {
            onStreamFinished: {
                g.kombleInstalled = this.text.indexOf("k") >= 0
                g.settingsAppInstalled = this.text.indexOf("s") >= 0 || this.text.indexOf("o") >= 0
                if (this.text.indexOf("s") < 0 && this.text.indexOf("o") >= 0) g.settingsAppBin = "hypr-settings"
            }
        }
    }

    // ── System updates (the bar's Komble indicator) ───────────────────────────
    // The bar shows a permanent status glyph (check = current, download+count =
    // updates pending, spinner = a pacman transaction is running) fed by
    // scripts/updates-check.sh: checkupdates + paru -Qua + the db.lck probe.
    // Komble pokes `qs ipc call updates refresh` after every transaction it
    // runs, and while a transaction holds the lock the re-check tightens to 5 s
    // so the spinner clears the moment pacman does.
    property int updatesRepo: 0
    property int updatesAur: 0
    readonly property int updatesTotal: updatesRepo + updatesAur
    property bool updatesBusy: false
    // Komble raises this over IPC for the whole of a long upgrade — AUR builds
    // hold no pacman lock while makepkg runs, so db.lck alone would show
    // "updating" only for the final seconds. Auto-clears if Komble dies
    // mid-run and stops re-poking (it re-asserts before every package).
    property bool updatesWorking: false
    property Timer _updWorkTimeout: Timer {
        interval: 15 * 60 * 1000
        running: g.updatesWorking
        onTriggered: g.updatesWorking = false
    }
    function setUpdatesWorking(on) {
        g.updatesWorking = on
        if (on) { g._updWorkTimeout.restart() }
    }
    property Process _updProc: Process {
        command: ["bash", "-c", "exec \"$HOME/.config/quickshell/scripts/updates-check.sh\""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    g.updatesBusy = !!j.busy
                    if (j.error) {
                        // keep the last known counts; retry soon with backoff
                        // (30s, 60s, … up to 5 tries) instead of an hour later
                        if (g._updRetries < 5) {
                            g._updRetries++
                            g._updRetry.interval = 30 * 1000 * g._updRetries
                            g._updRetry.restart()
                        }
                        return
                    }
                    g._updRetries = 0
                    g.updatesRepo = j.repo || 0
                    g.updatesAur = j.aur || 0
                } catch (e) {}
            }
        }
    }
    property int _updRetries: 0
    property Timer _updRetry: Timer { onTriggered: g.checkUpdates() }
    // last known counts from the previous session, shown instantly at login —
    // the live check (60 s in) then confirms or corrects them
    property Process _updCachedProc: Process {
        running: true
        command: ["bash", "-c", "exec \"$HOME/.config/quickshell/scripts/updates-check.sh\" --cached"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    g.updatesRepo = j.repo || 0
                    g.updatesAur = j.aur || 0
                } catch (e) {}
            }
        }
    }
    function checkUpdates() { g._updProc.running = false; g._updProc.running = true }
    // first check a minute after login (let the network settle), then hourly;
    // 5 s while a transaction is live so "updating" ends when pacman does
    property Timer _updKick: Timer { interval: 60 * 1000; running: true; onTriggered: g.checkUpdates() }
    property Timer _updTimer: Timer {
        interval: g.updatesBusy ? 5000 : (g.lowPower ? 2 : 1) * 3600 * 1000
        running: true; repeat: true
        onTriggered: g.checkUpdates()
    }
    property IpcHandler _updIpc: IpcHandler {
        target: "updates"
        function refresh(): void { g.checkUpdates() }
        function count(): string { return String(g.updatesTotal) }
        // Komble: `qs ipc call updates working true|false` around upgrades
        function working(on: bool): void { g.setUpdatesWorking(on) }
    }

    // ── Shell look ────────────────────────────────────────────────────────────
    // "flock" (soft dark greys) or "blacksheep" (absolute-black surfaces) —
    // Theme.pitchBlack switches the five neutral surface tokens on this.
    // GTK apps follow too: any change re-runs colorscheme.sh, which reads
    // themeName back out of user-theme.json (covers the in-shell chips AND
    // ewe-settings, whose write lands here via the settings-reload poke).
    property string themeName: "flock"
    onThemeNameChanged: g.applyColorScheme()

    // ── User-chosen accent colour ─────────────────────────────────────────────
    // Single mutable source the Settings → Theme pane writes; Theme.accent binds to
    // it so the whole shell recolours live. Persisted to ~/.config/quickshell/
    // user-theme.json and re-read here at startup (default = system blue).
    property color accentColor: "#0a84ff"
    property bool tintBorders: false        // mirror window border colour to the accent
    // false → fully opaque windows (decoration inactive_opacity forced to 1.0);
    // true keeps hyprland.lua's subtle unfocused translucency. user-theme.json.
    property bool windowTransparency: true

    // Tiling on (the Hyprland default) vs every new window opening floating, for
    // people who want the DE to behave like GNOME/Unity rather than a tiling WM.
    // Implemented as a catch-all float window rule in hypr/generated/user.lua —
    // see Settings.tilingLua(). Persisted in user-theme.json.
    property bool tilingEnabled: true

    // Animation speed multiplier driving both the QML shell (Theme.dur*) and the
    // Hyprland window animations (Settings writes scaled hl.animation overrides).
    // 1.0 = default; >1 faster; 0 = animations off. Persisted in user-theme.json.
    property real animationSpeed: 1.0

    // ── App appearance (GTK + Qt) ──────────────────────────────────────────────
    // Dark-only by decision (2026-09-01): light mode was deleted, not shipped.
    // The property stays because user-theme.json's "colorScheme" key is read by
    // Komble to follow the DE's app colour scheme — it is always "dark"; a
    // persisted "light" is ignored on load. colorscheme.sh ignores its mode arg.
    property string colorScheme: "dark"
    property Process _csApply: Process {}
    function applyColorScheme() {
        var acc = String(Theme.accent).replace("#", "")
        g._csApply.command = ["sh", "-c", "\"$HOME/.config/quickshell/scripts/colorscheme.sh\" " + g.colorScheme + " " + acc]
        g._csApply.running = false; g._csApply.running = true
    }

    // ── Dock prefs (bottom dock; persisted in user-theme.json) ─────────────────
    property bool dockEnabled: true
    property bool dockAutohide: false       // intelligent hide: slide away, reveal on bottom-edge hover
    property string dockIconSize: "normal"  // dock icon size: "small" | "normal" | "large"

    // ── Screensaver (persisted in user-theme.json; hypridle owns the timing via
    // the generated hypridle.conf — see Settings.writeIdleConf) ────────────────
    property bool saverEnabled: false
    property int  saverMin: 5               // idle minutes before the saver appears
    property string saverStyle: "clock"     // "clock" | "blank"
    property bool saverLock: false          // true → idle goes straight to the session lock
    property int  saverLockAfterMin: 5      // saver mode: lock N min after the saver starts (0 = never)
    // runtime only: the session lock surface is up. Set by Lock.qml. Nothing in
    // the shell could condition on lock state before this existed — it was a
    // private bool inside one component.
    property bool locked: false
    property bool saverActive: false        // runtime only: the overlay is currently shown
    // runtime only: the pre-lock dim is showing. This is the grace period made
    // visible — the screen fades down a little before anything irreversible
    // happens, so "it's about to lock" is something you can see and cancel by
    // moving, rather than something you discover afterwards.
    property bool saverDimming: false

    // ── Dock popups ────────────────────────────────────────────────────────────
    property bool launcherOpen: false       // pinned-apps / launcher panel
    property bool storeOpen: false           // app-store panel
    property bool placesOpen: false          // places / directories panel (Home, Desktop, … + pinned folders)
    property bool mediaOpen: false           // now-playing popup (MediaPlayer.qml, above the dock's music button)
    property real launcherAnchorX: 200       // screen-local x of the launcher dock button (popup centers on it)
    property real storeAnchorX: 200          // screen-local x of the store dock button
    property real placesAnchorX: 200         // screen-local x of the places dock button
    property real mediaAnchorX: 200          // screen-local x of the media dock button
    property var  mediaPlayer: null          // active MPRIS player (resolved by MediaPlayer.qml; dock button shows iff non-null)

    // ── System-tray context menu (themed, rendered by TrayMenu.qml) ─────────────
    property bool trayMenuOpen: false
    property var  trayMenuHandle: null       // the clicked item's QsMenuHandle
    property real trayMenuAnchorX: 200       // screen-local x of the tray icon (menu centers on it)

    // ── RFC-001: every persist goes through ewe-conf, the ONE writer of the
    // ONE file. It rewrites ~/.config/ewe/ewe.conf and regenerates the runtime
    // JSON this shell reads — the shell never writes state files directly.
    // The path resolves through the config farm, so dev checkouts, tarball
    // installs and the package each reach their own copy; --no-hooks because
    // the shell live-applies itself and IS the thing the reload poke targets.
    readonly property string eweConf: Quickshell.env("HOME") + "/.config/quickshell/../../bin/ewe-conf"

    // ── Pinned apps (desktop ids; persisted via ewe-conf → apps.pinned) ───────
    property var pinnedApps: []
    function isPinned(id) { return (g.pinnedApps || []).indexOf(id) >= 0 }
    function togglePin(id) {
        var a = (g.pinnedApps || []).slice()
        var i = a.indexOf(id)
        if (i >= 0) a.splice(i, 1); else a.push(id)
        g.pinnedApps = a
        g._pinWriter.command = [g.eweConf, "set", "--no-hooks", "apps.pinned", JSON.stringify(a)]
        g._pinWriter.running = false; g._pinWriter.running = true
    }
    // ── Pinned places (folder paths; persisted in places.json) ────────────────
    // The Places panel always shows the standard XDG dirs; these are the EXTRA
    // folders the user pinned. Same pattern as pinnedApps.
    property var pinnedPlaces: []
    function isPinnedPlace(p) { return (g.pinnedPlaces || []).indexOf(p) >= 0 }
    function togglePinPlace(p) {
        if (!p) return
        var a = (g.pinnedPlaces || []).slice()
        var i = a.indexOf(p)
        if (i >= 0) a.splice(i, 1); else a.push(p)
        g.pinnedPlaces = a
        g._placesWriter.command = [g.eweConf, "set", "--no-hooks", "apps.places", JSON.stringify(a)]
        g._placesWriter.running = false; g._placesWriter.running = true
    }
    // Re-read every JSON state file this singleton owns — used after a settings
    // restore rewrites them on disk (Google.applyRestore), and by the `settings
    // reload` IPC verb after the out-of-process Settings app has written one.
    //
    // The reads are asynchronous, so anything depending on the NEW values must
    // wait for prefsReloaded rather than run on the next line: until the reader
    // has parsed the file, the accent is still the old one.
    signal prefsReloaded()
    property bool _reloadPending: false
    function reloadUserState() {
        g._reloadPending = true
        g._themeLoad.running = false; g._themeLoad.running = true
        g._pinLoad.running = false; g._pinLoad.running = true
        g._placesLoad.running = false; g._placesLoad.running = true
        g._animLoad.running = false; g._animLoad.running = true
        g.recheckFace()
    }

    // ── Animations pane state (animations.json, written by ewe-settings) ──────
    // The Hyprland side of that pane applies via generated/animations.lua; the
    // shell reads the SAME json so its own motion (Theme.dur* / Theme.ease)
    // follows the pane too. null while the file doesn't exist — Theme then
    // falls back to the legacy Settings → Theme speed multiplier.
    property var animPrefs: null
    property Process _animLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/animations.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    g.animPrefs = (j && typeof j === "object" && !Array.isArray(j)) ? j : null
                } catch (e) { g.animPrefs = null }
            }
        }
    }

    property Process _placesWriter: Process {}
    property Process _placesLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/places.json\" 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { try { var j = JSON.parse(this.text); if (Array.isArray(j)) g.pinnedPlaces = j } catch (e) {} } }
    }

    // ── Avatar (~/.face) — shared by Settings (account card) and the lock screen.
    // faceUrl is THE avatar image source everywhere: "" while no ~/.face exists,
    // and cache-busted (?v=) after Settings saves a new one.
    property bool hasFace: false
    property int avatarVersion: 0
    property string avatarShape: "circle"   // "circle" | "rounded" | "square" — Avatar.qml masks to this; persisted in user-theme.json
    readonly property string faceUrl: hasFace ? "file://" + Quickshell.env("HOME") + "/.face?v=" + avatarVersion : ""
    property Process _faceChk: Process { running: true; command: ["sh", "-c", 'test -f "$HOME/.face"']; onExited: function (code) { g.hasFace = (code === 0) } }
    function recheckFace() { g.avatarVersion++; g._faceChk.running = false; g._faceChk.running = true }

    // ── CPU / memory sampling (the Quick Settings meters) ─────────────────────
    // Sampled ONLY while the panel that shows it is open. This used to run at
    // 1.5 s for the whole session, spawning three processes per tick — roughly
    // 170k fork/exec a day — to feed two meters behind a closed panel and a
    // RunCat widget that was deleted in 191d969.
    property real cpuUsage: 0      // 0..1
    property real memUsage: 0      // 0..1
    property var _prevCpu: null
    // drop the baseline when we stop sampling, so the first tick after reopening
    // doesn't compute a delta across the whole closed period
    onQuickSettingsOpenChanged: if (!g.quickSettingsOpen) g._prevCpu = null
    property Process _statProc: Process {
        command: ["sh", "-c", "head -1 /proc/stat; echo SEP; grep -E 'MemTotal|MemAvailable' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parts = this.text.split("SEP")
                    var nums = parts[0].trim().split(/\s+/).slice(1).map(Number)
                    var idle = (nums[3] || 0) + (nums[4] || 0)
                    var total = 0; for (var i = 0; i < nums.length; i++) total += (nums[i] || 0)
                    if (g._prevCpu) { var dt = total - g._prevCpu.total, di = idle - g._prevCpu.idle; if (dt > 0) g.cpuUsage = Math.max(0, Math.min(1, (dt - di) / dt)) }
                    g._prevCpu = { total: total, idle: idle }
                    var mt = 0, ma = 0, ml = (parts[1] || "").split("\n")
                    for (var j = 0; j < ml.length; j++) { if (ml[j].indexOf("MemTotal") >= 0) mt = parseInt(ml[j].replace(/\D/g, "")); else if (ml[j].indexOf("MemAvailable") >= 0) ma = parseInt(ml[j].replace(/\D/g, "")) }
                    if (mt > 0) g.memUsage = Math.max(0, Math.min(1, (mt - ma) / mt))
                } catch (e) {}
            }
        }
    }
    property Timer _statTimer: Timer {
        interval: g.lowPower ? 3000 : 1500
        running: g.quickSettingsOpen
        repeat: true; triggeredOnStart: true
        onTriggered: g._statProc.running = true
    }

    property Process _pinWriter: Process {}
    property Process _pinLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/pinned-apps.json\" 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { try { var j = JSON.parse(this.text); if (Array.isArray(j)) g.pinnedApps = j } catch (e) {} } }
    }

    // The last parsed contents of user-theme.json, verbatim.
    //
    // The shell is no longer the only writer of that file: the standalone Settings
    // app writes it too, and a newer Settings knows keys this shell does not. Kept
    // so writePrefs() can merge into it — a writer that emits only the keys it
    // knows would silently delete everyone else's.
    property var prefsRaw: ({})

    property Process _themeLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/user-theme.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (j && typeof j === "object" && !Array.isArray(j)) g.prefsRaw = j
                    // themeName: only the known looks are read back — anything
                    // else in the file is legacy (graphite/ambiance) and falls
                    // through to the "flock" default
                    if (j && (j.themeName === "flock" || j.themeName === "blacksheep")) g.themeName = j.themeName
                    if (j && j.accent) g.accentColor = j.accent
                    if (j && j.tintBorders !== undefined) g.tintBorders = j.tintBorders
                    if (j && j.windowTransparency !== undefined) g.windowTransparency = j.windowTransparency
                    if (j && j.dockEnabled !== undefined) g.dockEnabled = j.dockEnabled
                    if (j && j.dockAutohide !== undefined) g.dockAutohide = j.dockAutohide
                    if (j && j.dockIconSize) g.dockIconSize = j.dockIconSize
                    if (j && j.animationSpeed !== undefined) g.animationSpeed = j.animationSpeed
                    // dark-only by decision (2026-09-01): a persisted "light" is ignored
                    if (j && j.avatarShape) g.avatarShape = j.avatarShape
                    if (j && j.lidDockedSuspend !== undefined) g.lidDockedSuspend = j.lidDockedSuspend
                    if (j && j.lowPowerEnabled !== undefined) g.lowPowerEnabled = j.lowPowerEnabled
                    if (j && j.tilingEnabled !== undefined) g.tilingEnabled = j.tilingEnabled
                    if (j && j.eventSounds !== undefined) g.eventSounds = j.eventSounds
                    if (j && j.saver) {
                        if (j.saver.enabled !== undefined) g.saverEnabled = j.saver.enabled
                        if (j.saver.min !== undefined) g.saverMin = j.saver.min
                        if (j.saver.style) g.saverStyle = j.saver.style
                        if (j.saver.lock !== undefined) g.saverLock = j.saver.lock
                        if (j.saver.lockAfterMin !== undefined) g.saverLockAfterMin = j.saver.lockAfterMin
                    }
                } catch (e) {}
                // enforce the persisted (or default-dark) appearance on GTK + Qt
                g.applyColorScheme()
                // Only on an explicit reload: at startup every consumer is being
                // constructed anyway, and firing this then would re-apply the
                // Hyprland border on every login for no reason.
                if (g._reloadPending) { g._reloadPending = false; g.prefsReloaded() }
            }
        }
    }
}
