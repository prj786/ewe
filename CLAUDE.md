# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**ewe** (as in the sheep; repo `prj786/ewe`, formerly `hypr-shell` — old URLs
redirect) is an installable, **Arch-Linux-only**, clean dark desktop
environment: **Hyprland** (Wayland compositor, configured in Lua) + **Quickshell**
(a QML shell — bar, dock, launcher, notifications, quick settings, settings,
app store, lock, OSD). `install.sh` turns a minimal Arch install into the full DE.
Read `README.md` for the user-facing rationale (it is the source of truth). The
project is **Arch-only** end to end — no Fedora/COPR/`dnf`/GDM paths remain.

There is **no application source to compile and no test suite.** "Building" means
running the installer; "testing" means the verification commands below.

**Branding vs. plumbing:** the user-facing name is **ewe** (README, session
entry "Ewe", plymouth theme `ewe`, the sheep line-art logos in
`system/branding/ewe-logo-{dark,light}.png` + `dotfiles/quickshell/assets/logo.png`
+ `system/plymouth/ewe/watermark.png` — all transparent-background, regenerate
from source art with an ink-extraction script, alpha = darkness). Remaining
on-disk identifiers — the dev-host repo dir, `hypr-shell.service`,
`~/.local/state/hypr-shell` — are still hypr-shell-era. Don't rename those
piecemeal; a deep rename is a separate coordinated change. Distribution:
`get.sh` (curl bootstrap → `~/.local/share/ewe`) installs the
`ewe-<version>.tar.zst` artefact built by `release.sh` (`--publish` creates the
GitHub release).

## Development workflow (critical)

- **Work in the repo, then push — do not edit the live `~/.config`.** This repo is
  developed on a non-Arch dev host and deployed by the user pulling + re-running
  `install.sh` inside a throwaway QEMU/KVM Arch VM. Everything must work from a
  clean `git clone`. Never run `dotfiles/quickshell/scripts/colorscheme.sh`
  against the dev host — it rewrites the real `~/.config` (GTK/Qt/cursor theming).
- **Pushing requires the user's 1Password SSH agent (must be unlocked):**
  `SSH_AUTH_SOCK=/home/<user>/.1password/agent.sock git push origin main`
- **Commit/push only when asked.** Branch off if on the default branch otherwise.

## Commands

Iterate on the Quickshell QML and Hyprland Lua **without installing**, via the
project skill `run-hypr-shell` (`.claude/skills/run-hypr-shell/driver.sh`), which
nests a throwaway Hyprland on its own Wayland socket and screenshots it with grim —
the host's real session is untouched:

```bash
.claude/skills/run-hypr-shell/driver.sh check          # luac -p on hyprland.lua + colors.lua
.claude/skills/run-hypr-shell/driver.sh up             # launch nested compositor + shell; waits for "Configuration Loaded"
.claude/skills/run-hypr-shell/driver.sh open settings  # toggle a surface + screenshot -> /tmp/hs-driver/<name>.png
.claude/skills/run-hypr-shell/driver.sh targets        # list every IpcHandler target + function
.claude/skills/run-hypr-shell/driver.sh log            # tail the shell's qs log (QML errors name file:line)
.claude/skills/run-hypr-shell/driver.sh down           # tear down
```

- **QML has no live reload here** — after editing a `*.qml`, run `down && up`, then
  `open <surface>`, then **read the PNG** to confirm. A ~15 KB shot = bar only
  (surface didn't open); a real window is ~40–57 KB.
- A QML error makes `qs` die on `up`; inspect with the `log` subcommand. Ignore the
  benign "already registered" D-Bus / PolkitAgent / "hyprland-guiutils not
  installed" warnings (artifacts of nesting beside a live session).
- After editing shell scripts: `bash -n <file>`.

Installer (only meaningfully runs on Arch, but the dry-run is safe anywhere):

```bash
bash install.sh --dry-run     # print every action, change nothing (verify the pipeline)
bash install.sh --check-only  # run only phase 90's green/red verification checklist
bash install.sh               # full install (prompts before each change)
```

## Architecture

Two independent halves: a **shell-script install pipeline** and the **QML shell**.

### Install pipeline (`install.sh` + `lib/` + `phases/`)

`install.sh` sets `DOTREPO` (repo root) and `RUN_STAMP` (one fixed backup
timestamp per run — there is no `Date.now`-style drift), sources `lib/*.sh` then
`phases/NN-*.sh`, calls `detect_all`, and runs the phases in order:

| | |
|---|---|
| 00 preflight · 10 repos (paru; multilib only with --gaming) · 20 packages · 30 services (greetd/ReGreet) · 32 hibernate (swapfile + resume= for suspend-then-hibernate) · 35 bootsplash (plymouth) · 37 cpu microcode (intel/amd-ucode) · 40 gpu · 50 dotfiles · 60 userconfig · 90 postcheck | each phase is a `phase_<name>` function |

Cross-cutting mechanisms — understand these before touching any phase:

- **One choke point: `run()` / `sudo_run()` in `lib/log.sh`.** Every mutating action
  goes through them, which is what makes `--dry-run` honest and the whole thing
  re-runnable. Never call `cp`/`ln`/`pacman`/`systemctl` directly in a phase — wrap
  it in `run`.
- **Resilient package install (`lib/pkg.sh`).** `pacman -S` is all-or-nothing, so
  `install_official`/`install_aur` try the batch, then on failure retry
  package-by-package, **warn-and-skip** the missing ones, and always `return 0`. A
  single bad/unavailable package name must never abort the run (this was the root
  cause of a "no greeter" failure). Package lists are `packages/common.list`
  (pacman) and `packages/aur.list` (paru); the opt-in `packages/gaming.list` is
  installed only with `--gaming` (which also flips on [multilib] in phase 10 and
  the lib32 GPU drivers in phase 40). Real Arch names, `#` comments stripped.
- **Symlink farm with backups (`lib/deploy.sh`).** `link_tree` symlinks
  `dotfiles/<x>` → `~/.config/<x>`, moving any existing real dir to
  `<dest>.bak.<RUN_STAMP>` first (re-linking is a no-op). systemd user units are
  *copied*, not symlinked.
- **User-state seeding.** Files matching `*.default` (committed) seed their
  gitignored runtime counterparts only when missing — see `.gitignore`
  (`user-theme.json`, `pinned-apps.json`, `places.json`, `hypr/generated/user.lua`).
  Edit the `.default`; never commit the runtime file.

### Quickshell shell (`dotfiles/quickshell/`)

`shell.qml`'s `ShellRoot` instantiates every top-level component (`Bar`, `Dock`,
`QuickSettings`, `Settings`, `AppStore`, `Notifications`, …). Components are
registered in `qmldir`. Two singletons tie everything together:

- **`Globals.qml`** — shared mutable shell state (`quickSettingsOpen`, `settingsOpen`,
  `accentColor`, `version`, pinned lists, the live `NotificationServer`, …).
  In-shell toggles flip a `Globals` bool directly (no IPC round-trip).
- **`Theme.qml`** — the palette/metrics; `accent` binds to `Globals.accentColor`
  so changing the accent recolours the whole shell live.
- **`HyprMon.qml`** — display manager: per-monitor-set profiles
  (`display-profiles.json` → `hypr/generated/monitors.lua`), live apply via
  `hyprctl eval 'hl.monitor{…}'`, re-assert on hotplug/AC events. The Settings
  app also generates `hypr/generated/input.lua` and `wallpapers.conf`. See
  `docs/SETTINGS-BACKEND.md` for the full write-through contract.

Two first-party apps live in their own repos and are installed by phase 20 from
prebuilt GitHub releases: **Komble** (`prj786/komble-arch` — THE software
manager: pacman + AUR + AppImages) and **ewe-settings**
(`prj786/ewe-settings` — THE settings UI; binary `ewe-settings`, with a
`hypr-settings` compat symlink). When their binaries are
present every entry point launches them (`Globals.openStore()/openSettings()`);
the in-shell AppStore/Settings panels remain only as fallbacks. ewe-settings
writes the same generated files as the in-shell panel (see
`docs/SETTINGS-BACKEND.md`) and pokes `qs ipc call settings reload`.

External control (keybinds, scripts) uses **`qs ipc call <target> <fn>`** against an
`IpcHandler { target: "<name>" }` in a component — targets: `bar clipboard quicksettings
launcher lock osd overview places preview settings applauncher store`. Most expose
`toggle`/`show`/`hide`. Gotcha: `qs ipc call <t> show` collides with the `qs ipc
show` subcommand and no-ops — bind to **`toggle`**.

Drag-out idiom (used by Places/ScreenshotPreview): an invisible proxy `Item` with
`Drag.active` + `Drag.mimeData: ({"text/uri-list": "file://"+path+"\r\n"})`, plus a
box-only `mask: Region { item: box }` so clicks/drags outside the panel pass
through to apps behind it.

### Theming (single source: `scripts/colorscheme.sh`)

`colorscheme.sh <dark|light> [accent-hex]` writes *every* toolkit's config in one
pass — GTK is **primary** (adw-gtk3 + gsettings + `gtk-3.0/4.0/settings.ini`); Qt
gets a dark Fusion palette via `qt6ct` (`QT_QPA_PLATFORMTHEME=qt6ct`) as a fallback
for stray Qt apps; a `kdeglobals` fallback covers any KDE app added later; plus the
Reversal icon theme (hue-matched to the accent) and the Mocu cursor. It is `set -u`
(not `-e`) on purpose so a stray non-zero line never aborts before all files are
written. Called live by Settings → Theme, at shell startup, and by phase 60.

### Key design decisions (don't relitigate)

- **First-party apps are traditional GTK** (Nemo, Engrampa, imv, Zathura, mpv) — not
  KDE/Qt, not GNOME/libadwaita. Traditional GTK apps use a menubar + server-side
  decorations, so under Hyprland (no titlebar) they render borderless; only
  libadwaita forces an unhideable headerbar. Going all-GTK also makes one
  `~/.config/mimeapps.list` (read natively by GIO) the single source for default
  apps — no KDE `ksycoca` cache. Do not propose reverting to Qt/KDE apps or
  `plasma-integration`.
- **Toolkit theming env is exported in `dotfiles/hypr/start-hyprland.sh` before
  `exec Hyprland`**, not via `hl.env()` in `hyprland.lua` — `hl.env` propagation to
  on-demand-launched apps is unreliable.
- **Hyprland config is Lua** (`hyprland.lua` requires `colors.lua`), needs Hyprland
  **≥ 0.55**. User overrides land in `hypr/generated/user.lua` (sourced last).

### Versioning

Canonical version is the repo-root **`VERSION`** file (semver + `-alpha`/`-beta`).
The shell mirrors it in `Globals.version` (shown in the Settings sidebar) — **bump
both** and tag `vX.Y.Z` on release. (`VERSIONS`, plural, is unrelated — it documents
minimum tool versions.)
