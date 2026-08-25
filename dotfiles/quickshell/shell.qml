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
    Bar {}
    Dock {}
    LauncherPanel {}
    AppStore {}
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
    Settings {}
    Splash {}
    Battery {}
}
