#!/usr/bin/env bash
# ewe-conf sync engine test — push/pull/conflict against a LOCAL mock Drive.
# No network, no Google, no real config touched: XDG_CONFIG_HOME is a temp
# dir and EWE_CONF_DRIVE_BASE points at a python http server that speaks just
# enough Drive v3 (list, multipart create, media PATCH, metadata PATCH,
# alt=media GET) to exercise every branch RFC-002 promises:
#   * first push creates the file WITH the {machine, schema} manifest
#   * second push updates it and re-stamps the manifest
#   * push against a NEWER remote from ANOTHER machine → refused (remote-newer)
#   * push --force overrides
#   * pull adopts the remote and keeps the loser as ewe.conf.<ts>.bak
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'kill $MOCK 2>/dev/null || true; rm -rf "$WORK"' EXIT

export XDG_CONFIG_HOME="$WORK/config"
export EWE_CONF_TEST_TOKEN="test-token-abcdefghijklmnop"
export EWE_CONF_SSH_CONFIG="$WORK/ssh-config"   # never the real ~/.ssh/config
mkdir -p "$WORK/config/ewe"

PORT=$(( (RANDOM % 20000) + 30000 ))
python3 - "$PORT" "$WORK/drive.json" >"$WORK/mock.log" 2>&1 <<'PY' &
import json, re, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT, STATE = int(sys.argv[1]), sys.argv[2]

def load():
    try:
        return json.load(open(STATE))
    except Exception:
        return None

def save(f):
    json.dump(f, open(STATE, "w"))

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _json(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers()
        self.wfile.write(b)
    def do_GET(self):
        f = load()
        if "alt=media" in self.path:
            if not f: return self._json({"error": "notfound"}, 404)
            b = f["content"].encode()
            self.send_response(200); self.send_header("Content-Length", str(len(b)))
            self.end_headers(); self.wfile.write(b); return
        self._json({"files": ([{k: f[k] for k in ("id", "name", "modifiedTime", "appProperties")}] if f else [])})
    def do_POST(self):  # multipart create
        body = self.rfile.read(int(self.headers["Content-Length"])).decode(errors="replace")
        meta = json.loads(re.search(r"\{.*?\}(?=\r\n--)", body, re.S).group(0))
        content = body.split("\r\n\r\n", 2)[2].rsplit("\r\n--", 1)[0]
        content = content.split("\r\n\r\n", 1)[1] if "\r\n\r\n" in content else content
        f = {"id": "mock1", "name": meta["name"],
             "modifiedTime": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
             "appProperties": meta.get("appProperties", {}), "content": content}
        save(f); self._json({"id": f["id"]})
    def do_PATCH(self):
        f = load() or {}
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if "uploadType=media" in self.path:
            f["content"] = body.decode(errors="replace")
            f["modifiedTime"] = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
        else:
            j = json.loads(body or b"{}")
            if "appProperties" in j:
                f.setdefault("appProperties", {}).update(j["appProperties"])
            if "modifiedTime" in j:            # test backdoor: forge the clock
                f["modifiedTime"] = j["modifiedTime"]
        save(f); self._json({"id": f.get("id", "mock1")})

HTTPServer(("127.0.0.1", PORT), H).serve_forever()
PY
MOCK=$!
export EWE_CONF_DRIVE_BASE="http://127.0.0.1:$PORT"
for _ in $(seq 1 20); do curl -sf "$EWE_CONF_DRIVE_BASE/drive/v3/files" >/dev/null 2>&1 && break; sleep 0.2; done

EC="$HERE/bin/ewe-conf"
CONF="$WORK/config/ewe/ewe.conf"
fail() { echo "FAIL  $*" >&2; exit 1; }
ok()   { echo "ok  $*"; }
jget() { python3 -c "import json,sys; print(json.load(sys.stdin)$2)" <<<"$1"; }

printf 'schema = 1\n\n[desktop.theme]\naccent = "#0a84ff"\n' > "$CONF"

# 1 · first push creates the file with the manifest
r=$("$EC" push)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "first push: $r"
[ "$(jget "$r" "['machine']")" = "$(uname -n)" ] || fail "manifest machine missing: $r"
ok "first push creates + stamps {machine, schema}"

# 2 · status sees it
r=$("$EC" sync-status)
[ "$(jget "$r" "['remote']['appProperties']['machine']")" = "$(uname -n)" ] || fail "status manifest: $r"
ok "sync-status returns the manifest"

# 3 · same-machine push with an older local file still allowed (self wins)
r=$("$EC" push)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "same-machine repush: $r"
ok "same-machine push never conflicts with itself"

# 4 · a NEWER remote from ANOTHER machine → push refused
curl -sf -X PATCH -H 'Content-Type: application/json' \
    -d "{\"appProperties\": {\"machine\": \"other-machine\"}, \"modifiedTime\": \"2099-01-01T00:00:00.000Z\"}" \
    "$EWE_CONF_DRIVE_BASE/drive/v3/files/mock1" >/dev/null
r=$("$EC" push)
[ "$(jget "$r" "['ok']")" = "False" ] || fail "conflict push should refuse: $r"
[ "$(jget "$r" "['error']")" = "remote-newer" ] || fail "expected remote-newer: $r"
ok "push refuses to clobber another machine's newer document"

# 5 · --force overrides and re-stamps
r=$("$EC" push --force)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "force push: $r"
r=$("$EC" sync-status)
[ "$(jget "$r" "['remote']['appProperties']['machine']")" = "$(uname -n)" ] || fail "force restamp: $r"
ok "push --force overrides and re-stamps the manifest"

# 6 · pull adopts remote, keeps the loser as .bak
curl -sf -X PATCH "$EWE_CONF_DRIVE_BASE/upload/drive/v3/files/mock1?uploadType=media" \
    --data-binary $'schema = 1\n\n[desktop.theme]\naccent = "#ff0000"\n' >/dev/null
r=$("$EC" pull)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "pull: $r"
grep -q 'ff0000' "$CONF" || fail "pull did not adopt remote content"
ls "$WORK/config/ewe/"ewe.conf.*.bak >/dev/null 2>&1 || fail "pull kept no .bak"
ok "pull adopts the remote and keeps the loser as .bak"

echo "ALL PASS"
