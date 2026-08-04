#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  install.sh — turn a minimal base install into the Hyprland + Quickshell   ║
# ║  Clean, borderless dark desktop. Arch Linux only (pacman + the AUR).       ║
# ║                                                                            ║
# ║  Usage:                                                                    ║
# ║    bash install.sh                 full install (prompts before changes)   ║
# ║    bash install.sh --yes           no prompts                              ║
# ║    bash install.sh --dry-run       print every action, change nothing      ║
# ║    bash install.sh --no-packages   skip the package install (config only)  ║
# ║    bash install.sh --check-only    run only the verification checklist     ║
# ║    bash install.sh --gaming        also install the gaming stack           ║
# ║    bash install.sh --dev           also install the dev toolchain          ║
# ║    bash install.sh --coexist       install beside an existing WM/DM:       ║
# ║                                    keep your login manager, skip boot/GPU, ║
# ║                                    reuse the AUR helper, back up GTK theme ║
# ║                                                                            ║
# ║  Idempotent: re-running re-links (no-op), skips installed packages, and    ║
# ║  never clobbers an existing config without a timestamped .bak backup.      ║
# ╚══════════════════════════════════════════════════════════════════════════╝
set -u

DOTREPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export DOTREPO

# ── Never run as root. This is not a style rule; running under sudo produces a
# silently broken install that is very hard to trace back.
#
# $HOME builds the ENTIRE symlink farm (~/.config/hypr, quickshell, kitty, …),
# the systemd user units, and the Exec= line of the system-wide session entry.
# Under sudo, $HOME is /root, so the desktop installs into root's home while the
# session entry — written system-wide, so it lands regardless — points at
# /root/.config/hypr/start-hyprland.sh. Your own account then picks "Hyprland
# (DE)" at the greeter, greetd execs a path it cannot reach, the session dies
# instantly and you are dropped back at the greeter with no error anywhere.
#
# The installer escalates on its own (sudo_run) exactly where root is needed, so
# there has never been a reason to invoke it as root. makepkg refuses to run as
# root too, so the AUR phase could not work either.
if [ "$(id -u)" = "0" ]; then
    if [ -n "${SUDO_USER:-}" ]; then
        printf 'error: do not run install.sh with sudo.\n\n' >&2
        printf '  Run it as your normal user — it asks for a password only where\n' >&2
        printf '  root is actually needed:\n\n      bash install.sh\n\n' >&2
        printf '  (Under sudo, $HOME is /root, so the whole desktop would install\n' >&2
        printf '   into root'"'"'s home and the login session would fail silently.)\n' >&2
    else
        printf 'error: do not run install.sh as root — run it as your normal user.\n' >&2
    fi
    exit 2
fi

# --- flags ---
DRY_RUN=0; ASSUME_YES=0; NO_PACKAGES=0; CHECK_ONLY=0; GAMING=0; DEV=0; COEXIST=0
for a in "$@"; do
    case "$a" in
        --dry-run)     DRY_RUN=1 ;;
        --yes|-y)      ASSUME_YES=1 ;;
        --no-packages) NO_PACKAGES=1 ;;
        --check-only)  CHECK_ONLY=1 ;;
        --gaming)      GAMING=1 ;;
        --dev)         DEV=1 ;;
        --coexist)     COEXIST=1 ;;
        -h|--help)     sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown flag: $a (see --help)"; exit 2 ;;
    esac
done
export DRY_RUN ASSUME_YES NO_PACKAGES GAMING DEV COEXIST

# A fixed per-run timestamp for backups (passed without Date.now-style drift).
RUN_STAMP="$(date -u +%Y%m%d-%H%M%S 2>/dev/null || echo manual)"
export RUN_STAMP

# --- load libraries + phases ---
for f in lib/log.sh lib/detect.sh lib/pkg.sh lib/deploy.sh \
         phases/00-preflight.sh phases/10-repos.sh phases/20-packages.sh \
         phases/30-services.sh phases/35-bootsplash.sh phases/37-microcode.sh \
         phases/40-gpu.sh phases/50-dotfiles.sh \
         phases/60-userconfig.sh phases/90-postcheck.sh; do
    # shellcheck disable=SC1090
    . "$DOTREPO/$f"
done

detect_all

if [ "$CHECK_ONLY" = "1" ]; then
    phase_postcheck
    exit 0
fi

[ "$DRY_RUN" = "1" ] && info "DRY RUN — no changes will be made."

# Coexist mode: install the DE beside an existing WM/DM (e.g. Sway on CachyOS)
# without hijacking the system. Keeps your login manager, skips the boot/driver
# phases the host distro already owns, reuses your AUR helper, and backs up the
# GTK theme before the DE recolours it. Gaming is force-off (it flips multilib).
if [ "$COEXIST" = "1" ]; then
    [ "$GAMING" = "1" ] && warn "--gaming is ignored with --coexist (it flips [multilib] + lib32 drivers system-wide)."
    GAMING=0; export GAMING
    info "coexist mode: keeping your login manager, skipping bootsplash/microcode/gpu, reusing your AUR helper."
fi

# The gaming stack (Steam, gamescope, gamemode, mangohud + 32-bit libs) is OPT-IN.
# It pulls in [multilib] (phase 10) and the lib32 GPU drivers (phase 40), so the
# choice must be settled BEFORE those phases run. Default: not installed.
if [ "$COEXIST" = "1" ]; then
    : # settled above: coexist never touches [multilib], so don't offer gaming here
elif [ "$GAMING" = "1" ]; then
    info "gaming stack: enabled (--gaming) — [multilib] + Steam, gamescope, gamemode, mangohud."
elif [ "$ASSUME_YES" = "1" ] || [ "$DRY_RUN" = "1" ] || [ "$NO_PACKAGES" = "1" ]; then
    info "gaming stack: not selected (opt-in) — pass --gaming for Steam, gamescope, gamemode, mangohud."
elif ask_yes "Install the optional gaming stack? (Steam, gamescope, gamemode, mangohud + 32-bit libs)"; then
    GAMING=1
else
    info "gaming stack: skipped — re-run with --gaming to add it later."
fi

# The front-end dev toolchain (git-delta, lazygit, github-cli, mise + the Node/LSP
# stack via `mise install`, ripgrep, fd, fzf, bat, cmake, meson) is OPT-IN. Settle
# the choice here so phase 20 (dev.list) and phase 60 (mise install) honor it.
if [ "$DEV" = "1" ]; then
    info "dev toolchain: enabled (--dev) — dev CLIs + the mise Node/LSP toolchain."
elif [ "$ASSUME_YES" = "1" ] || [ "$DRY_RUN" = "1" ] || [ "$NO_PACKAGES" = "1" ]; then
    info "dev toolchain: not selected (opt-in) — pass --dev for the dev CLIs + mise Node stack."
elif ask_yes "Install the optional dev toolchain? (git-delta, lazygit, gh, mise+Node, ripgrep, fd, fzf, bat)"; then
    DEV=1
else
    info "dev toolchain: skipped — re-run with --dev to add it later."
fi

phase_preflight
phase_repos
phase_packages
phase_services
if [ "$COEXIST" = "1" ]; then
    info "coexist: skipping bootsplash/microcode/gpu — your host distro already manages boot + drivers."
else
    phase_bootsplash
    phase_microcode
    phase_gpu
fi
phase_dotfiles
phase_userconfig
phase_postcheck

step "done"
if [ "$COEXIST" = "1" ]; then
cat <<EOF
  Next (coexist — your existing WM/DM is untouched):
    1. Log OUT of your current session (no reboot needed).
    2. In your login manager, pick the 'Ewe' session (listed next to
       your existing one).
    3. First keys:  Super+Return (terminal) · Super+D (apps) · Super+, (Settings)
       Full list in ~/.config/hypr/SHORTCUTS.md
    4. Re-run the checklist any time:  bash install.sh --check-only
  Nothing was removed and your login manager was not changed.
  GTK theme backup (revert your other session's look): ~/.local/state/hypr-shell/theme-backup.*/restore.sh
  Config backups (if any) are at ~/.config/<name>.bak.$RUN_STAMP
EOF
else
cat <<EOF
  Next:
    1. Reboot (or restart your display manager) so the greeter picks up the
       'Ewe' session entry.
    2. Pick 'Ewe' at login.
    3. First keys:  Super+Return (terminal) · Super+D (apps) · Super+, (Settings)
       Full list in ~/.config/hypr/SHORTCUTS.md
    4. Re-run the checklist any time:  bash install.sh --check-only
  Backups (if any) are at ~/.config/<name>.bak.$RUN_STAMP
EOF
fi
ok "install complete"
