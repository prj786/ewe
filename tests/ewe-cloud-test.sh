#!/usr/bin/env bash
# ewe-cloud test — the Nextcloud broker against tests/mock-nextcloud.py.
# No network, no real server, no keyring, no real config: XDG_* point at a
# temp dir, EWE_CLOUD_FAKE_KEYRING replaces secret-tool, the browser hand-off
# is skipped and the test itself "clicks" the login link. Covers:
#   * the https guard (a plain-http server is refused unless it is the mock)
#   * login: flow start → link published → poll → app password stored →
#     cloud.json written → the account facts in the result
#   * status: signed in, facts from OCS, keyring state; offline status
#     still says signed in; a revoked app password says so
#   * token / --json / webdav-url / avatar
#   * logout revokes server-side and clears everything; status is clean after
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'kill $MOCK 2>/dev/null || true; rm -rf "$WORK"' EXIT

export XDG_CONFIG_HOME="$WORK/config"
export XDG_CACHE_HOME="$WORK/cache"
export XDG_RUNTIME_DIR="$WORK/run"
export XDG_STATE_HOME="$WORK/state"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
export EWE_CLOUD_FAKE_KEYRING="$WORK/keyring"
export EWE_CLOUD_NO_BROWSER=1
export EWE_CLOUD_SERVER_INSECURE=1

PORT=$(( (RANDOM % 20000) + 30000 ))
python3 "$HERE/tests/mock-nextcloud.py" "$PORT" "$WORK/nc.json" >"$WORK/mock.log" 2>&1 &
MOCK=$!
SRV="http://127.0.0.1:$PORT"
for _ in $(seq 1 30); do curl -s -o /dev/null "$SRV/index.php/login/v2" && break; sleep 0.2; done

EC="$HERE/bin/ewe-cloud"
fail() { echo "FAIL  $*" >&2; exit 1; }
ok()   { echo "ok  $*"; }
jget() { python3 -c "import json,sys; print(json.load(sys.stdin)$2)" <<<"$1"; }

# 1 · https guard: a plain-http server is refused unless the loopback exception is on
r=$(EWE_CLOUD_SERVER_INSECURE= "$EC" login "http://127.0.0.1:$PORT")
[ "$(jget "$r" "['error']")" = "insecure-server" ] || fail "insecure guard: $r"
r=$("$EC" login "http://example.org")            # loopback exception is loopback-only
[ "$(jget "$r" "['error']")" = "insecure-server" ] || fail "insecure guard (non-loopback): $r"
r=$("$EC" login)
[ "$(jget "$r" "['error']")" = "no-server" ] || fail "no-server: $r"
ok "https guard: plain http only for the loopback mock"

# 2 · status before any login
r=$("$EC" status)
[ "$(jget "$r" "['signed_in']")" = "False" ] || fail "status should be signed out: $r"
[ "$(jget "$r" "['keyring_state']")" = "ok" ] || fail "fake keyring state: $r"
ok "status is honest before a login"

# 3 · login: start the flow in the background, "click" the published link, collect the grant
"$EC" login "127.0.0.1:$PORT" >"$WORK/login.out" 2>"$WORK/login.err" &
LOGIN=$!
for _ in $(seq 1 50); do [ -s "$XDG_RUNTIME_DIR/ewe-cloud-login-url" ] && break; sleep 0.1; done
url=$(cat "$XDG_RUNTIME_DIR/ewe-cloud-login-url")
[[ "$url" == "$SRV/login/v2/flow/"* ]] || fail "login url not published: '$url'"
grep -q "^login-url: $url" "$WORK/login.err" || fail "login url not on stderr"
curl -sf "$url" >/dev/null || fail "the login page did not answer"
wait $LOGIN
r=$(cat "$WORK/login.out")
[ "$(jget "$r" "['ok']")" = "True" ] || fail "login: $r"
[ "$(jget "$r" "['user']")" = "tester" ] || fail "login user: $r"
[ "$(jget "$r" "['display_name']")" = "Test User" ] || fail "login display name: $r"
[ "$(jget "$r" "['email']")" = "tester@example.org" ] || fail "login email: $r"
[ "$(jget "$r" "['quota']['total']")" = "1000" ] || fail "login quota: $r"
[ "$(cat "$EWE_CLOUD_FAKE_KEYRING")" = "app-pass-0123456789abcdef" ] || fail "app password not in the keyring"
[ "$(jget "$(cat "$XDG_CONFIG_HOME/ewe/cloud.json")" "['server']")" = "$SRV" ] || fail "cloud.json server"
[ "$(jget "$(cat "$XDG_CONFIG_HOME/ewe/cloud.json")" "['login_name']")" = "tester" ] || fail "cloud.json login_name"
grep -q 'app-pass' "$XDG_CONFIG_HOME/ewe/cloud.json" && fail "the app password leaked into cloud.json"
[ ! -e "$XDG_RUNTIME_DIR/ewe-cloud-login-url" ] || fail "login url file not cleaned up"
ok "login: flow → link → poll → app password in the keyring, facts in the result"

# 4 · status after login
r=$("$EC" status)
[ "$(jget "$r" "['signed_in']")" = "True" ] || fail "status signed in: $r"
[ "$(jget "$r" "['display_name']")" = "Test User" ] || fail "status display name: $r"
[ "$(jget "$r" "['quota']['relative']")" = "10.0" ] || fail "status quota: $r"
ok "status reports the account facts from OCS"

# 5 · token, webdav-url
[ "$("$EC" token)" = "app-pass-0123456789abcdef" ] || fail "token"
r=$("$EC" token --json)
[ "$(jget "$r" "['user']")" = "tester" ] || fail "token --json: $r"
[ "$("$EC" webdav-url)" = "$SRV/remote.php/dav/files/tester/" ] || fail "webdav-url: $("$EC" webdav-url)"
ok "token and webdav-url"

# 6 · avatar is cached
r=$("$EC" avatar)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "avatar: $r"
[ -s "$XDG_CACHE_HOME/ewe/cloud-avatar.png" ] || fail "avatar not cached"
head -c 8 "$XDG_CACHE_HOME/ewe/cloud-avatar.png" | grep -q PNG || fail "avatar is not a PNG"
ok "avatar cached to ~/.cache/ewe"

# 7 · a revoked app password is reported, not hidden
python3 - "$WORK/nc.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); s["revoked"] = True; json.dump(s, open(sys.argv[1], "w"))
PY
r=$("$EC" status)
[ "$(jget "$r" "['signed_in']")" = "False" ] || fail "revoked should read signed out: $r"
[ "$(jget "$r" "['reason']")" = "revoked" ] || fail "revoked reason: $r"
python3 - "$WORK/nc.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); s["revoked"] = False; json.dump(s, open(sys.argv[1], "w"))
PY
ok "a revoked app password is reported as such"

# 8 · offline: the server is gone, status still says signed in (facts from cloud.json)
kill $MOCK; wait $MOCK 2>/dev/null || true
r=$("$EC" status)
[ "$(jget "$r" "['signed_in']")" = "True" ] || fail "offline status: $r"
[ "$(jget "$r" "['offline']")" = "True" ] || fail "offline flag: $r"
[ "$(jget "$r" "['display_name']")" = "Test User" ] || fail "offline facts: $r"
python3 "$HERE/tests/mock-nextcloud.py" "$PORT" "$WORK/nc.json" >>"$WORK/mock.log" 2>&1 &
MOCK=$!
for _ in $(seq 1 30); do curl -s -o /dev/null "$SRV/index.php/login/v2" && break; sleep 0.2; done
ok "offline: still signed in, last-known facts"

# 8b · ewe-files setup --offline writes the rclone remote from the signed-in account
export HOME="$WORK/home"; mkdir -p "$HOME"
r=$("$HERE/bin/ewe-files" setup --offline 2>&1) || fail "ewe-files setup: $r"
conf="$XDG_CONFIG_HOME/ewe/rclone-nextcloud.conf"
[ -f "$conf" ] || fail "rclone remote not written"
grep -q "^url = $SRV/remote.php/dav/files/tester/" "$conf" || fail "remote url: $(cat "$conf")"
grep -q '^user = tester$' "$conf" || fail "remote user"
grep -q '^type = webdav$' "$conf" && grep -q '^vendor = nextcloud$' "$conf" || fail "remote type/vendor"
[ "$(stat -c %a "$conf")" = "600" ] || fail "remote file mode: $(stat -c %a "$conf")"
grep -q 'Nextcloud' "$XDG_CONFIG_HOME/gtk-3.0/bookmarks" || fail "Nemo bookmark missing"
r=$("$HERE/bin/ewe-files" status)
[ "$(jget "$r" "['configured']")" = "True" ] || fail "ewe-files status: $r"
[ "$(jget "$r" "['mounted']")" = "False" ] || fail "ewe-files status mounted: $r"
"$HERE/bin/ewe-files" forget >/dev/null 2>&1
[ ! -f "$conf" ] || fail "forget left the remote"
ok "ewe-files: remote from the signed-in account, bookmark, status, forget"

# 9 · logout revokes server-side and clears everything
r=$("$EC" logout)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "logout: $r"
[ "$(jget "$r" "['revoked']")" = "True" ] || fail "logout did not revoke: $r"
[ ! -e "$EWE_CLOUD_FAKE_KEYRING" ] || fail "keyring not cleared"
[ ! -e "$XDG_CONFIG_HOME/ewe/cloud.json" ] || fail "cloud.json not removed"
r=$("$EC" status)
[ "$(jget "$r" "['signed_in']")" = "False" ] || fail "status after logout: $r"
"$EC" token >/dev/null 2>&1 && fail "token should fail after logout"
ok "logout revokes the app password and leaves no trace"

echo "ALL PASS"
