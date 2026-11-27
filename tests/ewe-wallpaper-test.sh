#!/usr/bin/env bash
# The first desktop has a wallpaper, and a wallpaper that is not on this
# computer never leaves a flat colour (2026-11-27).
#
#   1. dotfiles/hypr/scripts/wallpaper.sh — nothing configured, a `*` path
#      from another computer's home, a dead per-display path, a display with
#      no line of its own, a video without mpvpaper: each ends on a picture
#      (the user's default where there is one, else the wallpaper ewe ships),
#      never on `swaybg -c`. A valid choice is never replaced.
#   2. packaging/ewe-setup — a fresh account gets hypr/generated/
#      wallpapers.conf naming the shipped wallpaper, through ewe-conf and as
#      ONE key (no full import); a file that exists is left alone; a missing
#      file is written back from an ewe.conf that names a wallpaper; an
#      account deployed earlier is not written to (its picture is part 1).
#
# HERMETIC ON PURPOSE. wallpaper.sh runs `pkill -x swaybg|mpvpaper`, and
# ewe-setup runs colorscheme.sh (`pkill -USR1 kitty`, gsettings) and
# `systemctl --user` — on a desktop that is somebody's own session those
# would reach the real thing. So every script here runs under `env -i` with a
# PATH that holds ONLY a short list of plain tools (symlinks) and the fakes
# below: a tool that is not listed does not exist. Nothing outside the
# sandbox is read or signalled; no bus, no compositor.
# shellcheck disable=SC2015,SC2016  # `check && ok || no` reads as a table here
#                                     (ok/no never fail); the fakes' bodies are
#                                     sh source, meant to stay unexpanded
set -u
cd "$(dirname "$0")/.." || exit 1
REPO=$PWD
fail=0
ok() { echo "ok    $*"; }
no() { echo "FAIL  $*"; fail=1; }

for t in python3 readlink awk; do
    command -v "$t" >/dev/null 2>&1 || { echo "skip: needs $t"; exit 0; }
done

bash -n dotfiles/hypr/scripts/wallpaper.sh && ok "wallpaper.sh parses" || no "wallpaper.sh does not parse"
bash -n packaging/ewe-setup && ok "ewe-setup parses" || no "ewe-setup does not parse"

SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/run"
LOG="$SB/calls.log"

# ── the only tools that exist in there ───────────────────────────────────────
for t in bash sh env cat cp mv rm ln mkdir rmdir chmod touch date sed awk grep \
         find readlink realpath basename dirname head tail tr cut sort uniq wc \
         id cmp diff mktemp python3 install stat tee xargs true false ls expr \
         printf test uname; do
    p="$(command -v "$t" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$SB/bin/$t"
done

# ── the fakes: each one only writes down how it was called ───────────────────
fake() {   # fake <name> [body]
    { printf '#!/bin/sh\necho "%s $*" >> "$FAKE_LOG"\n' "$1"; [ $# -gt 1 ] && printf '%s\n' "$2"; } > "$SB/fakes/$1"
    chmod +x "$SB/fakes/$1"
}
mkdir -p "$SB/fakes"
fake swaybg
fake awww
fake awww-daemon
fake mpvpaper
fake pkill
fake sleep
# pgrep -x NAME / pgrep -f NAME: "running" only when the test says so
fake pgrep 'for a in "$@"; do n="$a"; done
case " ${FAKE_RUNNING:-} " in *" $n "*) exit 0 ;; esac
exit 1'
# hyprctl monitors: the displays the test plugs in
fake hyprctl '[ "$1" = monitors ] || exit 0
i=0; for m in ${FAKE_MONITORS:-}; do echo "Monitor $m (ID $i):"; i=$((i+1)); done'

# tools <name…>: put these fakes (and only these) on the sandbox PATH
tools() {
    local f
    for f in swaybg awww awww-daemon mpvpaper pkill pgrep sleep hyprctl; do rm -f "$SB/bin/$f"; done
    for f in pkill pgrep sleep hyprctl "$@"; do ln -sf "$SB/fakes/$f" "$SB/bin/$f"; done
}

# ── part 1: wallpaper.sh ─────────────────────────────────────────────────────
# A tree shaped like every install: the script under dotfiles/hypr/scripts,
# the shipped wallpaper under system/branding, ~/.config/hypr a link into it.
TREE="$SB/tree"
mkdir -p "$TREE/dotfiles/hypr/scripts" "$TREE/system/branding/wallpapers"
cp dotfiles/hypr/scripts/wallpaper.sh "$TREE/dotfiles/hypr/scripts/"
cp system/branding/wallpapers/ewe-dark.png "$TREE/system/branding/wallpapers/"
SHIPPED="$TREE/system/branding/wallpapers/ewe-dark.png"
H="$SB/home"; mkdir -p "$H/.config" "$H/Pictures"
ln -s "$TREE/dotfiles/hypr" "$H/.config/hypr"
CONF="$H/.config/hypr/generated/wallpapers.conf"
: > "$H/Pictures/mine.png"; : > "$H/Pictures/second.jpg"; : > "$H/Pictures/clip.mp4"
# the path the owner's desktop met: a file in another computer's home
ELSEWHERE="/home/someone-else/Downloads/Windows Vista Aurora Dreamscene 1080p 60FPS.webm"

OUT=""; RC=0
wp() {   # wp [args] — run the script; OUT = what it printed, RC = its exit
    : > "$LOG"
    OUT="$(env -i HOME="$H" PATH="$SB/bin" XDG_RUNTIME_DIR="$SB/run" FAKE_LOG="$LOG" \
              FAKE_MONITORS="${MONITORS:-DP-1}" FAKE_RUNNING="${RUNNING:-}" \
              bash "$H/.config/hypr/scripts/wallpaper.sh" "$@" 2>&1)"; RC=$?
    local i=0   # the backends are started with `&`: let their lines land
    while [ $i -lt 20 ] && [ "$(wc -l < "$LOG")" -lt "${EXPECT_LINES:-1}" ]; do
        i=$((i+1)); "$(command -v sleep)" 0.05
    done
}
conf() { mkdir -p "$(dirname "$CONF")"; printf '%s\n' "$@" > "$CONF"; }
called() { grep -qF -- "$1" "$LOG"; }
flat() { grep -q '^swaybg -c' "$LOG"; }

# 1 · nothing configured (a fresh account before anything wrote the file)
rm -f "$CONF"; tools awww awww-daemon swaybg mpvpaper
wp
called "awww img $SHIPPED -o DP-1 --resize crop" && ! flat && [ "$RC" = 0 ] \
    && ok "no wallpapers.conf: the shipped wallpaper, not a flat colour" \
    || no "no wallpapers.conf: expected the shipped wallpaper [rc=$RC] $(cat "$LOG")"
[ -z "$OUT" ] && ok "…and nothing to say about it" || no "a fresh account printed: $OUT"

# 2 · the `*` line names a file in another computer's home (synced ewe.conf)
conf "mode=fill" "mute=1" "*=$ELSEWHERE"
wp --reapply
called "awww img $SHIPPED -o DP-1 --resize crop" && ! flat && ! called "mpvpaper -f" \
    && ok "a path from another computer: the shipped wallpaper, no flat colour, no player" \
    || no "a path from another computer: $(cat "$LOG")"
case "$OUT" in
    "note: $ELSEWHERE is not on this computer — showing the default wallpaper instead") ok "…and one note names the missing file" ;;
    *) no "…the note reads: $OUT" ;;
esac
[ "$RC" = 0 ] && ok "…exit 0 (a note is not an error)" || no "…exit $RC"

# 3 · the same, on a machine with only swaybg
tools swaybg
wp --reapply
called "swaybg -o DP-1 -i $SHIPPED -m fill" && ! flat \
    && ok "swaybg only: it draws the shipped wallpaper (-i), not a colour (-c)" \
    || no "swaybg only: $(cat "$LOG")"

# 4 · a dead per-display path falls back to the user's own default
tools awww awww-daemon swaybg mpvpaper
conf "mode=fill" "*=$H/Pictures/mine.png" "DP-1=/gone/away.png"
wp --reapply
called "awww img $H/Pictures/mine.png -o DP-1 --resize crop" && ! called "$SHIPPED" \
    && ok "a dead per-display path: the user's default, not ewe's" \
    || no "a dead per-display path: $(cat "$LOG")"

# 5 · a valid choice is never replaced
conf "mode=fit" "*=$H/Pictures/mine.png" "HDMI-A-1=$H/Pictures/second.jpg"
MONITORS="DP-1 HDMI-A-1" EXPECT_LINES=3 wp --reapply
called "awww img $H/Pictures/mine.png -o DP-1 --resize fit" \
    && called "awww img $H/Pictures/second.jpg -o HDMI-A-1 --resize fit" \
    && ! called "$SHIPPED" && [ -z "$OUT" ] \
    && ok "valid choices are shown as chosen, with nothing said" \
    || no "valid choices: [$OUT] $(cat "$LOG")"

# 6 · a display with no line of its own and no `*`: the shipped one there
conf "mode=fill" "DP-1=$H/Pictures/mine.png"
MONITORS="DP-1 HDMI-A-1" EXPECT_LINES=3 wp --reapply
called "awww img $H/Pictures/mine.png -o DP-1 --resize crop" \
    && called "awww img $SHIPPED -o HDMI-A-1 --resize crop" \
    && ok "a display without a line: the shipped wallpaper there, the chosen one beside it" \
    || no "a display without a line: $(cat "$LOG")"

# 7 · a video that IS here, on a machine without mpvpaper: an error, and a picture
tools awww awww-daemon swaybg
conf "mode=fill" "*=$H/Pictures/clip.mp4"
wp --reapply
called "awww img $SHIPPED -o DP-1 --resize crop" && ! flat && [ "$RC" = 1 ] \
    && ok "a video without mpvpaper: the error stands (exit 1) and the display has a picture" \
    || no "a video without mpvpaper: [rc=$RC] $(cat "$LOG")"
case "$OUT" in *"error: a video wallpaper is set but mpvpaper is not installed"*) ok "…the error is said" ;; *) no "…printed: $OUT" ;; esac

# 8 · --backend stays one machine-read line, whatever the file says
tools awww awww-daemon swaybg mpvpaper
conf "*=$ELSEWHERE"
wp --backend
[ "$OUT" = "img=awww video=mpvpaper" ] && ok "--backend prints its one line only" || no "--backend printed: $OUT"

# 9 · login with everything already up does nothing (the shipped fallback included)
rm -f "$CONF"
RUNNING="awww-daemon" EXPECT_LINES=0 wp
! called "awww img" && ! called "swaybg" && [ "$RC" = 0 ] \
    && ok "a login with the daemon already up starts nothing" \
    || no "idempotent login: $(cat "$LOG")"

# 10 · no shipped wallpaper anywhere (a broken install): still never garbage
if [ -r /usr/share/ewe/system/branding/wallpapers/ewe-dark.png ]; then
    echo "skip  no-shipped-wallpaper case: this machine has the ewe package's copy in /usr/share/ewe"
else
    mv "$SHIPPED" "$SHIPPED.away"; tools awww awww-daemon swaybg mpvpaper
    conf "*=$ELSEWHERE"
    wp --reapply
    flat && ok "nothing to fall back to: the solid background, as before" || no "broken install: $(cat "$LOG")"
    mv "$SHIPPED.away" "$SHIPPED"
fi

# ── part 2: ewe-setup on a fresh account ─────────────────────────────────────
# The payload, as packaging/PKGBUILD lays it out under /usr/share/ewe.
PAY="$SB/payload"; mkdir -p "$PAY"
cp -a dotfiles systemd system packages phases lib templates docs bin plugins \
      install.sh update.sh uninstall.sh VERSION VERSIONS README.md LICENSE "$PAY/"
H2="$SB/home2"; mkdir -p "$H2"
tools   # none of the wallpaper backends: ewe-setup must not need them
setup() {
    env -i HOME="$H2" PATH="$SB/bin" XDG_RUNTIME_DIR="$SB/run" FAKE_LOG="$LOG" \
        EWE_PAYLOAD="$PAY" bash "$REPO/packaging/ewe-setup" > "$SB/setup.out" 2>&1
}
EWECONF2="$H2/.config/ewe/ewe.conf"
CONF2="$H2/.config/hypr/generated/wallpapers.conf"
# the read-only payload's copy: the same path on every packaged machine
WANT2="$PAY/system/branding/wallpapers/ewe-dark.png"

: > "$LOG"
setup && ok "ewe-setup runs on a fresh home" || no "ewe-setup failed: $(tail -5 "$SB/setup.out")"
if [ -r "$CONF2" ]; then
    line="$(grep '^\*=' "$CONF2")"
    [ "$line" = "*=$WANT2" ] && [ -r "${line#\*=}" ] \
        && ok "a fresh account has wallpapers.conf naming the shipped wallpaper (the payload's path)" \
        || no "wallpapers.conf says: $(cat "$CONF2")"
else
    no "a fresh account has no hypr/generated/wallpapers.conf: $(tail -5 "$SB/setup.out")"
fi
grep -q 'wallpaper could not be saved' "$SB/setup.out" && no "ewe-setup warned about the wallpaper" || ok "…without a warning"
# through ewe-conf (the one writer), and only that one key: a fresh machine
# must not hand its defaults for everything else to the account it syncs with
grep -q '^\[desktop\.wallpapers\]' "$EWECONF2" 2>/dev/null \
    && ok "…and ewe.conf holds the choice ([desktop.wallpapers])" || no "ewe.conf has no [desktop.wallpapers]: $(cat "$EWECONF2" 2>/dev/null)"
n="$(grep -c '^\[desktop\.' "$EWECONF2" 2>/dev/null)"
[ "$n" = 1 ] && ok "…as the only desktop key written (no full import)" || no "ewe.conf has $n [desktop.*] tables: $(grep '^\[' "$EWECONF2")"

# what the session then does with it (the deployed script, the deployed file)
tools awww awww-daemon swaybg mpvpaper
: > "$LOG"
env -i HOME="$H2" PATH="$SB/bin" XDG_RUNTIME_DIR="$SB/run" FAKE_LOG="$LOG" FAKE_MONITORS="DP-1" \
    bash "$H2/.config/hypr/scripts/wallpaper.sh" >/dev/null 2>&1
"$(command -v sleep)" 0.2
called "awww img $WANT2 -o DP-1 --resize crop" && ! flat \
    && ok "the first login draws it" || no "the first login: $(cat "$LOG")"

# a file that exists is the user's: a later sync leaves it — and ewe.conf — alone
tools
printf 'mode=fit\n*=%s\n' "$H2/Pictures/chosen.png" > "$CONF2"
cp "$CONF2" "$SB/chosen.conf"; cp "$EWECONF2" "$SB/before.conf"
setup
cmp -s "$CONF2" "$SB/chosen.conf" && cmp -s "$EWECONF2" "$SB/before.conf" \
    && ok "an existing wallpapers.conf survives a sync untouched, ewe.conf too" \
    || no "a sync rewrote something: $(cat "$CONF2"; diff "$SB/before.conf" "$EWECONF2")"

# ewe.conf names a wallpaper and the file is gone: written back from ewe.conf
rm -f "$CONF2"
setup
[ "$(grep '^\*=' "$CONF2" 2>/dev/null)" = "*=$WANT2" ] && cmp -s "$EWECONF2" "$SB/before.conf" \
    && ok "a missing file is written back from ewe.conf" || no "not written back: $(cat "$CONF2" 2>/dev/null)"

# an account deployed before this (no file, no wallpaper in ewe.conf), at a
# later sync: ewe.conf is NOT written to — the picture comes from
# wallpaper.sh's fallback (part 1), with no change to what the account syncs
python3 - "$EWECONF2" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r"(?ms)^# per-output wallpaper map[^\n]*\n\[desktop\.wallpapers\]\n.*?\n\n", "", s)
assert "[desktop.wallpapers]" not in s, s
open(p, "w").write(s)
PYEOF
cp "$EWECONF2" "$SB/old.conf"; rm -f "$CONF2"
setup
[ ! -e "$CONF2" ] && cmp -s "$EWECONF2" "$SB/old.conf" \
    && ok "an account deployed earlier is not written to at a later sync" \
    || no "a later sync wrote: $(cat "$CONF2" 2>/dev/null; diff "$SB/old.conf" "$EWECONF2")"
tools awww awww-daemon swaybg mpvpaper
: > "$LOG"
env -i HOME="$H2" PATH="$SB/bin" XDG_RUNTIME_DIR="$SB/run" FAKE_LOG="$LOG" FAKE_MONITORS="DP-1" \
    bash "$H2/.config/hypr/scripts/wallpaper.sh" >/dev/null 2>&1
"$(command -v sleep)" 0.2
called "awww img $H2/.local/share/ewe/system/branding/wallpapers/ewe-dark.png -o DP-1 --resize crop" && ! flat \
    && ok "…and its desktop still gets the shipped wallpaper (the script's own fallback)" \
    || no "…its desktop: $(cat "$LOG")"

# nothing a test may not touch was reached for
if grep -qE '^(systemctl|gsettings|busctl|dbus-send|qs) ' "$LOG" 2>/dev/null; then
    no "a session tool was reachable through the sandbox PATH: $(cat "$LOG")"
else
    ok "the sandbox PATH held (no session tool was reachable)"
fi

[ "$fail" = 0 ] && echo "all good" || echo "FAILED"
exit "$fail"
