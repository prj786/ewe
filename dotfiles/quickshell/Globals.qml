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
    readonly property string version: "0.51.0-beta"

    // ── event sounds (GNOME-style; the freedesktop sound theme, one toggle) ──
    // playSound("message-new-instant") etc — names are theme event ids from
    // /usr/share/sounds/freedesktop/stereo. Missing theme = silent no-op.
    property bool eventSounds: true
    // Game mode (0.42, [desktop.game] via user-theme.json): the level a
    // manual or automatic start uses, and whether a game window starts it
    // (GameMode.qml; bin/ewe-game does the work)
    property string gameLevel: "ultra"
    property bool gameAuto: true
    function playSound(name) {
        if (!g.eventSounds) return
        Quickshell.execDetached(["sh", "-c",
            'f="/usr/share/sounds/freedesktop/stereo/' + name + '.oga"; [ -r "$f" ] || exit 0; pw-play "$f" 2>/dev/null || paplay "$f" 2>/dev/null'])
    }

    property bool barVisible: true          // the top bar (Super+Shift+B toggles)
    property bool quickSettingsOpen: false  // the Quick Settings panel
    // "open Quick settings ON this tab" for components outside the panel
    // (Shell.openQuickSettings, add-on pages); QuickSettings.qml listens
    signal quickSettingsTabRequested(string name)
    function openQuickSettingsTab(name) { g.quickSettingsOpen = true; g.quickSettingsTabRequested(name) }
    property bool dnd: false               // Do Not Disturb (suppresses toasts)
    property var server: null              // set by Notifications.qml (the live NotificationServer)
    property string netBusy: ""            // "wifi" (or "vpn", set by the VPN add-on) while a connection attempt runs (bar spinner)
    property int netEpoch: 0               // bumped by NetState on every NetworkManager event (nmcli monitor) — panels re-read on change
    property bool overviewOpen: false      // the Overview: every window spread out (Super tapped alone)
    // "open the app launcher searching for <query>" — the Overview's
    // public `find` verb lands here since the search left it; Launcher.qml listens
    signal launcherFind(string query)
    property bool overviewCover: false     // the Overview owns the screen: backdrop up, bar (and a dock add-on) out of view (Overview.qml sequences it)
    property bool widgetsArrange: false    // desktop widgets in arrange mode (Super+Shift+W): frames with pinned/lock/hide chips
    property bool settingsOpen: false      // the Quickshell Settings window (Super+, or the CC gear)
    // the first-run Welcome overlay is up — Google.qml holds every auto-push
    // while it is (a fresh machine must never upload over the backup it is
    // about to restore; 0.9.16-2)
    property bool welcomeOpen: false
    // deep-link for the LAZY-loaded fallback panel: pane index, or -2 =
    // wallpaper pane + file chooser; the panel consumes and resets to -1
    property int settingsPaneRequest: -1
    property string openDd: ""             // ddId of the one open DropRow, shell-wide ("" = none)

    // ── Toasts (design system: Toast) ─────────────────────────────────────────
    // Toast.qml registers itself here so any component can confirm an action
    // it just took and offer one way back, without reaching for a notification:
    //   Globals.toast("Moved <b>report.pdf</b> to Trash",
    //                 { actionLabel: "Undo", action: function () { … } })
    // Out-of-process callers use `qs ipc call toast show|action|undo|hide`.
    property var toastHost: null
    function toast(message, opts) { if (toastHost) toastHost.show(message, opts) }

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
    // clicking the gear twice should land you on the window you had. Goes
    // through focusAppWindow (by address), so the window's workspace comes
    // with it.
    function focusWindowByClass(klass) { return g.focusAppWindow([klass]) }
    // ── ewe-sync state (RFC-006) ──────────────────────────────────────────
    // The account app owns the state machine; it pokes the value in here on
    // every change (qs ipc call sync state …), the same out-of-process
    // contract ewe-conf and ewe-settings use. The bar renders it so "is my
    // stuff safe" is answerable without opening anything.
    //   "" (unknown, nothing reported yet) · signed-out · offline
    //   · syncing · conflict · idle
    property string syncState: ""
    property string syncDetail: ""

    // ── Launching a .desktop entry ────────────────────────────────────────
    // Quickshell's DesktopEntry.execute() ignores Terminal=true, so every
    // console app in the launcher (micro, htop, anything TUI) appeared to do
    // nothing at all when clicked — the process started, wrote to a terminal
    // that did not exist, and died. Route those through kitty instead.
    //
    // `command` is the already-parsed argv, which is what we want: re-parsing
    // execString would have to redo %f/%U field-code removal that Quickshell
    // has done for us. Everything else takes the normal path.
    function launchEntry(e, fresh) {
        if (!e) return
        if (!fresh && g.activateAppWindow(e)) return
        g.markLaunch(e.runInTerminal ? "kitty" : (e.startupClass || e.id))
        if (e.runInTerminal) {
            var argv = ["kitty"]
            if (e.workingDirectory) argv = argv.concat(["--directory", e.workingDirectory])
            Quickshell.execDetached(argv.concat(["-e"]).concat(e.command))
            return
        }
        e.execute()
    }

    // ── "You asked for this window" ───────────────────────────────────────
    // Tells the compositor a launch is the user's own, so the window it opens
    // follows a Window Rules workspace and takes the user along
    // (workspaces.lua, "Launches you asked for"); windows an app opens by
    // itself — Steam's toasts — go to their workspace quietly. A Lua function
    // through the dispatch socket: no process. `hint` names the app whose
    // window spends the launch (StartupWMClass, desktop id or binary) — kept
    // to [A-Za-z0-9._-], so a desktop id can never become Lua.
    // here = true: open it on THIS workspace, whatever a Window Rule says
    // ("Open terminal here"; workspaces.lua M.launched)
    function markLaunch(hint, here) {
        var h = String(hint || "").replace(/[^A-Za-z0-9._-]/g, "")
        Hyprland.dispatch('function() if ewe_launched then ewe_launched("' + h + '"' + (here === true ? ', true' : '') + ') end end')
    }

    function openSettings() {
        if (g.focusWindowByClass("ewe-settings") || g.focusWindowByClass("hypr-settings")) return
        if (g.settingsAppInstalled) { g.markLaunch(g.settingsAppBin); Quickshell.execDetached([g.settingsAppBin]) }
        else g.settingsOpen = true
    }
    function openStore() {
        if (g.focusWindowByClass("komble")) return
        if (g.kombleInstalled) { g.markLaunch("komble"); Quickshell.execDetached(["komble"]) }
        else g.storeOpen = true
    }
    // ewe-sync (RFC-006): the account app — your machines, folders, conflicts.
    // Focus-or-launch like the others; nothing in-shell to fall back to, the
    // shell's own account cards stay for the sync of the one file.
    property bool syncAppInstalled: false
    function openSync() {
        if (g.focusWindowByClass("ewe-sync")) return
        if (g.syncAppInstalled) { g.markLaunch("ewe-sync"); Quickshell.execDetached(["ewe-sync"]) }
    }
    // ── Focus-or-launch ────────────────────────────────────────────────────
    // Clicking an app that already has a window JUMPS to it (focus +
    // workspace switch) instead of spawning a second instance — for
    // single-instance apps (Slack, Komble, browsers) a relaunch just pings the
    // existing process and looks like "nothing happened". Every launcher
    // calls this first; middle-click still forces a fresh instance. Prefers
    // the window that was most recently focused when an app has several.
    function activateAppWindow(entry) {
        if (!entry || !entry.id) return false
        return g.focusAppWindow([entry.id])
    }

    // ── Focus the window a notification came from ─────────────────────────
    // `names` are the notification's desktop entry and app name. A client
    // matches when its class (or Wayland app id) is one of them, their last
    // dotted segment ("org.kde.kdeconnect" → "kdeconnect"), or resolves to
    // the same desktop entry — all case-insensitive. The most recently
    // focused match wins, and focusing it by address switches to its
    // workspace. (This used to be `hyprctl dispatch focuswindow class:…`,
    // the pre-Lua dispatcher syntax, which the Lua config rejects — so a
    // click on a notification from another workspace did nothing.)
    function focusAppWindow(names) {
        var want = [], ids = []
        for (var i = 0; i < names.length; i++) {
            var n = String(names[i] || "").toLowerCase()
            if (n === "") continue
            want.push(n)
            var seg = n.split(".").pop().replace(/[^a-z0-9_-]/g, "")
            if (seg !== "" && seg !== n) want.push(seg)
            // the same answer the dock and Overview give a window's class, so
            // launching "Dota 2" (class steam_app_570) or a Komble AppImage
            // (komble-google-chrome, class google-chrome) finds its window
            var de = g.entryForClass(names[i])
            if (de && de.id) ids.push(String(de.id).toLowerCase())
        }
        if (want.length === 0) return false
        var tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
        var best = null, bestRank = 1e9
        for (var j = 0; j < tls.length; j++) {
            var t = tls[j], o = t.lastIpcObject
            var c = String((o && (o.class || o.initialClass)) || (t.wayland && t.wayland.appId) || "").toLowerCase()
            if (c === "") continue
            var hit = want.indexOf(c) >= 0 || want.indexOf(c.split(".").pop()) >= 0
            if (!hit && ids.length) {
                var ce = g.entryForClass(c)
                hit = !!(ce && ce.id && ids.indexOf(String(ce.id).toLowerCase()) >= 0)
            }
            if (!hit) continue
            // focusHistoryID: 0 is the window focused last
            var rank = (o && o.focusHistoryID !== undefined) ? o.focusHistoryID : (t.activated ? -1 : 1e8)
            if (!best || rank < bestRank) { best = t; bestRank = rank }
        }
        if (!best) return false
        return g.focusToplevel(best)
    }
    // ── Phone notifications (KDE Connect → ewe Mobile) ────────────────────
    // kdeconnectd posts each phone notification through the ordinary server
    // (contract C5). It is the phone's when it carries the phone's name
    // (`x-kdeconnect-source-device` / `x-kde-origin-name`), or comes from the
    // daemon's desktop entry / the app name "KDE Connect" (pairing, calls,
    // files). Returns null for any other notification, else
    //   app    the phone app's name (`x-kde-display-appname`), else "ewe Mobile"
    //          — a phone card never says "KDE Connect"
    //   phone  the phone's name for the chip ("Phone" when the daemon sent none)
    //   key    what a group is keyed by: phone + app
    //   icon   the notification's own picture (the phone app's icon), else ewe
    //          Mobile's icon, else "" (the tile shows the phone glyph). Never
    //          the notification's appIcon: for the daemon's own ones (pairing,
    //          calls, files) that is KDE Connect's logo. (A near-black
    //          single-colour glyph from an old phone build is not tinted:
    //          QML cannot read pixels cheaply.)
    function phoneNote(n) {
        if (!n) return null
        var h = {}
        try { h = n.hints || {} } catch (e) {}
        var dev = String(h["x-kdeconnect-source-device"] || "")
        var origin = String(h["x-kde-origin-name"] || "")
        var de = String(n.desktopEntry || "")
        var from = dev !== "" || origin !== "" || de === "org.kde.kdeconnect.daemon" || String(n.appName || "") === "KDE Connect"
        if (!from) return null
        var app = String(h["x-kde-display-appname"] || "")
        var phone = origin !== "" ? origin : dev !== "" ? dev : "Phone"
        return { app: app !== "" ? app : "ewe Mobile", phone: phone, key: phone + "\u001f" + (app !== "" ? app : "ewe Mobile"),
                 icon: g.hasPicture(n) ? String(n.image) : g.phoneAppIcon() }
    }
    // Quickshell hands the app's THEME icon back as `image` ("image://icon/kdeconnect")
    // when the notification has no picture of its own; that is no picture.
    function hasPicture(n) {
        var i = n && n.image ? String(n.image) : ""
        return i !== "" && i.indexOf("image://icon/") !== 0
    }
    function phoneAppIcon() {
        var e = g.entryForClass("ewe-mobile")
        if (!e || !e.icon) return ""
        // C4's entries carry an absolute icon path: a file, not a theme name
        return String(e.icon).charAt(0) === "/" ? "file://" + e.icon : Quickshell.iconPath(e.icon, true)
    }
    // What a group of notifications is called, and what it is keyed by
    function noteAppName(n) { var p = g.phoneNote(n); return p ? p.app : String(n.appName || "Notification") }
    function noteGroupKey(n) { var p = g.phoneNote(n); return p ? p.key : String(n.appName || "Notification") }
    // A click on a phone card: ewe Mobile's notifications page when that app is
    // installed, else the Mobile page of Quick settings when the ewe.phone
    // add-on is, else nothing (the caller dismisses). Returns "app", "page" or "".
    function openPhoneNotification() {
        if (g.entryForClass("ewe-mobile")) {
            Quickshell.execDetached(["ewe-mobile", "--page", "notifications"])
            return "app"
        }
        var ps = PluginHost.quickPages || []
        for (var i = 0; i < ps.length; i++)
            if (ps[i].key === "mobile") { g.openQuickSettingsTab("mobile"); return "page" }
        return ""
    }

    // ── A click on a notification (banner or Quick settings list) ─────────
    // Goes to the most recent window of the app, wherever it is, then fires
    // the app's "default" action (opens the message/thread) — after the
    // focus, so the app acts on the now-current window. GNOME's rule for the
    // rest: a notification with no action of its own opens its app. An app
    // hidden in the tray (Komble, Slack, Steam) has no window to focus, so
    // the click used to do nothing. Only the sender's own desktop-entry hint
    // is trusted — a fuzzy match on the app NAME could start something else.
    function openNotification(n) {
        if (!n) return ""
        if (g.phoneNote(n)) return g.openPhoneNotification()
        var had = g.focusAppWindow([n.desktopEntry, n.appName])
        var acted = false
        try {
            if (n.actions) for (var i = 0; i < n.actions.length; i++)
                if (n.actions[i].identifier === "default") { n.actions[i].invoke(); acted = true; break }
        } catch (e) {}
        if (!had && !acted && n.desktopEntry) {
            var de = DesktopEntries.byId(String(n.desktopEntry)) || DesktopEntries.heuristicLookup(String(n.desktopEntry))
            if (de) g.launchEntry(de, true)
        }
    }

    // ── Focus one window ──────────────────────────────────────────────────
    // THE way the shell brings a window forward (bar, dock, Overview,
    // launchers, notifications, the app openers above). By ADDRESS, so
    // Hyprland switches to the window's workspace; the foreign-toplevel
    // activate (t.wayland.activate()) is ignored for a window on another
    // workspace under Hyprland 0.56, and is only the fallback for a
    // toplevel whose IPC object has not arrived yet.
    function focusToplevel(t) {
        if (!t) return false
        var a = String(t.address || (t.lastIpcObject && t.lastIpcObject.address) || "")
        if (a === "") {
            if (t.wayland) { t.wayland.activate(); return true }
            return false
        }
        if (a.indexOf("0x") !== 0) a = "0x" + a   // Hyprland events sometimes omit the 0x
        // A minimized window (Super+Z → special:minimized; the retired Pen's
        // special:pen) comes back to the workspace you are on, as the dock's
        // restore does. Focusing it where it was only opened the hidden stash
        // over your workspace: the app looked half-open, stayed "minimized",
        // and the next new window landed inside the stash.
        var wsn = String((t.workspace && t.workspace.name)
                         || (t.lastIpcObject && t.lastIpcObject.workspace && t.lastIpcObject.workspace.name) || "")
        if (wsn === "special:minimized" || wsn === "special:pen") {
            var ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
            Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + ws + ', window = "address:' + a + '", follow = false })')
        }
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + a + '" })')
        return true
    }

    // ── Which app is this window? ─────────────────────────────────────────
    // ONE answer for a window class — the dock, Overview, Alt+Tab switcher,
    // share picker, bar and focus-or-launch all ask here (plugins through
    // Shell.entryForClass / Shell.iconForClass), so an app looks and behaves
    // the same everywhere. DesktopEntries.heuristicLookup alone knows only
    // the id, StartupWMClass and the reverse-DNS tail, which left two kinds
    // of app with the generic executable icon and a second copy on every
    // click: AppImages Komble installs (entry komble-google-chrome, Icon
    // komble-*, no StartupWMClass, while the window says google-chrome) and
    // Steam games ("Dota 2.desktop": Exec=steam steam://rungameid/570,
    // Icon=steam_icon_570, window class steam_app_570). In order:
    //   1. DesktopEntries.byId / heuristicLookup (id, StartupWMClass, tail)
    //   2. an entry whose StartupWMClass equals the class, case-insensitive
    //   3. the class's last dotted segment as an id ("org.foo.Bar" → bar)
    //   4. Komble: "komble-<class>", else the komble-* entry whose Exec runs
    //      ".komble-run/<class>/AppRun" or an AppImage named after the class
    //   5. Steam: steam_app_N → the entry whose Exec has "rungameid/N"
    // null when nothing fits. Cached per class; the cache empties whenever
    // the desktop entries change (an install, a Komble AppImage, a new game).
    property var _clsCache: ({})
    property Connections _clsCacheWatch: Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { g._clsCache = ({}) }
    }
    // ── What Quickshell's entry reader can't do (scripts/desktop-entries.py) ──
    // LF copies of CRLF .desktop files (LinOffice's Word, Excel…: dropped by
    // Quickshell, so missing everywhere) in a folder qs-launch.sh puts in the
    // shell's XDG_DATA_DIRS, and the untranslated Name of every translated
    // entry: the launcher matches "Files" on a Georgian desktop too.
    // Re-run whenever the app list changes (an install, a new CRLF file);
    // the script rewrites a copy only when it would change, so the rescan
    // its own write causes ends there.
    property var appEnglishNames: ({})
    function englishName(e) {
        var id = e && e.id ? String(e.id).replace(/\.desktop$/, "") : ""
        return id !== "" && Object.prototype.hasOwnProperty.call(g.appEnglishNames, id) ? g.appEnglishNames[id] : ""
    }
    property Process _deProc: Process {
        running: true
        command: ["python3", Qt.resolvedUrl("scripts/desktop-entries.py").toString().replace(/^file:\/\//, "")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (j && j.english) g.appEnglishNames = j.english
                } catch (err) {}
            }
        }
    }
    property Timer _deTimer: Timer { interval: 1500; onTriggered: if (!g._deProc.running) g._deProc.running = true }
    property Connections _deWatch: Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { g._deTimer.restart() }
    }
    function entryForClass(cls) {
        var c = String(cls || "")
        if (c === "") return null
        var cache = g._clsCache
        if (Object.prototype.hasOwnProperty.call(cache, c)) return cache[c]
        var e = null
        try { e = g._resolveClass(c) } catch (err) { e = null }
        cache[c] = e
        return e
    }
    function _resolveClass(c) {
        var e = DesktopEntries.byId(c) || DesktopEntries.heuristicLookup(c)
        if (e) return e
        var lc = c.toLowerCase()
        var all = DesktopEntries.applications ? DesktopEntries.applications.values : []
        var i, a
        // 2. StartupWMClass, case-insensitive
        for (i = 0; i < all.length; i++) {
            a = all[i]
            if (a && a.startupClass && String(a.startupClass).toLowerCase() === lc) return a
        }
        // 3. the last dotted segment as an id
        var seg = lc.split(".").pop()
        if (seg !== "" && seg !== lc) {
            e = DesktopEntries.byId(seg) || DesktopEntries.heuristicLookup(seg)
            if (e) return e
        }
        // 4. Komble's AppImages
        e = DesktopEntries.byId("komble-" + lc) || DesktopEntries.byId("komble-" + c)
        if (e) return e
        for (i = 0; i < all.length; i++) {
            a = all[i]
            if (!a || !a.id || String(a.id).toLowerCase().indexOf("komble-") !== 0) continue
            var x = String(a.execString || "").toLowerCase()
            if (x.indexOf(".komble-run/" + lc + "/") >= 0 || x.indexOf("/" + lc + ".appimage") >= 0) return a
        }
        // 5. Steam games
        var m = /^steam_app_(\d+)$/.exec(lc)
        if (m) {
            var re = new RegExp("rungameid/" + m[1] + "(\\D|$)")
            for (i = 0; i < all.length; i++) {
                a = all[i]
                if (a && re.test(String(a.execString || ""))) return a
            }
        }
        return null
    }
    // The icon for a window class: its entry's Icon, else the class as an
    // icon name, else `fallback` ("application-x-executable" by default;
    // `true` = "" when nothing resolves — the bar's name-instead-of-icon).
    function iconForClass(cls, fallback) {
        var fb = (fallback === undefined || fallback === null) ? "application-x-executable" : fallback
        var c = String(cls || "")
        var e = g.entryForClass(c)
        if (e && e.icon) return Quickshell.iconPath(e.icon, fb)
        if (c !== "") return Quickshell.iconPath(c, fb)
        return fb === true ? "" : Quickshell.iconPath(String(fb))
    }

    property Process _standaloneProbe: Process {
        running: true
        command: ["sh", "-c", "command -v komble >/dev/null && printf k; command -v ewe-settings >/dev/null && printf s; command -v hypr-settings >/dev/null && printf o; command -v ewe-sync >/dev/null && printf y"]
        stdout: StdioCollector {
            onStreamFinished: {
                g.kombleInstalled = this.text.indexOf("k") >= 0
                g.syncAppInstalled = this.text.indexOf("y") >= 0
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
    // VESTIGIAL. There is ONE ewe look now (2026-09-04) and it is built from
    // the accent in ewe.conf, not chosen from a list. This survives only as
    // the key the token file still publishes both look names under, so a
    // machine whose user-theme.json says "blacksheep" keeps resolving. It is
    // still what re-runs colorscheme.sh, which drags GTK apps along.
    property string themeName: "flock"
    onThemeNameChanged: g.applyColorScheme()

    // ── User-chosen accent colour ─────────────────────────────────────────────
    // Single mutable source the Settings → Theme pane writes; Theme.accent binds to
    // it so the whole shell recolours live. Persisted to ~/.config/quickshell/
    // user-theme.json and re-read here at startup. Until someone picks one it
    // is the accent the token file was built from (no colour of its own here).
    property color accentColor: (g.tokColor && g.tokColor["accent"]) ? g.tokColor["accent"] : "transparent"
    // false = user-theme.json carries no accent, i.e. nobody has ever picked
    // one in the shell. Theme.accent then falls back to the accent in
    // ewe.conf [desktop.theme], which is what the token file was built from.
    property bool accentExplicit: false
    // a palette scheme is active (ewe.conf desktop.theme.scheme != "accent"):
    // its accent is in the tokens and wins over the in-shell pick above
    property bool schemeActive: false
    property bool tintBorders: false        // mirror window border colour to the accent
    // false → fully opaque windows (decoration inactive_opacity forced to 1.0);
    // true draws unfocused windows at opacity-inactive (97%). Default false,
    // which is what ewe-conf's [desktop.theme] window_transparency says; this
    // singleton disagreed with it until the design system v3 (Phase 3).
    property bool windowTransparency: false

    // Tiling on (the Hyprland default) vs every new window opening floating, for
    // people who want the DE to behave like GNOME/Unity rather than a tiling WM.
    // Implemented as a catch-all float window rule in hypr/generated/user.lua.
    //
    // READ-ONLY FROM OUTSIDE. Assigning this flips the icon and nothing else:
    // a window rule cannot be withdrawn at runtime, so the change only becomes
    // real once user.lua is regenerated and Hyprland reloads. Settings.qml had
    // a Connections that did exactly that — but Settings is destroyed 30 s
    // after its window closes, so the bar's toggle wrote the bool into a shell
    // with nobody listening. It worked from Settings and nowhere else.
    // Go through setTiling(), which is always here.
    property bool tilingEnabled: true
    // Workspaces on several displays (ewe.conf [desktop.workspaces] mode,
    // carried in user-theme.json): "separate" — each display has its own
    // workspaces 1, 2, 3 … — or "shared" — one set across all of them, and
    // switching one switches every display. dotfiles/hypr/workspaces.lua does
    // the switching; every display owns a block of ten Hyprland ids (the
    // first 1–10, the second 11–20 …), so the shell shows wsNumber(id).
    property string workspacesMode: "separate"
    readonly property bool workspacesShared: g.workspacesMode === "shared"
    function wsNumber(id) { return id >= 1 ? ((id - 1) % 10) + 1 : id }
    function wsBlock(id) { return id >= 1 ? Math.floor((id - 1) / 10) : 0 }

    // The one way to change it: ewe-conf owns the file, regenerates user.lua
    // and reloads Hyprland, then pokes `settings reload` — which comes back
    // through reloadUserState() and moves the property above. WITH hooks, and
    // deliberately so: the regeneration IS the feature here.
    function setTiling(on) {
        g._tilingWriter.command = [g.eweConf, "set", "desktop.tiling.enabled", on ? "true" : "false"]
        g._tilingWriter.running = false; g._tilingWriter.running = true
    }

    // Animation speed multiplier driving both the QML shell (Theme.dur*) and the
    // Hyprland window animations (Settings writes scaled hl.animation overrides).
    // 1.0 = default; >1 faster; 0 = animations off. Persisted in user-theme.json.
    property real animationSpeed: 1.0

    // ── App appearance (GTK + Qt) ──────────────────────────────────────────────
    // Light or dark comes from the active scheme's variant (theme-tokens.json),
    // never from here: light mode is supported since 2026-10-14 (Ewe Light, any
    // light scheme). This legacy key stays "dark" for user-theme.json, where
    // Komble only uses it to notice a change, and colorscheme.sh ignores the
    // mode argument it is passed.
    property string colorScheme: "dark"
    property Process _csApply: Process {}
    function applyColorScheme() {
        var acc = String(Theme.accent).replace("#", "")
        g._csApply.command = ["sh", "-c", "\"$HOME/.config/quickshell/scripts/colorscheme.sh\" " + g.colorScheme + " " + acc]
        g._csApply.running = false; g._csApply.running = true
    }

    // ── Dock prefs (persisted in user-theme.json / ewe.conf desktop.dock.*) ──
    // The dock itself is the ewe.dock add-on since 0.25; it reads these through
    // Shell.dockPrefs, and Settings keeps writing them.
    property bool dockEnabled: true
    property bool dockAutohide: false       // intelligent hide: slide away, reveal on bottom-edge hover
    property string dockIconSize: "normal"  // dock icon size: "small" | "normal" | "large"
    // ── top bar (Settings → Layout → Top bar; user-theme.json) ──
    property string barIconSize: "normal"   // status glyph size: "small" | "normal" | "large" (relative to the theme's icon size)
    property var barShow: ({})              // { tray, screenshot, clipboard, tiling, keyboard, sound, mic, wifi, bluetooth, power, battery } — absent = shown
    function barShows(key) { return !(barShow && barShow[key] === false) }
    // the fold (0.45, `desktop.bar.collapse`): the tray, the plugins' bar
    // widgets and the tiling switch sit behind a chevron; barExtrasOpen is
    // whether they are out right now — per session, every screen's bar alike
    property bool barCollapse: false
    property bool barExtrasOpen: false

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

    // ── the AppStore fallback panel (Komble absent) ───────────────────────────
    property bool storeOpen: false           // app-store panel

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
    // Read by the Launcher and, through Shell.pinnedApps / setPinned, the dock add-on.
    property var pinnedApps: []
    function isPinned(id) { return (g.pinnedApps || []).indexOf(id) >= 0 }
    function togglePin(id) { g.setPinned(id, !g.isPinned(id)) }
    // the ONE writer of the pinned list (Shell.setPinned lands here too)
    function setPinned(id, on) {
        var a = (g.pinnedApps || []).slice()
        var i = a.indexOf(id)
        if (on && i < 0) a.push(id)
        else if (!on && i >= 0) a.splice(i, 1)
        else return
        g._writePins(a)
    }
    function _writePins(a) {
        g.pinnedApps = a
        g._pinWriter.command = [g.eweConf, "set", "--no-hooks", "apps.pinned", JSON.stringify(a)]
        g._pinWriter.running = false; g._pinWriter.running = true
    }
    // A pin from before ewe browser (firefox.desktop was the default pin,
    // Helium the browser until 0.26) names an entry that is gone, so the
    // dock's apps box showed no browser at all while `ewe-browser` ran fine
    // from a terminal. Once the pins and the desktop entries are both in, a
    // dead browser pin becomes ewe-browser.desktop in its place — once, and
    // only while ewe browser is installed and not pinned already.
    readonly property var _oldBrowserPins: ["helium.desktop", "firefox.desktop", "firefox-esr.desktop", "org.mozilla.firefox.desktop"]
    property bool _pinsLoaded: false
    property bool _browserPinChecked: false
    function _migrateBrowserPin() {
        if (g._browserPinChecked || !g._pinsLoaded) return
        var all = DesktopEntries.applications ? DesktopEntries.applications.values : []
        var a = (g.pinnedApps || []).slice()
        if (all.length === 0 || a.length === 0) return   // a later reload may bring the pins
        g._browserPinChecked = true
        if (a.indexOf("ewe-browser.desktop") >= 0 || !DesktopEntries.byId("ewe-browser")) return
        for (var i = 0; i < a.length; i++) {
            if (g._oldBrowserPins.indexOf(a[i]) < 0) continue
            if (DesktopEntries.byId(a[i].replace(/\.desktop$/, ""))) continue
            a[i] = "ewe-browser.desktop"
            g._writePins(a)
            return
        }
    }
    // the desktop entries arrive a moment after start-up (a scan); wait for
    // them to settle so a still-installed Firefox is never taken for gone
    property Timer _browserPinTimer: Timer { interval: 3000; onTriggered: g._migrateBrowserPin() }
    property Connections _browserPinWatch: Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { if (!g._browserPinChecked) g._browserPinTimer.restart() }
    }
    // (Pinned places — places.json / ewe-conf apps.places — belong to the
    // ewe.places add-on since 0.25; lib/deploy.sh still seeds places.json.default
    // and ewe-conf still owns the key, so the file is where the add-on reads it.)
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
        g._animLoad.running = false; g._animLoad.running = true
        // The accent lives in ewe.conf, so picking one re-runs `ewe-theme
        // build` and REWRITES theme-tokens.json. Without this line the shell
        // kept the old greys — the accent moved and nothing derived from it
        // did — until the next restart.
        g._tokenLoad.running = false; g._tokenLoad.running = true
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

    // ── Avatar (~/.face) — shared by Settings (account card) and the lock screen.
    // faceUrl is THE avatar image source everywhere: "" while no ~/.face exists,
    // and cache-busted (?v=) after Settings saves a new one.
    // ── 12- or 24-hour: the region's formats (Settings → Time and place →
    // Formats = LC_TIME). On Unix Qt.locale() reads the LC_* categories, so
    // its short time pattern has an AM/PM marker ("h:mm AP") only where the
    // region uses one; quoted literal text is ignored. The ewe date strings
    // stay English (the shell is not translated), only the hour cycle and
    // the calendar's first weekday (QuickSettings) follow the region.
    readonly property bool clock24: !/[aA]/.test(String(Qt.locale().timeFormat(Locale.ShortFormat)).replace(/'[^']*'/g, ""))
    // padded: "02:05 PM" (the bar's fixed-width look) vs "2:05 PM"
    function timeFormat(padded) { return g.clock24 ? "HH:mm" : (padded ? "hh:mm AP" : "h:mm AP") }
    function formatTime(d, padded) { return Qt.formatDateTime(d, g.timeFormat(padded)) }
    property bool hasFace: false
    property int avatarVersion: 0
    property string avatarShape: "circle"   // "circle" | "rounded" | "square" — Avatar.qml masks to this; persisted in user-theme.json
    readonly property string faceUrl: hasFace ? "file://" + Quickshell.env("HOME") + "/.face?v=" + avatarVersion : ""
    property Process _faceChk: Process { running: true; command: ["sh", "-c", 'test -f "$HOME/.face"']; onExited: function (code) { g.hasFace = (code === 0) } }
    function recheckFace() { g.avatarVersion++; g._faceChk.running = false; g._faceChk.running = true }

    property Process _pinWriter: Process {}
    property Process _tilingWriter: Process {}
    property Process _pinLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/pinned-apps.json\" 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: {
            try { var j = JSON.parse(this.text); if (Array.isArray(j)) g.pinnedApps = j } catch (e) {}
            g._pinsLoaded = true; g._browserPinTimer.restart()
        } }
    }

    // The last parsed contents of user-theme.json, verbatim.
    //
    // The shell is no longer the only writer of that file: the standalone Settings
    // app writes it too, and a newer Settings knows keys this shell does not. Kept
    // so writePrefs() can merge into it — a writer that emits only the keys it
    // knows would silently delete everyone else's.
    property var prefsRaw: ({})

    // ── Generated theme tokens (ewe.conf -> `ewe-theme build`) ────────────────
    // The Ewe token set as data, one block per kind: colour roles, shape
    // (radii and outline widths), sizes (type scale, spacing, controls,
    // icons, panels). Theme.qml reads its tokens out of here, so the scheme
    // and the accent are changed in ewe.conf and the whole shell follows
    // without touching QML. The values compiled into Theme.qml stay as the
    // FALLBACK — a missing or unparsable file degrades to Ewe Dark rather
    // than to a colourless shell.
    property var tokColor: ({})
    property var tokShape: ({})
    property var tokSize:  ({})
    // what ewe.conf [desktop.theme] actually said — accent, corner, density,
    // stroke, neutral_tint. The Settings pane shows the live value from here
    // rather than keeping a second copy that can disagree with the file.
    property var tokInput: ({})
    // {bar_alpha, glass, blur, app_blur, app_alpha, inactive_alpha, solid} —
    // Theme.glass / Theme.barAlpha / Theme.glassBlur read it
    property var tokSurface: ({})
    // The rest of the v3 token file, each block as the generator wrote it:
    // type (families, weights, tracking, the styles), motion (the four
    // durations already divided by the animation speed, the easings),
    // opacity, shadow, gradient, bar (height/module/icon for the bar size)
    // and accessibility (the four modes). Theme.qml turns them into
    // properties; nothing else should read these directly.
    property var tokType: ({})
    property var tokMotion: ({})
    property var tokOpacity: ({})
    property var tokShadow: ({})
    property var tokGradient: ({})
    property var tokBar: ({})
    // the dock's cells per icon size, unscaled by Text size
    property var tokDock: ({})
    property var tokA11y: ({})
    // the Accent picker's presets [{name, hex, ink}] — the generator's list,
    // so Settings carries no colour of its own
    property var tokAccentPresets: []
    // the tallest thing in the bar (its rows' implicit height), reported by
    // Bar.qml: Theme.barHeight is this plus barPadding above and below
    property int barContentHeight: 0
    // start-hyprland.sh exports EWE_NO_BLUR=1 in VMs and on NVIDIA, where the
    // compositor's blur is a known cost or glitch. Glass still applies there —
    // the fills stay translucent (Theme.barAlpha, the glass-* roles), only the
    // compositor blur behind them is skipped (Theme.glassBlur is false).
    readonly property bool noBlur: Quickshell.env("EWE_NO_BLUR") === "1"
    property Process _tokenLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/theme-tokens.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (j && j.color && typeof j.color === "object") g.tokColor = j.color
                    if (j && j.shape && typeof j.shape === "object") g.tokShape = j.shape
                    if (j && j.size  && typeof j.size  === "object") g.tokSize  = j.size
                    if (j && j.input && typeof j.input === "object") g.tokInput = j.input
                    g.schemeActive = !!(j && j.input && j.input.scheme && j.input.scheme !== "accent")
                    g.tokSurface = (j && j.surface && typeof j.surface === "object") ? j.surface : {}
                    if (j && j.type && typeof j.type === "object") g.tokType = j.type
                    if (j && j.motion && typeof j.motion === "object") g.tokMotion = j.motion
                    if (j && j.opacity && typeof j.opacity === "object") g.tokOpacity = j.opacity
                    if (j && j.shadow && typeof j.shadow === "object") g.tokShadow = j.shadow
                    if (j && j.gradient && typeof j.gradient === "object") g.tokGradient = j.gradient
                    if (j && j.bar && typeof j.bar === "object") g.tokBar = j.bar
                    if (j && j.dock && typeof j.dock === "object") g.tokDock = j.dock
                    if (j && j.accessibility && typeof j.accessibility === "object") g.tokA11y = j.accessibility
                    if (j && Array.isArray(j.accent_presets)) g.tokAccentPresets = j.accent_presets
                } catch (e) {}
            }
        }
    }
    function reloadThemeTokens() { g._tokenLoad.running = false; g._tokenLoad.running = true }

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
                    if (j && j.accent) { g.accentColor = j.accent; g.accentExplicit = true }
                    if (j && j.tintBorders !== undefined) g.tintBorders = j.tintBorders
                    if (j && j.windowTransparency !== undefined) g.windowTransparency = j.windowTransparency
                    if (j && j.dockEnabled !== undefined) g.dockEnabled = j.dockEnabled
                    if (j && j.dockAutohide !== undefined) g.dockAutohide = j.dockAutohide
                    if (j && j.dockIconSize) g.dockIconSize = j.dockIconSize
                    if (j && j.barEnabled !== undefined) g.barVisible = j.barEnabled !== false
                    if (j && j.barIconSize) g.barIconSize = j.barIconSize
                    if (j && j.barShow && typeof j.barShow === "object") g.barShow = j.barShow
                    if (j && j.barCollapse !== undefined) g.barCollapse = j.barCollapse === true
                    if (j && j.animationSpeed !== undefined) g.animationSpeed = j.animationSpeed
                    // a persisted "colorScheme" is ignored: the scheme's variant decides
                    if (j && j.avatarShape) g.avatarShape = j.avatarShape
                    if (j && j.lidDockedSuspend !== undefined) g.lidDockedSuspend = j.lidDockedSuspend
                    if (j && j.lowPowerEnabled !== undefined) g.lowPowerEnabled = j.lowPowerEnabled
                    if (j && j.tilingEnabled !== undefined) g.tilingEnabled = j.tilingEnabled
                    if (j && (j.workspacesMode === "separate" || j.workspacesMode === "shared")) g.workspacesMode = j.workspacesMode
                    if (j && j.eventSounds !== undefined) g.eventSounds = j.eventSounds
                    if (j && (j.gameLevel === "ultra" || j.gameLevel === "balanced")) g.gameLevel = j.gameLevel
                    if (j && j.gameAuto !== undefined) g.gameAuto = j.gameAuto !== false
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
