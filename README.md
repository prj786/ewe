<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="system/branding/ewe-logo-dark.png">
    <img src="system/branding/ewe-logo-light.png" width="190" alt="ewe — a line-art sheep in a circle">
  </picture>
</p>

<h1 align="center">ewe</h1>

<p align="center">
  <b>The desktop environment of ewe OS.</b><br>
  Hyprland + Quickshell, shipped as one package — bar, dock, launcher, lock, settings and all.
</p>

<p align="center">
  <a href="https://prj786.github.io"><img src="https://img.shields.io/badge/website-prj786.github.io-8fbce0" alt="website"></a>
  <a href="https://github.com/prj786/ewe/releases"><img src="https://img.shields.io/github/v/release/prj786/ewe?include_prereleases&sort=semver&label=release&color=8fbce0" alt="release"></a>
  <a href="https://github.com/prj786/ewe/actions/workflows/ci.yml"><img src="https://github.com/prj786/ewe/actions/workflows/ci.yml/badge.svg" alt="ci"></a>
  <img src="https://img.shields.io/badge/distro-Arch%20only-1793d1" alt="Arch only">
  <img src="https://img.shields.io/badge/session-Wayland-7fb1da" alt="Wayland">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/prj786/ewe?color=blue" alt="license: GPL-2.0"></a>
</p>

---

**ewe** *(the sheep, [juː])* is an Arch-based **operating system** — and this repo
is the layer you actually look at: the desktop environment. **Hyprland** (Wayland
compositor, Lua-configured) with a **Quickshell** QML shell — bar, dock, launcher,
notifications, control centre, lock, OSD, clipboard history — plus the greeter, a
silent Plymouth boot, the CLI tools, and the `ewe` package that installs the lot.

> **Most people don't want this repo — they want the ISO.**
> ewe OS installs in about ten minutes and decides the technical parts for you:
> **[prj786.github.io/download](https://prj786.github.io/download/)** ·
> [ewe-os](https://github.com/prj786/ewe-os)

> **Beta** — the `0.9.x` line. **Arch only** (assumes `pacman` + the AUR).
> Daily-drivable; read the [known limitations](docs/MANUAL.md#known-limitations)
> first.

## Install

### The whole OS (recommended)

Download the ISO, write it to a stick, boot it, install. The live session *is*
this desktop, so you can try everything before touching a disk —
**[the install guide](https://prj786.github.io/download/)**.

### Just the desktop, on Arch you already have

The DE is a normal package in a normal pacman repository. Add `[ewe]` to
`/etc/pacman.conf` (see [ewe-repo](https://github.com/prj786/ewe-repo)), then:

```sh
sudo pacman -S ewe        # the desktop, Komble, ewe-settings and dependencies
```

Per-user deployment is `ewe-setup`; system setup (greeter, plymouth, hibernate)
is `/usr/share/ewe/install.sh`. Afterwards `sudo pacman -Syu` updates the
desktop like anything else, and the session refreshes itself at login whenever a
newer payload has landed.

<details>
<summary>From a clone, for hacking on it</summary>

```sh
git clone https://github.com/prj786/ewe ~/ewe && cd ~/ewe
bash install.sh              # symlink farm; prompts before each change
./update.sh                  # pull + converge + restart the shell
```

Or the release tarball without git:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/prj786/ewe/main/get.sh)
```

Both are idempotent and back up every config they touch; `uninstall.sh` restores
them. Details in the [manual](docs/MANUAL.md).
</details>

Then reboot, pick **Ewe** at the greeter, and you're in —
`Super+Return` terminal · `Super+D` apps · `Super+,` Settings
(full keymap: `dotfiles/hypr/SHORTCUTS.md`).

## What you get

- **The whole desktop, not a starting point** — greeter to lock screen, themed
  end to end, working out of the box.
- **Dark by decision** — two dark looks (`flock` neutral greys, `blacksheep`
  absolute black for OLED). There is no light mode, deliberately.
- **One theme, one icon language** — the look carries across the shell, GTK apps,
  Qt strays, icons and cursor; the accent applies live, with no relogin.
- **The machine as one file** — `~/.config/ewe/ewe.conf` describes the desktop;
  every runtime file is generated from it ([RFC-001](docs/RFC-001-one-config.md)).
- **Curated GTK app set** — Nemo, Engrampa, imv, Zathura, mpv, kitty, Zed:
  borderless under Hyprland, defaults managed in one `mimeapps.list`.
- **Komble + ewe-settings** — first-party software manager and settings app.
- **Optional Google account** — calendar, Gmail unread + notifications, settings
  sync to Drive, and your Drive mounted as a folder. One consent screen for every
  ewe app, native OAuth, no GNOME Online Accounts ([RFC-002](docs/RFC-002-broker-and-sync.md)).
- **Optional phone link** — KDE Connect's daemon driven from the shell: phone
  battery, notifications and SMS from the control centre.
- **Cast to TV** — a control-centre card mirrors the desktop to a Samsung
  (Miracast) or Chromecast/Google TV, served by ewe's own headless daemon
  ([ewe-cast](https://github.com/prj786/ewe-cast)) — no foreign window — with
  ewe's share picker (live previews, real display names) for every screen-share.

## The CLI

Every graphical thing here is a front end to one of these, so anything you can
click, you can script — and debug by running the same command yourself.

| | |
|---|---|
| [`ewe-conf`](bin/ewe-conf) | the one file: `get` · `set` · `dump` · `import` · `apply` · `push` · `pull` |
| [`ewe-auth`](bin/ewe-auth) | one Google identity for every ewe app: `status` · `login` · `token` · `logout` |
| [`ewe-drive`](bin/ewe-drive) | your Drive as a folder: `setup` · `mount` · `unmount` · `status` |
| `ewe-setup` | per-user deployment of the installed payload |
| `ewe-share-picker` | the portal's screen-share picker, backed by the shell |

Every one prints JSON and exits 0, so callers never hang on them. The refresh
token lives only in the keyring — `ewe-auth` is the single thing that touches it.

## The project

| repo | role |
|---|---|
| [ewe-os](https://github.com/prj786/ewe-os) | the distro — archiso profile, the live/install ISO |
| ewe | this — the desktop environment + the `ewe` package |
| [ewe-repo](https://github.com/prj786/ewe-repo) | the `[ewe]` pacman repository |
| [komble-arch](https://github.com/prj786/komble-arch) | Komble — the software manager |
| [ewe-settings](https://github.com/prj786/ewe-settings) | the Settings app |
| [ewe-cast](https://github.com/prj786/ewe-cast) | `ewe-castd` — the headless casting daemon |
| [prj786.github.io](https://github.com/prj786/prj786.github.io) | the website |

## Docs

| | |
|---|---|
| [Website](https://prj786.github.io) | what ewe is, the install path, the philosophy |
| [Manual](docs/MANUAL.md) | phases, packages, safety model, Google/phone setup, limitations |
| [Shortcuts](dotfiles/hypr/SHORTCUTS.md) | the full keymap |
| [RFC-001](docs/RFC-001-one-config.md) | one file: `ewe.conf` |
| [RFC-002](docs/RFC-002-broker-and-sync.md) | the auth broker and the sync of that file |
| [Settings backend](docs/SETTINGS-BACKEND.md) | how Settings writes Hyprland config |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | post-freeze playbook and friends |

## Feedback

Reports genuinely help — especially from real hardware.
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
