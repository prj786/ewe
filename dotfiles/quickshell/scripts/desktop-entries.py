#!/usr/bin/env python3
"""desktop-entries.py — what the shell's app list needs that Quickshell's own
desktop-entry reader cannot do. One JSON line on stdout, exit 0 always.

1. Windows line ends. A .desktop file written with CRLF (LinOffice's word,
   excel, outlook, onenote and powerpoint entries) reads, to Quickshell 0.3,
   as "[Desktop Entry]\\r" — not a group header — so the whole entry is
   dropped (and "Encountered invalid line in desktop entry (no =)" is logged
   for it on every rescan): the app was missing from the launcher, the dock
   and the Overview. The user's file is NEVER touched. A copy with the \\r
   removed goes to $XDG_CACHE_HOME/ewe/desktop-entries/applications/ under
   the same relative path (so the same desktop id), and qs-launch.sh puts
   that folder in the shell's XDG_DATA_DIRS. A broken file does not shadow
   the copy (Quickshell skips it), and only the file that WINS for its id
   (XDG_DATA_HOME first, then XDG_DATA_DIRS in order) is copied. Copies
   whose source is gone or fixed are removed; a copy is rewritten only when
   its content would change, so the rescan it causes finds nothing to do.

2. English names. Quickshell gives an entry's Name in the session's language
   (Name[ka]); the launcher also matches the untranslated Name, so "Files"
   finds ewe Files on a Georgian desktop. `english` maps a desktop id to its
   plain Name, only for entries that carry a translated Name[…].

Output: {"ok": true, "fixed": [<ids>], "english": {<id>: <Name>}, "dir": <copies' base>}
"""
import json
import os
import re
import sys
import tempfile

HOME = os.path.expanduser("~")


def env_dir(var, default):
    v = os.environ.get(var, "")
    return v if os.path.isabs(v) else default


CACHE = env_dir("XDG_CACHE_HOME", os.path.join(HOME, ".cache"))
FIX_BASE = os.path.join(CACHE, "ewe", "desktop-entries")
FIX_APPS = os.path.join(FIX_BASE, "applications")


def data_dirs():
    """applications/ folders in precedence order, without our own copies"""
    home = env_dir("XDG_DATA_HOME", os.path.join(HOME, ".local", "share"))
    rest = os.environ.get("XDG_DATA_DIRS", "") or "/usr/local/share:/usr/share"
    out, seen = [], set()
    for d in [home] + rest.split(":"):
        if not d or not os.path.isabs(d):
            continue
        d = os.path.normpath(d)
        if d in seen or d == os.path.normpath(FIX_BASE):
            continue
        seen.add(d)
        out.append(os.path.join(d, "applications"))
    return out


def entries(apps_dir):
    """(desktop id, relative path, full path) under one applications/ dir —
    the id is the relative path with "/" → "-", without ".desktop" (the
    Desktop Entry spec, and Quickshell's DesktopEntry.id)"""
    for root, _dirs, files in os.walk(apps_dir):
        for f in sorted(files):
            if not f.endswith(".desktop"):
                continue
            full = os.path.join(root, f)
            rel = os.path.relpath(full, apps_dir)
            yield rel[: -len(".desktop")].replace(os.sep, "-"), rel, full


_GROUP = re.compile(r"^\[(.+)\]$")


def english_name(text):
    """the plain Name of the [Desktop Entry] group, when a Name[…] exists"""
    group, name, translated = None, None, False
    for line in text.splitlines():
        line = line.strip()
        m = _GROUP.match(line)
        if m:
            if group == "Desktop Entry":
                break
            group = m.group(1)
            continue
        if group != "Desktop Entry" or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        if k == "Name":
            name = v.strip()
        elif k.startswith("Name["):
            translated = True
    return name if (name and translated) else None


def fixed_bytes(data):
    """CRLF (or a stray CR) → LF, with a final newline"""
    out = re.sub(rb"\r+\n", b"\n", data).replace(b"\r", b"\n")
    return out if out.endswith(b"\n") else out + b"\n"


def write_if_changed(path, data):
    try:
        with open(path, "rb") as f:
            if f.read() == data:
                return
    except OSError:
        pass
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp-")
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    os.replace(tmp, path)


def main():
    seen, fixed, english, keep = set(), [], {}, set()
    for apps in data_dirs():
        if not os.path.isdir(apps):
            continue
        for did, rel, full in entries(apps):
            if did in seen:
                continue            # a higher-precedence file has this id
            seen.add(did)
            try:
                with open(full, "rb") as f:
                    data = f.read(1 << 20)
            except OSError:
                continue
            if b"\r" in data:
                fixed.append(did)
                keep.add(rel)
                write_if_changed(os.path.join(FIX_APPS, rel), fixed_bytes(data))
                data = fixed_bytes(data)
            name = english_name(data.decode("utf-8", "replace"))
            if name:
                english[did] = name
    # copies whose source is gone, fixed, or shadowed now
    if os.path.isdir(FIX_APPS):
        for root, _dirs, files in os.walk(FIX_APPS, topdown=False):
            for f in files:
                rel = os.path.relpath(os.path.join(root, f), FIX_APPS)
                if rel not in keep:
                    try:
                        os.unlink(os.path.join(root, f))
                    except OSError:
                        pass
            if root != FIX_APPS:
                try:
                    os.rmdir(root)
                except OSError:
                    pass
    return {"ok": True, "fixed": fixed, "english": english, "dir": FIX_BASE}


if __name__ == "__main__":
    try:
        res = main()
    except Exception as e:  # noqa: BLE001 — the shell only ever reads JSON
        res = {"ok": False, "error": str(e), "fixed": [], "english": {}, "dir": FIX_BASE}
    if "--dir" in sys.argv[1:]:
        print(FIX_BASE)
    else:
        print(json.dumps(res, ensure_ascii=False))
    sys.exit(0)
