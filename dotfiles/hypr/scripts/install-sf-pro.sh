#!/usr/bin/env bash
# install-sf-pro.sh — fetch the SF Pro (Display + Text) OTFs into the
# per-user font dir. No root needed. These font files have a proprietary license
# (free to install for personal use); we mirror the weights a UI shell
# actually uses. Re-runnable: skips files already present.
set -u

DEST="$HOME/.local/share/fonts/sf-pro"
BASE="https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master"
WEIGHTS=(Thin Light Regular Medium Semibold Bold Heavy)
FAMILIES=(Display Text)

mkdir -p "$DEST"
ok=0; fail=0
for fam in "${FAMILIES[@]}"; do
    for w in "${WEIGHTS[@]}"; do
        f="SF-Pro-${fam}-${w}.otf"
        out="$DEST/$f"
        [ -s "$out" ] && { ok=$((ok+1)); continue; }
        if curl -fsSL "$BASE/$f" -o "$out" 2>/dev/null && [ -s "$out" ]; then
            ok=$((ok+1))
        else
            rm -f "$out"; fail=$((fail+1)); echo "  ! missing upstream: $f"
        fi
    done
done
echo ":: SF Pro: $ok installed, $fail skipped/missing → $DEST"
fc-cache -f "$DEST" >/dev/null 2>&1
echo ":: families now visible:"
fc-list | grep -i "SF Pro" | sed 's/.*: //' | sort -u
