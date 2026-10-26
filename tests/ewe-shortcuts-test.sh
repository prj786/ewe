#!/usr/bin/env bash
# The shell's own keys (0.35.2): hyprland.lua binds them with
# hl.dsp.global("ewe:<name>") and the QML answers with a
# GlobalShortcut { appid: "ewe"; name: "<name>" } — the global-shortcuts
# protocol, no `sh -c qs ipc call` process per press. Static: every name one
# side uses must exist on the other, no name twice, and none of the shell's
# own surfaces may fall back to a `qs ipc call` bind.
set -u
cd "$(dirname "$0")/.."
fail=0
ok() { echo "ok    $*"; }
no() { echo "FAIL  $*"; fail=1; }

LUA=dotfiles/hypr/hyprland.lua
lua_names=$(grep -v '^[[:space:]]*--' "$LUA" | grep -o 'hl.dsp.global("ewe:[^"]*")' | sed 's/.*ewe:\([^"]*\)".*/\1/' | sort -u)
qml_names=$(grep -rhoE 'appid: "ewe"; name: "[^"]+"' dotfiles/quickshell/*.qml | sed 's/.*name: "\([^"]*\)".*/\1/' | sort)

[ -n "$lua_names" ] && ok "hyprland.lua binds $(echo "$lua_names" | wc -l) ewe: shortcuts" || no "hyprland.lua binds no ewe: shortcut"

dup=$(echo "$qml_names" | uniq -d)
[ -z "$dup" ] && ok "no shortcut name is registered twice" || no "registered twice: $dup"

for n in $lua_names; do
    echo "$qml_names" | grep -qx "$n" && ok "ewe:$n has its GlobalShortcut" || no "ewe:$n is bound but no QML registers it"
done
for n in $(echo "$qml_names" | sort -u); do
    echo "$lua_names" | grep -qx "$n" && ok "ewe:$n is bound in hyprland.lua" || no "ewe:$n is registered but nothing binds it"
done

# the surfaces with a shortcut must not also be reached by a spawn per press
for t in applauncher quicksettings settings lock bar widgets display overview; do
    if grep -E "^hl\.(bind|gesture)|action *=" "$LUA" | grep -q "qs ipc call $t "; then
        no "$t is still bound through qs ipc call"
    else
        ok "$t is not bound through qs ipc call"
    fi
done

# a press bind delivers pressed AND released: toggles must act on one of them
# only (both would open and close in one press)
both=$(grep -rlE 'appid: "ewe"' dotfiles/quickshell/*.qml | while read -r f; do
    awk '/GlobalShortcut \{/{p=1; blk=""} p{blk=blk $0 "\n"} p&&/^    \}/{ if (blk ~ /onPressed/ && blk ~ /onReleased/) print FILENAME; p=0 }' "$f"
done)
[ -z "$both" ] && ok "no shortcut acts on both pressed and released" || no "pressed and released both handled in: $both"

exit $fail
