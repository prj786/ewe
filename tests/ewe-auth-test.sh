#!/usr/bin/env bash
# ewe-auth plumbing tests — no Google, no real keyring, no browser.
# A mock token endpoint + a fake keyring file exercise: client-config
# precedence, token caching + refresh, client-swap detection, logout cleanup.
set -euo pipefail
cd "$(dirname "$0")/.."

SB="$(mktemp -d)"
trap 'rm -rf "$SB"; kill $MOCK_PID 2>/dev/null || true' EXIT
export XDG_CONFIG_HOME="$SB/cfg" XDG_RUNTIME_DIR="$SB/run"
export EWE_AUTH_FAKE_KEYRING="$SB/keyring"
mkdir -p "$SB/cfg/ewe" "$SB/cfg/quickshell" "$SB/run"

# mock token endpoint: returns a counter-stamped access token
python3 - "$SB" <<'PY' &
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
sb = sys.argv[1]
n = 0
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        global n
        n += 1
        body = json.dumps({"access_token": f"AT-{n}", "expires_in": 3600}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
srv = HTTPServer(("127.0.0.1", 0), H)
open(sb + "/mockport", "w").write(str(srv.server_address[1]))
srv.serve_forever()
PY
MOCK_PID=$!
until [ -s "$SB/mockport" ]; do sleep 0.1; done
export EWE_AUTH_TOKEN_URL="http://127.0.0.1:$(cat "$SB/mockport")/token"

fail() { echo "FAIL: $1"; exit 1; }

# 1 · unconfigured
[ "$(./bin/ewe-auth token --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["error"])')" = "not-configured" ] \
    && echo "ok  unconfigured → not-configured" || fail unconfigured

# 2 · legacy client is found when the ewe client is absent
printf '{"installed":{"client_id":"legacy-id","client_secret":"s"}}' > "$SB/cfg/quickshell/google-oauth.json"
[ "$(./bin/ewe-auth status | python3 -c 'import json,sys;print(json.load(sys.stdin)["client"])')" = "legacy" ] \
    && echo "ok  legacy client discovered" || fail legacy

# 3 · the ewe client wins over legacy
printf '{"client_id":"ewe-id","client_secret":"s"}' > "$SB/cfg/ewe/oauth-client.json"
[ "$(./bin/ewe-auth status | python3 -c 'import json,sys;print(json.load(sys.stdin)["client"])')" = "ewe" ] \
    && echo "ok  ewe client wins" || fail precedence

# 4 · token: refreshes once, then serves the cache
printf 'fake-refresh-token' > "$SB/keyring"
printf '{"client_id":"ewe-id","email":"t@t"}' > "$SB/cfg/ewe/auth.json"
t1="$(./bin/ewe-auth token)"; t2="$(./bin/ewe-auth token)"
[ "$t1" = "AT-1" ] && [ "$t2" = "AT-1" ] && echo "ok  token refresh + runtime cache" || fail "token ($t1/$t2)"

# 5 · client swap → signed-out with reason
printf '{"client_id":"other-id","client_secret":"s"}' > "$SB/cfg/ewe/oauth-client.json"
r="$(./bin/ewe-auth refresh | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("reason",""))')"
[ "$r" = "client-changed" ] && echo "ok  client swap detected → clean signed-out" || fail "swap ($r)"
[ ! -e "$SB/keyring" ] && echo "ok  swap cleared the stale refresh token" || fail swap-clear

# 6 · logout is quiet and clean when already signed out
[ "$(./bin/ewe-auth logout | python3 -c 'import json,sys;print(json.load(sys.stdin)["ok"])')" = "True" ] \
    && echo "ok  logout idempotent" || fail logout

# 7 · keyring-reset is JSON, ok, and leaves the fake keyring empty
[ "$(./bin/ewe-auth keyring-reset | python3 -c 'import json,sys;print(json.load(sys.stdin)["ok"])')" = "True" ] \
    && [ ! -s "$EWE_AUTH_FAKE_KEYRING" ] \
    && echo "ok  keyring-reset" || fail keyring-reset

echo "ALL PASS"
