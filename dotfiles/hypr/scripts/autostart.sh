#!/usr/bin/env bash
# autostart.sh — one-shot session bring-up, run by the hyprland.start hook.
#
# Idempotent by construction: every daemon is guarded with `pgrep` and every
# optional program with `command -v`, so re-running it (e.g. after `hyprctl
# reload`) never double-spawns anything. Ported from the old Qtile autostart.sh.

set -u

# run_once <pgrep-pattern> <command...> — start only if not already running.
run_once() {
    local pat="$1"; shift
    command -v "$1" >/dev/null 2>&1 || return 0
    pgrep -f "$pat" >/dev/null 2>&1 && return 0
    "$@" >/dev/null 2>&1 &
}

# ── Export the session env into the systemd user + DBus activation env so ─────
# DBus-activated services (xdg-desktop-portal, screen sharing) inherit
# WAYLAND_DISPLAY / XDG_CURRENT_DESKTOP=Hyprland etc.
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd --all >/dev/null 2>&1 || true
fi

# ── Activate the systemd graphical session ───────────────────────────────────
# Custom start-hyprland.sh doesn't go through uwsm, so graphical-session.target
# never came up — which left xdg-desktop-portal dead (its Requisite). Starting
# hyprland-session.target (BindsTo=graphical-session.target) pulls it active and
# brings the portals up. Without this, Flatpak apps can't open the browser and
# the browser can't hand back slack:// (Slack sign-in did nothing).
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user start hyprland-session.target >/dev/null 2>&1 || true
fi

# Polkit authentication agent is now Quickshell's own (Auth.qml) — no
# lxqt-policykit-agent / polkit-gnome (only one agent may register per session).

# ── Wallpaper (swaybg) ───────────────────────────────────────────────────────
"$HOME/.config/hypr/scripts/wallpaper.sh" >/dev/null 2>&1 &

# ── Quickshell (the QML shell: bar/dock/launcher/notifications/lock) ─────────────
# Run as a systemd USER SERVICE so it RESPAWNS on crash (Restart=on-failure) —
# otherwise a shell crash kills the bar/dock/lock with no way back. The session
# env was exported into the systemd manager above, so the service inherits
# WAYLAND_DISPLAY etc. `start` is idempotent (no-op if already active), so a
# `hyprctl reload` re-run never double-spawns. Falls back to a bare `qs &` only
# if the unit isn't installed yet (first run before the next relogin).
if command -v systemctl >/dev/null 2>&1 && systemctl --user cat ewe.service >/dev/null 2>&1; then
    systemctl --user start ewe.service >/dev/null 2>&1 || true
elif command -v qs >/dev/null 2>&1 && ! pgrep -x qs >/dev/null 2>&1; then
    "$HOME/.config/quickshell/scripts/qs-launch.sh" >/dev/null 2>&1 &
fi

# ── Clipboard history recorder (feeds the scissors-icon popup) ────────────────
# Two watchers (text + images); guarded separately so both always come up.
if command -v cliphist >/dev/null 2>&1 && command -v wl-paste >/dev/null 2>&1; then
    pgrep -f "wl-paste --type text --watch cliphist"  >/dev/null 2>&1 || \
        wl-paste --type text  --watch cliphist store >/dev/null 2>&1 &
    pgrep -f "wl-paste --type image --watch cliphist" >/dev/null 2>&1 || \
        wl-paste --type image --watch cliphist store >/dev/null 2>&1 &
fi

# Notifications + network/bluetooth indicators are now handled natively by
# Quickshell (NotificationServer + the bar's own modules) — no swaync, no
# nm-applet/blueman-applet tray icons (those duplicated the bar).

# ── Per-window keyboard layout (GNOME-style): remembers the layout per window ─
# and restores it on focus. Self-contained Python daemon (no extra deps).
# Settings → Keyboard & Mouse toggles it via the .disabled flag file.
if [ ! -e "$HOME/.config/hypr/generated/kb-per-window.disabled" ]; then
    run_once "kb-per-window.py" python3 "$HOME/.config/hypr/scripts/kb-per-window.py"
fi

# ── Nemo: bare-window seed (one-time; same keys as phase 60) — no sidebar/  ───
# menubar/toolbar/statusbar, pure folder view. Stamp-guarded so the user's own
# View toggles (F9 sidebar, Alt menubar) stick afterwards instead of being
# reverted at every login.
NEMO_STAMP="${XDG_STATE_HOME:-$HOME/.local/state}/ewe/nemo-chrome.seeded"
if command -v gsettings >/dev/null 2>&1 && command -v nemo >/dev/null 2>&1 && [ ! -e "$NEMO_STAMP" ]; then
    if gsettings set org.nemo.window-state start-with-sidebar false 2>/dev/null; then
        gsettings set org.nemo.window-state start-with-menu-bar false 2>/dev/null || true
        gsettings set org.nemo.window-state start-with-toolbar false 2>/dev/null || true
        gsettings set org.nemo.window-state start-with-status-bar false 2>/dev/null || true
        mkdir -p "${NEMO_STAMP%/*}" && touch "$NEMO_STAMP"
    fi
fi

# ── Same bare-window treatment for the rest of the built-ins (one-time). ──────
# Engrampa exposes toolbar/statusbar via gsettings; galculator keeps its own
# conf file (which it rewrites on exit — hence seed-once, never a symlink).
CHROME_STAMP="${XDG_STATE_HOME:-$HOME/.local/state}/ewe/app-chrome.seeded"
if [ ! -e "$CHROME_STAMP" ]; then
    seeded=0
    if command -v gsettings >/dev/null 2>&1 && command -v engrampa >/dev/null 2>&1; then
        gsettings set org.mate.engrampa.ui view-toolbar false 2>/dev/null \
            && gsettings set org.mate.engrampa.ui view-statusbar false 2>/dev/null \
            && seeded=1
    fi
    GCONF="$HOME/.config/galculator/galculator.conf"
    if command -v galculator >/dev/null 2>&1 && ! pgrep -x galculator >/dev/null; then
        if [ -f "$GCONF" ]; then
            sed -i 's/^show_menu_bar=true$/show_menu_bar=false/' "$GCONF" && seeded=1
        else
            mkdir -p "${GCONF%/*}"
            printf '[general]\nshow_menu_bar=false\n' > "$GCONF" && seeded=1
        fi
    fi
    [ "$seeded" = 1 ] && mkdir -p "${CHROME_STAMP%/*}" && touch "$CHROME_STAMP"
fi

# ── Idle / lock: hypridle. The Settings → Screensaver pane writes a generated
# config (saver stage + timeouts) which wins over the shipped default. ────────
# Live-ISO sessions (EWE_LIVE=1, exported by the ISO's ewe-live-session) get
# NO idle daemon at all: the live user has an empty password, so a lock would
# be a dead end — and a demo session must never lock or suspend by itself.
LOCK="$HOME/.config/hypr/scripts/lock.sh"
if [ "${EWE_LIVE:-0}" = "1" ]; then
    :
elif command -v hypridle >/dev/null 2>&1 && [ -r "$HOME/.config/hypr/generated/hypridle.conf" ]; then
    run_once hypridle hypridle -c "$HOME/.config/hypr/generated/hypridle.conf"
elif command -v hypridle >/dev/null 2>&1 && [ -r "$HOME/.config/hypr/hypridle.conf" ]; then
    run_once hypridle hypridle
elif command -v swayidle >/dev/null 2>&1 && ! pgrep -x swayidle >/dev/null 2>&1; then
    swayidle -w \
        timeout 300 "$LOCK" \
        timeout 600 'hyprctl dispatch dpms off' \
        resume       'hyprctl dispatch dpms on' \
        before-sleep "$LOCK" >/dev/null 2>&1 &
fi

# ── User startup applications (Settings → Startup) + kdeconnectd — launched in
# a detached waiter that first blocks (max ~20 s) until the Quickshell bar owns
# org.kde.StatusNotifierWatcher. Launching earlier has TWO silent failure
# modes: tray apps register no icon (no watcher on the bus yet → the icon never
# appears), and 1Password probes for a polkit agent once at startup — before
# the shell's agent is registered it caches "system auth: NotSetup" for the
# whole run. Waiting for the watcher covers both (same process registers both).
(
    if command -v busctl >/dev/null 2>&1; then
        _i=0
        while [ "$_i" -lt 40 ] && ! busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>&1; do
            sleep 0.5; _i=$((_i + 1))
        done
    else
        sleep 3   # no busctl (non-systemd?) — a fixed grace beats nothing
    fi

    # user startup applications: a plain JSON list the Settings pane owns;
    # disabled entries are kept but skipped
    SAPPS="$HOME/.config/quickshell/startup-apps.json"
    if [ -r "$SAPPS" ] && command -v jq >/dev/null 2>&1; then
        jq -r '.apps[] | select(.enabled != false) | .exec' "$SAPPS" 2>/dev/null | while IFS= read -r cmd; do
            [ -n "$cmd" ] && sh -c "$cmd" >/dev/null 2>&1 &
        done
    fi

    # KDE Connect daemon (phone integration — Quick Settings "Mobile" card).
    # Hyprland doesn't process XDG autostart, so start it here; the shell's
    # bridge can also D-Bus-activate it on demand.
    if command -v kdeconnectd >/dev/null 2>&1; then
        run_once kdeconnectd kdeconnectd
    elif [ -x /usr/lib/kdeconnectd ]; then
        run_once kdeconnectd /usr/lib/kdeconnectd
    fi
) >/dev/null 2>&1 &

# ── First-launch warm-up: pre-fault the big apps' working set at idle so the
# user's first click feels like their second (details + cost model in the
# script). Battery-aware; page cache only — no steady-state RSS cost.
run_once "warmup.sh" "$HOME/.config/hypr/scripts/warmup.sh"

exit 0
