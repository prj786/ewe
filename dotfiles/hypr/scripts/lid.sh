#!/usr/bin/env bash
# lid.sh — report the lid switch to the shell. Nothing more.
#
# ALL clamshell policy now lives in the shell (dotfiles/quickshell/Lid.qml):
# whether to suspend, whether to keep working on an external monitor, and which
# output is the built-in panel. This script used to hold that policy, which meant
# a hardcoded eDP-1 (wrong on LVDS/DSI or a second panel), a jq dependency, and
# nothing the user could configure. The compositor reports the event; the shell
# decides what it means.
#
# The ONE decision left here is the failure case: if the shell is not answering
# (crashed, or not up yet), a closing lid must never leave the machine awake in a
# bag, so we suspend. That path cannot lock first — with the shell down there is
# no locker running — but a hot laptop in a rucksack is the worse outcome.
#
# Locking on the normal path is not done here either: suspending raises
# PrepareForSleep, and the shell's logind delay inhibitor locks the session
# before the machine goes down. That handshake replaced an unreliable `sleep 0.5`.
#
# NOTE: this only runs if systemd-logind ignores the lid — phase 30 installs
# /etc/systemd/logind.conf.d/10-hypr-shell-lid.conf for exactly that.

set -u

# timeout: a WEDGED shell (hung, not crashed) would leave `qs ipc` blocking
# forever — on close that must still fall through to suspend, and on open it
# must never leave a stuck process behind the bind.
case "${1:-}" in
  close)
    timeout 3 qs ipc call display lid close >/dev/null 2>&1 || "$(dirname "$0")/zzz.sh"
    ;;
  open)
    timeout 3 qs ipc call display lid open >/dev/null 2>&1 || true
    ;;
esac
