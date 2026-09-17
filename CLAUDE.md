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
from source art with an ink-extraction script, alpha = darkness). The deep
rename landed 2026-08-19: the user unit is `ewe.service`, state lives in
`~/.local/state/ewe`, and every system file is `*ewe*`-named. The old-name
references that remain in phases 20/30/32/35 and the deploy/startup scripts
are MIGRATIONS (remove old unit/drop-ins/state on upgrade) — leave them until
a release or two has passed. The dev checkout may still sit in a directory
called `hypr-shell`; that's outside the repo. Distribution:
`get.sh` (curl bootstrap → `~/.local/share/ewe`) installs the
`ewe-<version>.tar.zst` artefact built by `release.sh` (`--publish` creates the
GitHub release).

## Design system

- The design system in `design/system/` is the source of truth for how every surface looks.
- Read `design/system/guidelines/40-implementation.md` before UI work.

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
project skill `run-ewe` (`.claude/skills/run-ewe/driver.sh`), which
nests a throwaway Hyprland on its own Wayland socket and screenshots it with grim —
the host's real session is untouched:

```bash
.claude/skills/run-ewe/driver.sh check          # luac -p on hyprland.lua + colors.lua
.claude/skills/run-ewe/driver.sh up             # launch nested compositor + shell; waits for "Configuration Loaded"
.claude/skills/run-ewe/driver.sh open settings  # toggle a surface + screenshot -> /tmp/hs-driver/<name>.png
.claude/skills/run-ewe/driver.sh targets        # list every IpcHandler target + function
.claude/skills/run-ewe/driver.sh log            # tail the shell's qs log (QML errors name file:line)
.claude/skills/run-ewe/driver.sh down           # tear down
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
  so changing the accent recolours the whole shell live. Values come from
  `bin/ewe-theme` (scheme + accent in `ewe.conf` → every token of the Ewe
  design system v3, `design/system/`); `design/check-spec.sh` holds the
  generated `design/tokens.css` to `design/system/tokens.json` and
  `design/check-contrast.sh` holds the derivation to the contrast rules.
- **`BtAgent.qml`** — the bluez pairing agent (`scripts/bt-agent.py`, default
  `org.bluez.Agent1`, NDJSON over stdio like `KdeConnect.qml`); `BtPairing.qml`
  is its dialog. Device state still comes from `Quickshell.Bluetooth`; pairing
  and connecting go through `BtAgent.pair()/connectDevice()` so failures have a
  reason. `bin/ewe-bt` is the same for the Settings app (see
  `docs/SETTINGS-BACKEND.md`).
- **First-party plugins (2026-09-16, `plugins/`)** — the clipboard history
  (`ewe.clipboard`: scissors bar widget + popup + the `wl-paste --watch`
  service that used to live in autostart.sh), screenshots (`ewe.screenshot`:
  camera widget, preview stack, Print keybinds) and the password fill picker
  (`ewe.passwords`: Super+P, its own `ewe-pass` honouring `EWE_PASS_PROVIDER`/
  `EWE_PASS_ENTER` from the plugin's settings) are **plugins, not shell
  components**. Their repos are `prj786/ewe-plugin-{clipboard,screenshot,
  passwords}`; `scripts/vendor-plugins.sh` copies them into `plugins/<id>/`
  (vendored copies — `git archive` ships them; a submodule would arrive
  empty). `ewe-setup` runs `ewe-plugin seed <payload>/plugins`: each bundled
  plugin is copied into `~/.config/ewe/plugins/<id>/` with source `bundled`
  and enabled, refreshed when its version changes; `ewe-plugin remove` puts
  the id in `[plugins].removed` so a later seed leaves it alone
  (`seed --restore <id>` undoes that). Manifest `keybinds` become
  `generated/plugin-keybinds.lua` (written by every state-changing verb,
  sourced by hyprland.lua) — the Print keys and Super+P are no longer in
  hyprland.lua. Reserved `ewe.` ids validate only in the payload or with
  `--first-party`. `GlobalShortcuts.qml` + `bin/ewe-globalshortcuts` (portal
  global shortcuts, 1Password Quick Access…) stay in the shell. Tests:
  `tests/ewe-plugin-test.sh` (seed/remove/keybinds), the passwords plugin's
  own `test.sh`, `tests/ewe-globalshortcuts-test.sh`.
- **Plugin kit (2026-09-16):** `ewe-plugin create|dev|place|set|get`;
  manifest v1 gains kind `desktop-widget`, `desktopWidget` defaults and a
  typed `settings` schema (5 types, validated). User side in ewe.conf
  `[plugins.widgets]` / `[plugins.settings]` keyed by quoted id (dots!) —
  always written as whole tables. `DesktopWidgets.qml` = two full-output
  layer windows per screen (Bottom = desktop, Top = sticky), input mask =
  union of widget rects, arrange mode via `Globals.widgetsArrange`
  (Super+Shift+W, IPC `widgets`). `PluginHost.reload()` (IPC
  `plugins reload`) re-reads placement + settings without a restart and
  pushes `settings` into every instance that declares the property. Inside
  a Scope use `Variants`, never `Repeater` (needs an Item parent — silently
  creates nothing). Test: `tests/ewe-plugin-test.sh`.
- **`AudioState.qml`** — where sound goes (headset / headphones / external /
  built-in, from the default sink's PipeWire properties), the level, whether an
  app has the mic open (a link from the default source to a stream — Quickshell
  0.3.1 never reports link STATE, so "open" is the signal), and the
  follow-the-device policy: a headset that appears becomes the output (and
  input), and output returns to where it was when the headset leaves.
  WirePlumber will not do this once a user ever picked a default. The bar's
  sound and mic glyphs read it.
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
`IpcHandler { target: "<name>" }` in a component — targets: `bar cast picker quicksettings
launcher lock osd overview places player preview settings applauncher store updates plugins widgets`
(plus each plugin's own, `ewe.clipboard ewe.screenshot ewe.passwords`…). Most expose
`toggle`/`show`/`hide`. Gotcha: `qs ipc call <t> show` collides with the `qs ipc
show` subcommand and no-ops — bind to **`toggle`**.

Drag-out idiom (used by Places and the screenshot plugin's preview): an invisible proxy `Item` with
`Drag.active` + `Drag.mimeData: ({"text/uri-list": "file://"+path+"\r\n"})`, plus a
box-only `mask: Region { item: box }` so clicks/drags outside the panel pass
through to apps behind it.

### Theming (single source: `scripts/colorscheme.sh`)

**Schemes + the v3 generator (2026-09-17, branch `ewe-design-v3`, Phase 1):**
`bin/ewe-theme` derives the Ewe design system v3 token set from a Base24
scheme + an accent (`design/system/guidelines/10-color-schemes.md`): Ewe
Dark (`ewe-dark`, the default) and Ewe Light are records embedded in the
tool and marked `builtin` (tests hold them to
`design/system/assets/Schemes/*.json`); user schemes live in
`[[desktop.theme.schemes]]`. Derivation → `overrides` → guarantees (text
4.5:1, borders 3:1, surfaces 2 L apart, warning ≠ accent hue; every move
recorded in `adjusted`, shown by `scheme show`) → look presets and
accessibility modes as remaps. The pre-v3 value `scheme = "accent"` reads
as ewe-dark wearing `desktop.theme.accent`; `corner = round` reads as
`large`. Every Fluent name is still emitted as an alias (Migration guide)
until Phase 6. `ewe-theme scheme list|show|apply|import|duplicate|remove|
export|set|from-wallpaper` is the CLI (imports: base16/24 YAML via a mini
parser, Omarchy TOML, Catppuccin JSON, Gogh; wallpaper via ImageMagick
histogram, Pillow fallback); `set overrides.<role> <hex|none>` edits an
override. `build --scheme SLUG --selector SEL` builds the CSS for another
scheme without touching ewe.conf (the website's light/dark toggle).
`colorscheme.sh` reads `input.variant` and `scheme.palette` from
theme-tokens.json (GTK light switch, Qt/KDE palettes from tokens, kitty
ANSI); `ewe-conf effective_accent()` gives the border and the colorscheme
hook the scheme's accent; `Globals.schemeActive` stops the in-shell accent
pick from overriding a scheme. `wallpaper.sh` re-derives when scheme =
"wallpaper".

**Fonts + Theme.qml (2026-09-17, Phases 2-3):** the DE faces are **Geist**
and **Geist Mono** (OFL, not in the Arch repos): the variable woff2 files
ship in `dotfiles/quickshell/fonts/geist/` and `dotfiles/fontconfig/fonts.conf`
adds that folder with a relative `<dir>` (no installer change) and prefers
**Noto Sans Georgian** (noto-fonts) next in every stack — Geist has no
Georgian glyphs, and Georgian is NEVER uppercased (`Theme.labelCaps` is
MixedCase for good). GTK, kitty (with the Nerd PUA mapped to Symbols Nerd
Font Mono), Zed, mpv, the groupbar and Helium follow; the greeter keeps
Inter because it runs from /etc as another user. `Theme.qml` is now one
property per v3 token (QML names from `40-implementation.md`), plus
`Theme.type.<style>` (both `body-strong` and `bodyStrong`), the motion
table (`durFast/Base/Slow/Dim`, OutCubic + InOutCubic, no OutBack), the
Glass trio (`glass`, `barAlpha`, `glassBlur` — `EWE_NO_BLUR=1` keeps the
translucency, drops the blur) and the accessibility modes. Every Fluent
name still exists pointing at its Ewe role (Migration guide) until Phase 6.
**Gotcha:** `onAccent: <expr>` beside a property called `accent` parses as a
signal handler — the token is declared bare and filled by a `Binding`.
Iterating: `.claude/skills/run-ewe/driver.sh` now sandboxes HOME/XDG and
generates the tokens itself (`HS_SCHEME=ewe-light`, `HS_CONF=<ewe.conf>`),
so the live config and ewe-conf's sync hooks are never touched.

**Bar & dock opacity:** `desktop.theme.bar_opacity = 0..100` in ewe.conf
(Settings → Appearance slider). The bar and dock are painted at
`Theme.barAlpha` (`barTop`, `dockFill`); between 10 and 99 `ewe-conf` writes
the compositor blur + a `quickshell:(bar|dock)` layer rule into
`generated/user.lua`; `EWE_NO_BLUR=1` (VMs, NVIDIA — `start-hyprland.sh`)
skips the blur. `desktop.theme.app_blur` draws every WINDOW at 85 % with blur
behind it (`decoration.active/inactive_opacity`, fullscreen opaque) — fixed, not
the slider. Every other panel (`Theme.panel`) stays opaque. Prefs the
Settings app writes MUST be in `ewe-conf`'s `THEME_MAP`, or `absorb` drops
them on the next write (that was the 0.12.7 "Top bar settings do nothing").

`colorscheme.sh <mode> [accent-hex]` writes *every* toolkit's config in one
pass — ewe is **dark-only by decision (2026-09-01)**; the mode argument is
accepted and ignored for caller compatibility. GTK is **primary** (adw-gtk3 + gsettings + `gtk-3.0/4.0/settings.ini`); Qt
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
