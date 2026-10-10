pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Shell — the public shell API for plugins (API 3, docs/PLUGINS.md "The
// Shell singleton"). Frozen: a plugin written against this file keeps
// working until apiVersion moves. Everything here is a thin door onto
// Globals and the panels, so the shell's internals can move without the
// plugins noticing.
//
//   read     overviewOpen · quickSettingsOpen · lowPower · onBattery · locked ·
//            dnd · bottomInset · bottomReserved · dockPresent · dockPrefs ·
//            pinnedApps · primaryScreenName · dockItems · activeCount
//   call     toast() · openQuickSettings() · closeQuickSettings() ·
//            openSettings() · openStore() · launch() · focusApp() ·
//            toggleOverview() · registerAction() · runAction() ·
//            setBottomInset() · anchorFor() · setActive() · isActive() ·
//            setPinned() · setDockItemShown() · dockItemShown() · closePopups()
//   signals  aboutToSleep() · resumed()   (Resume.qml emits them) ·
//            popupsClosing(exceptId)      (closePopups emits it)
QtObject {
    id: sh

    readonly property int apiVersion: 3

    // ── read ───────────────────────────────────────────────────────────────
    readonly property bool overviewOpen: Globals.overviewOpen
    readonly property bool quickSettingsOpen: Globals.quickSettingsOpen
    readonly property bool lowPower: Globals.lowPower
    readonly property bool onBattery: Globals.onBattery
    readonly property bool locked: Globals.locked
    readonly property bool dnd: Globals.dnd
    // The primary output's name — a shell concept (Wayland has none): the
    // output HyprMon's display profile marks primary, else the first one.
    // A dock pins itself to this screen.
    readonly property string primaryScreenName: HyprMon.primaryName
    // The dock-item registry: [{ id, name, icon, label, action, order }] for
    // every enabled plugin that declares `dockItem`, in order — read-only,
    // bindable; what a dock plugin renders (filtered by dockItemShown).
    readonly property var dockItems: PluginHost.dockItems

    // The bottom inset: the pixels a dock takes from the bottom of the
    // screen (its strip plus windowGap), 0 without a dock. Panels that open
    // above the dock keep clear of it; nothing leaves a gap when no dock is
    // installed. `bottomReserved` says the dock RESERVES that strip as a
    // layer-shell exclusive zone (always-visible dock) — a bottom-anchored
    // surface is then already pushed up by the compositor and only adds its
    // own small gap (Toast, OSD). A dock plugin (ewe.dock) publishes both
    // through setBottomInset(); nothing in the core does.
    property var _insets: ({})           // pluginId -> { px, reserved }
    readonly property int bottomInset: {
        var m = 0
        for (var k in sh._insets) m = Math.max(m, sh._insets[k].px || 0)
        return m
    }
    readonly property bool bottomReserved: {
        for (var k in sh._insets) if (sh._insets[k].reserved && (sh._insets[k].px || 0) > 0) return true
        return false
    }
    readonly property bool dockPresent: sh.bottomInset > 0
    function setBottomInset(pluginId, px, reserved) {
        var m = Object.assign({}, sh._insets)
        if (!px || px <= 0) delete m[pluginId]
        else m[pluginId] = { px: Math.round(px), reserved: !!reserved }
        sh._insets = m
    }

    // The pre-plugin-settings dock prefs (ewe.conf [desktop.dock] enabled /
    // autohide / icon_size, loaded by Globals from user-theme.json). Kept
    // for API 3: since Dock 1.1.0 the dock's settings are its own (manifest
    // `settings`, Komble's Options) and these are only its fallback.
    // `iconSize` is "small" | "normal" | "large".
    readonly property var dockPrefs: ({ enabled: Globals.dockEnabled, autohide: Globals.dockAutohide, iconSize: Globals.dockIconSize })

    // A plugin writes one of ITS OWN declared settings (manifest `settings`)
    // — from its own UI, the same value Komble's Options dialog shows.
    // Applied to the plugin's live instances at once, persisted through
    // `ewe-plugin set` (which validates it against the manifest and keeps
    // ewe-conf the one writer). Added in ewe 0.25.1 (additive, API 3).
    function setSetting(pluginId, key, value) { PluginHost.setSetting(String(pluginId), String(key), value) }

    // Pinned apps (desktop ids, ewe-conf apps.pinned): read-only here; a
    // plugin pins or unpins through setPinned — Globals keeps the one
    // writer path (ewe-conf), so the file never has two authors.
    readonly property var pinnedApps: Globals.pinnedApps
    function setPinned(desktopId, on) { Globals.setPinned(String(desktopId), !!on) }

    // ── call ───────────────────────────────────────────────────────────────
    // toast(text, kind): kind is "" · "info" · "warning" · "danger" (the
    // Toast's tone); an object as the second argument is passed through as
    // the Toast options ({ actionLabel, action, icon, timeout }).
    function toast(text, kind) {
        var opts = (kind && typeof kind === "object") ? kind : { tone: (kind && kind !== "info") ? String(kind) : "" }
        Globals.toast(String(text), opts)
    }
    // Quick settings on a tab: a built-in key (home, wifi, bt, audio, cal,
    // notifs) or a plugin page's quickPage.key — the same route as
    // `qs ipc call quicksettings tab <key>`.
    function openQuickSettings(tab) { Globals.openQuickSettingsTab(tab || "home") }
    function closeQuickSettings() { Globals.quickSettingsOpen = false }
    // The Overview, in-shell (a `qs ipc call overview toggle` spawn costs
    // 50–70 ms per click; this is the flag the dock's button flips).
    function toggleOverview() { Globals.overviewOpen = !Globals.overviewOpen }
    // The Settings app (ewe-settings) and Komble; `page` is forwarded as
    // `--<page>` to Komble ("addons", "updates") and `--page <name>` to
    // ewe-settings. An already-open window is focused instead of doubled.
    function openSettings(page) {
        if (!page) { Globals.openSettings(); return }
        if (Globals.focusWindowByClass("ewe-settings") || Globals.focusWindowByClass("hypr-settings")) return
        if (Globals.settingsAppInstalled) Quickshell.execDetached([Globals.settingsAppBin, "--page", String(page)])
        else Globals.settingsOpen = true
    }
    function openStore(page) {
        if (!page) { Globals.openStore(); return }
        if (Globals.kombleInstalled) {
            Globals.focusAppWindow(["komble"])
            Quickshell.execDetached(["komble", "--" + String(page)])
        } else Globals.storeOpen = true
    }
    // launch(desktopId): a .desktop id ("org.gnome.Nautilus" / "kitty");
    // focuses the app's window when it already has one. Returns false when
    // no such entry exists.
    function launch(desktopId) {
        var e = DesktopEntries.byId(String(desktopId)) || DesktopEntries.heuristicLookup(String(desktopId))
        if (!e) return false
        Globals.launchEntry(e)
        return true
    }
    // focusApp([classes]): bring the window of one of these app classes
    // forward (its workspace comes with it); false when none is open.
    function focusApp(classes) { return Globals.focusAppWindow(Array.isArray(classes) ? classes : [classes]) }

    // Actions: a plugin registers a named function (manifest dockItem.action
    // names one); the dock — or any other plugin — runs it with an anchor.
    property var _actions: ({})
    function registerAction(name, fn) {
        var m = Object.assign({}, sh._actions)
        if (typeof fn === "function") m[String(name)] = fn; else delete m[String(name)]
        sh._actions = m
    }
    function runAction(name, anchor) {
        var fn = sh._actions[String(name)]
        if (typeof fn !== "function") return false
        fn(anchor || null)
        return true
    }
    // An action's open state (a dock item lights while its popup is open):
    // AnchoredPopup reports it through `action`.
    property var _active: ({})
    readonly property int activeCount: {
        var n = 0
        for (var k in sh._active) if (sh._active[k]) n++
        return n
    }
    function setActive(name, on) {
        var m = Object.assign({}, sh._active)
        if (on) m[String(name)] = true; else delete m[String(name)]
        sh._active = m
    }
    function isActive(name) { return !!sh._active[String(name)] }
    // One add-on popup at a time: closePopups(exceptId) asks every popup
    // but the caller's to close — every AnchoredPopup honours it (spared
    // when exceptId is its `owner`, its `action` or its `name`), and a
    // plugin with its own PanelWindow (Places, the dock's pinned-apps panel)
    // listens to popupsClosing and calls closePopups(<its id>) when it
    // opens. What the built-in dock did between Places and the player.
    signal popupsClosing(string exceptId)
    function closePopups(exceptId) { sh.popupsClosing(exceptId === undefined || exceptId === null ? "" : String(exceptId)) }
    // A plugin's dock item is shown by default; the plugin hides its own at
    // runtime (the music player has no button while no player exists, or
    // when its setting says bar-only). The dock add-on filters on this;
    // `_dockHidden` is bindable so the dock follows live.
    property var _dockHidden: ({})
    function setDockItemShown(pluginId, on) {
        var m = Object.assign({}, sh._dockHidden)
        if (on === false) m[String(pluginId)] = true; else delete m[String(pluginId)]
        sh._dockHidden = m
    }
    function dockItemShown(pluginId) { return !sh._dockHidden[String(pluginId)] }

    // anchorFor(item, window) → { screen, x, y, edge, item } for a popup: x/y
    // are the item's centre in its window (screen-local for a full-width
    // bar or dock), edge is "top" or "bottom" by which half of the window
    // the item sits in. Pass the item's window when you have it (bar
    // widgets and bar-status glyphs get `barWindow`; a dock passes its
    // own); without it the focused monitor is assumed and the edge is
    // bottom.
    function anchorFor(item, window) {
        if (!item) return null
        var p = item.mapToItem(null, item.width / 2, item.height / 2)
        var scr = (window && window.screen) ? window.screen : sh._focusedScreen()
        var h = window ? window.height : 0
        return { screen: scr, x: p.x, y: p.y, edge: (h > 0 && p.y < h / 2) ? "top" : "bottom", item: item }
    }
    function _focusedScreen() {
        var fm = Hyprland.focusedMonitor, ss = Quickshell.screens
        if (fm) for (var i = 0; i < ss.length; i++) if (ss[i].name === fm.name) return ss[i]
        return ss.length > 0 ? ss[0] : null
    }

    // ── signals (Resume.qml emits them from the logind bridge's events) ───
    signal aboutToSleep()      // the system is about to suspend
    signal resumed()           // the wake sequence reached the network step (~3 s after wake)
}
