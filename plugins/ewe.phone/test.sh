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
trap 'rm -rf "$SB"' EXIT
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
check "bridge compiles" "python3 -m py_compile kdeconnect-bridge.py"

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
assert set(m["kinds"]) == {"service", "quick-page", "bar-status"}
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

# 6. the ewe tool, when this box has it (the shell's own validator) ───────────
tool="${EWE_PLUGIN_TOOL:-$(command -v ewe-plugin || true)}"
if [ -n "$tool" ]; then
  # sandboxed HOME, and no compositor signature: the tool must never touch the live shell
  check "ewe-plugin validate --first-party" "env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY HOME='$SB/home' XDG_CONFIG_HOME='$SB/home/.config' XDG_STATE_HOME='$SB/home/.local/state' XDG_DATA_HOME='$SB/home/.local/share' EWE_PAYLOAD_PLUGINS='$SB/payload' '$tool' validate . --first-party >/dev/null 2>&1"
fi

echo "ewe.phone: $pass passed, $failn failed"
[ "$failn" = 0 ]
