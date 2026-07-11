#!/usr/bin/env bash
# wallpaper.sh — set the desktop background (idempotent; per-monitor aware;
# static images, animated GIFs and videos).
#
# Reads ~/.config/hypr/generated/wallpapers.conf, written atomically by
# Settings → Wallpaper:
#     mode=fill|fit|stretch|tile|center
#     backend=swww|swaybg              # optional IMAGE backend override
#     mute=1|0                         # video audio (default 1 = muted)
#     *=/path/to/default.{png,gif,mp4,…}   # outputs without their own line
#     DP-1=/path/to/that-monitor.…         # per-output override
#
# Backend by file type — chosen automatically:
#     video (mp4/webm/mkv/mov/avi/m4v) → mpvpaper          (required for video)
#     image / animated GIF             → swww (or its Arch rename `awww`);
#                                        falls back to swaybg = static only
# Flags:
#     --reapply   re-assert everything (Settings after a change, HyprMon on
#                 monitor hotplug) so a newly plugged display gets covered
#     --backend   print "img=<swww|awww|swaybg|none> video=<mpvpaper|none>"
#
# Problems are printed with an "error:"/"note:" prefix and a non-zero exit for
# errors — Settings runs this through a Process and shows the output inline.

set -u

REAPPLY=0; QUERY=0
case "${1:-}" in
    --reapply) REAPPLY=1 ;;
    --backend) QUERY=1 ;;
esac

CONF="$HOME/.config/hypr/generated/wallpapers.conf"
MODE=fill
BACKEND=""
MUTE=1
DEFAULT=""
declare -A PER=()

if [ -r "$CONF" ]; then
    while IFS='=' read -r k v; do
        case "$k" in
            ''|\#*) ;;
            mode) MODE="$v" ;;
            backend) BACKEND="$v" ;;
            mute) MUTE="$v" ;;
            \*) DEFAULT="$v" ;;
            *) [ -n "$v" ] && PER["$k"]="$v" ;;
        esac
    done < "$CONF"
fi

# drop images that no longer exist so a dead path can't black out the desktop
[ -n "$DEFAULT" ] && [ ! -r "$DEFAULT" ] && DEFAULT=""
for o in "${!PER[@]}"; do [ -r "${PER[$o]}" ] || unset 'PER[$o]'; done

# legacy single-image fallback when nothing (valid) is configured
if [ -z "$DEFAULT" ] && [ "${#PER[@]}" -eq 0 ]; then
    for f in \
        "${DE_WALLPAPER:-}" \
        "$HOME/.config/hypr/wallpaper.jpg" \
        "$HOME/.config/hypr/wallpaper.jpeg" \
        "$HOME/.config/hypr/wallpaper.png"
    do
        if [ -n "$f" ] && [ -r "$f" ]; then DEFAULT="$f"; break; fi
    done
fi

have() { command -v "$1" >/dev/null 2>&1; }
SWWW="$(command -v swww || command -v awww || true)"
SWWWD="$(command -v swww-daemon || command -v awww-daemon || true)"

IMGBACK=""
if [ "$BACKEND" = "swaybg" ] && have swaybg; then IMGBACK=swaybg
elif [ -n "$SWWW" ]; then IMGBACK="$(basename "$SWWW")"
elif have swaybg; then IMGBACK=swaybg
fi
VIDBACK=""
have mpvpaper && VIDBACK=mpvpaper

if [ "$QUERY" -eq 1 ]; then echo "img=${IMGBACK:-none} video=${VIDBACK:-none}"; exit 0; fi

is_video() { case "${1##*.}" in mp4|webm|mkv|mov|avi|m4v|MP4|WEBM|MKV|MOV|AVI|M4V) return 0 ;; *) return 1 ;; esac }
is_gif()   { case "${1##*.}" in gif|GIF) return 0 ;; *) return 1 ;; esac }

# ── resolve what each connected output should show ────────────────────────────
# (grep keeps this jq-free; if the query fails we fall back to '*'-style groups)
OUTPUTS=()
while IFS= read -r n; do [ -n "$n" ] && OUTPUTS+=("$n"); done \
    < <(hyprctl monitors -j 2>/dev/null | grep -oP '"name": *"\K[^"]+')

declare -A SHOW=()   # output → file
if [ "${#OUTPUTS[@]}" -gt 0 ]; then
    for o in "${OUTPUTS[@]}"; do
        f="${PER[$o]:-$DEFAULT}"
        [ -n "$f" ] && SHOW["$o"]="$f"
    done
else
    # no output list available: explicit entries only, plus '*' default
    for o in "${!PER[@]}"; do SHOW["$o"]="${PER[$o]}"; done
    [ -n "$DEFAULT" ] && SHOW['*']="$DEFAULT"
fi

declare -A VID=() IMG=()
for o in "${!SHOW[@]}"; do
    if is_video "${SHOW[$o]}"; then VID["$o"]="${SHOW[$o]}"; else IMG["$o"]="${SHOW[$o]}"; fi
done

st=0
if [ "${#VID[@]}" -gt 0 ] && [ -z "$VIDBACK" ]; then
    echo "error: a video wallpaper is set but mpvpaper is not installed — sudo pacman -S mpvpaper"
    st=1
    VID=()
fi
if [ "$IMGBACK" = "swaybg" ]; then
    for f in "${IMG[@]}"; do
        if is_gif "$f"; then echo "note: GIFs are static with swaybg — install swww (packaged as 'awww': sudo pacman -S awww) for animation"; break; fi
    done
fi

# nothing to show → solid Gruvbox background so the root is never garbage
if [ "${#IMG[@]}" -eq 0 ] && [ "${#VID[@]}" -eq 0 ]; then
    if have swaybg; then
        if [ "$REAPPLY" -eq 1 ] || ! pgrep -x swaybg >/dev/null 2>&1; then
            pkill -x swaybg 2>/dev/null
            swaybg -c "#282828" >/dev/null 2>&1 &
        fi
    fi
    exit "$st"
fi

# at plain login with everything already up, do nothing (idempotent autostart)
if [ "$REAPPLY" -eq 0 ]; then
    ok=1
    [ "${#VID[@]}" -gt 0 ] && ! pgrep -x mpvpaper >/dev/null 2>&1 && ok=0
    if [ "${#IMG[@]}" -gt 0 ]; then
        case "$IMGBACK" in
            swaybg) pgrep -x swaybg >/dev/null 2>&1 || ok=0 ;;
            *) pgrep -f "$(basename "${SWWWD:-swww-daemon}")" >/dev/null 2>&1 || ok=0 ;;
        esac
    fi
    [ "$ok" -eq 1 ] && exit "$st"
fi

# ── videos → mpvpaper (one instance per output; never '*' to avoid overlap) ──
pkill -x mpvpaper 2>/dev/null
if [ "${#VID[@]}" -gt 0 ]; then
    MPVOPTS="loop"
    [ "$MUTE" = "1" ] && MPVOPTS="$MPVOPTS no-audio"
    case "$MODE" in
        fill) MPVOPTS="$MPVOPTS panscan=1.0" ;;
        stretch) MPVOPTS="$MPVOPTS keepaspect=no" ;;
        center) MPVOPTS="$MPVOPTS video-unscaled=yes" ;;
    esac
    for o in "${!VID[@]}"; do
        out=$(mpvpaper -f -o "$MPVOPTS" "$o" "${VID[$o]}" 2>&1) || { echo "error: mpvpaper $o: ${out:-failed}"; st=1; }
    done
fi

# ── images/GIFs → swww (animated) or swaybg (static) ─────────────────────────
if [ "${#IMG[@]}" -gt 0 ]; then
    if [ "$IMGBACK" != "swaybg" ] && [ -n "$SWWW" ]; then
        if ! pgrep -f "$(basename "${SWWWD:-swww-daemon}")" >/dev/null 2>&1; then
            [ -n "$SWWWD" ] && "$SWWWD" >/dev/null 2>&1 &
            sleep 0.4
        fi
        pkill -x swaybg 2>/dev/null   # static backend no longer owns any output
        case "$MODE" in
            fit) RS=fit ;;
            stretch) RS=stretch ;;
            tile|center) RS=no ;;
            *) RS=crop ;;
        esac
        for o in "${!IMG[@]}"; do
            if [ "$o" = "*" ]; then args=(); else args=(-o "$o"); fi
            out=$("$SWWW" img "${IMG[$o]}" "${args[@]}" --resize "$RS" 2>&1) || { echo "error: ${IMGBACK} $o: ${out:-failed}"; st=1; }
        done
    elif have swaybg; then
        args=()
        for o in "${!IMG[@]}"; do
            if [ "$o" = "*" ]; then args+=(-i "${IMG[$o]}" -m "$MODE")
            else args+=(-o "$o" -i "${IMG[$o]}" -m "$MODE"); fi
        done
        pkill -x swaybg 2>/dev/null
        swaybg "${args[@]}" >/dev/null 2>&1 &
    else
        echo "error: no image wallpaper backend — install swww (sudo pacman -S awww) or swaybg"
        st=1
    fi
fi

exit "$st"
