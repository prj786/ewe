#!/usr/bin/env bash
# ewe.phone tests — no compositor, no D-Bus, no phone. A stub `dbus` and
# `gi.repository.GLib` on PYTHONPATH stand in for the real modules (their
# calls fail the way a bus with no kdeconnectd fails), so the test covers the
# bridge's pure functions (type flattening, message normalisation, device ids
# from object paths), the NDJSON framing end to end (hello → commands on
# stdin → events on stdout, bad input ignored, a failing command reported as
# an `error` event, never a crash), the missing-deps `fatal` path, and the
# manifest's compat contract (key `mobile`, API 3, Theme icon names).
set -euo pipefail
cd "$(dirname "$0")"

SB="$(mktemp -d)"
trap '[ -n "${KEEP:-}" ] || rm -rf "$SB"' EXIT
pass=0; failn=0
check() { if eval "$2"; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1"; fi; }

# ── stub modules ─────────────────────────────────────────────────────────────
mkdir -p "$SB/stub/dbus/mainloop" "$SB/stub/gi/repository"
cat > "$SB/stub/dbus/__init__.py" <<'PY'
class DBusException(Exception):
    def get_dbus_message(self): return str(self)
class String(str): pass
class ObjectPath(str): pass
class Signature(str): pass
class Boolean(int): pass
class Byte(int): pass
class Int16(int): pass
class UInt16(int): pass
class Int32(int): pass
class UInt32(int): pass
class Int64(int): pass
class UInt64(int): pass
class Double(float): pass
class Array(list):
    def __init__(self, it=(), signature=None): super().__init__(it)
class Dictionary(dict):
    def __init__(self, d=None, signature=None): super().__init__(d or {})
class Interface:
    def __init__(self, obj, iface): self.iface = iface
    def __getattr__(self, name):
        def call(*a, **k): raise DBusException("%s.%s: no such service (stub bus)" % (self.iface, name))
        return call
class _Bus:
    def add_signal_receiver(self, *a, **k): pass
    def watch_name_owner(self, name, cb): pass
    def name_has_owner(self, name): return False
    def get_object(self, service, path): return object()
def SessionBus(): return _Bus()
PY
cat > "$SB/stub/dbus/mainloop/__init__.py" <<'PY'
PY
cat > "$SB/stub/dbus/mainloop/glib.py" <<'PY'
def DBusGMainLoop(set_as_default=False): return None
PY
cat > "$SB/stub/gi/__init__.py" <<'PY'
PY
cat > "$SB/stub/gi/repository/__init__.py" <<'PY'
PY
cat > "$SB/stub/gi/repository/GLib.py" <<'PY'
PRIORITY_DEFAULT = 0
IO_IN = 1
IO_HUP = 16
_watches = []
def io_add_watch(fd, prio, cond, cb):
    _watches.append((fd, cb)); return 1
def timeout_add(ms, cb): return 1          # never fires in the stub
class MainLoop:
    def __init__(self): self._run = True
    def quit(self): self._run = False
    def run(self):
        while self._run and _watches:
            fd, cb = _watches[0]
            if not cb(fd, IO_IN): _watches.pop(0)
PY
export PYTHONPATH="$SB/stub" EWE_PHONE_NO_DAEMON=1

# 1. the script compiles ────────────────────────────────────────────────────
check "bridge compiles" "python3 -m py_compile kdeconnect-bridge.py phone_apps.py hide_kdeconnect.py"

# 2. pure functions ───────────────────────────────────────────────────────────
python3 - <<'PY' > "$SB/pure.out" 2>&1 || true
import importlib.util, json, dbus
spec = importlib.util.spec_from_file_location("bridge", "kdeconnect-bridge.py")
b = importlib.util.module_from_spec(spec); spec.loader.exec_module(b)
# plain(): every dbus type becomes a JSON-native value, nested
v = b.plain(dbus.Dictionary({dbus.String("a"): dbus.Array([dbus.Int32(1), dbus.Boolean(True), dbus.Double(2.5)]),
                             dbus.String("p"): dbus.ObjectPath("/x")}))
assert v == {"a": [1, True, 2.5], "p": "/x"} and type(v["a"][0]) is int and type(v["a"][1]) is bool, v
# id_from_path(): the device id is the 5th path segment
assert b.Bridge.id_from_path(None, "/modules/kdeconnect/devices/abc123/notifications/42") == "abc123"
assert b.Bridge.id_from_path(None, "/modules/kdeconnect") == ""
# norm_message(): the D-Bus message dict → the QML shape
m = b.Bridge.norm_message(None, dbus.Dictionary({
    "thread_id": dbus.Int64(7), "body": dbus.String("hi"), "date": dbus.Int64(1700000000000),
    "type": dbus.Int32(1), "read": dbus.Int32(0), "u_id": dbus.Int32(99),
    "addresses": dbus.Array([dbus.Dictionary({"address": dbus.String("+4912345")}), dbus.String("+4967890")]),
    "attachments": dbus.Array([]), "event": dbus.Int32(1)}))
assert m == {"threadId": 7, "body": "hi", "date": 1700000000000, "type": 1, "read": 0,
             "addresses": ["+4912345", "+4967890"], "uid": 99, "multitarget": True,
             "hasAttachments": False, "event": 1}, m
# … and the shape kdeconnectd really sends (26.08): a STRUCT in a variant —
# (event, body, [(address,)…], date, type, read, thread id, uid, sub id,
# [(part id, mime, base64 thumbnail, unique id)…]); dbus-python hands a
# Struct over as a tuple
wire = (dbus.Int32(1), dbus.String("hi"), dbus.Array([(dbus.String("+4912345"),), (dbus.String("+4967890"),)]),
        dbus.Int64(1700000000000), dbus.Int32(1), dbus.Int32(0), dbus.Int64(7), dbus.Int32(99), dbus.Int64(1),
        dbus.Array([(dbus.Int64(3), dbus.String("image/jpeg"), dbus.String("/9j/"), dbus.String("PART_3"))]))
m = b.Bridge.norm_message(None, wire)
assert m == {"threadId": 7, "body": "hi", "date": 1700000000000, "type": 1, "read": 0,
             "addresses": ["+4912345", "+4967890"], "uid": 99, "multitarget": True,
             "hasAttachments": True, "event": 1}, m
assert b.Bridge.norm_message(None, (dbus.Int32(1), dbus.String("too short"))) is None
assert b.Bridge.norm_message(None, dbus.String("garbage")) is None
# a message with no thread id defaults to -1 (QML drops it)
assert b.Bridge.norm_message(None, {})["threadId"] == -1
print("PURE-OK")
PY
check "plain / id_from_path / norm_message" "grep -q PURE-OK '$SB/pure.out'" || cat "$SB/pure.out"

# 3. NDJSON framing: hello, a refresh with no daemon, a failing command, junk ─
# (always under EWE_PHONE_NO_DAEMON: without it the bridge's fallback would
# Popen the REAL /usr/bin/kdeconnectd on a box that has it installed)
printf '%s\n' 'not json at all' '{"cmd":"refresh"}' '{"cmd":"pair","deviceId":"dev1"}' '{"cmd":"nonsense"}' \
  | python3 kdeconnect-bridge.py > "$SB/frames.out" 2> "$SB/frames.err"
rc=$?
check "bridge exits 0 on stdin EOF" "[ $rc = 0 ]"
check "no python traceback" "! grep -qi traceback '$SB/frames.err'"
python3 - "$SB/frames.out" <<'PY' > "$SB/frames.chk" 2>&1 || true
import json, sys
lines = [l for l in open(sys.argv[1]).read().split("\n") if l.strip()]
evs = [json.loads(l) for l in lines]                     # every line is one JSON object
assert evs[0]["event"] == "hello" and isinstance(evs[0]["installed"], bool), evs[0]
kinds = [e["event"] for e in evs]
assert "devices" in kinds and all(e["list"] == [] for e in evs if e["event"] == "devices"), evs
assert any(e["event"] == "daemon" and e["running"] is False for e in evs), evs
errs = [e for e in evs if e["event"] == "error"]
assert len(errs) == 1 and errs[0]["cmd"] == "pair" and errs[0]["error"], errs   # the failing command, reported, not fatal
print("FRAMES-OK")
PY
check "hello first, devices [] after refresh, daemon down, pair → error event, junk ignored" "grep -q FRAMES-OK '$SB/frames.chk'" || cat "$SB/frames.chk" "$SB/frames.out"

# 4. missing python deps: ONE fatal line, exit 0 (the QML side stops respawning) ─
mkdir -p "$SB/nodbus"
printf 'raise ImportError("no module named dbus (test)")\n' > "$SB/nodbus/dbus.py"
PYTHONPATH="$SB/nodbus" python3 kdeconnect-bridge.py < /dev/null > "$SB/fatal.out" 2>/dev/null; rc=$?
check "missing deps → exit 0" "[ $rc = 0 ]"
check "missing deps → one fatal event naming the packages" "[ \"\$(wc -l < '$SB/fatal.out')\" = 1 ] && grep -q '\"event\": \"fatal\"' '$SB/fatal.out' && grep -q python-dbus '$SB/fatal.out'"

# 5. the manifest's contract ─────────────────────────────────────────────────
python3 - <<'PY' > "$SB/manifest.chk" 2>&1 || true
import json, re, os
m = json.load(open("manifest.json"))
assert m["id"] == "ewe.phone" and m["apiVersion"] == 3 and m["schemaVersion"] == 1
assert set(m["kinds"]) == {"service", "quick-page", "bar-status", "dock-item", "panel"}
assert m["version"] == "1.2.0" and m["dockItem"]["action"] == "ewe.phone.toggle" and m["entryPoints"]["panel"] == "Popup.qml"
hk = [x for x in m["settings"] if x["key"] == "hide_kdeconnect"][0]
assert hk["type"] == "bool" and hk["default"] is True
assert m["quickPage"]["key"] == "mobile", "legacy key `mobile` keeps `quicksettings tab mobile` working"
for k, f in m["entryPoints"].items(): assert os.path.isfile(f), f
assert re.match(r"^ic[A-Z]", m["icon"]) and re.match(r"^ic[A-Z]", m["quickPage"]["icon"])
assert "kdeconnect" in m["requires"]["packages"] and "kdeconnectd" in m["requires"]["commands"]
print("MANIFEST-OK")
PY
check "manifest: id, API 3, kinds, legacy key, icons, requires" "grep -q MANIFEST-OK '$SB/manifest.chk'" || cat "$SB/manifest.chk"
# Rule 8: no raw colours or pixel sizes in QML — Theme tokens only
check "no raw hex colours in QML" "! grep -nE '#[0-9a-fA-F]{3,8}\\b' *.qml"
check "no numeric durations in QML" "! grep -nE 'duration: *[0-9]' *.qml"
check "qmldir declares the Phone singleton" "grep -q '^singleton Phone 1.0 Phone.qml' qmldir"

# 7. C1 parse + validation, hostile fixtures ──────────────────────────────────
python3 - <<'PY' > "$SB/c1.out" 2>&1 || true
import base64, json, struct, sys, zlib
sys.path.insert(0, ".")
import phone_apps as pa
def png(px=96, w=None):
    w = w or px
    raw = b"".join(b"\x00" + b"\x10\x20\x30" * w for _ in range(px))
    def ch(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, px, 8, 2, 0, 0, 0)) + ch(b"IDAT", zlib.compress(raw)) + ch(b"IEND", b"")
b64 = lambda b: base64.b64encode(b).decode()
good = png()
ewe = {"ewe": {"name": "ewe Mobile", "command": "", "v": 1, "count": 3, "app": "0.1", "sdk": 37}}
lst = dict(ewe, **{
    "com.whatsapp": {"name": "WhatsApp", "command": "com.whatsapp", "icon": b64(good), "sys": False},
    "com.android.camera": {"name": "camera", "icon": b64(good), "sys": True},
})
k, d = pa.parse_commands(json.dumps(lst).encode())
assert k == "ewe" and [a["package"] for a in d["apps"]] == ["com.android.camera", "com.whatsapp"], d   # sorted by name, case-insensitive
assert d["apps"][0]["sys"] is True and d["apps"][1]["png"] == good
# D-Bus hands `ay` over as a list of ints
assert pa.parse_commands(list(json.dumps(lst).encode()))[0] == "ewe"
# not ours / not there yet
assert pa.parse_commands(b"")[0] == "pending" and pa.parse_commands("{}")[0] == "pending"
assert pa.parse_commands(json.dumps({"ewe.spike": {"name": "x", "command": "x"}}))[0] == "other"   # someone else's list
assert pa.parse_commands(json.dumps({"ewe": {"v": 0}}))[0] == "other"
assert pa.parse_commands(json.dumps({"ewe": {"v": True}}))[0] == "other"
assert pa.parse_commands(json.dumps({"ewe": "x"}))[0] == "other"
assert pa.parse_commands(b"\xff\xfe not utf8")[0] == "other" and pa.parse_commands("[1,2]")[0] == "other"
assert pa.parse_commands("not json")[0] == "other" and pa.parse_commands("[" * 100000)[0] == "other"
# hostile keys: path traversal, separators, NUL, spaces, too long, the reserved ewe: keys
hostile = {"../../etc/passwd": {"name": "a"}, "a/b": {"name": "b"}, "..": {"name": "c"}, ".hidden": {"name": "d"},
           "a..b": {"name": "e"}, "x" * 256: {"name": "f"}, "ewe:refresh": {"name": "g"}, "a b": {"name": "h"},
           "nul\x00byte": {"name": "i"}, "ünï.code": {"name": "j"}, "ok.app": {"name": "fine"}, "notadict": "x", "alsonot": [1]}
k, d = pa.parse_commands(json.dumps(dict(ewe, **hostile)))
assert [a["package"] for a in d["apps"]] == ["ok.app"] and d["dropped"] == 12, (d["apps"], d["dropped"])
# hostile names: control characters, newlines, RTL override, length, wrong type
h = dict(ewe, **{"p.one": {"name": "Evil\x1b[31m\nName‮" + "z" * 500}, "p.two": {"name": 7}, "p.three": {}})
k, d = pa.parse_commands(json.dumps(h))
n = {a["package"]: a["name"] for a in d["apps"]}
assert len(n["p.one"]) <= 200 and "\x1b" not in n["p.one"] and "\n" not in n["p.one"] and "‮" not in n["p.one"], n
assert n["p.two"] == "p.two" and n["p.three"] == "p.three"        # no usable name: the package stands in
# hostile icons: not base64, not PNG, WebP, oversize, not square, huge/tiny, truncated, wrong type
webp = b"RIFF\x00\x00\x00\x00WEBPVP8 " + b"\x00" * 40
icons = {"i.junk": "!!!not base64!!!", "i.text": b64(b"hello world, definitely not a png at all..."), "i.webp": b64(webp),
         "i.big": b64(good + b"\x00" * (257 * 1024)), "i.wide": b64(png(96, 64)), "i.tiny": b64(png(8)),
         "i.huge": b64(png(1024)), "i.cut": b64(good[:20]), "i.num": 5, "i.ok": b64(good), "i.empty": ""}
k, d = pa.parse_commands(json.dumps(dict(ewe, **{p: {"name": p, "icon": i} for p, i in icons.items()})))
got = {a["package"]: a["png"] for a in d["apps"]}
assert len(got) == len(icons), "a bad icon never drops the app"
assert got["i.ok"] == good and all(v is None for p, v in got.items() if p != "i.ok"), {p: v is not None for p, v in got.items()}
# a list past the cap is cut, not trusted
many = dict(ewe, **{"p.%d" % i: {"name": "n"} for i in range(pa.APPS_MAX + 10)})
k, d = pa.parse_commands(json.dumps(many)); assert len(d["apps"]) == pa.APPS_MAX and d["dropped"] == 10
print("C1-OK")
PY
check "C1: parse + validate (keys, names, icons are hostile input)" "grep -q C1-OK '$SB/c1.out'" || cat "$SB/c1.out"

# 8. C2 cache: format, atomic writes, icons only rewritten when changed, stale icons removed ─
python3 - "$SB" <<'PY' > "$SB/c2.out" 2>&1 || true
import json, os, sys
sys.path.insert(0, ".")
import phone_apps as pa
sb = sys.argv[1]
base = os.path.join(sb, "cache", "ewe-mobile")
P1 = b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + (96).to_bytes(4, "big") * 2 + b"\x08\x02\x00\x00\x00" + b"x" * 30
P2 = P1 + b"changed"
A = lambda pkg, name, png=P1, sys_=False: {"package": pkg, "name": name, "sys": sys_, "png": png}
doc, ch = pa.write_cache(base, "dev1", "Pixel", [A("com.b", "beta"), A("com.a", "Alpha"), A("com.c", "noicon", None)], now_ms=1764170000000)
assert ch and doc["v"] == 1 and doc["device"] == "dev1" and doc["deviceName"] == "Pixel" and doc["updated"] == 1764170000000
assert [a["name"] for a in doc["apps"]] == ["Alpha", "beta", "noicon"], doc          # case-insensitive name order
d = os.path.join(base, "dev1")
assert json.load(open(d + "/apps.json")) == doc
assert doc["apps"][0]["icon"] == d + "/icons/com.a.png" and open(d + "/icons/com.a.png", "rb").read() == P1
assert doc["apps"][2]["icon"] == "" and not os.path.exists(d + "/icons/com.c.png")
# unchanged -> nothing rewritten (not apps.json, not the icons)
ino = os.stat(d + "/apps.json").st_ino; ino_a = os.stat(d + "/icons/com.a.png").st_ino; ino_b = os.stat(d + "/icons/com.b.png").st_ino
doc2, ch = pa.write_cache(base, "dev1", "Pixel", [A("com.b", "beta"), A("com.a", "Alpha"), A("com.c", "noicon", None)], now_ms=1)
assert not ch and doc2["updated"] == 1764170000000 and os.stat(d + "/apps.json").st_ino == ino and os.stat(d + "/icons/com.a.png").st_ino == ino_a
# atomic: written through a temp file + rename (a new inode, no temp file left behind)
doc3, ch = pa.write_cache(base, "dev1", "Pixel", [A("com.b", "beta"), A("com.a", "Alpha", P2), A("com.c", "noicon", None)], now_ms=2)
assert ch and os.stat(d + "/apps.json").st_ino != ino and os.stat(d + "/icons/com.a.png").st_ino != ino_a
assert open(d + "/icons/com.a.png", "rb").read() == P2
assert not [f for f in os.listdir(d) + os.listdir(d + "/icons") if ".tmp" in f]
assert os.stat(d + "/icons/com.b.png").st_ino == ino_b, "an icon whose bytes did not change is not rewritten"
# a package that left the list loses its icon; a crashed writer's temp file goes too
open(d + "/icons/com.a.png.tmp.99", "wb").write(b"half")
doc4, ch = pa.write_cache(base, "dev1", "Pixel", [A("com.b", "beta")], now_ms=3)
assert sorted(os.listdir(d + "/icons")) == ["com.b.png"] and [a["package"] for a in doc4["apps"]] == ["com.b"]
# the device id goes into a path: nothing else passes
for bad in ("../x", "a/b", "", "x" * 129, "a b", ".."):
    try: pa.write_cache(base, bad, "n", []); raise SystemExit("accepted " + repr(bad))
    except ValueError: pass
# read-back treats the file as data: an icon path outside this device's icons/ is blanked
j = json.load(open(d + "/apps.json")); j["apps"][0]["icon"] = "/etc/passwd"; j["apps"].append({"package": "../evil", "name": "x"})
open(d + "/apps.json", "w").write(json.dumps(j))
r = pa.read_cache(base, "dev1"); assert r["apps"][0]["icon"] == "" and len(r["apps"]) == 1, r
open(d + "/apps.json", "w").write("{not json"); assert pa.read_cache(base, "dev1") is None
assert pa.read_cache(base, "nope") is None
# unpaired: everything of the device goes
pa.remove_cache(base, "dev1"); assert not os.path.exists(d)
assert pa.cache_base({"XDG_CACHE_HOME": "/x"}) == "/x/ewe-mobile" and pa.cache_base({"HOME": "/h"}) == "/h/.cache/ewe-mobile"
print("C2-OK")
PY
check "C2: cache format, atomic rename, icons rewritten only on change, stale icons removed" "grep -q C2-OK '$SB/c2.out'" || cat "$SB/c2.out"

# 9. the bridge end to end in fixture mode: events, cache on disk, mount, open ─
mkdir -p "$SB/fx/mnt/storage/emulated/0/DCIM/Camera" "$SB/fx/mnt/storage/emulated/0/Download" "$SB/xdgcache"
python3 - "$SB" <<'PY'
import base64, json, struct, sys, zlib
sb = sys.argv[1]
def png(px=96):
    raw = b"".join(b"\x00" + b"\x10\x20\x30" * px for _ in range(px))
    def ch(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", px, px, 8, 2, 0, 0, 0)) + ch(b"IDAT", zlib.compress(raw)) + ch(b"IEND", b"")
cmds = {"ewe": {"v": 1, "name": "ewe Mobile", "command": ""}, "com.calc": {"name": "Calculator", "icon": base64.b64encode(png()).decode()},
        "../evil": {"name": "Evil"}}
json.dump({"devices": [{"id": "fix1", "name": "Pixel", "isReachable": True, "batteryCharge": 55}],
           "commands": {"fix1": cmds}, "storage": {"fix1": {"mode": "ok", "root": sb + "/fx/mnt"}}}, open(sb + "/fx/ewe.json", "w"))
PY
mkdir -p "$SB/bin"; printf '#!/bin/sh\necho "$@" >> "%s/cli.log"\necho {\\"ok\\":true}\n' "$SB" > "$SB/bin/ewe-mobile"; chmod +x "$SB/bin/ewe-mobile"
( printf '%s\n' '{"cmd":"apps"}' '{"cmd":"openApp","deviceId":"fix1","package":"com.calc","where":"here"}' \
    '{"cmd":"openApp","deviceId":"fix1","package":"../evil","where":"here"}' '{"cmd":"openApp","deviceId":"../x","package":"a.b"}' \
    '{"cmd":"mirror","deviceId":"fix1"}' '{"cmd":"mount","deviceId":"fix1"}'; sleep 2.5 ) \
  | env -u PYTHONPATH PATH="$SB/bin:$PATH" XDG_CACHE_HOME="$SB/xdgcache" EWE_PHONE_FIXTURE="$SB/fx/ewe.json" timeout 20 python3 kdeconnect-bridge.py > "$SB/fx.out" 2> "$SB/fx.err"
python3 - "$SB" <<'PY' > "$SB/fx.chk" 2>&1 || true
import json, os, sys
sb = sys.argv[1]
evs = [json.loads(l) for l in open(sb + "/fx.out") if l.strip()]
k = [e["event"] for e in evs]
assert k[0] == "hello" and "tools" in k and "devices" in k, k
ap = [e for e in evs if e["event"] == "apps"][0]
assert ap["ewe"] and not ap["cached"] and [a["package"] for a in ap["apps"]] == ["com.calc"], ap     # "../evil" never gets in
assert ap["apps"][0]["icon"] == sb + "/xdgcache/ewe-mobile/fix1/icons/com.calc.png" and os.path.isfile(ap["apps"][0]["icon"])
assert json.load(open(sb + "/xdgcache/ewe-mobile/fix1/apps.json"))["apps"][0]["name"] == "Calculator"
op = [e for e in evs if e["event"] == "openApp"]
assert len(op) == 1 and op[0]["ok"] and op[0]["via"] == "here", op                                      # the bad package and bad device were refused
assert len([e for e in evs if e["event"] == "error"]) == 2, [e for e in evs if e["event"] == "error"]
assert [e["state"] for e in evs if e["event"] == "storage"] == ["mounting", "mounted"]
f = {x["key"]: x["path"] for x in [e for e in evs if e["event"] == "storage"][-1]["folders"]}
assert f["camera"].endswith("DCIM/Camera") and f["downloads"].endswith("Download") and f["music"] == "" and f["storage"].endswith("storage/emulated/0"), f
assert [e for e in evs if e["event"] == "mirror"][0]["ok"]
assert "--open-app com.calc --device fix1 --here" in op[0]["message"] and "--screen --device fix1" in [e for e in evs if e["event"] == "mirror"][0]["message"], (op, evs)
print("FIXTURE-OK")
PY
check "bridge (fixture): apps event + C2 cache on disk, openApp -> C3 CLI, bad ids refused, mount -> folders, mirror" "grep -q FIXTURE-OK '$SB/fx.chk'" || cat "$SB/fx.chk" "$SB/fx.err"
python3 - <<'PY' > "$SB/sf.out" 2>&1 || true
import importlib.util
spec = importlib.util.spec_from_file_location("bridge", "kdeconnect-bridge.py")
b = importlib.util.module_from_spec(spec); spec.loader.exec_module(b)
assert b.dir_inside("/run/u/x/storage/0", "/run/u/x") and not b.dir_inside("/run/u/x/../../outside", "/run/u/x") and not b.dir_inside("/etc", "/run/u/x")
assert not b.dir_inside("/run/u/xy", "/run/u/x") and not b.dir_inside("rel", "/run/u/x")
assert b.storage_folders("/run/u/x", {"/etc": "Evil", "/run/u/x/../y": "Evil"}) == []
# the real run_cli: C3's argument list, the JSON answer read back, a failure's words passed on
import os, sys, tempfile, time, io, json
d = tempfile.mkdtemp(); exe = os.path.join(d, "ewe-mobile")
open(exe, "w").write("#!/bin/sh\necho \"$@\" > %s/args\nif [ \"$1\" = --screen ]; then echo '{\"ok\":false,\"error\":\"no-adb-tools\",\"message\":\"Install adb.\"}'; else echo '{\"ok\":true}'; fi\n" % d)
os.chmod(exe, 0o755); os.environ["PATH"] = d + os.pathsep + os.environ["PATH"]
out = []; b.emit = out.append
br = b.Bridge()
br.open_app("dev1", "com.calc", "here"); time.sleep(1)
assert open(d + "/args").read().strip() == "--open-app com.calc --device dev1 --here", open(d + "/args").read()
br.open_app("dev1", "com.calc", "auto"); time.sleep(1)
assert open(d + "/args").read().strip() == "--open-app com.calc --device dev1"
br.mirror("dev1"); time.sleep(1)
assert open(d + "/args").read().strip() == "--screen --device dev1"
assert out[0]["ok"] and out[0]["via"] == "here" and out[1]["via"] == "auto"
assert out[2]["event"] == "mirror" and not out[2]["ok"] and out[2]["error"] == "no-adb-tools" and out[2]["message"] == "Install adb."
try: br.open_app("dev1", "../x", "here"); raise SystemExit("accepted a bad package")
except ValueError: pass
print("SF-OK")
PY
check "storage folders: only inside the phone's mount point" "grep -q SF-OK '$SB/sf.out'" || cat "$SB/sf.out"

# 10. C6: hide / show KDE Connect's launcher entries ─────────────────────────
H="$SB/hide"; mkdir -p "$H/share/applications" "$H/home/.local/share/applications" "$H/bin"
for n in app sms nonplasma handler; do printf '[Desktop Entry]\nType=Application\nName=KDE Connect %s\nExec=kdeconnect-%s %%U\nMimeType=x-scheme-handler/kdeconnect;\n[Desktop Action x]\nName=X\nNoDisplay=false\n' $n $n > "$H/share/applications/org.kde.kdeconnect.$n.desktop"; done
printf '[Desktop Entry]\nType=Application\nName=Daemon\nNoDisplay=true\nExec=/usr/bin/kdeconnectd\n' > "$H/share/applications/org.kde.kdeconnect.daemon.desktop"
printf '[Desktop Entry]\nName=Mine\nExec=mine\n' > "$H/share/applications/other.desktop"
printf '[Desktop Entry]\nName=My own SMS\nExec=my-sms\nIcon=mine\n' > "$H/home/.local/share/applications/org.kde.kdeconnect.sms.desktop"
cp "$H/home/.local/share/applications/org.kde.kdeconnect.sms.desktop" "$H/own-sms.orig"
# EWE_PHONE_EEP=none: the real eep is never consulted; the eep test points it at a stub
hk() { env -u PYTHONPATH EWE_PHONE_EEP="${EEP_STUB:-none}" HOME="$H/home" XDG_DATA_HOME="$H/home/.local/share" XDG_STATE_HOME="$H/home/.local/state" XDG_DATA_DIRS="$H/share" python3 hide_kdeconnect.py "$@"; }
UA="$H/home/.local/share/applications"
hk hide > "$SB/h1.out"
check "hide: app, indicator, handler get NoDisplay copies marked X-Ewe-Phone-Hides" "for n in app nonplasma handler; do grep -q '^NoDisplay=true' $UA/org.kde.kdeconnect.\$n.desktop && grep -q '^X-Ewe-Phone-Hides=1' $UA/org.kde.kdeconnect.\$n.desktop && grep -q '^Exec=kdeconnect-' $UA/org.kde.kdeconnect.\$n.desktop && grep -q 'x-scheme-handler' $UA/org.kde.kdeconnect.\$n.desktop || exit 1; done"
check "hide: one NoDisplay in the main group, an action group's own is not rewritten" "[ \"\$(grep -c '^NoDisplay=true' $UA/org.kde.kdeconnect.app.desktop)\" = 1 ] && grep -q '^NoDisplay=false' $UA/org.kde.kdeconnect.app.desktop"
check "hide: the daemon (already NoDisplay) and other apps are left alone" "[ ! -e $UA/org.kde.kdeconnect.daemon.desktop ] && [ ! -e $UA/other.desktop ]"
check "hide: the user's own SMS entry is kept in backup, then hidden" "grep -q '^Exec=my-sms' $UA/org.kde.kdeconnect.sms.desktop && grep -q '^NoDisplay=true' $UA/org.kde.kdeconnect.sms.desktop && cmp -s $H/own-sms.orig $H/home/.local/state/ewe-phone/backup/org.kde.kdeconnect.sms.desktop"
hk hide > "$SB/h2.out"; hk status > "$SB/h3.out"
check "hide twice is the same; status says all four hidden" "python3 -c \"import json;j=json.load(open('$SB/h3.out'));assert j['visible']==[] and len(j['hidden'])==5, j\""
hk show > "$SB/h4.out"
check "show: our copies are gone, the user's own entry is back byte for byte" "[ ! -e $UA/org.kde.kdeconnect.app.desktop ] && [ ! -e $UA/org.kde.kdeconnect.handler.desktop ] && cmp -s $H/own-sms.orig $UA/org.kde.kdeconnect.sms.desktop"
printf '[Desktop Entry]\nName=Foreign\nNoDisplay=true\nX-Other=1\n' > "$UA/org.kde.kdeconnect.app.desktop"; hk show >/dev/null
check "show never touches a file without our mark" "grep -q Foreign $UA/org.kde.kdeconnect.app.desktop"
rm -f "$UA/org.kde.kdeconnect.app.desktop"
# eep knows the app: eep's own verb hides it (a stub eep that records its calls)
cat > "$H/bin/eep" <<'EEP'
#!/bin/sh
echo "$@" >> "$EEP_LOG"
case "$1" in
  list) echo '{"apps":[{"entry":"org.kde.kdeconnect.app.desktop","id":"sys-org-kde-kdeconnect-app","source":"system"},{"entry":"other.desktop","id":"sys-other"}]}' ;;
esac
EEP
chmod +x "$H/bin/eep"; export EEP_LOG="$H/eep.log" EEP_STUB="$H/bin/eep"; : > "$EEP_LOG"
hk hide >/dev/null
check "hide: with eep, a found app goes by eep's own verb (eep remove sys-...), the rest by copy" "grep -q '^remove sys-org-kde-kdeconnect-app\$' $EEP_LOG && [ ! -e $UA/org.kde.kdeconnect.app.desktop ] && grep -q X-Ewe-Phone-Hides $UA/org.kde.kdeconnect.nonplasma.desktop && ! grep -q 'remove sys-other' $EEP_LOG"
hk show >/dev/null
check "show: eep's card comes back (eep install sys-...), only for what we hid" "grep -q '^install sys-org-kde-kdeconnect-app\$' $EEP_LOG && [ \"\$(grep -c '^install' $EEP_LOG)\" = 1 ] && [ ! -e $UA/org.kde.kdeconnect.nonplasma.desktop ]"
check "hide_kdeconnect.py: a bad verb answers JSON, exit 0" "hk nonsense | grep -q '\"ok\": false'"
check "no KDE Connect window or name offered by Page/Popup (only the kdeconnect package, plainly)" "! grep -n -i 'kde connect' Page.qml Popup.qml"
check "Service applies the hide setting; the popup has no pixel literals" "grep -q hide_kdeconnect Service.qml && ! grep -nE '(width|height|spacing|radius|margins|pixelSize): [0-9.]+ *($|;|})' Popup.qml"

# 6. the ewe tool, when this box has it (the shell's own validator) ───────────
tool="${EWE_PLUGIN_TOOL:-$(command -v ewe-plugin || true)}"
if [ -n "$tool" ]; then
  # sandboxed HOME, and no compositor signature: the tool must never touch the live shell
  check "ewe-plugin validate --first-party" "env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY HOME='$SB/home' XDG_CONFIG_HOME='$SB/home/.config' XDG_STATE_HOME='$SB/home/.local/state' XDG_DATA_HOME='$SB/home/.local/share' EWE_PAYLOAD_PLUGINS='$SB/payload' '$tool' validate . --first-party >/dev/null 2>&1"
fi

echo "ewe.phone: $pass passed, $failn failed"
[ "$failn" = 0 ]
