# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**ewe** (as in the sheep; repo `prj786/ewe`, formerly `hypr-shell` — old URLs
redirect) is an installable, **Arch-Linux-only**, clean dark desktop
environment: **Hyprland** (Wayland compositor, configured in Lua) + **Quickshell**
(a QML shell — bar, launcher, notifications, quick settings, settings,
app store, lock, OSD; the dock and the other extras are first-party plugins). `install.sh` turns a minimal Arch install into the full DE.
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
GitHub release, then fires `prj786/ewe-repo`'s `publish` workflow by
`repository_dispatch` — that workflow builds the `ewe` pacman package of the
`[ewe]` repository from the LATEST release tag and takes ~35 min; until
0.35.3 it was a manual step, so a release was "not ready" for pacman installs
until someone ran it or the Monday cron did). `update.sh` knows three installs
(0.35.3): a git clone pulls origin, a tarball install (no `.git`) downloads the
newest release the way get.sh does and unpacks it in place, a pacman install
is pointed at `pacman -Syu` (`--check` reads `checkupdates` for a newer `ewe`
package); `--check`/`--json` keep Komble's exit-code contract (0/10/20/30/1).
Test: `tests/ewe-update-test.sh` (fake curl/pacman/checkupdates/systemctl on
PATH).

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
- **Keys in the nest:** a virtual keyboard (`wtype`) never reaches the nested
  Hyprland's binds (plain keys do reach the focused surface — `wtype -k
  Escape` tests a panel's keyboard focus). Exercise a bind by what it does:
  `driver.sh hc eval '<the hl.bind line>'` registers it, `driver.sh hc
  dispatch 'hl.dsp.global("<id>:<name>")'` fires a global shortcut; windows
  come from `driver.sh spawn kitty --title win1`, a group from
  `hc dispatch 'hl.dsp.group.toggle()'` (new windows then auto-join). Kill a
  stale nest by process name (`pgrep -a -x Hyprland | grep hs-driver`), never
  with `pkill -f` on a string your own shell command contains.

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

`shell.qml`'s `ShellRoot` instantiates every top-level component (`Bar`,
`QuickSettings`, `Launcher`, `Overview`, `Notifications`, `Toast`, `Lock`,
`Osd`, `Auth`, `SharePicker`, `Welcome`, the lazy `Settings`/`AppStore`
fallbacks, …). Components are registered in `qmldir`. **Since 0.25 the
dock (+ launcher panel), Places, the music player, Insomnia (keep awake),
the CPU/memory meters, SSH, VPN, the phone (KDE Connect), mail (+ the Gmail
half of Google.qml) and Cast are NOT shell components — they are
first-party plugins (`ewe.dock ewe.places ewe.media ewe.insomnia ewe.sysmon
ewe.ssh ewe.vpn ewe.phone ewe.mail ewe.cast ewe.switcher`, repos
`prj786/ewe-plugin-<name>`; `ewe.switcher` — the Alt+Tab window switcher,
2026-10-27 — was written straight into `plugins/`, its repo is still to be
created and vendored), carved out on 2026-10-04; their prefs
(`apps.pinned`, `apps.places`, `network.*`, the mail account) stay in
ewe.conf and the shell exposes what they need through `Shell` (pinnedApps,
bottomInset…). The dock's auto-hide / icon size are its own plugin settings
since Dock 1.1.0 (`desktop.dock.*` is only their `legacy` fallback,
`Shell.dockPrefs`).** Two singletons tie everything together:

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
  `org.bluez.Agent1`, NDJSON over stdio like the Phone plugin’s bridge); `BtPairing.qml`
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
  empty) and records repo + commit + version in `plugins/bundle.json`.
  **First-party plugins in the payload (0.25, plugin API 3 —
  `docs/PLUGINS.md`; the UI called them "add-ons" until 0.25.1, now
  "Plugins" everywhere):** nothing in the
  payload is installed on a FRESH machine; `ewe-setup` and phase 60 run
  `ewe-plugin seed` (bundle `default` ids only, none today, plus a refresh
  of installed bundled copies) then `ewe-plugin migrate` (once per plugin,
  upgraders only — marker `~/.local/state/ewe/addons-migrated`, local). A
  user installs one with `ewe-plugin install <id>` (Komble → Plugins, the
  Welcome screen); `list --json` lists them under `available`. API 3 adds
  the kinds `quick-tile`, `quick-page`, `bar-status`, `dock-item`, the
  public `Shell` singleton (`Shell.qml`: toast, openQuickSettings, actions,
  `bottomInset` — every panel that used to read `Theme.dockClearance` /
  `Globals.dockEnabled` for layout reads it), `AnchoredPopup`, and the
  promoted components (`Qs*`, `Text*`, `Glyph`, `BarModule`, `BarSep`,
  `BarStatusGlyph`); the host loads apiVersion 2 and 3. The harness:
  `HS_PLUGINS=1` installs every payload plugin (`HS_PAYLOAD=<dir>` picks
  the payload), `HS_PLUGIN_DIRS=a:b` adds fixtures
  (`tests/fixtures/plugins/acme.v3demo` exercises every kind),
  `HS_NO_SYSTEMCTL=1` puts a logging no-op `systemctl` on the nested
  shell's PATH (Welcome's plugins step ends in `ewe-plugin install <last>`
  WITHOUT --no-restart = the tool's restart — the shim keeps it off the
  host's ewe.service; `welcome pick|install|finish` drive it). The driver
  runs every `ewe-plugin` call with `HYPRLAND_INSTANCE_SIGNATURE` and
  `WAYLAND_DISPLAY` unset — the tool's `hyprctl reload` / `qs ipc` pokes
  would otherwise hit the LIVE session; do the same by hand.
  `ewe-plugin remove` puts
  the id in `[plugins].removed` so a later seed leaves it alone
  (`install <id>` or `seed --restore <id>` undoes that). Manifest `keybinds` become
  `generated/plugin-keybinds.lua` (written by every state-changing verb,
  sourced by hyprland.lua) — the Print keys and Super+P are no longer in
  hyprland.lua. A keybind is `ipc` (`qs ipc call …`, a spawn) or, API 3 /
  0.36, `global` (`hl.dsp.global("<id>:<name>")` → a `GlobalShortcut
  { appid: "<id>"; name }` in the plugin, no spawn) with Hyprland's
  `release` / `repeat` / `transparent` flags. `transparent` matters: Hyprland
  shadows a modifier's release bind once another bind fired during the hold
  (`src/keybinds/Manager.cpp` `shadowBinds`), so the switcher's "Alt up →
  commit" after Alt+Tab must be transparent — and the panel hears the Alt
  release itself too (ON-DEMAND keyboard focus while open, never Exclusive:
  Hyprland refuses to focus a window while a layer surface holds the
  keyboard exclusively, so the commit's `hl.dsp.focus` was silently lost in
  the race with the panel letting go — verified in the nest 2026-10-27). Reserved `ewe.` ids validate only in the payload, with
  `--first-party`, or INSTALLED as a copy of an id the payload ships
  (`payload_ships` — NOT only `[plugins.sources]` = bundled: ewe.conf syncs,
  and a Restore from the account once left all 13 INVALID; `enable`/`seed`
  write the record back). `GlobalShortcuts.qml` + `bin/ewe-globalshortcuts` (portal
  global shortcuts, 1Password Quick Access…) stay in the shell. Tests:
  `tests/ewe-plugin-test.sh` (seed/remove/keybinds), the passwords plugin's
  own `test.sh`, `tests/ewe-globalshortcuts-test.sh`.
- **Plugin kit (2026-09-16):** `ewe-plugin create|dev|place|set|get` (+ `bar`,
  Show in bar, 0.25.1);
  manifest v1 gains kind `desktop-widget`, `desktopWidget` defaults and a
  typed `settings` schema (5 types, validated). User side in ewe.conf
  `[plugins.widgets]` / `[plugins.settings]` keyed by quoted id (dots!) —
  always written as whole tables. `DesktopWidgets.qml` = three full-output
  layer windows per screen (Bottom = desktop, Top = pinned above the
  windows, Overlay = pinned above everything), input mask = union of widget
  rects; every widget drags and pins from its hover toolbar any time (lock
  stops dragging), arrange mode via `Globals.widgetsArrange`
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
`IpcHandler { target: "<name>" }` in a component — core targets: `bar picker quicksettings
lock osd overview settings applauncher store updates plugins widgets sync cloud google
display power saver welcome toast` (plus each plugin's own, `ewe.clipboard ewe.screenshot
ewe.passwords ewe.safe ewe.companion ewe.slack`…; the legacy targets `cast launcher places player mail` are the first-party
plugins' `ipcAliases` now — present only while that plugin is installed). Most expose
`toggle`/`show`/`hide`. Gotcha: `qs ipc call <t> show` collides with the `qs ipc
show` subcommand and no-ops — bind to **`toggle`**. **The shell's OWN keys
(0.35.2)** — Super+D/N/comma, Super+Alt+L, Super+Shift+B/W/R, the power
button, the swipe-up — are `hl.dsp.global("ewe:<name>")` in hyprland.lua and a
`GlobalShortcut { appid: "ewe"; name }` beside the matching IpcHandler: the
global-shortcuts protocol, no `sh -c qs ipc call` process per press. A press
bind delivers pressed+released, a gesture/dispatch pressed only, a release
bind released only — toggle on `pressed` (the Overview's Super tap is the
release-bind exception, so the swipe has its own `overview-swipe`). Plugin
manifest keybinds still go through `qs ipc call` (the shell cannot reach a
plugin's IpcHandler in-process).

Drag-out idiom (used by the Places plugin and the screenshot plugin's preview): an invisible proxy `Item` with
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
accessibility modes as remaps. **One source (2026-09-18):** the built-ins
are palette + accent only (no `overrides`); accent roles are ramp steps
(`ACCENT_STEP`); shadows and gradients are derived; `black` (#020202) is
the floor and `neutral-0` (#fefdfc) the ceiling of every emitted colour
(`in_range`) — never add a literal hex outside the FOUNDATIONS tables. The pre-v3 value `scheme = "accent"` reads
as ewe-dark wearing `desktop.theme.accent`; `corner = round` reads as
`large`. **Ewe names only (Phase 6, 2026-09-18):** the Fluent aliases
(`bg-1`, `fg-2`, `brand-bg` …) and the old `themes` block are gone from
theme-tokens.json and tokens.css; every reader (Theme.qml, colorscheme.sh,
colors.lua, the greeter, plugins) uses the design system's names.
**Text size** scales the type AND the control heights (`control-*`, whole
px) — rows, fields, buttons and, via `line-height-xs`, badges grow with
their text; icons, spacing, panels stay; the bar steps up an icon size at
130 and the dock keeps its cells (the JSON's `dock` block). In QML never
wrap a `control*` in `Theme.grow()` — it has grown already. `ewe-theme scheme list|show|apply|import|duplicate|remove|
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
Georgian glyphs, and Georgian is NEVER uppercased (small headers are the
`overline` style, which spaces letters and never changes case). GTK, kitty (with the Nerd PUA mapped to Symbols Nerd
Font Mono), Zed, mpv, the groupbar, ewe browser (theme-tokens.json) and Helium (when installed) follow; the greeter (another user, reads no dotfiles) gets them system-wide: phase 30 copies
the geist/ files + OFL to `/usr/share/fonts/ewe/` and
`system/fontconfig/60-ewe-geist.conf` (Noto Sans Georgian next) to
`/etc/fonts/conf.d/`; `uninstall.sh --purge` removes both. `Theme.qml` is now one
property per v3 token (QML names from `40-implementation.md`), plus
`Theme.type.<style>` (both `body-strong` and `bodyStrong`), the motion
table (`durFast/Base/Slow/Dim`, OutCubic + InOutCubic, no OutBack), the
Glass trio (`glass`, `barAlpha`, `glassBlur` — `EWE_NO_BLUR=1` keeps the
translucency, drops the blur) and the accessibility modes. **No Fluent
name is left** (`bg1`, `fg2`, `radiusControl`, `fsBody`, `barIconPx` … were
deleted in Phase 6, along with `Sheen.qml`); the "Theme.qml today → Ewe"
table in `40-implementation.md` maps any old name. No raw colour, size or
duration in QML: literals live only in `bin/ewe-theme` and as Theme.qml's
fallbacks.
**Gotcha:** `onAccent: <expr>` beside a property called `accent` parses as a
signal handler — the token is declared bare and filled by a `Binding`.
Iterating: `.claude/skills/run-ewe/driver.sh` now sandboxes HOME/XDG and
generates the tokens itself (`HS_SCHEME=ewe-light`, `HS_CONF=<ewe.conf>`),
so the live config and ewe-conf's sync hooks are never touched;
`HS_PLUGINS=1` seeds the bundled plugins into the sandbox and
`HS_NO_APPS=1` hides Komble/ewe-settings so the in-shell fallbacks open.
`ewe-plugin` verbs restart the host's `ewe.service` unless given
`--no-restart` — systemctl is not sandboxed.

**Bar & dock opacity:** `desktop.theme.bar_opacity = 0..100` in ewe.conf
(Settings → Appearance slider). The bar and dock are painted at
`Theme.barAlpha` (`barGround`, `dockGround`); between 10 and 99 `ewe-conf` writes
the compositor blur + a `quickshell:(bar|dock)` layer rule into
`generated/user.lua`; `EWE_NO_BLUR=1` (VMs, NVIDIA — `start-hyprland.sh`)
skips the blur. `desktop.theme.app_blur` draws every WINDOW at 85 % with blur
behind it (`decoration.active/inactive_opacity`, fullscreen opaque) — fixed, not
the slider. Every other panel (`Theme.surfaceRaised`) stays opaque. Prefs the
Settings app writes MUST be in `ewe-conf`'s `THEME_MAP`, or `absorb` drops
them on the next write (that was the 0.12.7 "Top bar settings do nothing").

`colorscheme.sh <mode> [accent-hex]` writes *every* toolkit's config in one
pass — ewe is **dark by default with a light mode (owner, 2026-10-14; it was
dark-only from 2026-09-01)**: light or dark comes from the active scheme's
`variant` in `theme-tokens.json`, and the mode argument is accepted and
ignored for caller compatibility. Every generated config must follow the
variant (no dark-only literals; take colours from the tokens), and
`tests/ewe-theme-test.sh` applies Ewe Light to check it. GTK is **primary** (adw-gtk3 + gsettings + `gtk-3.0/4.0/settings.ini`); Qt
gets the scheme's Fusion palette via `qt6ct` (`QT_QPA_PLATFORMTHEME=qt6ct`) as a fallback
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
- **The bar's height is its icons plus `space-xs` above and below** (36 / 40 / 48
  by `[desktop.bar] icon_size` small / normal / large — the old 44 / 48 / 56
  used `space-s`). The right cluster has one rhythm: every gap between tray
  icons, widgets, modules and dividers is `space-xs` (4px). The clock (date and
  time) lives **inside the Quick settings button** — the two share the click
  (toggle Quick settings) and the wheel (volume); there is no separate clock
  module. The Bar card (`design/system/components/Bar/README.md`) is the spec.
  Do not "fix" any of this back.

- **The terminal shell is zsh, started by kitty; the login shell stays bash
  (2026-09-21).** `dotfiles/shell/` (`ewe.zsh`, `ewe.bash`, `aliases.sh`,
  `shell-setup.sh`) is linked to `~/.config/ewe-shell`; `shell-setup.sh` is the
  ONLY writer of the rc files and runs from phase 60 AND `packaging/ewe-setup`
  (the packaged path used to wire nothing — a bare prompt). kitty's `shell` is
  `dotfiles/kitty/ewe-shell.sh`: falls back to `$SHELL` without zsh, honours
  `~/.config/ewe/shell = bash`, and wires a missing `~/.zshrc` itself (zsh's
  new-user questionnaire otherwise). Every package is in the official repos
  (`packages/common.list`). `fastfetch` replaced the vanished neofetch
  (`dotfiles/fastfetch/`, PNG logo in kitty, braille text elsewhere). Test:
  `tests/ewe-shell-test.sh`; to run real zsh/fastfetch without installing
  them, see the vault note "Terminal Shell — zsh in kitty, bash at login".
- **Workspaces per display (2026-10-23, 0.35):** `dotfiles/hypr/workspaces.lua`
  (required by hyprland.lua) gives every display a block of ten Hyprland ids
  (1–10, 11–20 …) shown as 1, 2, 3 … (`Globals.wsNumber`, plugins:
  `Shell.workspaceNumber`) — never show a raw workspace id. ewe.conf
  `[desktop.workspaces] mode` = `separate` (default, macOS "Displays have
  separate Spaces") | `shared` (one set; the `workspace.active` hook moves
  every display along). Super+N/Shift+N/wheel and the swipe-down are Lua
  functions in the compositor (no process per key); a display that leaves
  merges its workspaces into the same numbers of the one its windows land on.
  Nothing may hand Hyprland a raw id (0.35.1 hotfix: a window rule's
  `workspace = "3"` made id 3 on the second display, beside its own 13 —
  two "3"s): window rules carry a `+ewe-ws-N` tag that `M.place` resolves on
  `window.open_early`, and `workspace.created` re-homes any stray id.
  Never start an `hl.timer` from `config.reloaded`: it also fires while the
  config is first parsed (`Hyprland --verify-config` segfaulted). Test:
  `tests/ewe-workspaces-test.sh`; a second display in the nested harness is
  `hyprctl output create headless`.
- **Tiling styles (0.36, 2026-10-27):** `[desktop.layout] mode` = `dwindle`
  (default, emits nothing) · `master` · `scrolling` · `monocle` (Hyprland
  ≥ 0.54, one window at a time); ewe-conf writes `general.layout` into
  user.lua for the three, ewe-settings' Layout page lists all four. On
  monocle `hl.dsp.window.cycle_next()` is a no-op — Super+Tab checks the
  live layout and sends the `cyclenext` / `cycleprev` layout messages there.
- **Overview, groups and the new-workspace drop (0.36):** a Hyprland group
  is ONE card (members with `lastIpcObject.hidden` + a `grouped` list of >1
  are filtered from the cards and thumbnails; the tab on top carries a pill
  of the tabs' icons). Dropping a card on the strip beside the workspaces,
  or on the "+" cell that shows while dragging, moves the window to a new
  workspace of that display (`moveToNew`: last number in use + 1, lowest
  free once 10 is taken, a toast when all ten are in use). Hit-test the drop
  BEFORE flipping `dragActive` — the strip starts closing on it.
- **One brand mark (2026-09-21):** the line-art logo everywhere; the cartoon
  `sheep.svg` is gone. `dotfiles/quickshell/assets/ewe-mark.svg` is the bold
  cut (white, tinted by a `MultiEffect`); the vectors live in
  `design/system/assets/Logos/ewe-mark{,-bold}.svg`. The three apps' launcher
  icons stay per-app.

### Versioning

Canonical version is the repo-root **`VERSION`** file (semver + `-alpha`/`-beta`).
The shell mirrors it in `Globals.version` (shown in the Settings sidebar) — **bump
both** and tag `vX.Y.Z` on release. (`VERSIONS`, plural, is unrelated — it documents
minimum tool versions.)
