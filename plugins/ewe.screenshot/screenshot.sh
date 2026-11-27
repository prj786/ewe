#!/usr/bin/env bash
# screenshot.sh — grim/slurp screenshots, saved to ~/Pictures/Screenshots AND
# copied to the clipboard (wl-copy). Sends a notification with the result.
#
# Usage: screenshot.sh full | region | window

# camera shutter — honours the event-sounds switch (ewe.conf); silent no-op
# without the freedesktop sound theme
shutter() {
    [ "$("$HOME/.config/quickshell/../../bin/ewe-conf" get desktop.sound.event_sounds 2>/dev/null)" = "false" ] && return 0
    f=/usr/share/sounds/freedesktop/stereo/camera-shutter.oga
    [ -r "$f" ] && { pw-play "$f" 2>/dev/null || paplay "$f" 2>/dev/null; } &
}

set -u
mode="${1:-region}"

dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
file="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"

case "$mode" in
    full)
        # the focused monitor (not every screen). Fallback: whole layout.
        mon="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused==true) | .name')"
        if [ -n "$mon" ]; then grim -o "$mon" "$file"; else grim "$file"; fi
        shutter
        ;;
    region)
        geom="$(slurp 2>/dev/null)" || exit 0   # cancelled selection
        [ -z "$geom" ] && exit 0
        grim -g "$geom" "$file"
        shutter
        ;;
    window)
        # Feed every mapped window's box to slurp; hovering highlights a window,
        # click captures it (Esc/right-click cancels).
        boxes="$(hyprctl clients -j 2>/dev/null \
            | jq -r '.[] | select(.mapped == true and .hidden == false and .workspace.id != -1)
                     | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')"
        geom="$(printf '%s\n' "$boxes" | slurp 2>/dev/null)" || exit 0
        [ -z "$geom" ] && exit 0
        grim -g "$geom" "$file"
        shutter
        ;;
    activewindow)
        # the currently focused window, captured instantly (no selection).
        geom="$(hyprctl activewindow -j 2>/dev/null \
            | jq -r 'if .at and .size then "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])" else empty end')"
        [ -z "$geom" ] && { command -v notify-send >/dev/null 2>&1 && notify-send "Screenshot" "No focused window to capture."; exit 0; }
        grim -g "$geom" "$file"
        shutter
        ;;
    *)
        echo "usage: screenshot.sh full|region|window|activewindow" >&2; exit 2 ;;
esac

# Copy the PNG to the clipboard as an image (so it pastes into apps).
[ "${EWE_SHOT_COPY:-1}" != 0 ] && [ -r "$file" ] && wl-copy --type image/png < "$file" 2>/dev/null

# Show the draggable thumbnail preview (Quickshell), bottom-right. This IS the
# feedback now — no notify-send (its full-screen toast overlay would block the
# preview's pointer input). If the shell does not answer, fall back to a notify.
#
# Ask the shell itself, never `pgrep -x qs` (1.1.2): Quickshell restarts
# itself after a crash as /usr/bin/quickshell, so the process is no longer
# called `qs` and every shot after a crash showed nothing at all. `qs ipc
# call` fails with no shell running, and prints "Target not found." (exit 0)
# when the shell runs without this plugin's panel.
[ -r "$file" ] || exit 0
shown=0
if command -v qs >/dev/null 2>&1; then
    out="$(qs ipc call ewe.screenshot pop "$file" 2>&1)" \
        && case "$out" in *"not found"*|*"No running"*) ;; *) shown=1 ;; esac
fi
if [ "$shown" = 0 ] && command -v notify-send >/dev/null 2>&1; then
    notify-send -i "$file" "Screenshot saved" "$(basename "$file") — also on clipboard"
fi
