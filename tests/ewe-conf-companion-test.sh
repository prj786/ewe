#!/usr/bin/env bash
# ewe-conf and the [companion] section (RFC-007): a companion setting is
# stored and applies NOTHING. Before the `companion` domain existed, an
# unknown section fell through to a full apply: theme tokens rebuilt,
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

bin/ewe-conf set companion.proactive '"quiet"' || no "set exited non-zero"
bin/ewe-conf set companion.nudges_per_hour 3 || no "set exited non-zero"
[ "$(bin/ewe-conf get companion.proactive)" = "quiet" ] && ok "the value is stored" || no "get companion.proactive"
[ "$(bin/ewe-conf get companion.nudges_per_hour)" = "3" ] && ok "an int is stored" || no "get companion.nudges_per_hour"
for f in quickshell/theme-tokens.json quickshell/user-theme.json hypr/generated/user.lua; do
  [ -e "$S/cfg/$f" ] && no "a companion set regenerated $f" || ok "nothing regenerated: $f"
done
grep -q "hyprctl reload" "$S/calls.log" 2>/dev/null && no "a companion set reloaded Hyprland" || ok "Hyprland not reloaded"
grep -q "^# the desktop companion" "$S/cfg/ewe/ewe.conf" && ok "the section explains itself" || no "no SECTION_NOTES comment above [companion]"
exit $fail
