#!/bin/sh
# open-url.sh — the session's $BROWSER (start-hyprland.sh): open each link in
# the browser the user chose (Settings → Default apps, ~/.config/mimeapps.list).
#
# xdg-open under Hyprland is its "generic" mode, which rejects a desktop entry
# whose Exec path is quoted — Komble writes every AppImage that way — and then
# falls back to $BROWSER. So $BROWSER has to honour the choice itself: GIO
# reads the same mimeapps.list and parses Exec properly. It also returns once
# the browser is started (gh auth login no longer waits for the browser to exit).
#
# A link usually comes from an app (Unity Hub's sign-in, an Electron or
# AppImage app), and the browser would inherit that app's private environment:
# its CHROME_DESKTOP kills Electron browsers on start, its AppImage library
# path and schemas leak into whatever starts next. Drop them first.
unset CHROME_DESKTOP
if [ -n "${APPDIR:-}" ]; then
    # keep only the entries that are not inside the app's mount
    strip() {
        printf '%s' "$1" | tr ':' '\n' | grep -v "^$APPDIR" | paste -sd: -
    }
    LD_LIBRARY_PATH="$(strip "${LD_LIBRARY_PATH:-}")"
    XDG_DATA_DIRS="$(strip "${XDG_DATA_DIRS:-}")"
    PATH="$(strip "$PATH")"
    [ -n "$LD_LIBRARY_PATH" ] && export LD_LIBRARY_PATH || unset LD_LIBRARY_PATH
    [ -n "$XDG_DATA_DIRS" ] && export XDG_DATA_DIRS || unset XDG_DATA_DIRS
    export PATH
    case "${GSETTINGS_SCHEMA_DIR:-}" in "$APPDIR"*) unset GSETTINGS_SCHEMA_DIR ;; esac
    unset APPDIR APPIMAGE ARGV0 OWD
fi

status=0
for url in "$@"; do
    gio open "$url" 2>/dev/null && continue
    # no default browser at all: the shipped one
    for d in ewe-browser.desktop helium.desktop; do
        [ -f "/usr/share/applications/$d" ] && gio launch "/usr/share/applications/$d" "$url" && continue 2
    done
    status=1
done
exit $status
