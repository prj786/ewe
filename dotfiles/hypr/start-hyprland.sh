#!/usr/bin/env bash
# start-hyprland.sh — the session-entry wrapper used by "Hyprland (DE)".
#
# This wrapper sets the pre-launch desktop identity (so portals resolve the
# Hyprland backend), the toolkit theming env, and a software-render escape
# hatch for the brand-new Lunar Lake iGPU, then exec's Hyprland.

# ── Session stdout/stderr → a log file, not the VT ───────────────────────────
# greetd leaves the session's stdio pointed at the virtual terminal, so every
# line Hyprland prints before hyprland.lua's `debug.enable_stdout_logs = 0`
# takes effect — the rlimit lines, the scheduling warning, the "launched
# without start-hyprland" warning, the Creating-the-*Manager dump — flashed
# raw over the screen on every login. Hyprland's full log already lands in
# $XDG_RUNTIME_DIR/hypr/<sig>/hyprland.log; this file catches only that
# pre-config chatter plus any wrapper-level failure. Truncated each login, so
# the last session is always available for post-mortem. If the redirect ever
# fails, bash keeps the old stdout (the VT) and login proceeds — verified: a
# failed bare `exec >` does not exit a non-interactive bash.
_hs_log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/ewe"
# migrate: pre-rename installs kept state in .../hypr-shell (theme backups,
# the nemo seed stamp, old session logs) — carry it over once, then forget
_hs_old_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hypr-shell"
[ -d "$_hs_old_dir" ] && [ ! -e "$_hs_log_dir" ] && mv "$_hs_old_dir" "$_hs_log_dir" 2>/dev/null
mkdir -p "$_hs_log_dir" 2>/dev/null && exec >"$_hs_log_dir/session.log" 2>&1

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_DESKTOP=Hyprland
export DESKTOP_SESSION=hyprland

# ── Toolkit theming env — MUST be exported HERE, before `exec Hyprland`, not only
#    via hl.env() in hyprland.lua. hl.env applies to Hyprland's children, but its
#    propagation is unreliable for apps launched on-demand, and the symptom is a
#    GTK or Qt app that comes up with a WHITE palette because the theme env never
#    reached it. Exporting here puts these in the real process environment of
#    Hyprland AND every descendant, however it's spawned. Keep in sync with
#    scripts/colorscheme.sh (writes the GTK settings.ini + qt6ct/kdeglobals fallback)
#    and ~/.icons/default (cursor inheritance).
export QT_QPA_PLATFORM="wayland;xcb"
# First-party apps are GTK now (Nemo/Engrampa/Zathura/imv), themed via GTK below.
# qt6ct is just a fallback so any stray Qt app you install gets a dark Fusion
# palette instead of blinding white — there are no KDE apps, so no plasma-integration
# / "kde" platform theme. (The shell itself is Quickshell/Qt, themed by Theme.qml.)
export QT_QPA_PLATFORMTHEME=qt6ct
export QT_STYLE_OVERRIDE=Fusion
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export XCURSOR_THEME=Mocu-White-Right      # one cursor everywhere (XWayland + every toolkit)
export XCURSOR_SIZE=24
export HYPRCURSOR_SIZE=24
export GDK_BACKEND="wayland,x11"
export SDL_VIDEODRIVER=wayland
export CLUTTER_BACKEND=wayland
export MOZ_ENABLE_WAYLAND=1
export _JAVA_AWT_WM_NONREPARENTING=1

# Locally-built tools (e.g. hyprland-per-window-layout in step 6 of install.sh)
# live in ~/.local/bin — make sure the session and its children can find them.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

# mise shims — Node/pnpm + the language servers Fresh uses are mise-managed (no
# system nodejs). The shims are static executables, so putting them on PATH here
# makes them resolve for GUI-launched apps (Fresh, opened from the editor or a
# file association) without needing an interactive shell's `mise activate`.
case ":$PATH:" in *":$HOME/.local/share/mise/shims:"*) ;; *) export PATH="$HOME/.local/share/mise/shims:$PATH" ;; esac

# Default editor for the whole session (Fresh, terminal IDE).
export EDITOR=fresh VISUAL=fresh

# GPU escape hatch: if the Arc 140V (xe) driver ever tears/hangs/corrupts, log
# in once with DE_SOFTWARE_RENDER=1 in your environment to fall back to Mesa
# software rendering. (The cursor-plane bug is already handled in hyprland.lua
# via cursor:use_cpu_buffer.)
if [ "${DE_SOFTWARE_RENDER:-0}" = "1" ]; then
    export LIBGL_ALWAYS_SOFTWARE=1
    export WLR_RENDERER_ALLOW_SOFTWARE=1
fi

exec Hyprland
