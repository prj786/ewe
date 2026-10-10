#!/usr/bin/env bash
# ewe-conf sync engine test — push/pull/conflict against LOCAL mocks of BOTH
# providers (RFC-002 Drive, RFC-005 Nextcloud). No network, no real account,
# no real config touched: XDG_CONFIG_HOME and XDG_STATE_HOME are temp dirs,
# EWE_CONF_DRIVE_BASE points at a python mock Drive, and [sync].server at
# tests/mock-nextcloud.py. The SAME scenario list runs against each backend,
# because the contract is the same:
#   * first push creates the file WITH the {machine, schema} stamp and
#     records what it saw
#   * a re-push from the machine that last synced is allowed (in sync)
#   * the remote changed since we last synced (another machine pushed) →
#     push refused (remote-newer) — no clocks, no hostnames involved
#   * push --force overrides and re-stamps
#   * pull adopts the remote atomically, keeps the loser as ewe.conf.<ts>.bak,
#     and records the remote so the next push is allowed
#   * a machine that has NEVER synced but finds a backup → push refused
#     (remote-exists): restore first, or --force
#   * a fresh machine may push into an EMPTY remote
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'kill $MOCK_DRIVE $MOCK_NC 2>/dev/null || true; rm -rf "$WORK"' EXIT

export XDG_CONFIG_HOME="$WORK/config"
export XDG_STATE_HOME="$WORK/state"                # sync.json lives here
export XDG_RUNTIME_DIR="$WORK/run"
unset HYPRLAND_INSTANCE_SIGNATURE                   # never reload the host's Hyprland
export EWE_CONF_SSH_CONFIG="$WORK/ssh-config"   # never the real ~/.ssh/config
mkdir -p "$WORK/config/ewe" "$WORK/run"

# ── mock Drive ──────────────────────────────────────────────────────────────
DPORT=$(( (RANDOM % 20000) + 30000 ))
python3 - "$DPORT" "$WORK/drive.json" >"$WORK/mock-drive.log" 2>&1 <<'PY' &
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
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        meta, content = multipart(self.headers, body)
        f = {"id": "mock1", "name": meta["name"], "modifiedTime": now(),
             "appProperties": meta.get("appProperties", {}), "content": content}
        save(f); self._json(self._public(f))
    def do_PATCH(self):
        f = load() or {}
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if "uploadType=multipart" in self.path:
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
            if "modifiedTime" in j:
                f["modifiedTime"] = j["modifiedTime"]
        save(f); self._json(self._public(f))

HTTPServer(("127.0.0.1", PORT), H).serve_forever()
PY
MOCK_DRIVE=$!
DRIVE="http://127.0.0.1:$DPORT"
for _ in $(seq 1 20); do curl -sf "$DRIVE/drive/v3/files" >/dev/null 2>&1 && break; sleep 0.2; done

# ── mock Nextcloud ──────────────────────────────────────────────────────────
NPORT=$(( (RANDOM % 20000) + 30000 ))
python3 "$HERE/tests/mock-nextcloud.py" "$NPORT" "$WORK/nc.json" >"$WORK/mock-nc.log" 2>&1 &
MOCK_NC=$!
NC="http://127.0.0.1:$NPORT"
NC_AUTH="tester:app-pass-0123456789abcdef"
NC_DAV="$NC/remote.php/dav/files/tester/ewe"
for _ in $(seq 1 30); do curl -s -o /dev/null "$NC/index.php/login/v2" && break; sleep 0.2; done

EC="$HERE/bin/ewe-conf"
CONF="$WORK/config/ewe/ewe.conf"
SYNC="$WORK/state/ewe/sync.json"
fail() { echo "FAIL  [$PROVIDER] $*" >&2; exit 1; }
ok()   { echo "ok  [$PROVIDER] $*"; }
jget() { python3 -c "import json,sys; print(json.load(sys.stdin)$2)" <<<"$1"; }
no_tmp() { ls "$WORK/config/ewe/".ewe.conf* >/dev/null 2>&1 && fail "temp file left behind: $(ls "$WORK/config/ewe/")"; true; }

# ── provider hooks: how a FOREIGN machine touches the remote ────────────────
write_conf() {   # write_conf <accent>
    if [ "$PROVIDER" = google ]; then
        printf 'schema = 1\n\n[desktop.theme]\naccent = "%s"\n\n[sync]\nprovider = "google"\n' "$1" > "$CONF"
    else
        printf 'schema = 1\n\n[desktop.theme]\naccent = "%s"\n\n[sync]\nprovider = "nextcloud"\nserver = "%s"\nuser = "tester"\nfolder = "ewe"\n' "$1" "$NC" > "$CONF"
    fi
}
foreign_stamp() {   # another machine saved (a small edit) with an OLDER clock — remote moved
    if [ "$PROVIDER" = google ]; then
        body="$(curl -sf "$DRIVE/drive/v3/files/mock1?alt=media")"$'\n# edited elsewhere\n'
        curl -sf -X PATCH "$DRIVE/upload/drive/v3/files/mock1?uploadType=media" --data-binary "$body" >/dev/null
        curl -sf -X PATCH -H 'Content-Type: application/json' \
            -d '{"appProperties": {"machine": "other-machine", "machine_id": "0000000000000000"}, "modifiedTime": "2020-01-01T00:00:00.000Z"}' \
            "$DRIVE/drive/v3/files/mock1" >/dev/null
    else
        cur="$(curl -sf -u "$NC_AUTH" "$NC_DAV/ewe.conf")"$'\n# edited elsewhere\n'
        curl -sf -u "$NC_AUTH" -X PUT --data-binary "$cur" "$NC_DAV/ewe.conf" >/dev/null
        curl -sf -u "$NC_AUTH" -X PUT -d '{"machine":"other-machine","machine_id":"0000000000000000","saved_at":"2020-01-01T00:00:00Z","schema":"1"}' "$NC_DAV/ewe.conf.meta.json" >/dev/null
    fi
}
same_bytes_reupload() {   # the Nextcloud desktop client re-uploads ~/Nextcloud/ewe/ewe.conf unchanged
    if [ "$PROVIDER" = google ]; then
        curl -sf -X PATCH -H 'Content-Type: application/json' \
            -d '{"modifiedTime": "2030-01-01T00:00:00.000Z"}' "$DRIVE/drive/v3/files/mock1" >/dev/null
    else
        curl -sf -u "$NC_AUTH" -o "$WORK/reupload" "$NC_DAV/ewe.conf"          # byte-exact ($(…) drops the newline)
        curl -sf -u "$NC_AUTH" -X PUT --data-binary @"$WORK/reupload" "$NC_DAV/ewe.conf" >/dev/null   # etag moves, meta unchanged
    fi
}
nc_fault() {   # nc_fault <switch> <file> — arm one of mock-nextcloud.py's fault switches
    python3 - "$WORK/nc.json" "$1" "$2" <<'PY'
import json, sys
p, k, v = sys.argv[1:]
s = json.load(open(p)); s[k] = v; json.dump(s, open(p, "w"))
PY
}
foreign_content() {   # another machine saved DIFFERENT content
    body=$'schema = 1\n\n[desktop.theme]\naccent = "#ff0000"\n'
    if [ "$PROVIDER" = google ]; then
        curl -sf -X PATCH "$DRIVE/upload/drive/v3/files/mock1?uploadType=media" --data-binary "$body" >/dev/null
        curl -sf -X PATCH -H 'Content-Type: application/json' -d '{"appProperties": {"machine": "other-machine"}}' \
            "$DRIVE/drive/v3/files/mock1" >/dev/null
    else
        curl -sf -u "$NC_AUTH" -X PUT --data-binary "$body" "$NC_DAV/ewe.conf" >/dev/null
        curl -sf -u "$NC_AUTH" -X PUT -d '{"machine":"other-machine","saved_at":"2026-01-01T00:00:00Z","schema":"1"}' "$NC_DAV/ewe.conf.meta.json" >/dev/null
    fi
}
remote_empty() {
    if [ "$PROVIDER" = google ]; then
        rm -f "$WORK/drive.json"
    else
        curl -s -u "$NC_AUTH" -X DELETE "$NC_DAV" >/dev/null
    fi
}

run_suite() {
    PROVIDER=$1
    rm -f "$SYNC" "$WORK/config/ewe/"ewe.conf.*.bak
    remote_empty
    write_conf "#0a84ff"
    if [ "$PROVIDER" = google ]; then
        export EWE_CONF_DRIVE_BASE="$DRIVE" EWE_CONF_TEST_TOKEN="test-token-abcdefghijklmnop"
    else
        export EWE_CONF_DRIVE_BASE="http://127.0.0.1:1" EWE_CONF_TEST_TOKEN="app-pass-0123456789abcdef"
    fi

    # 1 · first push creates the file with the stamp, and records it
    r=$("$EC" push)
    [ "$(jget "$r" "['ok']")" = "True" ] || fail "first push: $r"
    [ "$(jget "$r" "['provider']")" = "$PROVIDER" ] || fail "provider in result: $r"
    [ "$(jget "$r" "['machine']")" = "$(uname -n)" ] || fail "stamp machine missing: $r"
    [ -n "$(jget "$r" "['modified']")" ] || fail "push did not return the remote time: $r"
    [ -f "$SYNC" ] || fail "push recorded no sync state"
    [ "$(jget "$(cat "$SYNC")" "['provider']")" = "$PROVIDER" ] || fail "record provider"
    [ "$(jget "$(cat "$SYNC")" "['id']")" = "$(jget "$r" "['id']")" ] || fail "recorded id differs"
    ok "first push creates + stamps {machine, schema}, records it"

    # 2 · status sees it — both facts, separately
    r=$("$EC" sync-status)
    [ "$(jget "$r" "['remote']['appProperties']['machine']")" = "$(uname -n)" ] || fail "status stamp: $r"
    [ "$(jget "$r" "['remote_machine']")" = "$(uname -n)" ] || fail "status remote_machine: $r"
    [ -n "$(jget "$r" "['local_synced_at']")" ] || fail "status local_synced_at: $r"
    [ "$(jget "$r" "['in_sync']")" = "True" ] || fail "status in_sync: $r"
    [ "$(jget "$r" "['conflict']")" = "None" ] || fail "status conflict: $r"
    [ "$(jget "$r" "['remote_is_this_machine']")" = "True" ] || fail "status remote_is_this_machine: $r"
    [ "$(jget "$r" "['provider']")" = "$PROVIDER" ] || fail "status provider: $r"
    ok "sync-status returns the stamp, who saved it (by machine id), and when we last synced"

    # 3 · re-push from the machine that last synced: allowed (in sync), re-stamped
    touch -d '2001-01-01' "$CONF"                        # local mtime is irrelevant
    r=$("$EC" push)
    [ "$(jget "$r" "['ok']")" = "True" ] || fail "in-sync repush: $r"
    ok "a machine that is in sync can push whatever its clock says"

    # 4 · the remote moved since we synced (another machine pushed) → refused
    foreign_stamp
    r=$("$EC" push)
    [ "$(jget "$r" "['ok']")" = "False" ] || fail "conflict push should refuse: $r"
    [ "$(jget "$r" "['error']")" = "remote-newer" ] || fail "expected remote-newer: $r"
    r=$("$EC" sync-status)
    [ "$(jget "$r" "['in_sync']")" = "False" ] || fail "status should say out of sync: $r"
    [ "$(jget "$r" "['remote_machine']")" = "other-machine" ] || fail "status remote_machine after foreign push: $r"
    [ "$(jget "$r" "['conflict']")" = "remote-newer" ] || fail "status conflict after foreign push: $r"
    [ "$(jget "$r" "['remote_is_this_machine']")" = "False" ] || fail "foreign stamp read as this machine: $r"
    [ "$(jget "$r" "['error']")" = "None" ] || fail "a conflict is not a transport error: $r"
    ok "push refuses when the remote changed since we last synced (even with an OLDER remote clock)"

    # 5 · --force overrides and re-stamps
    r=$("$EC" push --force)
    [ "$(jget "$r" "['ok']")" = "True" ] || fail "force push: $r"
    r=$("$EC" sync-status)
    [ "$(jget "$r" "['remote']['appProperties']['machine']")" = "$(uname -n)" ] || fail "force restamp: $r"
    [ "$(jget "$r" "['in_sync']")" = "True" ] || fail "force push did not record: $r"
    ok "push --force overrides and re-stamps"

    # 6 · pull adopts remote atomically, keeps the loser as .bak, records the remote
    foreign_content
    r=$("$EC" push)
    [ "$(jget "$r" "['error']")" = "remote-newer" ] || fail "foreign content push must block ours: $r"
    r=$("$EC" pull)
    [ "$(jget "$r" "['ok']")" = "True" ] || fail "pull: $r"
    [ "$(jget "$r" "['machine']")" = "other-machine" ] || fail "pull did not say who saved it: $r"
    grep -q 'ff0000' "$CONF" || fail "pull did not adopt remote content"
    ls "$WORK/config/ewe/"ewe.conf.*.bak >/dev/null 2>&1 || fail "pull kept no .bak"
    grep -q '0a84ff' "$WORK/config/ewe/"ewe.conf.*.bak || fail ".bak is not the loser"
    no_tmp
    python3 -c "import tomllib; tomllib.load(open('$CONF','rb'))" || fail "pulled file is not valid TOML"
    ok "pull adopts the remote atomically and keeps the loser as .bak"

    # 7 · after a pull we are in sync again: push allowed
    write_conf "#ff0000"                                  # (the pulled file lost [sync] — restore it)
    r=$("$EC" push)
    [ "$(jget "$r" "['ok']")" = "True" ] || fail "push after pull: $r"
    ok "push is allowed again once we pulled what the other machine saved"

    # 8 · a NEVER-synced machine that finds a backup must not overwrite it
    rm -f "$SYNC"
    r=$("$EC" push)
    [ "$(jget "$r" "['ok']")" = "False" ] || fail "fresh machine push should refuse: $r"
    [ "$(jget "$r" "['error']")" = "remote-exists" ] || fail "expected remote-exists: $r"
    [ "$(jget "$r" "['remote']['appProperties']['machine']")" = "$(uname -n)" ] || fail "remote-exists carries the remote: $r"
    r=$("$EC" sync-status)
    [ "$(jget "$r" "['conflict']")" = "remote-exists" ] || fail "status conflict on a fresh machine: $r"
    ok "a fresh machine never clobbers an existing backup (remote-exists)"

    # 9 · …unless told to; and a fresh machine may push when the remote is EMPTY
    r=$("$EC" push --force)
    [ "$(jget "$r" "['ok']")" = "True" ] || fail "fresh force push: $r"
    rm -f "$SYNC"; remote_empty
    r=$("$EC" push)
    [ "$(jget "$r" "['ok']")" = "True" ] || fail "fresh push to an empty remote: $r"
    ok "fresh machine: --force overrides, and an empty remote takes the first push"

    # 10 · pull --out previews without touching the file or the record
    before=$(cat "$SYNC")
    r=$("$EC" pull --out "$WORK/preview.toml")
    [ "$(jget "$r" "['ok']")" = "True" ] || fail "pull --out: $r"
    [ -s "$WORK/preview.toml" ] || fail "pull --out wrote nothing"
    [ "$before" = "$(cat "$SYNC")" ] || fail "pull --out must not touch the sync record"
    ok "pull --out previews without recording"

    # 11 · the remote moved but holds the SAME bytes this machine last synced
    #      (the Nextcloud desktop client re-uploading its ~/Nextcloud copy):
    #      not a conflict — the new ETag is adopted
    r=$("$EC" push --force)   # bring the record to the current remote
    [ "$(jget "$r" "['ok']")" = "True" ] || fail "resync: $r"
    same_bytes_reupload
    r=$("$EC" sync-status)
    [ "$(jget "$r" "['conflict']")" = "None" ] || fail "same-bytes re-upload read as a conflict: $r"
    [ "$(jget "$r" "['in_sync']")" = "True" ] || fail "same-bytes re-upload not in sync: $r"
    write_conf "#00ff00"
    r=$("$EC" push)
    [ "$(jget "$r" "['ok']")" = "True" ] || fail "push after a same-bytes re-upload: $r"
    ok "a moved remote with the bytes we last synced is adopted, not a conflict"

    # …while DIFFERENT bytes under a stale stamp still are one
    foreign_stamp
    r=$("$EC" push)
    [ "$(jget "$r" "['error']")" = "remote-newer" ] || fail "an edit elsewhere must still block: $r"
    r=$("$EC" sync-status)
    [ "$(jget "$r" "['conflict']")" = "remote-newer" ] || fail "status after the edit elsewhere: $r"
    "$EC" push --force >/dev/null
    ok "an edit elsewhere is still a conflict"

    if [ "$PROVIDER" = nextcloud ]; then
        # 12 · the upload landed but its reply never came back (lid closed
        #      mid-push): the next push recognises its own bytes
        write_conf "#123456"
        nc_fault drop_reply ewe.conf
        r=$("$EC" push)
        [ "$(jget "$r" "['ok']")" = "False" ] || fail "a dropped reply must fail this push: $r"
        curl -sf -u "$NC_AUTH" "$NC_DAV/ewe.conf" | grep -q '123456' || fail "the mock did not store the upload"
        r=$("$EC" sync-status)
        [ "$(jget "$r" "['conflict']")" = "None" ] || fail "own interrupted upload read as a conflict: $r"
        write_conf "#654321"
        r=$("$EC" push)
        [ "$(jget "$r" "['ok']")" = "True" ] || fail "push after an interrupted upload: $r"
        ok "an upload whose reply was lost is recognised as our own (no endless remote-newer)"

        # 13 · the file landed but the meta stamp was refused: recorded anyway
        write_conf "#abcdef"
        nc_fault refuse_put ewe.conf.meta.json
        r=$("$EC" push)
        [ "$(jget "$r" "['ok']")" = "True" ] || fail "a refused stamp must not fail the push: $r"
        [ "$(jget "$r" "['warning']")" = "stamp-missing" ] || fail "stamp-missing not reported: $r"
        write_conf "#fedcba"
        r=$("$EC" push)
        [ "$(jget "$r" "['ok']")" = "True" ] || fail "push after a refused stamp: $r"
        ok "a refused meta stamp is a warning; the upload is recorded"

        # 14 · same hostname, different machine: the machine id tells them apart
        echo "another-machine-id" > "$WORK/other-machine-id"
        r=$(EWE_CONF_MACHINE_ID_FILE="$WORK/other-machine-id" "$EC" sync-status)
        [ "$(jget "$r" "['remote_machine']")" = "$(uname -n)" ] || fail "hostname stamp: $r"
        [ "$(jget "$r" "['remote_is_this_machine']")" = "False" ] || fail "a same-named machine read as this one: $r"
        ok "two machines with one hostname are told apart by machine id"
    fi
}

run_suite google
run_suite nextcloud
echo "ALL PASS"
