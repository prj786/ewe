#!/usr/bin/env bash
# ewe-globalshortcuts tests — a fake `hyprctl` plays the compositor: it serves
# the registered portal shortcuts and the current binds, and records every
# `eval`. Covers: Electron-name parsing, the generated Lua, live apply once
# per instance (no duplicate binds), conflict skipping, self-healing after a
# config reload, and `reset`.
set -euo pipefail
cd "$(dirname "$0")/.."

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
export HOME="$SB/home" HYPRLAND_INSTANCE_SIGNATURE="sig-one"
mkdir -p "$HOME/.config/hypr/generated" "$SB/bin"
export SHORTCUTS="$SB/shortcuts.json" BINDS="$SB/binds.json" EVALS="$SB/evals.log"
cat > "$SB/bin/hyprctl" <<'HC'
#!/usr/bin/env bash
case "$1" in
  globalshortcuts) cat "$SHORTCUTS" ;;
  binds) cat "$BINDS" ;;
  eval) echo "$2" >> "$EVALS"; echo ok ;;
  *) echo "unexpected: $*" >&2; exit 1 ;;
esac
HC
chmod +x "$SB/bin/hyprctl"; export PATH="$SB/bin:$PATH"; : > "$EVALS"
GEN="$HOME/.config/hypr/generated/globalshortcuts.lua"

pass=0; failn=0
OUT="$SB/out"
run() { "$@" > "$OUT" 2>&1 || true; }          # last command's output, for the checks
check() { if eval "$2"; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1"; fi; }

cat > "$SHORTCUTS" <<'J'
[{"name":"com.onepassword.OnePassword:CDEEB48EE23AC5C54505DF91D419005F-Ctrl+Shift+Space","description":"1Password shortcut: Ctrl+Shift+Space"},
 {"name":"com.onepassword.OnePassword:9BB2FCB8F35F90E3434FCDE6A83B923B-","description":"1Password shortcut: "},
 {"name":"com.discordapp.Discord:0123456789ABCDEF0123456789ABCDEF-Super+D","description":"push to talk"},
 {"name":"obs:hotkey_start","description":"OBS start recording"}]
J
# ewe already binds Super+D (modmask 64, key D)
echo '[{"modmask":64,"key":"D","dispatcher":"__lua","arg":"9"}]' > "$BINDS"

run bin/ewe-globalshortcuts sync
check "sync ok" "grep -q '\"ok\": true' \"\$OUT\""
check "1Password bound, Discord (Super+D taken) and OBS skipped" "grep -q '\"bound\": 1' \"\$OUT\" && grep -q 'already bound in ewe' \"\$OUT\" && grep -q 'not an Electron-style' \"\$OUT\""
check "empty trigger explained" "grep -q 'no key assigned' \"\$OUT\""
check "generated lua has the bind" "grep -q 'hl.bind(\"CTRL + SHIFT + Space\", hl.dsp.global(\"com.onepassword.OnePassword:CDEEB48EE23AC5C54505DF91D419005F-Ctrl+Shift+Space\"))' '$GEN'"
check "applied live once" "[ \"\$(grep -c 'hl.bind' \"\$EVALS\")\" = 1 ]"

# the compositor now has it; a second sync must not stack a duplicate
echo '[{"modmask":64,"key":"D","dispatcher":"__lua","arg":"9"},{"modmask":5,"key":"Space","dispatcher":"__lua","arg":"12"}]' > "$BINDS"
bin/ewe-globalshortcuts sync >/dev/null
check "second sync applies nothing" "[ \"\$(grep -c 'hl.bind' \"\$EVALS\")\" = 1 ]"

# config reload dropped the live bind → re-applied
echo '[{"modmask":64,"key":"D","dispatcher":"__lua","arg":"9"}]' > "$BINDS"
bin/ewe-globalshortcuts sync >/dev/null
check "after a reload the bind is re-applied" "[ \"\$(grep -c 'hl.bind' \"\$EVALS\")\" = 2 ]"

# new compositor instance: the file was sourced at startup → nothing to apply
echo '[{"modmask":64,"key":"D","dispatcher":"__lua","arg":"9"},{"modmask":5,"key":"Space","dispatcher":"__lua","arg":"12"}]' > "$BINDS"
HYPRLAND_INSTANCE_SIGNATURE=sig-two bin/ewe-globalshortcuts sync >/dev/null
check "fresh instance trusts the sourced file" "[ \"\$(grep -c 'hl.bind' \"\$EVALS\")\" = 2 ]"

# list is readable
run bin/ewe-globalshortcuts list
check "list shows combo + app" "grep -q 'CTRL + SHIFT + Space' \"\$OUT\" && grep -q 'skipped' \"\$OUT\""
run bin/ewe-globalshortcuts list --json
check "list --json" "python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d[\"bound\"][0][\"combo\"]==\"CTRL + SHIFT + Space\", d' \"\$OUT\""

run bin/ewe-globalshortcuts reset
check "reset removes the file and state" "[ ! -f '$GEN' ] && [ ! -f '$HOME/.local/state/ewe/globalshortcuts.json' ]"

echo "ewe-globalshortcuts: $pass passed, $failn failed"
[ "$failn" = 0 ]
