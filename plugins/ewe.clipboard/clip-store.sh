#!/usr/bin/env bash
# clip-store.sh — the clipboard-history recorder's gate. `wl-paste --watch`
# runs this with the new clipboard TEXT on stdin; it stores it in cliphist
# unless the copy is a password.
#
# Two tells, either skips the copy:
#   1. the x-kde-passwordManagerHint mime type — KeePassXC, Bitwarden and the
#      KDE apps mark secret copies with it (wl-paste -l lists the offered types)
#   2. the FOCUSED window is a password manager — 1Password (Electron) and
#      friends offer no hint at all, and a copy that lands while their window
#      is focused is a secret being copied out of the vault
# Extra classes: EWE_CLIP_IGNORE_CLASSES="regex" (case-insensitive, matched
# against the active window's class).
set -u
# 3. `ewe-pass copy` (the fill picker's copy action) drops a marker just
#    before wl-copy — one copy passes, then the marker is gone
skip="${XDG_RUNTIME_DIR:-/tmp}/ewe-clip-skip"
if [ -f "$skip" ]; then
    # only honour a fresh marker (a stale one from a failed copy must not eat
    # a later real copy) — judge its age BEFORE removing it: `find` on a file
    # already deleted prints nothing, which read as "fresh" and ate the copy
    stale="$(find "$skip" -mmin +0.1 2>/dev/null)"
    rm -f "$skip"
    if [ -z "$stale" ]; then cat >/dev/null; exit 0; fi
fi
if wl-paste -l 2>/dev/null | grep -qi 'x-kde-passwordManagerHint'; then
    cat >/dev/null; exit 0
fi
IGNORE='^(1Password|com\.onepassword\.OnePassword|Bitwarden|bitwarden|Proton Pass|proton-pass|org\.keepassxc\.KeePassXC|keepassxc|Enpass|com\.belmoussaoui\.Authenticator)$'
if [ -n "${EWE_CLIP_IGNORE_CLASSES:-}" ]; then IGNORE="${IGNORE}|${EWE_CLIP_IGNORE_CLASSES}"; fi
cls="$(hyprctl activewindow -j 2>/dev/null | sed -n 's/^ *"class": *"\(.*\)",*$/\1/p' | head -1)"
if [ -n "$cls" ] && printf '%s' "$cls" | grep -qiE "$IGNORE"; then
    cat >/dev/null; exit 0
fi
exec cliphist store
