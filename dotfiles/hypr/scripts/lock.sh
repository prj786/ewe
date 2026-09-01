#!/usr/bin/env bash
# lock.sh — lock the session. The shell's own lock surface (Lock.qml,
# ext-session-lock-v1) is THE locker: everything routes through
# `qs ipc call lock lock` (same path hypridle and the Super+Alt+L bind use).
# There is deliberately no hyprlock/swaylock first choice any more — hyprlock
# has no config of ours and exits on the spot, which read as "lock is broken".

set -u

if qs ipc call lock lock 2>/dev/null; then
    exit 0
fi

# Shell unreachable (crashed / not started) — only then try a standalone
# locker, and only one that can actually run (hyprlock needs a config).
pgrep -x hyprlock >/dev/null 2>&1 && exit 0
if command -v hyprlock >/dev/null 2>&1 && [ -r "$HOME/.config/hypr/hyprlock.conf" ]; then
    exec hyprlock
fi
notify-send "Lock" "Screen lock unavailable — the shell is not running." 2>/dev/null
exit 1
