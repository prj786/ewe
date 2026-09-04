import QtQuick
import Quickshell
import Quickshell.Io

// IpcHub — the always-resident IPC verbs for surfaces that are otherwise
// LAZY-LOADED (RSS diet, ewe#18). The in-shell Settings and AppStore panels
// are pure fallbacks now that ewe-settings and Komble exist as apps, so
// shell.qml only instantiates them on demand — but their IPC targets are
// public API (keybinds, ewe-conf's reload poke, shipped binaries), so the
// verbs live HERE, permanently registered, and deep-links route through
// Globals for the panel to consume when it materialises.
Scope {
    // ewe-sync reports its state here on every change. Public API — the
    // shipped ewe-sync binary depends on this name.
    IpcHandler {
        target: "sync"
        function state(name: string, detail: string): void {
            Globals.syncState = name
            Globals.syncDetail = detail
        }
    }

    IpcHandler {
        target: "settings"
        // Every "open" verb routes through Globals.openSettings(): the
        // standalone ewe-settings app is THE settings UI when installed, and
        // the in-shell window exists only as a fallback while it is absent.
        function toggle(): void {
            if (Globals.settingsAppInstalled) { Globals.openSettings(); return }
            Globals.settingsOpen = !Globals.settingsOpen
        }
        function show(): void { Globals.openSettings() }
        function hide(): void { Globals.settingsOpen = false }
        // deep-link straight to a pane: qs ipc call settings pane 1 (Displays)
        function pane(n: int): void {
            if (Globals.settingsAppInstalled) { Globals.openSettings(); return }
            Globals.settingsPaneRequest = n
            Globals.settingsOpen = true
        }
        // jump to Wallpaper and open the file chooser (bindable to a key)
        function pickWallpaper(): void {
            if (Globals.settingsAppInstalled) { Globals.openSettings(); return }
            Globals.settingsPaneRequest = -2   // sentinel: wallpaper + chooser
            Globals.settingsOpen = true
        }

        // ── the contract with the out-of-process writers ────────────────────
        // ewe-settings and ewe-conf cannot touch Globals; they rewrite the
        // runtime files and poke `reload`. Public API — shipped binaries
        // depend on these names, and none of it needs the panel loaded.
        function reload(): void { Globals.reloadUserState(); HyprMon.reloadProfiles() }
        // Liveness probe: ewe-settings greys out controls when the shell is
        // not running, since a write would then only land at next login.
        function ping(): string { return "pong" }
        // Fallback for the version footer, used when the checkout is absent.
        function version(): string { return Globals.version }
    }

    IpcHandler {
        target: "store"
        function toggle(): void {
            if (Globals.kombleInstalled) { Globals.openStore(); return }
            Globals.launcherOpen = false; Globals.placesOpen = false; Globals.storeOpen = !Globals.storeOpen
        }
        function show(): void { Globals.openStore() }
        function hide(): void { Globals.storeOpen = false }
    }
}
