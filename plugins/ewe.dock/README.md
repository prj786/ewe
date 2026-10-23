# Dock — an ewe plugin

`ewe.dock` — first-party, shipped inside the ewe payload, not installed on a
fresh machine (ewe 0.25: plugins are opt-in). Upgraders who had the dock keep it:
`ewe-plugin migrate` installs it unless `[desktop.dock] enabled = false`.

A small, centred dock at the bottom of the main screen:

    [ apps ] [ overview ] [ komble ] [ music ] [ places ] … | [ 1: ▢ ▢ ] [ 2: empty ] | [▣] [▣] [ ◔ ]

- **the sheep** — the pinned-apps popup: your pinned apps, or type to search
  every installed app; click to launch (middle-click for a fresh instance),
  the pin badge pins and unpins (`ewe-conf apps.pinned`, synced).
- **layers** — the window Overview.
- **store** — Komble (the shell's quick installer when Komble is missing).
- **dock items** other plugins declare (`dock-item` in their manifest: Music,
  Places, …), in their manifest order; a click opens their popup above the
  button, and the button lights while it is open.
- **workspace boxes** — one per workspace with windows plus the current one;
  click a tile to focus that window, click the box to switch.
- **minimized windows** (1.2.1, as in macOS's dock) — one tile per window
  Super+Z minimized (`special:minimized`, bound in ewe's hyprland.lua),
  oldest first and the newest at the right end: the window's picture with
  the app's icon on its corner. Click one to bring it back to the workspace
  you are on. The picture is one captured frame, shrunk to the tile and
  kept as a small image — the capture itself is dropped at once. They
  replaced the Pen: windows left in `special:pen` count as minimized.
  (1.2.0 had a Minimized box with a thumbnail panel instead.)
- **Downloads** (1.2.0) — the ewe browser's downloads: a progress ring round
  the glyph while one runs; a click lists the running ones and the day's
  finished ones (open the file, show it in its folder, Clear). Shown only
  while there is something to list. It reads the browser's own record,
  `$XDG_CONFIG_HOME/ewe-browser/downloads.json`, through a file watch — no
  polling, no process; "Clear" is a local mark in
  `~/.local/state/ewe/dock-downloads.json`, never ewe.conf.

It slides out of view while the Overview is open and comes back when the
cards have gone; with auto-hide on it ducks when the current workspace has a
tiled or fullscreen window and returns when the pointer reaches the bottom
edge, while any dock popup is open, and for a moment after the pointer leaves.

## Install

Komble → Plugins → Dock, or

    ewe-plugin install ewe.dock
    ewe-plugin remove ewe.dock          # gone until you install it again

## Settings

Its own, since 1.1.0 — Komble → Plugins → Dock → Options, or

    ewe-plugin set ewe.dock autohide true
    ewe-plugin set ewe.dock icon_size small      # small · normal · large

stored in ewe.conf `[plugins.settings]."ewe.dock"`. Until one is set, the old
`[desktop.dock]` value stands (the settings' `legacy` keys), so an upgrade
changes nobody's dock. Turning the dock off is the plugin's own switch in
Komble (`ewe-plugin disable ewe.dock`); Settings no longer has a Dock section.

## What it tells the shell

`Shell.setBottomInset("ewe.dock", px, reserved)` — the strip the dock takes
from the bottom of the screen (dock + `windowGap`), reserved as an exclusive
zone when auto-hide is off. Toasts, the OSD and every popup that opens above
the dock read `Shell.bottomInset`; it is 0 again the moment this plugin is
removed, so nothing leaves a gap without a dock.

## IPC

    qs ipc call launcher toggle|show|hide            # the pinned-apps popup (legacy target, kept)
    qs ipc call ewe.dock launcher|showLauncher|hideLauncher|isLauncherOpen

Layer namespaces: `quickshell:dock` (the dock), `quickshell:launcher` (the
popup), `quickshell:downloads` (the Downloads panel) — the Hyprland layer rules and the Glass blur rule match them by name.

## Development

    ewe-plugin dev . --first-party       # link it in, replacing the bundled copy
    ./test.sh                            # manifest validation + a Rule 8 sweep

Plugin API 3 (`docs/PLUGINS.md` in the ewe repo). MIT.
