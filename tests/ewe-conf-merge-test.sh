#!/usr/bin/env bash
# ewe-conf sync — two machines, one account, merged key by key (0.33).
# Machines A and B are two XDG trees (own ewe.conf, own sync record, own
# machine id) against tests/mock-nextcloud.py. No network, nothing real
# touched. Checks:
#   * no [sync].provider + a Nextcloud sign-in (cloud.json) → nextcloud
#   * a machine that never synced neither merges nor uploads while the
#     account holds a file (remote-exists) — not from `sync`, not from the
#     sync that follows a write; its own lost first upload is still adopted
#   * a machine joining the account (`sync --join`) takes the account's value
#     on a conflict, keeps keys only it has, and never takes LOCAL_ONLY paths
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
nc_fault() {   # nc_fault <switch> <file> — arm one of mock-nextcloud.py's fault switches
    python3 - "$WORK/nc.json" "$1" "$2" <<'PY'
import json, sys
p, k, v = sys.argv[1:]
s = json.load(open(p)); s[k] = v; json.dump(s, open(p, "w"))
PY
}

for m in a b c; do
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

# 2b · B never synced and the account holds A's file: whose settings win is
# the user's answer (restore, keep this computer's, or join) — no sync gives
# it for them. 2026-11-27: signing in sets sync.enabled, and the sync that
# followed 2 s later merged the account into the new machine and pushed the
# new machine's app list over the backup's, before the restore offer showed.
before=$(etag); bconf=$(cat "$WORK/b/config/ewe/ewe.conf")
r=$(on b sync --no-hooks)
[ "$(jget "$r" "['ok']")" = "False" ] && [ "$(jget "$r" "['error']")" = "remote-exists" ] || fail "a never-synced machine's sync must be refused: $r"
[ "$(jget "$r" "['remote']['appProperties']['machine']")" = "$(uname -n)" ] || fail "remote-exists should name who saved the backup: $r"
[ "$(cat "$WORK/b/config/ewe/ewe.conf")" = "$bconf" ] || fail "a refused sync changed B's file"
[ "$before" = "$(etag)" ] || fail "a refused sync uploaded"
on b set --no-hooks sync.enabled true >/dev/null          # what signing in does; a sync follows by itself
refused() { local n; n=$(grep -c remote-exists "$WORK/b/state/ewe/sync.log" 2>/dev/null || true); echo "${n:-0}"; }
for _ in $(seq 1 40); do
    [ "$(refused)" -ge 2 ] && break
    sleep 0.5
done
[ "$(refused)" -ge 2 ] || fail "the sync after a write never ran, or was not refused: $(cat "$WORK/b/state/ewe/sync.log")"
[ "$(get b desktop.theme.accent)" = "#0000ff" ] || fail "the sync after a write merged the account into B: $(get b desktop.theme.accent)"
[ "$(get b desktop.layout.gaps_in)" = "<unset>" ] || fail "the sync after a write brought A's keys to B"
[ "$before" = "$(etag)" ] || fail "the sync after a write uploaded B's file over the backup"
curl -s -u "$NC_AUTH" "$NC_DAV/ewe.conf" | grep -q 'a-only' || fail "the backup's app list is gone from the account"
r=$(on b sync-status)
[ "$(jget "$r" "['conflict']")" = "remote-exists" ] && [ "$(jget "$r" "['local_synced_at']")" = "" ] \
    || fail "B must still read as never synced with a backup waiting (the restore offer keys on it): $r"
on b set --no-hooks sync.enabled false >/dev/null
ok "a machine that never synced neither merges nor uploads while the account holds a file (remote-exists)"

# 2c · …but its OWN first upload whose reply was lost is no question: the
# account then holds a file this machine has no record of, with the bytes it
# sent. (its own folder in the account, so the account is empty for it)
printf 'schema = 1\n\n[desktop.theme]\naccent = "#c0ffee"\n\n[sync]\nenabled = false\nfolder = "lost"\n' > "$WORK/c/config/ewe/ewe.conf"
nc_fault drop_reply ewe.conf
r=$(on c sync --no-hooks)
[ "$(jget "$r" "['ok']")" = "False" ] || fail "a dropped reply must fail this sync: $r"
curl -sf -u "$NC_AUTH" "$NC/remote.php/dav/files/tester/lost/ewe.conf" | grep -q 'c0ffee' || fail "the mock did not store C's upload"
r=$(on c sync --no-hooks)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "C's own interrupted first upload read as someone else's backup: $r"
r=$(on c sync-status)
[ "$(jget "$r" "['conflict']")" = "None" ] && [ "$(jget "$r" "['local_synced_at']")" != "" ] || fail "C not in step after adopting its own upload: $r"
ok "a first upload whose reply was lost is adopted as this machine's own"

# 3 · B joins (the explicit merge): account wins the conflict, B keeps what only it has + its own devices
r=$(on b sync --join --no-hooks)
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

# 8c · a per-machine key never arrives — also when this machine has no such
# table at all. merge3 guards a LOCAL_ONLY path only when it reaches it, and
# it never did when the parent was absent on one side: B (no [plugins]) took
# A's whole table — its enabled list, sources, widgets.
on a set --no-hooks plugins.enabled '["ewe.dock"]' >/dev/null
on a set --no-hooks plugins.sources '{"ewe.dock": "bundled"}' >/dev/null
on a set --no-hooks plugins.widgets '{"ewe.sysmon": {"x": 1, "y": 2}}' >/dev/null
on a set --no-hooks desktop.displays '{"version": 1, "lastKey": "A-PANEL", "profiles": {}}' >/dev/null
on a set --no-hooks desktop.layout.gaps_in 11 >/dev/null       # something shared, so A uploads
on a sync --no-hooks >/dev/null
r=$(on b sync --no-hooks)
[ "$(get b desktop.layout.gaps_in)" = "11" ] || fail "B did not get A's shared change: $r"
[ "$(get b plugins.enabled)" = "<unset>" ] || fail "A's plugins.enabled landed on B, which has no [plugins]: $(get b plugins.enabled)"
[ "$(get b plugins)" = "<unset>" ] || fail "B grew a [plugins] table out of A's per-machine keys: $(get b plugins)"
[ "$(get b desktop.displays.version)" = "1" ] || fail "B did not get the shared part of desktop.displays"
[ "$(get b desktop.displays.lastKey)" = "<unset>" ] || fail "A's desktop.displays.lastKey landed on B: $(get b desktop.displays.lastKey)"
ok "per-machine keys stay behind when the other machine has no such table"

# …and the other way: B uploads a file with no [plugins]; A's table — which
# holds only A's own keys, exactly as the last agreed copy — must survive it
on b set --no-hooks desktop.layout.gaps_out 30 >/dev/null
on b sync --no-hooks >/dev/null
curl -s -u "$NC_AUTH" "$NC_DAV/ewe.conf" | grep -q '^\[plugins' && fail "B's upload carries a [plugins] table it never had"
r=$(on a sync --no-hooks)
[ "$(get a desktop.layout.gaps_out)" = "30" ] || fail "A did not get B's shared change: $r"
[ "$(get a plugins.enabled)" = '["ewe.dock"]' ] || fail "A lost its plugin list to a copy that has none: $(get a plugins.enabled)"
on a get plugins.widgets | grep -q '"ewe.sysmon"' || fail "A lost its widget placement"
[ "$(get a desktop.displays.lastKey)" = "A-PANEL" ] || fail "A lost its lastKey"
ok "a table of only this machine's keys survives a copy that has no such table"

# in step again, with a table on one side and none on the other: no uploads
for _ in 1 2; do on a sync --no-hooks >/dev/null; on b sync --no-hooks >/dev/null; done
before=$(etag)
ra=$(on a sync --no-hooks); rb=$(on b sync --no-hooks)
[ "$(jget "$ra" "['action']")" = "none" ] && [ "$(jget "$rb" "['action']")" = "none" ] || fail "not in step: $ra / $rb"
[ "$before" = "$(etag)" ] || fail "a per-machine table on one side only made the machines trade uploads"
ok "in step: a per-machine table on one side only causes no upload"

# a shared key in that same table still travels, alone
on a set --no-hooks 'plugins.settings."ewe.dock"' '{"autohide": true}' >/dev/null
on a sync --no-hooks >/dev/null
on b sync --no-hooks >/dev/null
[ "$(get b 'plugins.settings."ewe.dock".autohide')" = "true" ] || fail "B did not get A's plugin settings"
[ "$(get b plugins.enabled)" = "<unset>" ] || fail "plugins.enabled rode along with plugins.settings"
ok "the shared key of a mixed table travels, its per-machine neighbours do not"

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
