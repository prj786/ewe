# Contributing to ewe

Thanks for helping! ewe is an **Arch-only**, opinionated Hyprland +
Quickshell desktop. A few things make contributing here smooth.

## Ground rules

- **Arch only.** Package install assumes `pacman` + the AUR. Don't add multi-distro
  branches to the installer.
- **Opinionated by design.** It's a curated DE, not a framework. New components are
  welcome; sprawling config knobs and clone-of-another-OS aesthetics usually aren't.
- **Everything lives in the repo.** Edit `dotfiles/`, `phases/`, `lib/`, `systemd/`,
  `system/` — never hand-edit a deployed `~/.config` and call it done. The whole DE
  must come up from a clean `git clone && ./install.sh`.

## Dev setup

You don't need to wreck your own session to iterate:

- **Shell (QML) + Hyprland config:** use the driver in `.claude/skills/run-ewe/`
  — it nests a throwaway Hyprland on its own Wayland socket and screenshots it; your
  real session is untouched. `driver.sh up` / `open <surface>` / `down`, and
  `driver.sh check` for `luac -p` on the Lua config. QML has no live reload there —
  `down && up` after edits.
- **Full install / greeter / boot splash:** test by reinstalling in a throwaway
  **QEMU/KVM Arch VM**. Don't test the installer on a machine you care about.

See [`CLAUDE.md`](CLAUDE.md) for the architecture (install pipeline + `run()`/
`sudo_run()` choke point + the Quickshell singletons + the single-source theming).

## Before you open a PR

- `bash install.sh --dry-run` if you touched the installer.
- `.claude/skills/run-ewe/driver.sh check` if you touched `hyprland.lua`.
- Bring the shell up with no QML errors if you touched `dotfiles/quickshell/`.
- CI runs shellcheck (errors), `luac -p`, and a `qmldir` consistency check.

## Commits

Scoped, descriptive messages (`fix(kitty): …`, `feat(theme): …`). Keep PRs focused —
one concern per PR. For anything visible, attach before/after screenshots.

## Capturing media

Screenshots live on the website (prj786.github.io), not in this repo.
`docs/capture.sh` (run inside the real DE) grabs shots/GIFs for it into
`docs/media/` (gitignored). See its header for usage.
