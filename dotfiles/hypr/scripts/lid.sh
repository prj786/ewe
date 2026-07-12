#!/usr/bin/env bash
# lid.sh — clamshell lid handling for Hyprland (Lua config).
#   close: if an external monitor is connected, turn off the laptop panel and
#          keep working on the external; if the laptop is alone, lock + suspend.
#   open:  re-enable the laptop panel; the shell (HyprMon) then re-asserts the
#          saved display profile, restoring the panel's real mode/scale/position.
#
# The shell is told about the lid first (`qs ipc call display lid …`) so its
# profile re-asserts never relight a panel inside a closed lid.
#
# NOTE: this only runs if systemd-logind ignores the lid — phase 30 installs
# /etc/systemd/logind.conf.d/10-hypr-shell-lid.conf for exactly that.

set -u
INTERNAL="eDP-1"

externals() { hyprctl monitors -j | jq "[.[] | select(.name != \"$INTERNAL\")] | length"; }

case "${1:-}" in
  close)
    qs ipc call display lid close >/dev/null 2>&1 || true
    if [ "$(externals)" -gt 0 ]; then
        # docked-style: external present → power off just the laptop panel
        hyprctl eval "hl.monitor({output=\"$INTERNAL\", disabled=true})" >/dev/null 2>&1
    else
        # laptop alone → lock, then sleep
        qs ipc call lock lock >/dev/null 2>&1
        sleep 0.5
        systemctl suspend
    fi
    ;;
  open)
    qs ipc call display lid open >/dev/null 2>&1 || true
    # enable with safe defaults — HyprMon's re-assert applies the saved profile
    # (exact mode/scale/position) right after the monitoradded event
    hyprctl eval "hl.monitor({output=\"$INTERNAL\", disabled=false, mode=\"preferred\", position=\"auto\"})" >/dev/null 2>&1
    ;;
esac
