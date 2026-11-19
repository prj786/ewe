#!/bin/sh
# ewe-set-wallpaper.sh FILE — Nemo's "Set as Wallpaper" (set-wallpaper.nemo_action).
# Writes the default wallpaper through ewe-conf (the only writer of ewe.conf;
# it regenerates hypr/generated/wallpapers.conf and the change syncs like any
# other), then redraws it the way Settings → Wallpaper does. A per-display
# wallpaper you set in Settings stays on its display. Exits 0 always.
f="$1"
[ -f "$f" ] || exit 0
case "$f" in /*) ;; *) f="$PWD/$f" ;; esac
# a JSON string: the path may hold quotes or backslashes
v="$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$f" 2>/dev/null)" || exit 0
ewe-conf set desktop.wallpapers.default "$v" >/dev/null 2>&1 || {
    command -v notify-send >/dev/null && notify-send -a Files "Could not set the wallpaper" "$f"
    exit 0
}
"${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/wallpaper.sh" --reapply >/dev/null 2>&1 &
exit 0
