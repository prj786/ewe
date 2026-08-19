---
name: run-ewe
description: Run, drive, and screenshot the ewe Quickshell desktop shell (top bar, Settings app, App Store, Quick Settings, dock) and syntax-check the Hyprland Lua config — without installing to the live session. Use when asked to launch, start, test, screenshot, or verify a change to the ewe DE, its Quickshell QML, or hyprland.lua.
---

# Running ewe

`ewe` is an Arch-only, clean dark Hyprland + Quickshell desktop
environment. The part that changes most (top **Bar**, **Settings** app,
**App Store**, **Quick Settings**, **Dock**) is the Quickshell QML shell in
`dotfiles/quickshell/`. You drive it with **`.claude/skills/run-ewe/driver.sh`**,
which nests a throwaway Hyprland compositor on its own Wayland socket, runs
`qs -p dotfiles/quickshell` inside it, and screenshots that virtual output with
`grim`. **Nothing touches the host's real screen** and the host's own running
shell is left alone.

All paths below are relative to the repo root (`ewe/`). The driver lives
at `.claude/skills/run-ewe/driver.sh`.

## Prerequisites

This is the dev/test host — these are already installed here. On a clean Arch box:

```
sudo pacman -S --needed hyprland quickshell grim wlr-randr lua
```

- A **host Wayland session must be running** (`WAYLAND_DISPLAY` set). The driver
  nests via aquamarine's *Wayland backend*; the headless backend can't grab a
  seat that logind already owns (`Could not take control of session: Device or
  resource busy`). On a headless box, start a parent compositor first
  (`cage`/`sway --headless`) and export its `WAYLAND_DISPLAY`.
- The driver sets `AQ_DRM_DEVICES=/dev/dri/renderD128` so the nested compositor
  has a render node to allocate buffers from.

## Run (agent path) — the driver

```bash
.claude/skills/run-ewe/driver.sh up              # nested compositor + shell, waits for "Configuration Loaded"
.claude/skills/run-ewe/driver.sh open settings   # toggle a surface + screenshot -> /tmp/hs-driver/settings.png
.claude/skills/run-ewe/driver.sh open store       # the App Store
.claude/skills/run-ewe/driver.sh open quicksettings   # the Quick Settings
.claude/skills/run-ewe/driver.sh shot bar.png     # screenshot whatever is on the nested output now (the bar+dock)
.claude/skills/run-ewe/driver.sh targets          # list every IpcHandler target + function
.claude/skills/run-ewe/driver.sh ipc settings toggle   # raw IpcHandler call (target + function)
.claude/skills/run-ewe/driver.sh log              # tail the shell's qs log
.claude/skills/run-ewe/driver.sh down             # tear it all down
```

Screenshots land in `/tmp/hs-driver/` (override with `HS_OUT=/somewhere`).
**Read the PNG** to confirm the change — a blank/bar-only shot (~15 KB) means the
surface didn't open; a real window is 40–57 KB at 1280×800.

Typical loop for verifying a QML change: edit `dotfiles/quickshell/*.qml` →
`driver.sh down && driver.sh up` (qs has no live reload here) → `driver.sh open <surface>`
→ read the PNG.

IpcHandler targets exposed by the shell (from `targets`): `settings`, `store`,
`quicksettings`, `bar`, `applauncher`, `launcher`, `overview`, `clipboard`, `lock`,
`osd`, `preview` — most take `show`/`hide`/`toggle`.

### Hyprland config check

The Hyprland side is Lua (`dotfiles/hypr/hyprland.lua` + `colors.lua`). Static
syntax check (no compositor needed):

```bash
.claude/skills/run-ewe/driver.sh check     # luac -p hyprland.lua colors.lua  ->  "lua config: syntax OK"
```

The driver deliberately hosts the shell under a *minimal* compositor config, **not**
the repo's real `hyprland.lua` — the real config autostarts apps and binds keys,
which would spawn duplicates inside the nest. To exercise keybinds/autostart you
need a full install in a VM (see below).

## Run (human path / real install)

The real deployment is `./install.sh` (Arch only — phases under `phases/`,
deploys dotfiles, installs greetd + a Wayland session entry). The maintainer
tests it by **reinstalling in a QEMU/KVM VM**, never on the live host. Useless to
run headless in this container; use the driver for shell iteration instead.

## Gotchas (learned by running it here)

- **`qs ipc call <tgt> show` does NOT open the window** — `show` collides with the
  `qs ipc show` listing subcommand and just prints the target list (exit 0). Use
  **`toggle`** (what `driver.sh open` does). `hide`/`toggle` are unaffected.
- **Target qs by `--pid`, not `--id`.** The nested instance's by-id dir exists
  under `$XDG_RUNTIME_DIR/quickshell/by-id/` but `qs ipc -i <thatid>` reported "No
  running instances start with…". `qs ipc --pid <pid>` is reliable; the driver
  captures the pid at launch.
- **`Hyprland` (no flags) on a desktop crashes with `CBackend::create() failed!`**
  — it tries the DRM backend, can't take the seat (GNOME/your session owns it),
  then tries the Wayland backend but you unset `WAYLAND_DISPLAY`. Fix: *keep*
  `WAYLAND_DISPLAY` set so it nests via the Wayland backend. There is no
  `AQ_FORCE_BACKENDS`; the headless backend is only a fallback and won't allocate
  without a seat.
- **Benign warnings in `qs.log`** when nesting alongside a live session:
  "Could not register notification server… already registered" and "failed to
  register listener on path /org/quickshell/PolkitAgent / authentication agent
  already exists". The host shell already owns those D-Bus names — harmless.
- The shell raises a real **"hyprland-guiutils not installed"** notification toast
  in this minimal env (it's a runtime dep some dialogs want). Expected; not a bug
  in your change.
- The nested output is **1280×800** and the shell centers its windows for a real
  monitor, so wide panels (Settings, the bar's right edge) run off the right edge
  of the grab. That's a capture-size artifact, not a layout bug.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `no host WAYLAND_DISPLAY` | You're not in a Wayland session. Start a parent compositor and export its `WAYLAND_DISPLAY`. |
| `nested Hyprland died — see /tmp/hs-driver/hypr.log` | Check the log; usually `CBackend::create() failed!` (no render node) — confirm `/dev/dri/renderD128` exists and `AQ_DRM_DEVICES` points at it. |
| `qs died — see /tmp/hs-driver/qs.log` | A QML error in `shell.qml` or a component. The log names the file + line. |
| `open <x>` PNG is ~15 KB (bar only) | The surface didn't open — you used a target with no `toggle`, or it was already open and toggled shut. Run `driver.sh targets`, then `driver.sh down && up` to reset state. |
| stale nested compositor after a crash | `pkill -f hypr-min.conf` then `driver.sh down`. |
