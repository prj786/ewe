#!/usr/bin/env bash
# ewe-conf sync engine test — push/pull/conflict against a LOCAL mock Drive.
# No network, no Google, no real config touched: XDG_CONFIG_HOME and
# XDG_STATE_HOME are temp dirs and EWE_CONF_DRIVE_BASE points at a python
# http server that speaks just enough Drive v3 (list, multipart create,
# multipart + media PATCH, metadata PATCH, alt=media GET) to exercise every
# branch RFC-002 promises:
#   * first push creates the file WITH the {machine, schema} manifest, in
#     the SAME request as the content, and records what it saw
#   * a re-push from the machine that last synced is allowed (in sync)
#   * the remote changed since we last synced (another machine pushed) →
#     push refused (remote-newer) — no clocks, no hostnames involved
#   * push --force overrides and re-stamps
#   * pull adopts the remote atomically, keeps the loser as ewe.conf.<ts>.bak,
#     and records the remote so the next push is allowed
#   * a machine that has NEVER synced but finds a backup → push refused
#     (remote-exists): restore first, or --force
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'kill $MOCK 2>/dev/null || true; rm -rf "$WORK"' EXIT

export XDG_CONFIG_HOME="$WORK/config"
export XDG_STATE_HOME="$WORK/state"                # sync.json lives here
unset HYPRLAND_INSTANCE_SIGNATURE                   # never reload the host's Hyprland
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

def now():
    return time.strftime("%Y-%m-%dT%H:%M:%S.", time.gmtime()) + "%03dZ" % (int(time.time() * 1000) % 1000)

def multipart(headers, body):
    """(metadata dict, content str) from a multipart/related body"""
    m = re.search(r'boundary=([^;]+)', headers.get("Content-Type", ""))
    b = ("--" + m.group(1)).encode()
    parts = [p for p in body.split(b) if p.strip() not in (b"", b"--")]
    meta, content = {}, ""
    for p in parts:
        head, _, data = p.partition(b"\r\n\r\n")
        data = data[:-2] if data.endswith(b"\r\n") else data
        if b"application/json" in head:
            meta = json.loads(data.decode())
        else:
            content = data.decode(errors="replace")
    return meta, content

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _json(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers()
        self.wfile.write(b)
    def _public(self, f):
        return {k: f[k] for k in ("id", "name", "modifiedTime", "appProperties")}
    def do_GET(self):
        f = load()
        if "alt=media" in self.path:
            if not f: return self._json({"error": "notfound"}, 404)
            b = f["content"].encode()
            self.send_response(200); self.send_header("Content-Length", str(len(b)))
            self.end_headers(); self.wfile.write(b); return
        self._json({"files": ([self._public(f)] if f else [])})
    def do_POST(self):  # multipart create
        body = self.rfile.read(int(self.headers["Content-Length"]))
        meta, content = multipart(self.headers, body)
        f = {"id": "mock1", "name": meta["name"], "modifiedTime": now(),
             "appProperties": meta.get("appProperties", {}), "content": content}
        save(f); self._json(self._public(f))
    def do_PATCH(self):
        f = load() or {}
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if "uploadType=multipart" in self.path:      # content + manifest, one request
            meta, content = multipart(self.headers, body)
            f["content"] = content
            f["modifiedTime"] = now()
            f["appProperties"] = meta.get("appProperties", f.get("appProperties", {}))
        elif "uploadType=media" in self.path:        # test backdoor: a foreign content push
            f["content"] = body.decode(errors="replace")
            f["modifiedTime"] = now()
        else:                                        # metadata-only PATCH (test backdoors)
            j = json.loads(body or b"{}")
            if "appProperties" in j:
                f.setdefault("appProperties", {}).update(j["appProperties"])
            if "modifiedTime" in j:            # forge the clock
                f["modifiedTime"] = j["modifiedTime"]
        save(f); self._json(self._public(f))

HTTPServer(("127.0.0.1", PORT), H).serve_forever()
PY
MOCK=$!
export EWE_CONF_DRIVE_BASE="http://127.0.0.1:$PORT"
for _ in $(seq 1 20); do curl -sf "$EWE_CONF_DRIVE_BASE/drive/v3/files" >/dev/null 2>&1 && break; sleep 0.2; done

EC="$HERE/bin/ewe-conf"
CONF="$WORK/config/ewe/ewe.conf"
SYNC="$WORK/state/ewe/sync.json"
fail() { echo "FAIL  $*" >&2; exit 1; }
ok()   { echo "ok  $*"; }
jget() { python3 -c "import json,sys; print(json.load(sys.stdin)$2)" <<<"$1"; }
no_tmp() { ls "$WORK/config/ewe/".ewe.conf* >/dev/null 2>&1 && fail "temp file left behind: $(ls "$WORK/config/ewe/")"; true; }

printf 'schema = 1\n\n[desktop.theme]\naccent = "#0a84ff"\n' > "$CONF"

# 1 · first push creates the file with the manifest IN the upload, and records it
r=$("$EC" push)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "first push: $r"
[ "$(jget "$r" "['machine']")" = "$(uname -n)" ] || fail "manifest machine missing: $r"
[ -n "$(jget "$r" "['modified']")" ] || fail "push did not return the remote modifiedTime: $r"
[ -f "$SYNC" ] || fail "push recorded no sync state"
[ "$(jget "$(cat "$SYNC")" "['remote_modified']")" = "$(jget "$r" "['modified']")" ] || fail "recorded modifiedTime differs"
ok "first push creates + stamps {machine, schema} in one request, records it"

# 2 · status sees it — both facts, separately
r=$("$EC" sync-status)
[ "$(jget "$r" "['remote']['appProperties']['machine']")" = "$(uname -n)" ] || fail "status manifest: $r"
[ "$(jget "$r" "['remote_machine']")" = "$(uname -n)" ] || fail "status remote_machine: $r"
[ -n "$(jget "$r" "['local_synced_at']")" ] || fail "status local_synced_at: $r"
[ "$(jget "$r" "['in_sync']")" = "True" ] || fail "status in_sync: $r"
ok "sync-status returns the manifest, who saved it, and when we last synced"

# 3 · re-push from the machine that last synced: allowed (in sync), re-stamped
touch -d '2001-01-01' "$CONF"                        # local mtime is irrelevant now
r=$("$EC" push)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "in-sync repush: $r"
ok "a machine that is in sync can push whatever its clock says"

# 4 · the remote moved since we synced (another machine pushed) → refused
curl -sf -X PATCH -H 'Content-Type: application/json' \
    -d "{\"appProperties\": {\"machine\": \"other-machine\"}, \"modifiedTime\": \"2020-01-01T00:00:00.000Z\"}" \
    "$EWE_CONF_DRIVE_BASE/drive/v3/files/mock1" >/dev/null
r=$("$EC" push)
[ "$(jget "$r" "['ok']")" = "False" ] || fail "conflict push should refuse: $r"
[ "$(jget "$r" "['error']")" = "remote-newer" ] || fail "expected remote-newer: $r"
r=$("$EC" sync-status)
[ "$(jget "$r" "['in_sync']")" = "False" ] || fail "status should say out of sync: $r"
[ "$(jget "$r" "['remote_machine']")" = "other-machine" ] || fail "status remote_machine after foreign push: $r"
ok "push refuses when the remote changed since we last synced (even with an OLDER remote clock)"

# 5 · --force overrides and re-stamps in the same request
r=$("$EC" push --force)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "force push: $r"
r=$("$EC" sync-status)
[ "$(jget "$r" "['remote']['appProperties']['machine']")" = "$(uname -n)" ] || fail "force restamp: $r"
[ "$(jget "$r" "['in_sync']")" = "True" ] || fail "force push did not record: $r"
ok "push --force overrides and re-stamps the manifest"

# 6 · pull adopts remote atomically, keeps the loser as .bak, records the remote
curl -sf -X PATCH "$EWE_CONF_DRIVE_BASE/upload/drive/v3/files/mock1?uploadType=media" \
    --data-binary $'schema = 1\n\n[desktop.theme]\naccent = "#ff0000"\n' >/dev/null
r=$("$EC" push)
[ "$(jget "$r" "['error']")" = "remote-newer" ] || fail "foreign content push must block ours: $r"
r=$("$EC" pull)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "pull: $r"
grep -q 'ff0000' "$CONF" || fail "pull did not adopt remote content"
ls "$WORK/config/ewe/"ewe.conf.*.bak >/dev/null 2>&1 || fail "pull kept no .bak"
grep -q '0a84ff' "$WORK/config/ewe/"ewe.conf.*.bak || fail ".bak is not the loser"
no_tmp
python3 -c "import tomllib; tomllib.load(open('$CONF','rb'))" || fail "pulled file is not valid TOML"
ok "pull adopts the remote atomically and keeps the loser as .bak"

# 7 · after a pull we are in sync again: push allowed
r=$("$EC" push)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "push after pull: $r"
ok "push is allowed again once we pulled what the other machine saved"

# 8 · a NEVER-synced machine that finds a backup must not overwrite it
rm -f "$SYNC"
r=$("$EC" push)
[ "$(jget "$r" "['ok']")" = "False" ] || fail "fresh machine push should refuse: $r"
[ "$(jget "$r" "['error']")" = "remote-exists" ] || fail "expected remote-exists: $r"
[ "$(jget "$r" "['remote']['appProperties']['machine']")" = "$(uname -n)" ] || fail "remote-exists carries the remote: $r"
ok "a fresh machine never clobbers an existing backup (remote-exists)"

# 9 · …unless told to; and a fresh machine may push when Drive is EMPTY
r=$("$EC" push --force)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "fresh force push: $r"
rm -f "$SYNC" "$WORK/drive.json"
r=$("$EC" push)
[ "$(jget "$r" "['ok']")" = "True" ] || fail "fresh push to an empty Drive: $r"
ok "fresh machine: --force overrides, and an empty Drive takes the first push"

# 10 · pull --out previews without touching the file or the record
before=$(cat "$SYNC")
r=$("$EC" pull --out "$WORK/preview.toml")
[ "$(jget "$r" "['ok']")" = "True" ] || fail "pull --out: $r"
[ -s "$WORK/preview.toml" ] || fail "pull --out wrote nothing"
[ "$before" = "$(cat "$SYNC")" ] || fail "pull --out must not touch the sync record"
ok "pull --out previews without recording"

echo "ALL PASS"
