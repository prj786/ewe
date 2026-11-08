#!/usr/bin/env python3
"""kb-per-window.py — GNOME-style per-window keyboard layout for Hyprland.

Hyprland has no native per-window layout: switchxkblayout changes the layout for
the whole keyboard. This daemon remembers the chosen layout per window address and
restores it on focus, so e.g. a terminal can stay on Georgian while the browser
stays on US.

No external deps: it reads Hyprland's event socket (.socket2.sock) and sends its
queries and switches to the request socket (.socket.sock) with the stdlib
`socket` module — no process per event. Until 0.40 every focus change spawned
one `hyprctl switchxkblayout` per "keyboard" (power button, video bus, mice …:
11 processes, ~27 ms); now it is one `switchxkblayout all N` (~0.2 ms), and
nothing at all when the layout already matches. Layouts come from kb_layout =
"us,ge" (index 0 = us, 1 = ge); the name→index map below covers that pair and
degrades gracefully to 0 for anything unrecognised.
"""

import json
import os
import socket
import subprocess
import sys

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "")
SIG = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
SOCK = f"{RUNTIME}/hypr/{SIG}/.socket2.sock"
REQ = f"{RUNTIME}/hypr/{SIG}/.socket.sock"

# layout code (as configured in input.kb_layout) → prefixes of the keymap name
# Hyprland reports in `activelayout` events. Covers the codes the Settings app
# offers; unknown names fall back to index 0 (the default layout).
CODE_HINTS = {
    "us": ("english (us", "english (intl", "english (dvorak", "english (colemak"),
    "gb": ("english (uk",), "ge": ("georgian",), "ru": ("russian",), "ua": ("ukrainian",),
    "de": ("german",), "at": ("german (austria",), "ch": ("german (switzerland", "swiss"),
    "fr": ("french",), "be": ("belgian",), "ca": ("french (canada",),
    "es": ("spanish",), "latam": ("spanish (latin",), "it": ("italian",),
    "pt": ("portuguese",), "br": ("portuguese (brazil",), "nl": ("dutch",),
    "tr": ("turkish",), "gr": ("greek",), "pl": ("polish",), "cz": ("czech",),
    "sk": ("slovak",), "hu": ("hungarian",), "ro": ("romanian",), "bg": ("bulgarian",),
    "se": ("swedish",), "no": ("norwegian",), "fi": ("finnish",), "dk": ("danish",),
    "is": ("icelandic",), "lt": ("lithuanian",), "lv": ("latvian",), "ee": ("estonian",),
    "rs": ("serbian",), "hr": ("croatian",), "si": ("slovenian",), "by": ("belarusian",),
    "kz": ("kazakh",), "am": ("armenian",), "az": ("azerbaijani",), "il": ("hebrew",),
    "ara": ("arabic",), "ir": ("persian",), "in": ("indian",), "jp": ("japanese",),
    "kr": ("korean",), "cn": ("chinese",), "th": ("thai",), "vn": ("vietnamese",),
}


def hypr(request: str) -> str:
    """One request on Hyprland's request socket (what hyprctl does, minus the
    process). Falls back to hyprctl if the socket is unusable."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as c:
            c.settimeout(2)
            c.connect(REQ)
            c.sendall(request.encode())
            out = b""
            while True:
                b = c.recv(65536)
                if not b:
                    break
                out += b
        return out.decode("utf-8", "replace")
    except OSError:
        flags, _, rest = request.rpartition("/") if request.startswith("j/") else ("", "", request)
        args = rest.split() + (["-j"] if flags else [])
        return subprocess.run(["hyprctl", *args], capture_output=True, text=True).stdout


def layout_codes() -> list:
    try:
        raw = json.loads(hypr("j/getoption input:kb_layout")).get("str", "us")
        return [c.strip() for c in raw.split(",") if c.strip()] or ["us"]
    except Exception:
        return ["us"]


def layout_map(codes: list) -> dict:
    """keymap-name prefix → index, built from the live kb_layout list."""
    m = {}
    for idx, code in enumerate(codes):
        for hint in CODE_HINTS.get(code, (code,)):
            m.setdefault(hint, idx)
    return m


CODES = layout_codes()
LAYOUTS = layout_map(CODES)


def name_to_index(name: str) -> int:
    # longest hint first: "german (austria" must win over "german" when both
    # layouts are active, or country variants could never be restored
    n = (name or "").lower()
    for hint in sorted(LAYOUTS, key=len, reverse=True):
        if n.startswith(hint):
            return LAYOUTS[hint]
    return 0  # the default layout for anything unrecognised


def active_index() -> int | None:
    """Layout index the main keyboard is on now (None if unknown)."""
    try:
        kbds = json.loads(hypr("j/devices")).get("keyboards", [])
        main = next((k for k in kbds if k.get("main")), kbds[0] if kbds else None)
        return name_to_index(main["active_keymap"]) if main else None
    except Exception:
        return None


def apply_layout(index: int) -> None:
    # `all` = every keyboard device, including ones plugged in later
    hypr(f"switchxkblayout all {index}")


def main() -> int:
    if not os.path.exists(SOCK):
        print(f"kb-per-window: event socket not found: {SOCK}", file=sys.stderr)
        return 1

    global CODES, LAYOUTS
    mem: dict[str, int] = {}   # window address → layout index
    current = ""               # focused window address
    active = active_index()    # layout the keyboards are on (None = unknown)

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(SOCK)

    buf = b""
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            try:
                ev = line.decode("utf-8", "replace")
            except Exception:
                continue
            if ">>" not in ev:
                continue
            name, _, payload = ev.partition(">>")

            if name == "activewindowv2":
                # payload = window address (hex, no 0x). Restore its layout.
                current = payload.strip()
                want = mem.get(current, 0)
                if len(CODES) > 1 and want != active:
                    apply_layout(want)
                    active = want

            elif name == "activelayout":
                # payload = "keyboardname,LayoutName". Record what the focused
                # window is now using (covers manual switches: shortcut/bar/click).
                layout = payload.rsplit(",", 1)[-1]
                active = name_to_index(layout)
                if current:
                    mem[current] = active

            elif name == "closewindow":
                mem.pop(payload.strip(), None)

            elif name in ("configreloaded", "monitoradded", "monitorremoved"):
                # the layout list can change on reload / hotplug
                CODES = layout_codes()
                LAYOUTS = layout_map(CODES)
                active = active_index()

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
