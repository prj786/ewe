#!/usr/bin/env bash
# ewe-conf sync — two machines, one account, merged key by key (0.33).
# Machines A and B are two XDG trees (own ewe.conf, own sync record, own
# machine id) against tests/mock-nextcloud.py. No network, nothing real
# touched. Checks:
#   * no [sync].provider + a Nextcloud sign-in (cloud.json) → nextcloud
#   * a machine joining the account takes the account's value on a conflict,
#     keeps keys only it has, and never takes LOCAL_ONLY paths
#   * a key only one side changed takes that change, both ways
#   * a deletion on one side carries over
#   * the same key changed on both: the newer file wins
#   * once in step, sync is a no-op on both — LOCAL_ONLY differences never
#     bounce between the machines
#   * every sync leaves a line in sync.log
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'kill $MOCK_NC 2>/dev/null || true; rm -rf "$WORK"' EXIT
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY   # never reload or poke the host's session
export EWE_CONF_SSH_CONFIG="$WORK/ssh-config"   # never the real ~/.ssh/config
export EWE_CONF_TEST_TOKEN="app-pass-0123456789abcdef"
EC="$HERE/bin/ewe-conf"

NPORT=$(( (RANDOM % 20000) + 30000 ))
python3 "$HERE/tests/mock-nextcloud.py" "$NPORT" "$WORK/nc.json" >"$WORK/mock-nc.log" 2>&1 &
MOCK_NC=$!
NC="http://127.0.0.1:$NPORT"
NC_AUTH="tester:app-pass-0123456789abcdef"
NC_DAV="$NC/remote.php/dav/files/tester/ewe"
for _ in $(seq 1 30); do curl -s -o /dev/null "$NC/index.php/login/v2" && break; sleep 0.2; done

fail() { echo "FAIL  $*" >&2; exit 1; }
ok()   { echo "ok  $*"; }
jget() { python3 -c "import json,sys; print(json.load(sys.stdin)$2)" <<<"$1"; }
etag() { curl -s -u "$NC_AUTH" -X PROPFIND -H 'Depth: 0' "$NC_DAV/ewe.conf" | grep -o '<d:getetag>[^<]*' ; }

for m in a b; do
    mkdir -p "$WORK/$m/config/ewe" "$WORK/$m/state" "$WORK/$m/run"
    echo "machine-$m-0123456789" > "$WORK/$m/machine-id"
    # signed in to the ewe account, and NO [sync].provider in the file
    printf '{"server": "%s", "login_name": "tester"}\n' "$NC" > "$WORK/$m/config/ewe/cloud.json"
done
on() {   # on <a|b> <ewe-conf args…>
    local m="$1"; shift
    XDG_CONFIG_HOME="$WORK/$m/config" XDG_STATE_HOME="$WORK/$m/state" XDG_RUNTIME_DIR="$WORK/$m/run" \
        EWE_CONF_MACHINE_ID_FILE="$WORK/$m/machine-id" "$EC" "$@"
}
get() { on "$1" get "$2" 2>/dev/null || echo "<unset>"; }

cat > "$WORK/a/config/ewe/ewe.conf" <<'EOF'
schema = 1

[desktop.theme]
accent = "#ff0000"

[desktop.layout]
gaps_in = 5
rounding = 8

[desktop.input]
kb_layout = "us"

[desktop.input.devices.a-mouse]
sensitivity = 1

[apps]
pinned = ["kitty.desktop"]

[apps.installed]
packages = [{ package = "a-only", source = "repo" }]

[sync]
enabled = false
EOF
cat > "$WORK/b/config/ewe/ewe.conf" <<'EOF'
schema = 1

[desktop.theme]
accent = "#0000ff"

[desktop.input]
kb_layout = "us"

[desktop.input.devices.b-touchpad]
tap = true

[desktop.dock]
autohide = true

[apps.installed]
packages = [{ package = "b-only", source = "repo" }]

[sync]
enabled = false
EOF

# 1 · provider: the sign-in decides, not the Google default
r=$(on a sync-status)
[ "$(jget "$r" "['provider']")" = "nextcloud" ] || fail "no provider + signed in should be nextcloud: $r"
ok "no [sync].provider + a Nextcloud sign-in syncs to the ewe account"

# 2 · A is first: its file goes up
r=$(on a sync --no-hooks)
[ "$(jget "$r" "['ok']")" = "True" ] && [ "$(jget "$r" "['action']")" = "pushed" ] || fail "A first sync: $r"
[ "$(get a sync.provider)" = "nextcloud" ] || fail "A did not record its provider"
ok "the first machine pushes and records provider = nextcloud"

# 3 · B joins: account wins the conflict, B keeps what only it has + its own devices
r=$(on b sync --no-hooks)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "B join: $r"
[ "$(get b desktop.theme.accent)" = "#ff0000" ] || fail "B should take the account's accent: $(get b desktop.theme.accent)"
[ "$(get b desktop.layout.gaps_in)" = "5" ] || fail "B should gain gaps_in"
[ "$(get b desktop.dock.autohide)" = "true" ] || fail "B lost a key only it had"
on b get desktop.input.devices | grep -q b-touchpad || fail "B lost its own device"
on b get desktop.input.devices | grep -q a-mouse && fail "A's device landed on B"
on b get apps.installed | grep -q b-only || fail "B lost its own app manifest"
on b get apps.installed | grep -q a-only && fail "A's app manifest landed on B"
ls "$WORK/b/config/ewe/"ewe.conf.*.merge.bak >/dev/null 2>&1 || fail "no merge backup on B"
ok "a joining machine takes the account on a conflict, keeps its own keys, devices and apps"

# 4 · A catches up with what B brought (dock.autohide), without taking B's devices
r=$(on a sync --no-hooks)
[ "$(get a desktop.dock.autohide)" = "true" ] || fail "A did not get B's dock.autohide: $r"
on a get desktop.input.devices | grep -q b-touchpad && fail "B's device landed on A"
on a get apps.installed | grep -q a-only || fail "A lost its manifest"
ok "the first machine picks up what the second one added"

# 5 · in step: syncing again changes nothing and uploads nothing, on both
for _ in 1 2; do on a sync --no-hooks >/dev/null; on b sync --no-hooks >/dev/null; done
before=$(etag)
ra=$(on a sync --no-hooks); rb=$(on b sync --no-hooks)
[ "$(jget "$ra" "['action']")" = "none" ] || fail "A should be in step: $ra"
[ "$(jget "$rb" "['action']")" = "none" ] || fail "B should be in step: $rb"
[ "$before" = "$(etag)" ] || fail "an in-step sync uploaded again (LOCAL_ONLY ping-pong)"
ok "in step: no-op on both machines, no upload ping-pong over local-only keys"

# 6 · one side changes a key, the other another: both changes survive
on b set --no-hooks desktop.layout.gaps_in 10 >/dev/null
on b sync --no-hooks >/dev/null
on a set --no-hooks desktop.theme.accent '"#00ff00"' >/dev/null
r=$(on a sync --no-hooks)
[ "$(jget "$r" "['action']")" = "merged" ] || fail "A should merge and push: $r"
[ "$(get a desktop.layout.gaps_in)" = "10" ] || fail "A lost B's gaps_in"
[ "$(get a desktop.theme.accent)" = "#00ff00" ] || fail "A lost its own accent"
on b sync --no-hooks >/dev/null
[ "$(get b desktop.theme.accent)" = "#00ff00" ] || fail "B did not get A's accent"
[ "$(get b desktop.layout.gaps_in)" = "10" ] || fail "B lost its gaps_in"
ok "different keys changed on each side: both changes reach both machines"

# 7 · a deletion carries over
on a unset --no-hooks desktop.layout.rounding
on a sync --no-hooks >/dev/null
on b sync --no-hooks >/dev/null
[ "$(get b desktop.layout.rounding)" = "<unset>" ] || fail "B kept a key A deleted"
ok "a key deleted on one machine is deleted on the other"

# 8 · the same key on both: the newer file wins
on b set --no-hooks desktop.theme.accent '"#111111"' >/dev/null
touch -d '2020-01-01' "$WORK/b/config/ewe/ewe.conf"            # B's edit is older…
on a set --no-hooks desktop.theme.accent '"#222222"' >/dev/null
on a sync --no-hooks >/dev/null                                 # …than A's save
on b sync --no-hooks >/dev/null
[ "$(get b desktop.theme.accent)" = "#222222" ] || fail "older local edit beat a newer save: $(get b desktop.theme.accent)"
on b set --no-hooks desktop.theme.accent '"#333333"' >/dev/null
on a set --no-hooks desktop.theme.accent '"#444444"' >/dev/null
touch -d '2020-01-01' "$WORK/a/config/ewe/ewe.conf"
on b sync --no-hooks >/dev/null                                 # B saves now
on a sync --no-hooks >/dev/null                                 # A's older edit loses
[ "$(get a desktop.theme.accent)" = "#333333" ] || fail "newer save lost to an older edit: $(get a desktop.theme.accent)"
ok "the same key changed on both: the newer file wins"

# 8b · the folders you sync follow you; this machine's own [sync] choices do not
on a set --no-hooks sync.folders '[{"remote": "Documents", "local": "~/Documents", "mode": "two-way"}]' >/dev/null
on a set --no-hooks sync.browser false >/dev/null
on a sync --no-hooks >/dev/null
on b sync --no-hooks >/dev/null
on b get sync.folders | grep -q '"Documents"' || fail "B did not get A's folder pairs: $(get b sync.folders)"
[ "$(get b sync.browser)" = "<unset>" ] || fail "A's sync.browser landed on B: $(get b sync.browser)"
[ "$(get b sync.enabled)" = "false" ] || fail "B's sync.enabled moved: $(get b sync.enabled)"
on b set --no-hooks sync.folders '[]' >/dev/null
on b sync --no-hooks >/dev/null
on a sync --no-hooks >/dev/null
[ "$(get a sync.folders)" = "[]" ] || fail "A kept a folder pair B removed: $(get a sync.folders)"
ok "[[sync.folders]] travels between machines; enabled/browser stay on each machine"

# 9 · the log
[ -s "$WORK/a/state/ewe/sync.log" ] || fail "no sync.log"
tail -1 "$WORK/a/state/ewe/sync.log" | python3 -c 'import json,sys; j=json.loads(sys.stdin.read()); assert j["verb"]=="sync" and j["ok"] and j["at"].endswith("Z"), j' \
    || fail "sync.log line: $(tail -1 "$WORK/a/state/ewe/sync.log")"
ok "every sync leaves a line in sync.log"

# 10 · auto-sync after a write: a burst of sets → one trailing sync that
# carries the LAST change (the old throttle dropped it)
rm -f "$WORK/a/run/ewe-conf-push.stamp"
on a set --no-hooks sync.enabled true >/dev/null
on a set --no-hooks desktop.layout.gaps_out 21 >/dev/null
on a set --no-hooks desktop.layout.gaps_out 22 >/dev/null
for _ in $(seq 1 40); do
    curl -s -u "$NC_AUTH" "$NC_DAV/ewe.conf" | grep -q '^gaps_out = 22' && break
    sleep 0.5
done
curl -s -u "$NC_AUTH" "$NC_DAV/ewe.conf" | grep -q '^gaps_out = 22' || fail "the burst's last change never went up"
ok "a burst of writes ends in one sync that carries the last change"

echo "ALL PASS"
