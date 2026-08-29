#!/bin/sh
# cast-audio.sh — route this machine's audio to the TV while casting.
#
# gnome-network-displays creates a null sink named "gnome_network_displays_*"
# and streams ITS monitor to the TV, but it never moves your audio into it — so
# by default the picture goes to the TV and the sound stays on the laptop. This
# runs alongside gnome-network-displays (Cast.qml starts it, SIGTERMs it on
# stop): when the GND sink appears it makes it the default and moves every
# playing stream onto it; on exit it puts the previous default back and moves
# the streams home. Idempotent and self-restoring — if the shell dies, the EXIT
# trap still restores your speakers.
set -u
command -v pactl >/dev/null 2>&1 || exit 0

GND_RE='^gnome_network_displays'
prev=""          # the default sink we replaced
moved=""         # sink-input ids we moved, to move back

gnd_sink() { pactl list short sinks 2>/dev/null | awk '$2 ~ /'"$GND_RE"'/ { print $2; exit }'; }

route_to_tv() {
    tv="$1"
    [ "$(pactl get-default-sink 2>/dev/null)" = "$tv" ] && return
    prev="$(pactl get-default-sink 2>/dev/null)"
    pactl set-default-sink "$tv" 2>/dev/null || return
    # move everything currently playing (except a stream already on the TV sink)
    pactl list short sink-inputs 2>/dev/null | while read -r id _ _ sink _; do
        [ "$sink" = "$tv" ] && continue
        pactl move-sink-input "$id" "$tv" 2>/dev/null || true
    done
    notify-send -a "Cast to TV" -i audio-speakers -u low \
        -h "string:x-canonical-private-synchronous:ewe-cast-audio" \
        "Cast to TV" "Audio is playing on the TV." 2>/dev/null || true
}

restore() {
    tv="$(gnd_sink)"
    # put the old default back if it still exists
    if [ -n "$prev" ] && pactl list short sinks 2>/dev/null | awk '{print $2}' | grep -qx "$prev"; then
        pactl set-default-sink "$prev" 2>/dev/null || true
    fi
    # move streams off the (about-to-vanish) TV sink back to the default
    if [ -n "$tv" ]; then
        def="$(pactl get-default-sink 2>/dev/null)"
        pactl list short sink-inputs 2>/dev/null | while read -r id _ _ sink _; do
            [ "$sink" = "$tv" ] && pactl move-sink-input "$id" "$def" 2>/dev/null || true
        done
    fi
}
# React to sink add/remove and new streams; re-assert routing each time.
# `pactl subscribe` blocks and prints an event per change — zero busy-wait.
# It runs as a TRACKED background child feeding a fifo, not a `pactl | while`
# pipeline: a pipeline's pactl survives the script's death as an immortal
# orphan (the shell's Screensaver leaked 64 of those by 2026-08-30 and
# starved pipewire-pulse's client cap, killing audio control session-wide).
fifo="${XDG_RUNTIME_DIR:-/tmp}/ewe-cast-audio.$$"
mkfifo "$fifo" 2>/dev/null || exit 0
sub=""
trap 'kill "$sub" 2>/dev/null; rm -f "$fifo"; restore; exit 0' INT TERM EXIT

tv="$(gnd_sink)"; [ -n "$tv" ] && route_to_tv "$tv"
pactl subscribe >"$fifo" 2>/dev/null &
sub=$!
while read -r line; do
    case "$line" in
        *"'change'"*sink*|*"'new'"*sink*|*"'remove'"*sink*)
            tv="$(gnd_sink)"
            [ -n "$tv" ] && route_to_tv "$tv"
            ;;
    esac
done < "$fifo"
