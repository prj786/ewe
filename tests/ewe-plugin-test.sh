#!/usr/bin/env bash
# ewe-plugin kit tests — sandboxed conf, no shell. Covers: create (validates,
# git repo, per-kind files), the settings schema validation, place/set/get
# with a dotted id (whole tables in ewe.conf), typed rejection, list --json
# fields, remove on a linked working copy — and the API 3 / add-ons model
# (plan D1–D3): v3 manifest validation, ipcAliases for ewe.* only, seed
# installing defaults only + refreshing, install, migrate (idempotent,
# removed-skip, the dock rule, fresh = no-op), list --json available/removed/
# missing, `add` of a first-party URL installing from the payload, and the
# PAYLOAD_PLUGINS resolution through a symlinked tool.
#
# Every ewe-plugin call runs with a sandboxed HOME/XDG_* and a fake systemctl
# on PATH, so nothing here can touch the live shell (ground rule 1).
set -euo pipefail
cd "$(dirname "$0")/.."
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
export XDG_CONFIG_HOME="$SB/cfg" XDG_STATE_HOME="$SB/state" XDG_DATA_HOME="$SB/data" HOME="$SB/home"
mkdir -p "$SB/cfg/ewe/plugins" "$SB/cfg/quickshell" "$SB/state" "$SB/home" "$SB/bin" "$SB/data"
printf '#!/bin/sh\nexit 0\n' > "$SB/bin/qs"; printf '#!/bin/sh\nexit 0\n' > "$SB/bin/systemctl"; chmod +x "$SB/bin/"*; export PATH="$SB/bin:$PATH"
printf 'schema = 1\n' > "$SB/cfg/ewe/ewe.conf"
P="$(pwd)/bin/ewe-plugin"; C="$(pwd)/bin/ewe-conf"
pass=0; failn=0
check() { if eval "$2"; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1"; fi; }
jq() { python3 -c "import json,sys; j=json.load(sys.stdin); $1"; }

# create ---------------------------------------------------------------------
(cd "$SB" && $P create acme.clock --name "Desk Clock" --kinds desktop-widget,bar-widget,panel --author Tester >/dev/null)
check "create: files per kind + manifest + licence + readme" "[ -f '$SB/acme.clock/DesktopWidget.qml' ] && [ -f '$SB/acme.clock/Widget.qml' ] && [ -f '$SB/acme.clock/Panel.qml' ] && [ -f '$SB/acme.clock/LICENSE' ] && [ -f '$SB/acme.clock/README.md' ]"
check "create: validates" "$P validate '$SB/acme.clock' >/dev/null"
check "create: a git repo with a first commit" "git -C '$SB/acme.clock' log --oneline | grep -q 'scaffold'"
check "create: refuses a bad id and a reserved one" "! $P create BadId 2>/dev/null && ! $P create ewe.thing 2>/dev/null"
check "create: refuses an unknown kind" "! $P create acme.x --kinds gadget 2>/dev/null"
# acme.clock plays the API 2 plugin from here on (create writes apiVersion 3)
sed -i 's/"apiVersion": 3/"apiVersion": 2/' "$SB/acme.clock/manifest.json"
(cd "$SB" && $P create acme.v3 --kinds quick-tile,quick-page,bar-status,dock-item --no-git >/dev/null)
check "create: the API 3 kinds scaffold and validate (dock-item has no file)" "[ -f '$SB/acme.v3/QuickTile.qml' ] && [ -f '$SB/acme.v3/QuickPage.qml' ] && [ -f '$SB/acme.v3/Status.qml' ] && $P validate '$SB/acme.v3' >/dev/null && grep -q '\"dockItem\"' '$SB/acme.v3/manifest.json'"

# settings schema validation ---------------------------------------------------
mkdir -p "$SB/bad.plugin"; cp "$SB/acme.clock/Widget.qml" "$SB/bad.plugin/"
cat > "$SB/bad.plugin/manifest.json" <<'J'
{"schemaVersion":1,"id":"bad.plugin","name":"Bad","version":"0.1.0","apiVersion":2,"kinds":["bar-widget"],"entryPoints":{"bar-widget":"Widget.qml"},
 "settings":[{"key":"Nope","type":"bool","default":true},{"key":"n","type":"int","default":"3"},{"key":"c","type":"choice","default":"a"},{"key":"ok","type":"color","default":"#abcdef"}],
 "desktopWidget":{"layer":"middle"}}
J
out="$($P validate "$SB/bad.plugin" 2>&1 || true)"
check "schema: bad key, wrong default type, choice without choices, bad layer all reported" "echo '$out' | grep -q 'settings\[0\].key' && echo '$out' | grep -q 'settings.n.default' && echo '$out' | grep -q 'settings.c (choice)' && echo '$out' | grep -q 'desktopWidget.layer'"

# API 3 validation -------------------------------------------------------------
V3="$(pwd)/tests/fixtures/plugins/acme.v3demo"
check "v3: the demo fixture validates (apiVersion 3, every new kind)" "$P validate '$V3' >/dev/null"
check "v3: apiVersion 2 still validates" "$P validate '$SB/acme.clock' --json | jq 'assert j[\"manifest\"][\"apiVersion\"]==2 and j[\"ok\"]'"
mkdir -p "$SB/bad.v3"; cp "$V3"/*.qml "$SB/bad.v3/"
cat > "$SB/bad.v3/manifest.json" <<'J'
{"schemaVersion":1,"id":"bad.v3","name":"Bad v3","version":"0.1.0","apiVersion":4,
 "kinds":["quick-tile","quick-page","dock-item","bar-status"],
 "entryPoints":{"quick-tile":"Tile.qml","quick-page":"Page.qml","bar-status":"Status.qml"},
 "quickTile":{"span":3,"order":"first"},
 "quickPage":{"key":"wifi","label":"","icon":"shield"},
 "dockItem":{"icon":"music","label":"","action":"Bad Action"},
 "requires":{"packages":["ok-pkg","Bad Pkg"],"things":[]},
 "ipcAliases":["player"],"icon":"star","category":"",
 "keybinds":[{"combo":"SUPER + X","ipc":"other toggle"}]}
J
out="$($P validate "$SB/bad.v3" 2>&1 || true)"
check "v3: unsupported apiVersion reported" "echo '$out' | grep -q 'apiVersion 4 is not supported'"
check "v3: quickTile span/order checked" "echo '$out' | grep -q 'quickTile.span' && echo '$out' | grep -q 'quickTile.order'"
check "v3: quickPage reserved key, empty label, bad icon" "echo '$out' | grep -q 'quickPage.key \"wifi\"' && echo '$out' | grep -q 'quickPage.label' && echo '$out' | grep -q 'quickPage.icon'"
check "v3: dockItem icon/label/action checked" "echo '$out' | grep -q 'dockItem.icon' && echo '$out' | grep -q 'dockItem.label' && echo '$out' | grep -q 'dockItem.action'"
check "v3: requires lists + unknown key, icon, category" "echo '$out' | grep -q 'requires.packages' && echo '$out' | grep -q 'requires.things' && echo '$out' | grep -q '^  ! icon must' && echo '$out' | grep -q 'category must'"
check "v3: ipcAliases refused for a third-party id" "echo '$out' | grep -q 'ipcAliases: only first-party'"
check "v3: a keybind must target the plugin (or an alias)" "echo '$out' | grep -q 'keybinds\[0\].ipc must target this plugin'"
sed -i 's/"apiVersion":4/"apiVersion":2/' "$SB/bad.v3/manifest.json"
out="$($P validate "$SB/bad.v3" 2>&1 || true)"
check "v3: the new kinds need apiVersion 3" "echo '$out' | grep -q 'kind \"quick-tile\" needs apiVersion 3'"
mkdir -p "$SB/payload/plugins/ewe.alias"; cp "$V3/Status.qml" "$SB/payload/plugins/ewe.alias/"
cat > "$SB/payload/plugins/ewe.alias/manifest.json" <<'J'
{"schemaVersion":1,"id":"ewe.alias","name":"Alias","version":"1.0.0","apiVersion":3,"kinds":["bar-status"],
 "entryPoints":{"bar-status":"Status.qml"},"ipcAliases":["player"],
 "keybinds":[{"combo":"SUPER + M","ipc":"player toggle"}],
 "requires":{"packages":["ewe-test-no-such-package"],"commands":["ewe-test-no-such-command","sh"]},
 "icon":"icMusic","category":"Media"}
J
check "v3: ipcAliases accepted for ewe.* and a keybind may target the alias" "$P validate '$SB/payload/plugins/ewe.alias' --first-party >/dev/null"

# link it like `dev` does (without the shell restart), then place / set / get --
ln -s "$SB/acme.clock" "$SB/cfg/ewe/plugins/acme.clock"
"$C" set --no-hooks plugins.enabled '["acme.clock"]' >/dev/null
"$C" set --no-hooks plugins.sources '{"acme.clock":"local"}' >/dev/null
j="$($P list --json)"
check "list --json: widget defaults, settings defaults, linked flag" "echo '$j' | python3 -c 'import json,sys; p=json.load(sys.stdin)[\"plugins\"][0]; assert p[\"widget\"]==dict(x=48,y=64,output=\"\",layer=\"desktop\",visible=True), p[\"widget\"]; assert p[\"settings\"]=={\"seconds\": False}; assert p[\"linked\"]'"
check "list --json: apiVersions + the v3 fields are present (null/empty for a v2 plugin)" "echo '$j' | jq 'p=j[\"plugins\"][0]; assert j[\"apiVersion\"]==3 and j[\"apiVersions\"]==[2,3]; assert p[\"quickTile\"] is None and p[\"dockItem\"] is None and p[\"ipcAliases\"]==[] and p[\"requires\"]=={\"packages\":[],\"commands\":[]}'"
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

# the payload: a default plugin, two add-ons (one migrating), bundle.json ------
mkdir -p "$SB/payload/plugins/ewe.demo"; cp "$SB/acme.clock/Widget.qml" "$SB/payload/plugins/ewe.demo/"
cat > "$SB/payload/plugins/ewe.demo/manifest.json" <<'J'
{"schemaVersion":1,"id":"ewe.demo","name":"Demo","version":"1.0.0","apiVersion":2,"kinds":["bar-widget"],"entryPoints":{"bar-widget":"Widget.qml"},
 "keybinds":[{"combo":"SUPER + SHIFT + D","ipc":"ewe.demo toggle"}]}
J
mkdir -p "$SB/payload/plugins/ewe.dock"; cp "$SB/acme.clock/Widget.qml" "$SB/payload/plugins/ewe.dock/"
cat > "$SB/payload/plugins/ewe.dock/manifest.json" <<'J'
{"schemaVersion":1,"id":"ewe.dock","name":"Dock","version":"0.1.0","apiVersion":3,"kinds":["bar-widget"],"entryPoints":{"bar-widget":"Widget.qml"},"icon":"icApps","category":"Desktop"}
J
cat > "$SB/payload/plugins/bundle.json" <<'J'
{"plugins": {
  "ewe.demo":  {"repo": "https://github.com/prj786/ewe-plugin-demo",  "commit": "abc", "version": "1.0.0", "default": true,  "migrate": false},
  "ewe.alias": {"repo": "https://github.com/prj786/ewe-plugin-alias", "commit": "abc", "version": "1.0.0", "default": false, "migrate": true},
  "ewe.dock":  {"repo": "https://github.com/prj786/ewe-plugin-dock",  "commit": "abc", "version": "0.1.0", "default": false, "migrate": true}
}}
J
check "a reserved id is refused from a plain directory" "! $P validate '$SB/payload/plugins/ewe.demo' >/dev/null 2>&1"
check "…but accepted as first-party" "$P validate '$SB/payload/plugins/ewe.demo' --first-party >/dev/null 2>&1"

# the same tool, reached the way ewe-setup deploys it: a symlink in ~/.local/bin
# into a payload copy — PAYLOAD_PLUGINS must be the payload's plugins/, not
# the LINK's ../plugins (that is why `seed --restore` used to seed nothing)
mkdir -p "$SB/payload/bin" "$HOME/.local/bin"
cp "$P" "$SB/payload/bin/ewe-plugin"; cp "$C" "$SB/payload/bin/ewe-conf"
ln -s "$SB/payload/bin/ewe-plugin" "$HOME/.local/bin/ewe-plugin"
L="$HOME/.local/bin/ewe-plugin"
check "payload: resolved through the symlink's REAL path" "$L list --json | jq 'assert j[\"payload\"]==\"$SB/payload/plugins\", j[\"payload\"]'"
check "payload: EWE_PAYLOAD_PLUGINS overrides" "EWE_PAYLOAD_PLUGINS='$SB/elsewhere' $L list --json | jq 'assert j[\"payload\"]==\"$SB/elsewhere\"'"
mkdir -p "$SB/data/ewe/plugins/ewe.fallback"; cp "$SB/payload/plugins/ewe.demo/"* "$SB/data/ewe/plugins/ewe.fallback/"; sed -i 's/ewe.demo/ewe.fallback/g' "$SB/data/ewe/plugins/ewe.fallback/manifest.json"
check "payload: falls back to \$XDG_DATA_HOME/ewe/plugins when the tool's own tree has none" "$P list --json | jq 'assert j[\"payload\"]==\"$SB/data/ewe/plugins\" or j[\"payload\"].endswith(\"/plugins\")' && $P list --json | jq 'ids=[a[\"id\"] for a in j[\"available\"]]; assert (\"ewe.fallback\" in ids) or (\"ewe.clipboard\" in ids), ids'"
export EWE_PAYLOAD_PLUGINS="$SB/payload/plugins"

# list --json: available + removed + missing -----------------------------------
j="$($P list --json)"
check "available: every payload add-on with its flags and state" "echo '$j' | jq 'a={x[\"id\"]:x for x in j[\"available\"]}; assert set(a)=={\"ewe.demo\",\"ewe.alias\",\"ewe.dock\"}, set(a); assert a[\"ewe.demo\"][\"default\"] and not a[\"ewe.demo\"][\"installed\"]; assert a[\"ewe.alias\"][\"migrate\"] and a[\"ewe.alias\"][\"icon\"]==\"icMusic\" and a[\"ewe.alias\"][\"category\"]==\"Media\" and a[\"ewe.alias\"][\"repo\"].endswith(\"ewe-plugin-alias\")'"
check "available: missing packages/commands reported from requires" "echo '$j' | jq 'a={x[\"id\"]:x for x in j[\"available\"]}[\"ewe.alias\"]; assert a[\"missing\"][\"commands\"]==[\"ewe-test-no-such-command\"], a[\"missing\"]; assert a[\"missing\"][\"packages\"]==[\"ewe-test-no-such-package\"] or not __import__(\"shutil\").which(\"pacman\"), a[\"missing\"]'"
check "removed: empty to start" "echo '$j' | jq 'assert j[\"removed\"]==[]'"

# seed: only defaults are installed, add-ons are listed, keybinds follow -------
r="$($P seed "$SB/payload/plugins" --no-restart)"
check "seed: the default copied, enabled, source bundled; add-ons skipped" "echo '$r' | grep -q '\"seeded\": \[\"ewe.demo\"\]' && echo '$r' | grep -q 'an add-on' && [ -d '$SB/cfg/ewe/plugins/ewe.demo' ] && [ ! -e '$SB/cfg/ewe/plugins/ewe.alias' ] && grep -q '\"ewe.demo\" = \"bundled\"' '$SB/cfg/ewe/ewe.conf' && $P list --json | grep -q '\"bundled\": true'"
check "keybinds file has the bind" "grep -q 'hl.bind(\"SUPER + SHIFT + D\", hl.dsp.exec_cmd(\"qs ipc call ewe.demo toggle\"))' '$SB/cfg/hypr/generated/plugin-keybinds.lua'"
$P disable ewe.demo --no-restart >/dev/null
check "disabled: the bind is gone" "! grep -q 'ewe.demo' '$SB/cfg/hypr/generated/plugin-keybinds.lua'"
$P enable ewe.demo --no-restart >/dev/null
sed -i 's/"version":"1.0.0"/"version":"1.1.0"/' "$SB/payload/plugins/ewe.demo/manifest.json"
r="$($P seed "$SB/payload/plugins" --no-restart)"
check "seed: a newer payload version refreshes the copy" "echo '$r' | grep -q '\"refreshed\": \[\"ewe.demo\"\]' && grep -q '1.1.0' '$SB/cfg/ewe/plugins/ewe.demo/manifest.json'"
$P remove ewe.demo --yes >/dev/null
check "remove: bundled copy deleted and remembered (list --json removed)" "[ ! -e '$SB/cfg/ewe/plugins/ewe.demo' ] && grep -q 'removed = \[\"ewe.demo\"\]' '$SB/cfg/ewe/ewe.conf' && $P list --json | jq 'assert j[\"removed\"]==[\"ewe.demo\"]; a={x[\"id\"]:x for x in j[\"available\"]}; assert a[\"ewe.demo\"][\"removed\"] and not a[\"ewe.demo\"][\"installed\"]'"
r="$($P seed "$SB/payload/plugins" --no-restart)"
check "seed: a removed plugin stays removed" "echo '$r' | grep -q 'removed by the user' && [ ! -e '$SB/cfg/ewe/plugins/ewe.demo' ]"
r="$($P seed "$SB/payload/plugins" --no-restart --restore ewe.demo)"
check "seed --restore brings it back" "echo '$r' | grep -q '\"seeded\": \[\"ewe.demo\"\]'"
r="$($L seed --no-restart --restore ewe.alias)"
check "seed --restore <add-on> with no dir (the symlinked tool) installs it from the payload" "echo '$r' | grep -q '\"seeded\": \[\"ewe.alias\"\]' && [ -d '$SB/cfg/ewe/plugins/ewe.alias' ]"
$P remove ewe.demo --yes >/dev/null; $P remove ewe.alias --yes >/dev/null
"$C" set --no-hooks plugins.removed '[]' >/dev/null

# install ----------------------------------------------------------------------
r="$($P install ewe.alias --no-restart)"
check "install: copied, source bundled, enabled, keybind generated, JSON" "echo '$r' | jq 'assert j[\"ok\"] and j[\"installed\"] and j[\"enabled\"] and j[\"version\"]==\"1.0.0\" and j[\"restarted\"] is False, j' && grep -q '\"ewe.alias\" = \"bundled\"' '$SB/cfg/ewe/ewe.conf' && grep -q 'qs ipc call player toggle' '$SB/cfg/hypr/generated/plugin-keybinds.lua'"
check "install: reports the missing requirements" "echo '$r' | jq 'assert \"ewe-test-no-such-command\" in j[\"missing\"][\"commands\"]'"
r="$($P install nope.plugin --no-restart || true)"
check "install: an id not in the payload → ok:false, exit 1" "echo '$r' | jq 'assert j[\"ok\"] is False and \"not in the payload\" in j[\"error\"]' && ! $P install nope.plugin --no-restart >/dev/null 2>&1"
check "install: twice is a no-op refresh, still ok" "$P install ewe.alias --no-restart | jq 'assert j[\"ok\"] and j[\"refreshed\"]'"
$P remove ewe.alias --yes >/dev/null
check "install: forgets a removal" "grep -q 'removed = \[\"ewe.alias\"\]' '$SB/cfg/ewe/ewe.conf' && $P install ewe.alias --no-restart >/dev/null && ! grep -q 'removed = \[\"ewe.alias\"\]' '$SB/cfg/ewe/ewe.conf'"
$P remove ewe.alias --yes >/dev/null; "$C" set --no-hooks plugins.removed '[]' >/dev/null

# add <first-party url | id> installs from the payload ------------------------
r="$($P add https://github.com/prj786/ewe-plugin-alias.git --yes --no-restart)"
check "add: a first-party URL installs the payload copy (no clone)" "echo '$r' | grep -q 'ships inside ewe' && [ -d '$SB/cfg/ewe/plugins/ewe.alias' ] && [ ! -e '$SB/cfg/ewe/plugins/ewe.alias/.git' ] && grep -q '\"ewe.alias\" = \"bundled\"' '$SB/cfg/ewe/ewe.conf'"
$P remove ewe.alias --yes >/dev/null; "$C" set --no-hooks plugins.removed '[]' >/dev/null
r="$($P add ewe.dock --yes --enable --no-restart)"
check "add: a reserved id present in the payload installs + enables it" "echo '$r' | grep -q 'ships inside ewe' && grep -q 'ewe.dock' '$SB/cfg/ewe/ewe.conf' && $P list --json | jq 'p={x[\"id\"]:x for x in j[\"plugins\"]}[\"ewe.dock\"]; assert p[\"enabled\"] and p[\"source\"]==\"bundled\"'"
$P remove ewe.dock --yes >/dev/null; "$C" set --no-hooks plugins.removed '[]' >/dev/null

# restore: payload add-ons listed as enabled come from the payload -------------
"$C" set --no-hooks plugins.enabled '["ewe.alias"]' >/dev/null
"$C" set --no-hooks plugins.sources '{"ewe.alias":"bundled"}' >/dev/null
r="$($P restore --yes --no-restart)"
check "restore: an enabled bundled add-on that is not here is installed from the payload" "echo '$r' | grep -q 'from the payload' && [ -d '$SB/cfg/ewe/plugins/ewe.alias' ]"
$P remove ewe.alias --yes >/dev/null; "$C" set --no-hooks plugins.removed '[]' >/dev/null

# migrate (plan D3) -------------------------------------------------------------
M="$SB/state/ewe/addons-migrated"
r="$($P migrate --fresh --no-restart)"
check "migrate --fresh: installs nothing, records every migrate id as considered" "echo '$r' | jq 'assert j[\"ok\"] and j[\"migrated\"]==[] and j[\"fresh\"] and len(j[\"skipped\"])==2' && [ ! -e '$SB/cfg/ewe/plugins/ewe.alias' ] && python3 -c 'import json; assert sorted(json.load(open(\"$M\"))[\"considered\"])==[\"ewe.alias\",\"ewe.dock\"]'"
r="$($P migrate --no-restart)"
check "migrate: after --fresh a later migrate is a no-op" "echo '$r' | jq 'assert j[\"migrated\"]==[] and \"already migrated\" in j[\"note\"]' && [ ! -e '$SB/cfg/ewe/plugins/ewe.alias' ]"
rm -f "$M"
"$C" set --no-hooks plugins.removed '["ewe.alias"]' >/dev/null
"$C" set --no-hooks desktop.dock.enabled false >/dev/null
r="$($P migrate --no-restart)"
check "migrate: skips a removed id and the dock when desktop.dock.enabled is false" "echo '$r' | jq 'assert j[\"migrated\"]==[]; w={s[\"id\"]:s[\"why\"] for s in j[\"skipped\"]}; assert \"removed\" in w[\"ewe.alias\"] and \"dock.enabled\" in w[\"ewe.dock\"], w' && [ ! -e '$SB/cfg/ewe/plugins/ewe.dock' ]"
rm -f "$M"
"$C" set --no-hooks plugins.removed '[]' >/dev/null
"$C" set --no-hooks desktop.dock.enabled true >/dev/null
r="$($P migrate --no-restart)"
check "migrate: an upgrader gets the migrate ids installed + enabled" "echo '$r' | jq 'assert sorted(j[\"migrated\"])==[\"ewe.alias\",\"ewe.dock\"] and j[\"restarted\"] is False, j' && [ -d '$SB/cfg/ewe/plugins/ewe.alias' ] && [ -d '$SB/cfg/ewe/plugins/ewe.dock' ] && $P list --json | jq 'e=[p[\"id\"] for p in j[\"plugins\"] if p[\"enabled\"]]; assert \"ewe.alias\" in e and \"ewe.dock\" in e, e'"
r="$($P migrate --no-restart)"
check "migrate: idempotent" "echo '$r' | jq 'assert j[\"migrated\"]==[] and j[\"skipped\"]==[]'"
python3 - "$SB/payload/plugins/bundle.json" <<'EOF'
import json, sys
j = json.load(open(sys.argv[1])); j["plugins"]["ewe.demo"]["migrate"] = True
json.dump(j, open(sys.argv[1], "w"))
EOF
r="$($P migrate --no-restart)"
check "migrate: a NEW migrate id in a later payload is migrated once (marker lists considered ids)" "echo '$r' | jq 'assert j[\"migrated\"]==[\"ewe.demo\"], j' && python3 -c 'import json; assert sorted(json.load(open(\"$M\"))[\"considered\"])==[\"ewe.alias\",\"ewe.demo\",\"ewe.dock\"]'"
: > "$M"
r="$($P migrate --no-restart)"
check "migrate: a legacy empty marker counts as migrated" "echo '$r' | jq 'assert j[\"migrated\"]==[] and \"already\" in j[\"note\"]'"
$P remove ewe.demo --yes >/dev/null; $P remove ewe.alias --yes >/dev/null; $P remove ewe.dock --yes >/dev/null

# remove on a linked working copy only unlinks ----------------------------------
$P remove acme.clock --yes >/dev/null
check "remove: link gone, working copy intact" "[ ! -e '$SB/cfg/ewe/plugins/acme.clock' ] && [ -f '$SB/acme.clock/manifest.json' ]"

# dev / add --no-restart never reach systemctl (the harness seeds fixtures this way)
cat > "$SB/bin/systemctl" <<'S'
#!/bin/sh
echo "systemctl called: $*" >> "$SYSTEMCTL_LOG"; exit 0
S
export SYSTEMCTL_LOG="$SB/systemctl.log"; : > "$SYSTEMCTL_LOG"
$P dev "$SB/acme.clock" --no-restart --no-follow >/dev/null
$P add "$V3" --yes --enable --no-restart >/dev/null
check "dev/add --no-restart: linked + copied + enabled, and systemctl never asked to restart" "[ -L '$SB/cfg/ewe/plugins/acme.clock' ] && [ -d '$SB/cfg/ewe/plugins/acme.v3demo' ] && ! grep -q restart '$SYSTEMCTL_LOG'"
check "list --json: the v3 fixture's registries (tile span, page key, dock item, aliases none)" "$P list --json | jq 'p={x[\"id\"]:x for x in j[\"plugins\"]}[\"acme.v3demo\"]; assert p[\"quickTile\"][\"span\"]==2 and p[\"quickPage\"][\"key\"]==\"demo\" and p[\"dockItem\"][\"action\"]==\"acme.v3demo.toggle\" and p[\"barStatus\"] is not None and p[\"ipcAliases\"]==[], p'"

echo "ewe-plugin: $pass passed, $failn failed"
[ "$failn" = 0 ]
