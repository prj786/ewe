#!/usr/bin/env bash
# ewe-conf and quoted keys: a plugin id has dots, so its settings live under
# plugins.settings."ewe.passwords". A plain split of the dotted key once wrote
# a stray [plugins.settings."\"ewe"] table and left the real setting alone
# (2026-10-15). A quoted part keeps its dots; a broken key is refused.
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
export HYPRLAND_INSTANCE_SIGNATURE=test-only-stub
fail=0
ok() { echo "ok    $*"; }
no() { echo "FAIL  $*"; fail=1; }
CONF="$S/cfg/ewe/ewe.conf"

bin/ewe-conf set 'plugins.settings."ewe.passwords"' '{"provider": "1password", "press_enter": true}' \
  || no "setting a whole table under a quoted id failed"
bin/ewe-conf set 'plugins.settings."ewe.passwords".provider' ewe || no "set through a quoted id exited non-zero"
[ "$(bin/ewe-conf get 'plugins.settings."ewe.passwords".provider')" = "ewe" ] \
  && ok "a quoted id reaches the real setting" || no "get through a quoted id"
[ "$(bin/ewe-conf get "plugins.settings.'ewe.passwords'.press_enter")" = "true" ] \
  && ok "single quotes work, the sibling key survived" || no "press_enter lost or single quotes refused"
grep -q '"ewe.passwords" = {' "$CONF" && ok "the table keeps its quoted id" || no "no \"ewe.passwords\" table in the file"
grep -q '\\"ewe' "$CONF" && no "a stray \"\\\"ewe\" table was written" || ok "no stray table"

before="$(cat "$CONF")"
for bad in 'plugins.settings."ewe.passwords.provider' 'plugins..settings' 'plugins.settings."ewe"x' '.plugins' 'plugins.'; do
  bin/ewe-conf set "$bad" 1 2>"$S/err" && no "a broken key was accepted: $bad" || {
    grep -q '"bad-key"' "$S/err" && ok "refused with bad-key: $bad" || no "no bad-key error for: $bad"
  }
done
[ "$(cat "$CONF")" = "$before" ] && ok "refused keys changed nothing" || no "a refused key changed the file"

bin/ewe-conf unset 'plugins.settings."ewe.passwords".press_enter' || no "unset through a quoted id exited non-zero"
bin/ewe-conf get 'plugins.settings."ewe.passwords".press_enter' >/dev/null 2>&1 \
  && no "unset left the key" || ok "unset through a quoted id"
[ "$(bin/ewe-conf get desktop.theme.accent)" != "" ] && ok "plain keys still work" || no "a plain key broke"
exit $fail
