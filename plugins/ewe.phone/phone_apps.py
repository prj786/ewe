"""phone_apps.py — the phone's apps list, as ewe Mobile defines it.

Pure standard library (no D-Bus), so the bridge and the tests share it.

  C1  parse_commands()   `remotecommands.commands` (bytes or text) -> the
                         validated list. Keys, names and icons are strings the
                         phone wrote: nothing here trusts them.
  C2  write_cache()      $XDG_CACHE_HOME/ewe-mobile/<deviceId>/apps.json and
                         icons/<package>.png, the same format ewe Mobile's own
                         Rust side writes. Atomic (temp file + rename); icons
                         rewritten only when their bytes change; a package
                         that left the list loses its icon file.
      read_cache()       the same files back (the phone is away).

The contracts live in ewe-mobile/docs/ECOSYSTEM.md.
"""

import base64
import binascii
import json
import os
import re
import struct
import time
import unicodedata

PKG_RE = re.compile(r"^[A-Za-z0-9._]{1,255}$")
DEV_RE = re.compile(r"^[A-Za-z0-9_]{1,128}$")
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
ICON_MAX = 256 * 1024          # decoded PNG
NAME_MAX = 200
RAW_MAX = 8 * 1024 * 1024      # the whole commandList; the phone keeps it near 700 KB
APPS_MAX = 5000
ICON_PX_MIN, ICON_PX_MAX = 16, 512


def cache_base(env=None):
    env = os.environ if env is None else env
    root = env.get("XDG_CACHE_HOME") or os.path.join(env.get("HOME", os.path.expanduser("~")), ".cache")
    return os.path.join(root, "ewe-mobile")


def clean_name(v, fallback=""):
    """One short line: no control or format characters, spaces collapsed, <= 200."""
    if not isinstance(v, str):
        return fallback
    s = "".join(" " if unicodedata.category(c) in ("Zs", "Zl", "Zp") or c in "\t\r\n"
                else c for c in v if unicodedata.category(c) not in ("Cc", "Cf", "Cs", "Co", "Cn") or c in "\t\r\n")
    s = " ".join(s.split())[:NAME_MAX].strip()
    return s or fallback


def package_ok(k):
    return (isinstance(k, str) and PKG_RE.match(k) is not None
            and not k.startswith(".") and not k.endswith(".") and ".." not in k)


def png_ok(data):
    """A real PNG: magic, IHDR first, square, a size the shell can draw."""
    if not isinstance(data, (bytes, bytearray)) or len(data) < 33 or len(data) > ICON_MAX:
        return False
    if data[:8] != PNG_MAGIC or data[12:16] != b"IHDR":
        return False
    w, h = struct.unpack(">II", data[16:24])
    return w == h and ICON_PX_MIN <= w <= ICON_PX_MAX


def decode_icon(v):
    if not isinstance(v, str) or not v or len(v) > (ICON_MAX * 4) // 3 + 16:
        return None
    try:
        data = base64.b64decode(v, validate=True)
    except (binascii.Error, ValueError):
        return None
    return bytes(data) if png_ok(data) else None


def to_bytes(v):
    """What D-Bus hands over for `ay` (a list of ints), or already bytes/str."""
    if isinstance(v, (bytes, bytearray)):
        return bytes(v)
    if isinstance(v, str):
        return v.encode("utf-8", "replace")
    try:
        return bytes(bytearray(int(x) & 0xFF for x in v))
    except (TypeError, ValueError):
        return b""


def parse_commands(raw):
    """C1. Returns (kind, data):
         ("pending", None)  nothing (yet): empty or `{}` — the phone has not answered
         ("other", None)    someone else's command list (stock KDE Connect, a user's own)
         ("ewe", {"meta": {...}, "apps": [{package, name, sys, png}], "dropped": n})
    """
    b = to_bytes(raw)
    if len(b) > RAW_MAX:
        return ("other", None)
    try:
        text = b.decode("utf-8")
    except UnicodeDecodeError:
        return ("other", None)
    if not text.strip():
        return ("pending", None)
    try:
        j = json.loads(text)
    except (ValueError, RecursionError):
        return ("other", None)
    if not isinstance(j, dict):
        return ("other", None)
    if not j:
        return ("pending", None)
    e = j.get("ewe")
    if not isinstance(e, dict):
        return ("other", None)
    v = e.get("v")
    if isinstance(v, bool) or not isinstance(v, int) or v < 1:
        return ("other", None)
    meta = {"v": v}
    for k in ("count", "sdk"):
        if isinstance(e.get(k), int) and not isinstance(e.get(k), bool):
            meta[k] = e[k]
    if isinstance(e.get("app"), str):
        meta["app"] = clean_name(e["app"])[:40]
    apps, dropped = [], 0
    for k, ent in j.items():
        if k == "ewe":
            continue
        if len(apps) >= APPS_MAX:
            dropped += 1
            continue
        if not package_ok(k) or not isinstance(ent, dict):
            dropped += 1
            continue
        apps.append({
            "package": k,
            "name": clean_name(ent.get("name"), k),
            "sys": ent.get("sys") is True,
            "png": decode_icon(ent.get("icon")),
        })
    apps.sort(key=lambda a: (a["name"].casefold(), a["package"]))
    return ("ewe", {"meta": meta, "apps": apps, "dropped": dropped})


# ── C2 ───────────────────────────────────────────────────────────────────────

def _atomic(path, data):
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def _read(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return None


def device_dir(base, dev_id):
    if not isinstance(dev_id, str) or not DEV_RE.match(dev_id):
        raise ValueError("bad device id")
    return os.path.join(base, dev_id)


def read_cache(base, dev_id):
    """The cache as a dict (C2), or None. Icon paths that point anywhere but
    this device's icons/ folder are blanked — the file is read back as data."""
    try:
        d = device_dir(base, dev_id)
    except ValueError:
        return None
    raw = _read(os.path.join(d, "apps.json"))
    if raw is None:
        return None
    try:
        j = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError, RecursionError):
        return None
    if not isinstance(j, dict) or j.get("v") != 1 or not isinstance(j.get("apps"), list):
        return None
    icons = os.path.join(d, "icons") + os.sep
    apps = []
    for a in j["apps"]:
        if not isinstance(a, dict) or not package_ok(a.get("package")):
            continue
        ic = a.get("icon")
        if not (isinstance(ic, str) and ic.startswith(icons) and ".." not in ic[len(icons):] and "/" not in ic[len(icons):]):
            ic = ""
        apps.append({"package": a["package"], "name": clean_name(a.get("name"), a["package"]),
                     "sys": a.get("sys") is True, "icon": ic})
    return {"v": 1, "device": dev_id, "deviceName": clean_name(j.get("deviceName")),
            "updated": j["updated"] if isinstance(j.get("updated"), int) else 0, "apps": apps}


def write_cache(base, dev_id, dev_name, apps, now_ms=None):
    """C2. `apps` are parse_commands() entries. Returns (doc, changed)."""
    d = device_dir(base, dev_id)
    icons = os.path.join(d, "icons")
    os.makedirs(icons, mode=0o700, exist_ok=True)
    have = set()
    entries = []
    icon_changed = False
    for a in apps:
        path = ""
        png = a.get("png")
        if png:
            p = os.path.join(icons, a["package"] + ".png")
            if _read(p) != png:                      # rewritten only when the bytes change
                _atomic(p, png)
                icon_changed = True
            have.add(a["package"] + ".png")
            path = p
        entries.append({"package": a["package"], "name": a["name"], "sys": bool(a.get("sys")), "icon": path})
    entries.sort(key=lambda a: (a["name"].casefold(), a["package"]))
    # a package that left the list (or lost its icon) loses its icon file; so does a crashed temp file
    try:
        for f in os.listdir(icons):
            if f not in have:
                try:
                    os.unlink(os.path.join(icons, f))
                except OSError:
                    pass
    except OSError:
        pass
    name = clean_name(dev_name)
    old = read_cache(base, dev_id)
    if old and not icon_changed and old["deviceName"] == name and old["apps"] == entries:
        return old, False
    doc = {"v": 1, "device": dev_id, "deviceName": name,
           "updated": int(time.time() * 1000) if now_ms is None else int(now_ms), "apps": entries}
    _atomic(os.path.join(d, "apps.json"), json.dumps(doc, ensure_ascii=False).encode("utf-8"))
    return doc, True


def remove_cache(base, dev_id):
    """The phone was unpaired: its apps and icons go."""
    try:
        d = device_dir(base, dev_id)
    except ValueError:
        return
    icons = os.path.join(d, "icons")
    for root in (icons, d):
        try:
            for f in os.listdir(root):
                p = os.path.join(root, f)
                if os.path.isfile(p) and not os.path.islink(p):
                    os.unlink(p)
        except OSError:
            pass
    for p in (icons, d):
        try:
            os.rmdir(p)
        except OSError:
            pass
