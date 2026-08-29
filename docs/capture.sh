#!/usr/bin/env bash
# capture.sh — grab website/promo media from inside a running ewe session.
# Stills can't show motion, so the launcher/overview/notifications read far better
# as short GIFs. Run this ON the real desktop (it uses grim/wf-recorder/ffmpeg),
# not the test driver. Outputs land in docs/media/.
#
#   docs/capture.sh shot  <name>           full-output PNG          -> docs/media/<name>.png
#   docs/capture.sh region <name>          select a region (slurp)  -> docs/media/<name>.png
#   docs/capture.sh gif   <name> [secs]    record N s, make a GIF   -> docs/media/<name>.gif
#
# Deps: grim (shots), slurp (region), wf-recorder or gpu-screen-recorder (capture),
# ffmpeg (GIF). All but wf-recorder ship with the DE; install what's missing.
set -euo pipefail
OUT="$(cd "$(dirname "$0")" && pwd)/media"
mkdir -p "$OUT"
have() { command -v "$1" >/dev/null 2>&1; }

case "${1:-}" in
  shot)
    [ -n "${2:-}" ] || { echo "usage: capture.sh shot <name>"; exit 2; }
    have grim || { echo "need grim"; exit 1; }
    grim "$OUT/$2.png"; echo "wrote $OUT/$2.png" ;;
  region)
    [ -n "${2:-}" ] || { echo "usage: capture.sh region <name>"; exit 2; }
    have grim && have slurp || { echo "need grim + slurp"; exit 1; }
    grim -g "$(slurp)" "$OUT/$2.png"; echo "wrote $OUT/$2.png" ;;
  gif)
    name="${2:?usage: capture.sh gif <name> [seconds]}"; secs="${3:-6}"
    have ffmpeg || { echo "need ffmpeg for GIF conversion"; exit 1; }
    tmp="$(mktemp --suffix=.mp4)"
    echo "recording ${secs}s — interact now…"
    if have wf-recorder; then
      timeout "$secs" wf-recorder -f "$tmp" || true
    elif have gpu-screen-recorder; then
      timeout "$secs" gpu-screen-recorder -w screen -f 30 -o "$tmp" || true
    else
      echo "need wf-recorder or gpu-screen-recorder"; rm -f "$tmp"; exit 1
    fi
    # two-pass palette = clean, small GIF
    pal="$(mktemp --suffix=.png)"
    ffmpeg -y -i "$tmp" -vf "fps=18,scale=900:-1:flags=lanczos,palettegen" "$pal" >/dev/null 2>&1
    ffmpeg -y -i "$tmp" -i "$pal" -lavfi "fps=18,scale=900:-1:flags=lanczos[x];[x][1:v]paletteuse" "$OUT/$name.gif" >/dev/null 2>&1
    rm -f "$tmp" "$pal"
    echo "wrote $OUT/$name.gif" ;;
  *)
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
