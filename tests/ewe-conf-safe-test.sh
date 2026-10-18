#!/usr/bin/env bash
# ewe-conf and the [safe] section (RFC-008): a Safe setting is stored and
# applies NOTHING (ewe-safed reads the file). Without the `safe` domain an
# unknown section falls through to a full apply: theme tokens rebuilt,
# user.lua regenerated and Hyprland reloaded, on every single `set`.
# Hermetic: a throwaway XDG_CONFIG_HOME, stub qs and hyprctl on PATH.
set -u
cd "$(dirname "$0")/.."
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/bin"
printf '#!/bin/sh\necho "qs $*" >> "%s/calls.log"\n' "$S" > "$S/bin/qs"
printf '#!/bin/sh\necho "hyprctl $*" >> "%s/calls.log"\n' "$S" > "$S/bin/hyprctl"
chmod +x "$S/bin/qs" "$S/bin/hyprctl"
export PATH="$S/bin:$PATH" XDG_CONFIG_HOME="$S/cfg" XDG_STATE_HOME="$S/state"
export HYPRLAND_INSTANCE_SIGNATURE=test-only-stub   # the stub hyprctl would log a reload
fail=0
ok() { echo "ok    $*"; }
no() { echo "FAIL  $*"; fail=1; }

bin/ewe-conf set safe.place '"Nextcloud"' || no "set exited non-zero"
bin/ewe-conf set safe.location '"ewe/safe/passwords.kdbx"' || no "set exited non-zero"
bin/ewe-conf set safe.lock_after_minutes 30 || no "set exited non-zero"
bin/ewe-conf set safe.lock_on_screen_lock true || no "set exited non-zero"
[ "$(bin/ewe-conf get safe.place)" = "nextcloud" ] && ok "the place is stored, normalised" || no "get safe.place"
[ "$(bin/ewe-conf get safe.location)" = "ewe/safe/passwords.kdbx" ] && ok "the location is stored" || no "get safe.location"
[ "$(bin/ewe-conf get safe.lock_after_minutes)" = "30" ] && ok "an int is stored" || no "get safe.lock_after_minutes"
[ "$(bin/ewe-conf get safe.lock_on_screen_lock)" = "true" ] && ok "a bool is stored" || no "get safe.lock_on_screen_lock"
bin/ewe-conf set safe.place '"icloud"' 2>/dev/null && no "an unknown place was accepted" || ok "an unknown place is refused"
[ "$(bin/ewe-conf get safe.place)" = "nextcloud" ] && ok "a refused set leaves the value" || no "a refused set changed safe.place"
bin/ewe-conf set safe.ssh_agent true || no "set ssh_agent exited non-zero"
[ "$(bin/ewe-conf get safe.ssh_agent)" = "true" ] && ok "ssh_agent is stored" || no "get safe.ssh_agent"
bin/ewe-conf set safe.ssh_confirm '"Every-Time"' || no "set ssh_confirm exited non-zero"
[ "$(bin/ewe-conf get safe.ssh_confirm)" = "every-time" ] && ok "ssh_confirm is stored, normalised" || no "get safe.ssh_confirm"
bin/ewe-conf set safe.ssh_confirm '"sometimes"' 2>/dev/null && no "an unknown ssh_confirm was accepted" || ok "an unknown ssh_confirm is refused"
bin/ewe-conf set safe.unlock_at_login false || no "set unlock_at_login exited non-zero"
[ "$(bin/ewe-conf get safe.unlock_at_login)" = "false" ] && ok "unlock_at_login is stored" || no "get safe.unlock_at_login"
bin/ewe-conf set safe.confirm_cards true || no "set confirm_cards exited non-zero"
[ "$(bin/ewe-conf get safe.confirm_cards)" = "true" ] && ok "confirm_cards is stored" || no "get safe.confirm_cards"
for f in quickshell/theme-tokens.json quickshell/user-theme.json hypr/generated/user.lua; do
  [ -e "$S/cfg/$f" ] && no "a safe set regenerated $f" || ok "nothing regenerated: $f"
done
grep -q "hyprctl reload" "$S/calls.log" 2>/dev/null && no "a safe set reloaded Hyprland" || ok "Hyprland not reloaded"
grep -q "^# Safe, the password manager" "$S/cfg/ewe/ewe.conf" && ok "the section explains itself" || no "no SECTION_NOTES comment above [safe]"
exit $fail
