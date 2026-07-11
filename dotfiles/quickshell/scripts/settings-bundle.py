#!/usr/bin/env python3
"""settings-bundle.py — collect/apply the hypr-shell settings-sync bundle.

`collect` serializes the shell's EXISTING user state (the same files the
Settings pages write — nothing new is invented) into one schema-versioned
JSON document on stdout. `apply <bundle.json>` writes each present section
back to the same files (atomic temp+rename) and prints a summary. Package
lists are captured on collect and written to plain-text files on apply for
an OPT-IN reinstall — apply never installs anything itself.

Both commands always print a single JSON object and exit 0 so the QML side
can parse unconditionally.
"""

import hashlib
import json
import os
import socket
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
QS = HOME + "/.config/quickshell"
HYPR = HOME + "/.config/hypr"

# JSON state files owned by the shell (key → path)
JSON_FILES = {
    "userTheme": QS + "/user-theme.json",
    "pinnedApps": QS + "/pinned-apps.json",
    "pinnedPlaces": QS + "/places.json",
    "displayProfiles": QS + "/display-profiles.json",
    "inputDevices": QS + "/input-devices.json",
}
# generated plain-text configs (bundle path → real path)
TEXT_FILES = {
    "hypr/generated/user.lua": HYPR + "/generated/user.lua",
    "hypr/generated/input.lua": HYPR + "/generated/input.lua",
    "hypr/generated/wallpapers.conf": HYPR + "/generated/wallpapers.conf",
    "hypr/generated/hypridle.conf": HYPR + "/generated/hypridle.conf",
}
KB_FLAG = HYPR + "/generated/kb-per-window.disabled"


def out(obj):
    print(json.dumps(obj))
    sys.exit(0)


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def read_text(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None


def atomic_write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(content)
    os.replace(tmp, path)


def pacman_list(args):
    try:
        r = subprocess.run(["pacman", *args], capture_output=True, text=True, timeout=30)
        return [l for l in r.stdout.split("\n") if l.strip()] if r.returncode == 0 else []
    except (OSError, subprocess.TimeoutExpired):
        return []


def cmd_collect():
    settings = {}
    for key, path in JSON_FILES.items():
        j = read_json(path)
        if j is not None:
            settings[key] = j
    files = {}
    for key, path in TEXT_FILES.items():
        t = read_text(path)
        if t is not None:
            files[key] = t
    if files:
        settings["files"] = files
    settings["kbPerWindowDisabled"] = os.path.exists(KB_FLAG)

    apps = {
        "explicit": pacman_list(["-Qqe"]),
        "foreign": pacman_list(["-Qqm"]),
    }
    # stable content hash (settings + apps only — not updatedAt/device) so the
    # shell can skip pushes when nothing actually changed
    payload = json.dumps({"settings": settings, "apps": apps}, sort_keys=True)
    bundle = {
        "schemaVersion": 1,
        "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "device": socket.gethostname(),
        "hash": hashlib.sha256(payload.encode()).hexdigest(),
        "settings": settings,
        "apps": apps,
    }
    out(bundle)


def cmd_apply(path):
    bundle = read_json(path)
    if not bundle or not isinstance(bundle.get("settings"), dict):
        out({"ok": False, "error": "unreadable or invalid bundle"})
    if bundle.get("schemaVersion", 0) > 1:
        out({"ok": False, "error": "bundle schemaVersion %s is newer than this shell understands" % bundle.get("schemaVersion")})

    settings = bundle["settings"]
    applied = []
    for key, dest in JSON_FILES.items():
        if key in settings and settings[key] is not None:
            atomic_write(dest, json.dumps(settings[key], indent=2) + "\n")
            applied.append(key)
    for key, dest in TEXT_FILES.items():
        content = (settings.get("files") or {}).get(key)
        if content is not None:
            atomic_write(dest, content)
            applied.append(key)
    if "kbPerWindowDisabled" in settings:
        if settings["kbPerWindowDisabled"]:
            atomic_write(KB_FLAG, "")
        elif os.path.exists(KB_FLAG):
            os.remove(KB_FLAG)
        applied.append("kbPerWindowDisabled")

    # package lists → plain files for an opt-in reinstall; NEVER installed here
    apps = bundle.get("apps") or {}
    n_repo, n_aur = len(apps.get("explicit") or []), len(apps.get("foreign") or [])
    if n_repo:
        atomic_write(QS + "/google-restore-packages.txt", "\n".join(apps["explicit"]) + "\n")
    if n_aur:
        atomic_write(QS + "/google-restore-aur.txt", "\n".join(apps["foreign"]) + "\n")

    out({"ok": True, "applied": applied, "device": bundle.get("device", "?"),
         "updatedAt": bundle.get("updatedAt", "?"),
         "packages": {"repo": n_repo, "aur": n_aur}})


if __name__ == "__main__":
    try:
        if len(sys.argv) > 2 and sys.argv[1] == "apply":
            cmd_apply(sys.argv[2])
        else:
            cmd_collect()
    except SystemExit:
        raise
    except Exception as e:
        print(json.dumps({"ok": False, "error": "internal: %s" % e}))
