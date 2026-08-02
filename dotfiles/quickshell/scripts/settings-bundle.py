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

import base64
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
    "startupApps": QS + "/startup-apps.json",
}
FACE = HOME + "/.face"
FACE_MAX = 1024 * 1024   # avatars are ~100 KB; refuse to inflate the bundle past 1 MB
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

    # ssh: the host config + the shell's browse-tunnel scripts (SOCKS port /
    # browser command per host). NEVER keys, never known_hosts.
    ssh_cfg = read_text(HOME + "/.ssh/config")
    if ssh_cfg is not None:
        settings["sshConfig"] = ssh_cfg
    browse = {}
    bdir = QS + "/ssh-browse"
    if os.path.isdir(bdir):
        for fn in sorted(os.listdir(bdir)):
            p = os.path.join(bdir, fn)
            if os.path.isfile(p):
                t = read_text(p)
                if t is not None:
                    browse[fn] = t
    if browse:
        settings["sshBrowse"] = browse
    # vpn: names + types ONLY. The actual profiles live root-owned in /etc and
    # can embed credentials — secrets never go into the cloud bundle. Restore
    # lists these so the user knows what to re-import.
    vpns = []
    try:
        r = subprocess.run(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"],
                           capture_output=True, text=True, timeout=15)
        if r.returncode == 0:
            for line in r.stdout.split("\n"):
                parts = line.split(":")
                if len(parts) >= 2 and parts[1] in ("vpn", "wireguard"):
                    vpns.append({"name": parts[0], "type": parts[1]})
    except (OSError, subprocess.TimeoutExpired):
        pass
    if vpns:
        settings["vpnConnections"] = vpns

    # avatar: ~/.face travels base64 so a fresh install gets the user icon back
    try:
        if os.path.isfile(FACE) and os.path.getsize(FACE) <= FACE_MAX:
            with open(FACE, "rb") as f:
                settings["face"] = base64.b64encode(f.read()).decode()
    except OSError:
        pass

    apps = {
        # -Qqen: explicit NATIVE only — plain -Qqe also lists AUR packages,
        # which then duplicate into both lists and break the pacman install
        # ("target not found"). -Qqem: explicit foreign (AUR) — their deps get
        # rebuilt by the AUR helper anyway.
        "explicit": pacman_list(["-Qqen"]),
        "foreign": pacman_list(["-Qqem"]),
    }
    # Which of those are APPLICATIONS (own a .desktop entry)? Komble's
    # "For you" view offers only these — a backup restore that suggests
    # kernels, firmware and library packages is noise, not help. Recorded at
    # collect time because only the source machine can answer the question.
    try:
        import glob
        desktop_files = glob.glob("/usr/share/applications/*.desktop")
        r = subprocess.run(["pacman", "-Qqo", *desktop_files],
                           capture_output=True, text=True, timeout=60)
        owners = set(l.strip() for l in r.stdout.split("\n") if l.strip())
        apps["desktopApps"] = sorted(owners & set(apps["explicit"] + apps["foreign"]))
    except (OSError, subprocess.TimeoutExpired):
        pass
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

    if isinstance(settings.get("sshConfig"), str):
        sshdir = HOME + "/.ssh"
        os.makedirs(sshdir, exist_ok=True)
        os.chmod(sshdir, 0o700)
        atomic_write(sshdir + "/config", settings["sshConfig"])
        os.chmod(sshdir + "/config", 0o600)   # ssh refuses group/world-readable configs
        applied.append("sshConfig")
    if isinstance(settings.get("sshBrowse"), dict):
        bdir = QS + "/ssh-browse"
        os.makedirs(bdir, exist_ok=True)
        for fn, content in settings["sshBrowse"].items():
            fn = os.path.basename(str(fn))   # no path traversal from a tampered bundle
            if not fn or not isinstance(content, str):
                continue
            p = os.path.join(bdir, fn)
            atomic_write(p, content)
            os.chmod(p, 0o755)
        applied.append("sshBrowse")

    if isinstance(settings.get("face"), str):
        try:
            data = base64.b64decode(settings["face"])
            if 0 < len(data) <= FACE_MAX:
                tmp = FACE + ".tmp"
                with open(tmp, "wb") as f:
                    f.write(data)
                os.replace(tmp, FACE)
                applied.append("face")
                # AccountsService copy (world-readable — the greeter reads it);
                # best-effort: a missing accountsservice just skips
                subprocess.run(["busctl", "call", "org.freedesktop.Accounts",
                                "/org/freedesktop/Accounts/User" + str(os.getuid()),
                                "org.freedesktop.Accounts.User", "SetIconFile", "s", FACE],
                               capture_output=True, timeout=15)
        except (ValueError, OSError, subprocess.TimeoutExpired):
            pass

    # package lists → plain files for an opt-in reinstall; NEVER installed here
    apps = bundle.get("apps") or {}
    n_repo, n_aur = len(apps.get("explicit") or []), len(apps.get("foreign") or [])
    if n_repo:
        atomic_write(QS + "/google-restore-packages.txt", "\n".join(apps["explicit"]) + "\n")
    if n_aur:
        atomic_write(QS + "/google-restore-aur.txt", "\n".join(apps["foreign"]) + "\n")

    vpns = [v.get("name", "?") for v in (settings.get("vpnConnections") or []) if isinstance(v, dict)]
    out({"ok": True, "applied": applied, "device": bundle.get("device", "?"),
         "updatedAt": bundle.get("updatedAt", "?"),
         "packages": {"repo": n_repo, "aur": n_aur}, "vpn": vpns})


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
