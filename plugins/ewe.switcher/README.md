# Window switcher — an ewe plugin

`ewe.switcher` — first-party, ships inside the ewe payload, not installed
until you ask for it.

The classic Alt+Tab. Hold Alt and press Tab: the open windows appear as
their app icons, most recently used first, with the window you were in
before selected. Every Tab moves on, Shift+Tab moves back, the arrow keys
and the pointer move too; let go of Alt (or press Enter, or click) to
switch, Esc to cancel. The selected window's title, app and place are
written under the icons; a window on another workspace carries its number
on the icon; a minimized window is listed too and comes back onto the
workspace in view when picked.

Install: Komble → Plugins, or

    ewe-plugin install ewe.switcher

Settings (Komble → Plugins → Window switcher → Options, or `ewe-plugin set
ewe.switcher scope display`):
`scope` — which windows are offered: `workspace` (the default: this
workspace), `display` (every workspace of the display you are on) or
`everywhere`.

Keys: `Alt+Tab` next, `Alt+Shift+Tab` previous, releasing `Alt` switches —
the manifest's binds, generated into `hypr/generated/plugin-keybinds.lua`
while the plugin is enabled. They are global shortcuts, not `qs ipc`
spawns: nothing is started per press. `Super+Tab` (the blind next-window
cycle without a panel) stays the shell's own.

IPC: `qs ipc call ewe.switcher next | prev | commit | cancel | toggle |
isOpen`.

Needs nothing beyond ewe. The panel is `quickshell:ewe.switcher` in the
layer-shell, should a layer rule want it.
