# Hyprland config (Lua) — hypr-shell

The **Hyprland** half of [hypr-shell](../../README.md): a Wayland compositor
configured in **Lua**, paired with the **Quickshell** QML shell (bar, dock,
launcher, notifications, Quick Settings, settings, lock, OSD) that lives in
[`../quickshell/`](../quickshell/). Clean dark aesthetic, Super-based keybinds.

> **Arch Linux only.** This config is deployed by the repo-root `install.sh`
> (a symlink farm: `dotfiles/hypr` → `~/.config/hypr`) and the session is started
> by **greetd + ReGreet**. There is no per-directory installer, no COPR/`dnf`, and
> no GDM — see the top-level [`README.md`](../../README.md) for the full install.

## Requirements

**Hyprland ≥ 0.55** — that's where the Lua config landed. `~/.config/hypr/hyprland.lua`
is loaded in preference to the deprecated `hyprland.conf`; an older Hyprland
silently ignores it and the DE won't come up right. On Arch you get a current
Hyprland straight from the official repos (installed by phase 20).

## Layout

```
~/.config/hypr/
├── hyprland.lua          # main config: env, look & feel, input, keybinds, rules, autostart
├── colors.lua            # window-border / decoration palette (required by hyprland.lua)
├── hypridle.conf         # idle: locks (and suspends on battery); NO dpms-off (xe resume-bug guard)
├── start-hyprland.sh     # "Hyprland (DE)" session wrapper — exports toolkit theming env, then exec Hyprland
├── generated/            # all gitignored user state; see ../../docs/SETTINGS-BACKEND.md
│   ├── user.lua          # your overrides (seeded from user.lua.default)
│   ├── input.lua         # written by Settings → Keyboard & Mouse
│   ├── monitors.lua      # written by Settings → Displays (per-monitor-set profiles)
│   └── wallpapers.conf   # written by Settings → Wallpaper (read by scripts/wallpaper.sh)
├── scripts/
│   ├── autostart.sh      # one-shot session bring-up (run by the hyprland start hook)
│   ├── lock.sh           # lock the session (prefers hyprlock)
│   ├── power.sh          # Quick Settings power actions (lock/logout/suspend/reboot/poweroff)
│   ├── screenshot.sh     # grim/slurp → ~/Pictures/Screenshots + clipboard
│   ├── wallpaper.sh      # per-monitor wallpaper (swww/hyprpaper/swaybg)
│   ├── calendar.sh       # Super+C calendar popup
│   ├── idle-suspend.sh   # battery-only idle suspend helper
│   ├── lid.sh            # laptop lid handling
│   ├── kb-per-window.py  # per-window keyboard-layout memory
│   └── install-sf-pro.sh # optional: fetch SF Pro fonts (user-level)
├── SHORTCUTS.md          # every keybinding
└── README.md
```

The bar, launcher, Quick Settings and lock are **Quickshell**, not Waybar — see
[`../quickshell/`](../quickshell/). Edit `hyprland.lua` and reload with
**Super + Ctrl + R** (Hyprland also auto-reloads on save).

## Customising — don't edit `hyprland.lua` for personal tweaks

Put your overrides in **`generated/user.lua`**, which `hyprland.lua` sources last
so it wins. It's gitignored and seeded from `generated/user.lua.default` on first
install, so your changes survive `git pull` + re-running `install.sh` and are never
committed. Reserve `hyprland.lua` for changes you intend to upstream.

## Theming

`colors.lua` holds the Hyprland window-border / decoration colours and is required
by `hyprland.lua`. The **shell's** palette + accent live separately in the
Quickshell `Theme.qml`, driven by Settings → Theme (which also writes GTK/Qt via
`../quickshell/scripts/colorscheme.sh`). The toolkit theming env (`QT_QPA_PLATFORMTHEME`,
GTK/cursor vars) is exported in `start-hyprland.sh` **before** `exec Hyprland`, not
via `hl.env()` — propagation to on-demand-launched apps is unreliable otherwise.

## GPU notes (Intel Lunar Lake / Arc, `xe` driver)

- The `xe` hardware-cursor plane is flaky (cursor freeze/garble), so `hyprland.lua`
  sets `cursor:no_hardware_cursors = true`.
- The `xe` driver also has a DPMS-resume bug that can strand a black screen, so
  `hypridle.conf` **locks but never powers the panel off**. On hardware without the
  bug, add a `dpms off` listener back.
- If the screen ever tears/hangs/corrupts: log in once with `DE_SOFTWARE_RENDER=1`
  set — `start-hyprland.sh` honours it and forces software rendering.

## Keybindings

Mod is **Super**. Full list in [`SHORTCUTS.md`](SHORTCUTS.md). First keys:
`Super+Return` (terminal), `Super+D` (Launcher), `Super+,` (Settings),
`Super+N` (Quick Settings).
