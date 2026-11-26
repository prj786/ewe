#!/usr/bin/env python3
"""hide_kdeconnect.py — no KDE Connect window anywhere (ewe Mobile contract C6).

    hide_kdeconnect.py hide      take KDE Connect's launcher entries out of the launcher
    hide_kdeconnect.py show      put them back, exactly as they were
    hide_kdeconnect.py status    {"hidden": [...], "visible": [...]}   (JSON on stdout)

Pure standard library. `kdeconnectd` — the engine — is untouched; only the
entries that open a KDE Connect window go: the app, SMS, the indicator, the
URL handler and the settings module.

The house's way (eep/docs/CARD.md): a hidden entry is a `NoDisplay=true`
COPY in ~/.local/share/applications — not Hidden=true, so the app's file types
and URL schemes still resolve — marked so only its owner takes it away again.

  * eep knows the entry (it has a card for it: `sys-…`): eep's own verb hides
    it — `eep remove <id>` writes its `X-Eep-Hides` copy and takes the card out
    of ~/Applications; `eep install <id>` (here: `show`) brings both back. The
    ids eep hid for us are kept in $XDG_STATE_HOME/ewe-phone/hidden.json.
  * otherwise this script writes the copy itself, marked `X-Ewe-Phone-Hides=1`.
    A user's own, unmarked entry of the same name is kept byte for byte in
    $XDG_STATE_HOME/ewe-phone/backup/ and put back by `show`.

Only a file carrying one of the two marks is ever deleted or replaced.
"""

import json
import os
import shutil
import subprocess
import sys

MARK = "X-Ewe-Phone-Hides"
EEP_MARK = "X-Eep-Hides"

ENTRIES = [
    "org.kde.kdeconnect.app.desktop",
    "org.kde.kdeconnect.sms.desktop",
    "org.kde.kdeconnect.nonplasma.desktop",
    "org.kde.kdeconnect.handler.desktop",
    "org.kde.kdeconnect.daemon.desktop",     # already NoDisplay on most builds: skipped then
    "org.kde.kdeconnect.kcm.desktop",        # the settings module, under the names it has shipped with
    "kcm_kdeconnect.desktop",
    "kdeconnect-settings.desktop",
]


def env(k, d=""):
    return os.environ.get(k) or d


def home():
    return env("HOME", os.path.expanduser("~"))


def user_apps():
    return os.path.join(env("XDG_DATA_HOME", os.path.join(home(), ".local", "share")), "applications")


def system_apps():
    dirs = env("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    return [os.path.join(d, "applications") for d in dirs if d]


def state_dir():
    return os.path.join(env("XDG_STATE_HOME", os.path.join(home(), ".local", "state")), "ewe-phone")


def read(path):
    try:
        with open(path, "rb") as f:
            return f.read().decode("utf-8", "replace")
    except OSError:
        return None


def atomic(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp.%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def keys_of(text):
    """The [Desktop Entry] group as {key: value}."""
    out, grp = {}, False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("["):
            grp = s == "[Desktop Entry]"
        elif grp and "=" in s and not s.startswith("#"):
            k, v = s.split("=", 1)
            out.setdefault(k.strip(), v.strip())
    return out


def set_keys(text, pairs):
    """Set keys in [Desktop Entry] only (an action group's NoDisplay is its own)."""
    names = {k for k, _ in pairs}
    out, grp, placed = [], False, False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("["):
            if grp and not placed:
                out.extend("%s=%s" % kv for kv in pairs)
                placed = True
            grp = s == "[Desktop Entry]"
            out.append(line)
            continue
        if grp and "=" in s and s.split("=", 1)[0].strip() in names:
            continue
        out.append(line)
    if grp and not placed:
        out.extend("%s=%s" % kv for kv in pairs)
        placed = True
    if not placed:
        out = ["[Desktop Entry]"] + ["%s=%s" % kv for kv in pairs] + out
    return "\n".join(out) + "\n"


def find_system(name):
    for d in system_apps():
        p = os.path.join(d, name)
        if os.path.isfile(p):
            return p
    return None


def truthy(v):
    return str(v).strip().lower() == "true"


def load_state():
    try:
        with open(os.path.join(state_dir(), "hidden.json")) as f:
            j = json.load(f)
        return j if isinstance(j, dict) and isinstance(j.get("eep"), list) else {"eep": []}
    except (OSError, ValueError):
        return {"eep": []}


def save_state(st):
    p = os.path.join(state_dir(), "hidden.json")
    if st["eep"]:
        atomic(p, json.dumps(st))
    else:
        try:
            os.unlink(p)
        except OSError:
            pass


def eep_exe():
    """EWE_PHONE_EEP=<path> picks the eep to use ("none" = no eep): for tests."""
    o = os.environ.get("EWE_PHONE_EEP")
    if o is not None:
        return o if o != "none" and os.access(o, os.X_OK) else None
    return shutil.which("eep")


def eep_cards():
    """{entry file name: card id} of the cards eep keeps for found apps; {} without eep."""
    exe = eep_exe()
    if not exe:
        return {}
    try:
        r = subprocess.run([exe, "list", "--all"], capture_output=True, text=True, timeout=30)
        j = json.loads(r.stdout)
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}
    out = {}
    for a in (j.get("apps") or []) if isinstance(j, dict) else []:
        if isinstance(a, dict) and isinstance(a.get("entry"), str) and str(a.get("id", "")).startswith("sys-"):
            out[a["entry"]] = a["id"]
    return out


def eep_run(*args):
    exe = eep_exe()
    if not exe:
        return False
    try:
        return subprocess.run([exe] + list(args), capture_output=True, timeout=60).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def hide():
    ud = user_apps()
    st = load_state()
    cards = None
    done = []
    for name in ENTRIES:
        user = os.path.join(ud, name)
        utext = read(user)
        if utext is not None:
            k = keys_of(utext)
            if MARK in k or EEP_MARK in k or truthy(k.get("NoDisplay")) or truthy(k.get("Hidden")):
                continue                                   # already out of the launcher
            # the user's own entry of this name: keep it, hide a copy of it
            bak = os.path.join(state_dir(), "backup", name)
            if not os.path.exists(bak):
                os.makedirs(os.path.dirname(bak), exist_ok=True)
                shutil.copyfile(user, bak)
            atomic(user, set_keys(utext, [("NoDisplay", "true"), (MARK, "1")]))
            done.append(name)
            continue
        sp = find_system(name)
        stext = read(sp) if sp else None
        if stext is None:
            continue
        k = keys_of(stext)
        if truthy(k.get("NoDisplay")) or truthy(k.get("Hidden")):
            continue
        if cards is None:
            cards = eep_cards()
        cid = cards.get(name)
        if cid and eep_run("remove", cid):
            if cid not in st["eep"]:
                st["eep"].append(cid)
            save_state(st)
            done.append(name)
            continue
        atomic(user, set_keys(stext, [("NoDisplay", "true"), (MARK, "1")]))
        done.append(name)
    return done


def show():
    ud = user_apps()
    st = load_state()
    done = []
    for name in ENTRIES:
        user = os.path.join(ud, name)
        utext = read(user)
        if utext is None or MARK not in keys_of(utext):
            continue                                       # not ours: never touched
        bak = os.path.join(state_dir(), "backup", name)
        if os.path.isfile(bak):
            os.replace(bak, user)                          # the user's own entry, byte for byte
        else:
            os.unlink(user)
        done.append(name)
    for cid in list(st["eep"]):
        if eep_run("install", cid):
            st["eep"].remove(cid)
            done.append(cid)
    save_state(st)
    return done


def status():
    ud = user_apps()
    hidden, visible = [], []
    cards = None
    for name in ENTRIES:
        utext = read(os.path.join(ud, name))
        if utext is not None:
            k = keys_of(utext)
            (hidden if (MARK in k or EEP_MARK in k or truthy(k.get("NoDisplay"))) else visible).append(name)
            continue
        sp = find_system(name)
        stext = read(sp) if sp else None
        if stext is None:
            continue
        (hidden if truthy(keys_of(stext).get("NoDisplay")) else visible).append(name)
    return {"hidden": hidden, "visible": visible, "eep": load_state()["eep"]}


def main(argv):
    verb = argv[1] if len(argv) > 1 else "status"
    try:
        if verb == "hide":
            out = {"ok": True, "changed": hide()}
        elif verb == "show":
            out = {"ok": True, "changed": show()}
        elif verb == "status":
            out = dict(status(), ok=True)
        else:
            out = {"ok": False, "error": "usage: hide_kdeconnect.py hide|show|status"}
    except Exception as e:     # never a traceback for the shell to parse
        out = {"ok": False, "error": str(e)}
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
