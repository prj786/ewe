# Dock — an ewe add-on

`ewe.dock` — first-party, shipped inside the ewe payload, not installed on a
fresh machine (ewe 0.25 add-ons). Upgraders who had the dock keep it:
`ewe-plugin migrate` installs it unless `[desktop.dock] enabled = false`.

A small, centred dock at the bottom of the main screen:

    [ apps ] [ overview ] [ komble ] [ music ] [ places ] … | [ the Pen ] [ 1: ▢ ▢ ] [ 2: empty ]

- **the sheep** — the pinned-apps popup: your pinned apps, or type to search
  every installed app; click to launch (middle-click for a fresh instance),
  the pin badge pins and unpins (`ewe-conf apps.pinned`, synced).
- **layers** — the window Overview.
- **store** — Komble (the shell's quick installer when Komble is missing).
- **dock items** other add-ons declare (`dock-item` in their manifest: Music,
  Places, …), in their manifest order; a click opens their popup above the
  button, and the button lights while it is open.
- **the Pen** — ewe's stashed windows (`special:pen`, Super+Z): shown only
  while something is stashed; click a tile to fetch it, middle-click to send
  it back to the current workspace, click the box to show or hide the Pen.
- **workspace boxes** — one per workspace with windows plus the current one;
  click a tile to focus that window, click the box to switch.

It slides out of view while the Overview is open and comes back when the
cards have gone; with auto-hide on it ducks when the current workspace has a
tiled or fullscreen window and returns when the pointer reaches the bottom
edge, while any dock popup is open, and for a moment after the pointer leaves.

## Install

Komble → Add-ons → Dock, or

    ewe-plugin install ewe.dock
    ewe-plugin remove ewe.dock          # gone until you install it again

## Settings

Settings → Layout → Dock (ewe.conf `[desktop.dock]`): `enabled`, `autohide`,
`icon_size` (`small` · `normal` · `large`). The plugin reads the shell's
`Shell.dockPrefs`; nothing of its own.

## What it tells the shell

`Shell.setBottomInset("ewe.dock", px, reserved)` — the strip the dock takes
from the bottom of the screen (dock + `windowGap`), reserved as an exclusive
zone when auto-hide is off. Toasts, the OSD and every popup that opens above
the dock read `Shell.bottomInset`; it is 0 while the dock is off and 0 again
the moment this add-on is removed, so nothing leaves a gap without a dock.

## IPC

    qs ipc call launcher toggle|show|hide            # the pinned-apps popup (legacy target, kept)
    qs ipc call ewe.dock launcher|showLauncher|hideLauncher|isLauncherOpen

Layer namespaces: `quickshell:dock` (the dock), `quickshell:launcher` (the
popup) — the Hyprland layer rules and the Glass blur rule match them by name.

## Development

    ewe-plugin dev . --first-party       # link it in, replacing the bundled copy
    ./test.sh                            # manifest validation + a Rule 8 sweep

Plugin API 3 (`docs/PLUGINS.md` in the ewe repo). MIT.
