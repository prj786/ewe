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
    Scope { Component.onCompleted: HyprMon.start() }

    Notifications {}
    Bar {}
    Dock {}
    LauncherPanel {}
    AppStore {}
    Places {}
    TrayMenu {}
    Launcher {}
    QuickSettings {}
    Auth {}
    Clipboard {}
    ScreenshotPreview {}
    AppMenu {}
    Lock {}
    Caffeine {}
    Screensaver {}
    Osd {}
    Overview {}
    Settings {}
    Splash {}
    Battery {}
}
