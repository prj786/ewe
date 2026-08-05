<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="system/branding/ewe-logo-dark.png">
    <img src="system/branding/ewe-logo-light.png" width="190" alt="ewe — a line-art sheep in a circle">
  </picture>
</p>

<h1 align="center">ewe</h1>

<p align="center">
  <b>A clean, dark, complete desktop environment for Arch Linux.</b><br>
  Hyprland + Quickshell, turned into a full DE by one installer.
</p>

<p align="center">
  <a href="https://github.com/prj786/ewe/releases"><img src="https://img.shields.io/github/v/release/prj786/ewe?include_prereleases&sort=semver&label=release&color=8fbce0" alt="release"></a>
  <a href="https://github.com/prj786/ewe/actions/workflows/ci.yml"><img src="https://github.com/prj786/ewe/actions/workflows/ci.yml/badge.svg" alt="ci"></a>
  <img src="https://img.shields.io/badge/distro-Arch%20only-1793d1" alt="Arch only">
  <img src="https://img.shields.io/badge/session-Wayland-7fb1da" alt="Wayland">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/prj786/ewe?color=blue" alt="license: GPL-2.0"></a>
</p>

---

**ewe** *(the sheep, [juː])* is an opinionated, installable desktop: **Hyprland**
(Wayland compositor, Lua-configured) with a **Quickshell** QML shell — bar, dock,
launcher, notifications, Quick Settings, lock, OSD, clipboard history — plus the
**Komble** software manager (pacman + AUR + AppImages), the **ewe-settings**
app, a themed greeter and a silent Plymouth boot. One flock theme, one icon
language, everything matching.

> **Beta** (`0.5.0-beta`) · **Arch only** — assumes `pacman` + the AUR. Arch
> derivatives (EndeavourOS, CachyOS, Garuda, Manjaro) should work. Daily-drivable,
> but read the [known limitations](docs/MANUAL.md#known-limitations).

## Install

On a minimal Arch install (run as your normal user, not root):

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/prj786/ewe/main/get.sh)
```

That downloads the latest release to `~/.local/share/ewe` and runs the
installer — no git, no clone. It prompts before every change; add `--yes` for
unattended, `--dry-run` to see everything it would do first, `--gaming` /
`--dev` for the optional package stacks. Re-run the same one-liner to update.

<details>
<summary>From a clone instead</summary>

```sh
git clone https://github.com/prj786/ewe ~/ewe && cd ~/ewe
bash install.sh              # prompts before each change
./update.sh                  # later: pull + converge + restart the shell
```
</details>

The installer is idempotent and safe: every existing config is backed up before
being touched, a missing package is skipped rather than aborting the run, and
`uninstall.sh` restores your backups. Details in the [manual](docs/MANUAL.md).

Then reboot, pick **Ewe** at the login screen, and you're in —
`Super+Return` terminal · `Super+D` apps · `Super+,` Settings
(full keymap: `dotfiles/hypr/SHORTCUTS.md`).

## A look around

https://github.com/user-attachments/assets/a2ffb2e1-2482-46c7-911d-c94bb8413434

| | |
|---|---|
| **Tiling workflow**<br><img src="docs/media/2026-06-25_17-36-24.png" alt="Tiling workflow"> | **Launcher** — fuzzy app / file search<br><img src="docs/media/2026-06-25_17-37-21.png" alt="Launcher"> |
| **Quick Settings**<br><img src="docs/media/2026-06-25_17-37-57.png" alt="Quick Settings"> | **Software manager** — pacman + AUR<br><img src="docs/media/2026-06-25_17-36-39.png" alt="App Store"> |

<sub>More in [`docs/media/`](docs/media). Accent and light/dark are yours to change — Settings → Theme recolours the whole desktop live.</sub>

## What you get

- **The whole desktop, not a starting point** — greeter to lock screen, themed
  end to end, working out of the box.
- **Silent boot** — Plymouth splash from early boot to greeter, no kernel text.
- **One theme, one icon language** — the flock look across the shell, GTK apps,
  Qt strays, icons and cursor; accent changes apply live.
- **Curated GTK app set** — Nemo, Engrampa, imv, Zathura, mpv, kitty: borderless
  under Hyprland, defaults managed in one `mimeapps.list`.
- **Komble + ewe-settings** — first-party software manager and settings app.
- **Optional Google account** — calendar, Gmail unread + notifications, and
  settings sync to Drive; native OAuth, no GNOME Online Accounts.
- **Optional phone link** — KDE Connect daemon driven from the shell: phone
  battery, notifications, SMS from the control centre.

## Docs

| | |
|---|---|
| [Manual](docs/MANUAL.md) | phases, packages, safety model, Google/phone setup, limitations |
| [Shortcuts](dotfiles/hypr/SHORTCUTS.md) | the full keymap |
| [Settings backend](docs/SETTINGS-BACKEND.md) | how Settings writes Hyprland config |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | post-freeze playbook and friends |

A proper website is on the way; until then the manual is the deep dive.

## Feedback

It's a beta — reports genuinely help.
[Bugs](https://github.com/prj786/ewe/issues/new?template=bug_report.yml) ·
[Feature requests](https://github.com/prj786/ewe/issues/new?template=feature_request.yml) ·
[Discussions](https://github.com/prj786/ewe/discussions) ·
Security: privately via the repo's **Security** tab ([SECURITY.md](SECURITY.md)).

## Credits & license

Designed and built by **scubba**, pair-programmed with
[Claude Code](https://claude.com/claude-code). Built on
[Hyprland](https://hypr.land) and [Quickshell](https://quickshell.org).

**GPL-2.0-only** — see [LICENSE](LICENSE). Use it, study it, share it; modified
versions you distribute must ship under the same terms.
