#!/usr/bin/env bash
# power.sh — session power actions for the ewe Quick Settings.
#
# One tested path per action:
#   • The Lua /dispatch quirk: Hyprland's IPC evaluates `hyprctl dispatch <arg>`
#     as Lua in this config, so `hyprctl dispatch exit` does NOT reliably log
#     out (it constructs a dispatcher value without running it). We terminate
#     the logind session instead — works with the greetd session and brings the
#     greeter back.
#   • systemd: an active local session is authorised to power off / reboot /
#     suspend without a password, so no polkit prompt appears.
set -u

here="$(cd "$(dirname "$0")" && pwd)"

case "${1:-}" in
    lock)
        exec "$here/lock.sh"
        ;;
    logout)
        # End the graphical session cleanly. Prefer logind (it knows our
        # session id); fall back to terminating the user, then to SIGTERM on the
        # compositor (Hyprland exits cleanly on TERM).
        if [ -n "${XDG_SESSION_ID:-}" ] && loginctl terminate-session "$XDG_SESSION_ID" 2>/dev/null; then
            exit 0
        fi
        loginctl terminate-user "$USER" 2>/dev/null && exit 0
        pkill -x Hyprland
        ;;
    suspend)
        exec systemctl suspend
        ;;
    reboot)
        exec systemctl reboot
        ;;
    poweroff)
        exec systemctl poweroff
        ;;
    *)
        echo "usage: power.sh {lock|logout|suspend|reboot|poweroff}" >&2
        exit 2
        ;;
esac
