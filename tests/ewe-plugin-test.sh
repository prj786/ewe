#!/usr/bin/env bash
# ewe-plugin kit tests — sandboxed conf, no shell. Covers: create (validates,
# git repo, per-kind files), the settings schema validation, place/set/get
# with a dotted id (whole tables in ewe.conf), typed rejection, list --json
# fields, and remove on a linked working copy.
set -euo pipefail
cd "$(dirname "$0")/.."
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
export XDG_CONFIG_HOME="$SB/cfg" XDG_STATE_HOME="$SB/state" HOME="$SB/home"
mkdir -p "$SB/cfg/ewe/plugins" "$SB/cfg/quickshell" "$SB/state" "$SB/home" "$SB/bin"
printf '#!/bin/sh\nexit 0\n' > "$SB/bin/qs"; printf '#!/bin/sh\nexit 0\n' > "$SB/bin/systemctl"; chmod +x "$SB/bin/"*; export PATH="$SB/bin:$PATH"
printf 'schema = 1\n' > "$SB/cfg/ewe/ewe.conf"
P="$(pwd)/bin/ewe-plugin"; C="$(pwd)/bin/ewe-conf"
pass=0; failn=0
check() { if eval "$2"; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1"; fi; }

# create ---------------------------------------------------------------------
(cd "$SB" && $P create acme.clock --name "Desk Clock" --kinds desktop-widget,bar-widget,panel --author Tester >/dev/null)
check "create: files per kind + manifest + licence + readme" "[ -f '$SB/acme.clock/DesktopWidget.qml' ] && [ -f '$SB/acme.clock/Widget.qml' ] && [ -f '$SB/acme.clock/Panel.qml' ] && [ -f '$SB/acme.clock/LICENSE' ] && [ -f '$SB/acme.clock/README.md' ]"
check "create: validates" "$P validate '$SB/acme.clock' >/dev/null"
check "create: a git repo with a first commit" "git -C '$SB/acme.clock' log --oneline | grep -q 'scaffold'"
check "create: refuses a bad id and a reserved one" "! $P create BadId 2>/dev/null && ! $P create ewe.thing 2>/dev/null"
check "create: refuses an unknown kind" "! $P create acme.x --kinds gadget 2>/dev/null"

# settings schema validation ---------------------------------------------------
mkdir -p "$SB/bad.plugin"; cp "$SB/acme.clock/Widget.qml" "$SB/bad.plugin/"
cat > "$SB/bad.plugin/manifest.json" <<'J'
{"schemaVersion":1,"id":"bad.plugin","name":"Bad","version":"0.1.0","apiVersion":2,"kinds":["bar-widget"],"entryPoints":{"bar-widget":"Widget.qml"},
 "settings":[{"key":"Nope","type":"bool","default":true},{"key":"n","type":"int","default":"3"},{"key":"c","type":"choice","default":"a"},{"key":"ok","type":"color","default":"#abcdef"}],
 "desktopWidget":{"layer":"middle"}}
J
out="$($P validate "$SB/bad.plugin" 2>&1 || true)"
check "schema: bad key, wrong default type, choice without choices, bad layer all reported" "echo '$out' | grep -q 'settings\[0\].key' && echo '$out' | grep -q 'settings.n.default' && echo '$out' | grep -q 'settings.c (choice)' && echo '$out' | grep -q 'desktopWidget.layer'"

# link it like `dev` does (without the shell restart), then place / set / get --
ln -s "$SB/acme.clock" "$SB/cfg/ewe/plugins/acme.clock"
"$C" set --no-hooks plugins.enabled '["acme.clock"]' >/dev/null
"$C" set --no-hooks plugins.sources '{"acme.clock":"local"}' >/dev/null
j="$($P list --json)"
check "list --json: widget defaults, settings defaults, linked flag" "echo '$j' | python3 -c 'import json,sys; p=json.load(sys.stdin)[\"plugins\"][0]; assert p[\"widget\"]==dict(x=48,y=64,output=\"\",layer=\"desktop\",visible=True), p[\"widget\"]; assert p[\"settings\"]=={\"seconds\": False}; assert p[\"linked\"]'"
$P place acme.clock --x 420 --y 300 --layer top >/dev/null
$P set acme.clock seconds true >/dev/null
check "place/set: whole tables keyed by the quoted dotted id" "grep -q '^\[plugins.widgets\]' '$SB/cfg/ewe/ewe.conf' && grep -q '\"acme.clock\" = {x = 420, y = 300, layer = \"top\"}' '$SB/cfg/ewe/ewe.conf' && grep -q '\"acme.clock\" = {seconds = true}' '$SB/cfg/ewe/ewe.conf'"
check "get: the effective values + placement" "$P get acme.clock | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"settings\"][\"seconds\"] is True and d[\"widget\"][\"layer\"]==\"top\" and d[\"widget\"][\"x\"]==420, d'"
check "get one key" "[ \"$($P get acme.clock seconds)\" = true ]"
check "set: a wrong type is refused" "! $P set acme.clock seconds maybe 2>/dev/null && ! $P set acme.clock nosuch 1 2>/dev/null"
$P place acme.clock --visible off >/dev/null
check "place --visible off keeps x/y" "$P get acme.clock | python3 -c 'import json,sys; w=json.load(sys.stdin)[\"widget\"]; assert w[\"visible\"] is False and w[\"x\"]==420, w'"
$P place acme.clock --reset >/dev/null
check "place --reset returns to the manifest defaults" "$P get acme.clock | python3 -c 'import json,sys; w=json.load(sys.stdin)[\"widget\"]; assert w[\"x\"]==48 and w[\"layer\"]==\"desktop\", w'"
check "place refuses a plugin without a desktop widget" "mkdir -p '$SB/cfg/ewe/plugins/bad.plugin' && cp '$SB/bad.plugin/'* '$SB/cfg/ewe/plugins/bad.plugin/' && ! $P place bad.plugin --x 1 2>/dev/null"

# keybinds: declared in the manifest, generated for enabled plugins ----------
mkdir -p "$SB/payload/plugins/ewe.demo"; cp "$SB/acme.clock/Widget.qml" "$SB/payload/plugins/ewe.demo/"
cat > "$SB/payload/plugins/ewe.demo/manifest.json" <<'J'
{"schemaVersion":1,"id":"ewe.demo","name":"Demo","version":"1.0.0","apiVersion":2,"kinds":["bar-widget"],"entryPoints":{"bar-widget":"Widget.qml"},
 "keybinds":[{"combo":"SUPER + SHIFT + D","ipc":"ewe.demo toggle"}]}
J
check "a reserved id is refused from a plain directory" "! $P validate '$SB/payload/plugins/ewe.demo' >/dev/null 2>&1"
check "…but accepted as first-party" "$P validate '$SB/payload/plugins/ewe.demo' --first-party >/dev/null 2>&1"
r="$($P seed "$SB/payload/plugins" --no-restart)"
check "seed: copied, enabled, source bundled" "echo '$r' | grep -q '\"seeded\": \[\"ewe.demo\"\]' && [ -d '$SB/cfg/ewe/plugins/ewe.demo' ] && grep -q '\"ewe.demo\" = \"bundled\"' '$SB/cfg/ewe/ewe.conf' && $P list --json | grep -q '\"bundled\": true'"
check "keybinds file has the bind" "grep -q 'hl.bind(\"SUPER + SHIFT + D\", hl.dsp.exec_cmd(\"qs ipc call ewe.demo toggle\"))' '$SB/cfg/hypr/generated/plugin-keybinds.lua'"
$P disable ewe.demo --no-restart >/dev/null
check "disabled: the bind is gone" "! grep -q 'ewe.demo' '$SB/cfg/hypr/generated/plugin-keybinds.lua'"
$P enable ewe.demo --no-restart >/dev/null
sed -i 's/"version":"1.0.0"/"version":"1.1.0"/' "$SB/payload/plugins/ewe.demo/manifest.json"
r="$($P seed "$SB/payload/plugins" --no-restart)"
check "seed: a newer payload version refreshes the copy" "echo '$r' | grep -q '\"refreshed\": \[\"ewe.demo\"\]' && grep -q '1.1.0' '$SB/cfg/ewe/plugins/ewe.demo/manifest.json'"
$P remove ewe.demo --yes >/dev/null
check "remove: bundled copy deleted and remembered" "[ ! -e '$SB/cfg/ewe/plugins/ewe.demo' ] && grep -q 'removed = \[\"ewe.demo\"\]' '$SB/cfg/ewe/ewe.conf'"
r="$($P seed "$SB/payload/plugins" --no-restart)"
check "seed: a removed plugin stays removed" "echo '$r' | grep -q 'removed by the user' && [ ! -e '$SB/cfg/ewe/plugins/ewe.demo' ]"
r="$($P seed "$SB/payload/plugins" --no-restart --restore ewe.demo)"
check "seed --restore brings it back" "echo '$r' | grep -q '\"seeded\": \[\"ewe.demo\"\]'"
$P remove ewe.demo --yes >/dev/null

# remove on a linked working copy only unlinks ----------------------------------
$P remove acme.clock --yes >/dev/null
check "remove: link gone, working copy intact" "[ ! -e '$SB/cfg/ewe/plugins/acme.clock' ] && [ -f '$SB/acme.clock/manifest.json' ]"

echo "ewe-plugin: $pass passed, $failn failed"
[ "$failn" = 0 ]
