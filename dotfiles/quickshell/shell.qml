import QtQuick
import Quickshell

// Quickshell entry point. Built incrementally.
//   - Bar:           top bar (Search… · window · workspaces · status · clock).
//   - Launcher:      centered fuzzy app launcher (Super+D).
//   - Notifications: native notification server + top-right toasts.
//   - QuickSettings: clock → calendar + Do Not Disturb + notifications.
ShellRoot {
    // HyprMon is a lazy singleton: poke it at startup so its display guard —
    // hotplug/AC-transition re-assert of the saved monitor profiles — is armed
    // from login, not from the first time Settings → Displays is opened.
    // Logind owns the sleep delay inhibitor, so it must be up from login too —
    // a suspend that happens before anything touches it would not be locked.
    // Resume hangs off Logind's wake signal and must be armed before the first
    // suspend, not after it.
    // Lid likewise: the lid can be shut before anything else would have touched
    // the singleton, and a lid event nobody is listening for does nothing.
    Scope { Component.onCompleted: { HyprMon.start(); Logind.start(); Resume.start(); Lid.start(); Wallpaper.start() } }

    Notifications {}
    IpcHub {}
    // RSS diet (ewe#18): the fallback panels are the two biggest QML trees
    // and almost never render now that ewe-settings and Komble exist as
    // apps — load on first open, unload 30s after close (linger covers the
    // close animation and quick reopens). Their IPC verbs live in IpcHub.
    Scope {
        id: lazyPanels
        property bool settingsLinger: false
        property bool storeLinger: false
        property Timer settingsUnload: Timer { interval: 30000; onTriggered: lazyPanels.settingsLinger = false }
        property Timer storeUnload: Timer { interval: 30000; onTriggered: lazyPanels.storeLinger = false }
        property Connections hooks: Connections {
            target: Globals
            function onSettingsOpenChanged() {
                if (Globals.settingsOpen) { lazyPanels.settingsLinger = true; lazyPanels.settingsUnload.stop() }
                else lazyPanels.settingsUnload.restart()
            }
            function onStoreOpenChanged() {
                if (Globals.storeOpen) { lazyPanels.storeLinger = true; lazyPanels.storeUnload.stop() }
                else lazyPanels.storeUnload.restart()
            }
        }
        LazyLoader { active: Globals.settingsOpen || lazyPanels.settingsLinger; component: Settings {} }
        LazyLoader { active: Globals.storeOpen || lazyPanels.storeLinger; component: AppStore {} }
    }
    Bar {}
    Dock {}
    LauncherPanel {}
    Places {}
    MediaPlayer {}
    TrayMenu {}
    Launcher {}
    QuickSettings {}
    Auth {}
    Clipboard {}
    ScreenshotPreview {}
    Lock {}
    Caffeine {}
    Cast {}
    SharePicker {}
    Screensaver {}
    Osd {}
    Overview {}
    Battery {}
}
