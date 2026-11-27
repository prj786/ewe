#!/usr/bin/env bash
# ewe-drive (0.51.1): the Drive remote follows the CURRENT Google sign-in.
# Until 0.51.1 `setup` copied the client + refresh token once and nothing
# ever updated the copy: a new OAuth client, or signing in again from ewe
# Sync, left ~/Google Drive on a deleted client (`deleted_client`) and a dead
# token. No Google, no rclone, no real keyring, no real HOME: a fake
# secret-tool on PATH, the test refresh token, and --offline everywhere.
set -euo pipefail
cd "$(dirname "$0")/.."

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
export HOME="$SB/home" XDG_CONFIG_HOME="$SB/cfg" XDG_RUNTIME_DIR="$SB/run"
mkdir -p "$HOME" "$SB/cfg/ewe" "$SB/run" "$SB/bin"
# never the real keyring: secret-tool answers from a file
printf '#!/bin/sh\ncat "%s/keyring" 2>/dev/null\n' "$SB" > "$SB/bin/secret-tool"
chmod +x "$SB/bin/secret-tool"
export PATH="$SB/bin:$PATH"
unset EWE_DRIVE_TEST_RT EWE_GOOGLE_CLIENT_FILE
CONF="$SB/cfg/ewe/rclone-drive.conf"

fail() { echo "FAIL: $1"; exit 1; }
client() { printf '{"installed":{"client_id":"%s","client_secret":"s-%s"}}' "$1" "$1" > "$SB/cfg/ewe/oauth-client.json"; }

# 1 · not set up: refresh and mount are silent no-ops and create nothing
printf 'RT-1' > "$SB/keyring"; client old-client
./bin/ewe-drive refresh --offline >/dev/null 2>&1 || fail "refresh without a remote must exit 0"
./bin/ewe-drive mount >/dev/null 2>&1 || fail "mount without a remote must exit 0"
[ ! -e "$CONF" ] && echo "ok  not set up → nothing written" || fail "a remote appeared"

# 2 · setup writes the remote from the keyring + the client, private
./bin/ewe-drive setup --offline >/dev/null
grep -q 'client_id = old-client' "$CONF" && grep -q '"refresh_token":"RT-1"' "$CONF" \
    && echo "ok  setup copies the current sign-in" || fail setup
[ "$(stat -c %a "$CONF")" = 600 ] && echo "ok  the remote is 0600" || fail "mode $(stat -c %a "$CONF")"
grep -q 'Google%20Drive' "$SB/cfg/gtk-3.0/bookmarks" && echo "ok  sidebar bookmark" || fail bookmark

# 3 · a new client + a new sign-in (the owner's case): refresh follows both
client new-client; printf 'RT-2' > "$SB/keyring"
./bin/ewe-drive refresh --offline >/dev/null
grep -q 'client_id = new-client' "$CONF" && ! grep -q old-client "$CONF" \
    && grep -q '"refresh_token":"RT-2"' "$CONF" && ! grep -q RT-1 "$CONF" \
    && echo "ok  refresh follows a new client and token (all three remotes)" || fail "refresh did not follow"
[ "$(grep -c 'client_id = new-client' "$CONF")" = 2 ] || fail "both drive remotes must change"

# 4 · nothing changed: the remote is left as rclone last wrote it
sed -i 's/"access_token":"x"/"access_token":"rclone-wrote-this"/' "$CONF"
./bin/ewe-drive refresh --offline >/dev/null
grep -q rclone-wrote-this "$CONF" && echo "ok  an unchanged sign-in keeps rclone's own token" || fail "rewrote needlessly"

# 5 · signed out: refresh says so and keeps the copy it has
: > "$SB/keyring"
if ./bin/ewe-drive refresh --offline >/dev/null 2>&1; then fail "refresh with no sign-in must fail"; fi
grep -q '"refresh_token":"RT-2"' "$CONF" && echo "ok  signed out → refresh refuses, copy kept" || fail "copy lost"

# 6 · status reports whether the last sign-in allowed Drive
st() { ./bin/ewe-drive status | python3 -c 'import json,sys; print(json.load(sys.stdin)["drive_scope"])'; }
[ "$(st)" = unknown ] || fail "no auth.json → unknown"
printf '{"scopes":["openid","https://www.googleapis.com/auth/drive.appdata"]}' > "$SB/cfg/ewe/auth.json"
[ "$(st)" = no ] || fail "appdata only → no"
printf '{"scopes":["openid","https://www.googleapis.com/auth/drive"]}' > "$SB/cfg/ewe/auth.json"
[ "$(st)" = yes ] && echo "ok  status: drive_scope yes / no / unknown" || fail "drive scope → yes"

# 7 · ewe-auth: with Drive set up, a sign-in asks for Drive (the source:
# no browser here) and the drive set-up check reads the remote
python3 - "$PWD/bin/ewe-auth" <<'PY' || fail "ewe-auth drive_set_up"
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("ewe_auth", sys.argv[1])
spec = importlib.util.spec_from_loader("ewe_auth", loader)
m = importlib.util.module_from_spec(spec)
sys.argv = [sys.argv[1]]
loader.exec_module(m)
assert m.drive_set_up(), "the remote exists → Drive is set up"
PY
grep -q 'if "--with-drive" in argv or drive_set_up():' bin/ewe-auth \
    && grep -q 'drive_follow("refresh")' bin/ewe-auth \
    && echo "ok  ewe-auth keeps Drive in a sign-in and refreshes the remote after it" || fail "ewe-auth wiring"
rm -f "$CONF"
python3 - "$PWD/bin/ewe-auth" <<'PY' || fail "ewe-auth drive_set_up (none)"
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("ewe_auth", sys.argv[1])
spec = importlib.util.spec_from_loader("ewe_auth", loader)
m = importlib.util.module_from_spec(spec)
sys.argv = [sys.argv[1]]
loader.exec_module(m)
assert not m.drive_set_up(), "no remote → Drive is not set up"
PY
echo "ok  no remote → a sign-in leaves Drive alone"

echo "ALL PASS"
