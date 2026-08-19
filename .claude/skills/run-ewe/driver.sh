#!/usr/bin/env bash
# ewe driver — launch & drive the Quickshell shell WITHOUT installing to
# the live session. It nests a throwaway Hyprland compositor on its own Wayland
# socket (aquamarine's Wayland backend), runs `qs -p dotfiles/quickshell` inside
# it, and screenshots that virtual output with grim. Nothing touches the host's
# real screen, and the host's running shell (if any) is left untouched.
#
# REQUIRES: an existing host Wayland session (WAYLAND_DISPLAY set) — aquamarine's
# headless backend can't grab a seat when logind already owns it, so we nest via
# the Wayland backend instead. On a truly headless box, start a parent compositor
# first (e.g. `cage`/`sway --headless`) and point WAYLAND_DISPLAY at it.
#
# Binaries: Hyprland, qs (quickshell), grim, hyprctl, luac.
#
# Usage:
#   driver.sh up                 # start nested compositor + shell, wait for load
#   driver.sh ipc <tgt> <fn> ..  # call a shell IpcHandler (settings|store|quicksettings|...)
#   driver.sh open <tgt> [png]   # toggle a surface, screenshot it (default: <tgt>.png)
#   driver.sh shot [png]         # screenshot current nested output (default: shell.png)
#   driver.sh targets            # list all IpcHandler targets/functions
#   driver.sh log                # tail the shell's qs log
#   driver.sh check              # luac -p the Hyprland Lua config (static syntax check)
#   driver.sh down               # tear everything down
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
QSDIR="$REPO/dotfiles/quickshell"
WORK="${HS_WORK:-/tmp/hs-driver}"
STATE="$WORK/state"
OUTDIR="${HS_OUT:-$WORK}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export AQ_DRM_DEVICES="${AQ_DRM_DEVICES:-/dev/dri/renderD128}"
mkdir -p "$WORK"

die()  { echo "driver: $*" >&2; exit 1; }
load() { [ -f "$STATE" ] && . "$STATE" || die "not up — run 'driver.sh up' first"; }

cmd_up() {
  # tear down any prior instance first — `up` is idempotent and never leaks an
  # orphaned nested compositor (the state file only tracks the most recent one).
  [ -f "$STATE" ] && cmd_down >/dev/null 2>&1
  [ -n "${WAYLAND_DISPLAY:-}" ] || die "no host WAYLAND_DISPLAY — need a parent Wayland session to nest into"
  command -v Hyprland >/dev/null || die "Hyprland not found"
  command -v qs >/dev/null       || die "qs (quickshell) not found"

  cat > "$WORK/hypr-min.conf" <<'EOF'
# minimal compositor just to host the shell — no autostart, no keybinds.
# The aquamarine Wayland-backend output is named WAYLAND-1; the wildcard rule
# pins ANY output to a sane size so screenshots are consistent (without it the
# nested output defaults to a tiny ~350x420 and panels render off-viewport).
monitor = , 1280x800@60, 0x0, 1
misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
    disable_watchdog_warning = true
    force_default_wallpaper = 0
}
EOF

  local before after sock
  before="$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null)"
  Hyprland --config "$WORK/hypr-min.conf" > "$WORK/hypr.log" 2>&1 &
  local hpid=$!
  # wait for the new wayland socket the nested compositor opens
  for _ in $(seq 1 30); do
    sleep 0.3
    after="$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null)"
    sock="$(comm -13 <(echo "$before") <(echo "$after") | grep -v '\.lock$' | head -1)"
    [ -n "$sock" ] && break
    kill -0 $hpid 2>/dev/null || die "nested Hyprland died — see $WORK/hypr.log"
  done
  [ -n "$sock" ] || die "nested compositor never opened a socket — see $WORK/hypr.log"
  local nestwd; nestwd="$(basename "$sock")"

  # Find the nested instance's signature so the shell (Quickshell.Hyprland) and
  # our hyprctl talk to the NESTED compositor, not the host. Without this the
  # nested qs inherits the host HYPRLAND_INSTANCE_SIGNATURE and would read/move
  # the host's real windows — fine for static panes, dangerous for Overview drag.
  local nestsig=""
  for _ in $(seq 1 20); do
    nestsig="$(HYPRLAND_INSTANCE_SIGNATURE= hyprctl instances -j 2>/dev/null \
      | python3 -c "import sys,json
try:
  print(next(i['instance'] for i in json.load(sys.stdin) if i.get('wl_socket')=='$nestwd'))
except Exception: pass" 2>/dev/null)"
    [ -n "$nestsig" ] && break
    sleep 0.2
  done
  [ -n "$nestsig" ] || die "could not resolve nested Hyprland instance signature"

  WAYLAND_DISPLAY="$nestwd" HYPRLAND_INSTANCE_SIGNATURE="$nestsig" QT_QPA_PLATFORM=wayland \
    qs -p "$QSDIR" > "$WORK/qs.log" 2>&1 &
  local qpid=$!
  for _ in $(seq 1 30); do
    sleep 0.3
    grep -q "Configuration Loaded" "$WORK/qs.log" 2>/dev/null && break
    kill -0 $qpid 2>/dev/null || die "qs died — see $WORK/qs.log"
  done

  { echo "HYPR_PID=$hpid"; echo "QS_PID=$qpid"; echo "NEST_WD=$nestwd"; echo "NEST_SIG=$nestsig"; } > "$STATE"
  echo "up: nested compositor on $nestwd (hypr pid $hpid, sig $nestsig), shell qs pid $qpid"
  echo "    config loaded — try: driver.sh open settings  |  driver.sh spawn foot"
}

cmd_ipc()     { load; WAYLAND_DISPLAY="$NEST_WD" qs ipc --pid "$QS_PID" call "$@"; }
cmd_targets() { load; WAYLAND_DISPLAY="$NEST_WD" qs ipc --pid "$QS_PID" show; }
cmd_shot()    { load; WAYLAND_DISPLAY="$NEST_WD" grim "$OUTDIR/${1:-shell.png}" && echo "wrote $OUTDIR/${1:-shell.png}"; }
cmd_log()     { tail -n "${1:-25}" "$WORK/qs.log"; }
cmd_hc()      { load; HYPRLAND_INSTANCE_SIGNATURE="$NEST_SIG" hyprctl "$@"; }
cmd_spawn()   { load; HYPRLAND_INSTANCE_SIGNATURE="$NEST_SIG" hyprctl dispatch exec "$*" >/dev/null && echo "spawned: $*"; }
cmd_check()   { command -v luac >/dev/null || die "luac not found"; ( cd "$REPO/dotfiles/hypr" && luac -p hyprland.lua colors.lua && echo "lua config: syntax OK" ); }

cmd_open() {
  load
  local tgt="$1" out="${2:-$1.png}"
  # NOTE: use `toggle`, not `show` — quickshell's `qs ipc call <tgt> show` collides
  # with the `ipc show` listing subcommand and just prints the target list. After
  # `up` every surface starts hidden, so toggle == open.
  WAYLAND_DISPLAY="$NEST_WD" qs ipc --pid "$QS_PID" call "$tgt" toggle
  sleep 2
  WAYLAND_DISPLAY="$NEST_WD" grim "$OUTDIR/$out" && echo "wrote $OUTDIR/$out"
  # close with `hide` (not a 2nd toggle — toggle can race) so the next open()/shot
  # starts from a hidden surface. The settle lets the close render before any
  # following screenshot.
  WAYLAND_DISPLAY="$NEST_WD" qs ipc --pid "$QS_PID" call "$tgt" hide >/dev/null 2>&1
  sleep 1
}

cmd_down() {
  [ -f "$STATE" ] && . "$STATE"
  [ -n "${QS_PID:-}" ]   && kill "$QS_PID"   2>/dev/null
  [ -n "${HYPR_PID:-}" ] && kill "$HYPR_PID" 2>/dev/null
  rm -f "$STATE"
  echo "down"
}

case "${1:-}" in
  up)      cmd_up ;;
  ipc)     shift; cmd_ipc "$@" ;;
  open)    shift; cmd_open "$@" ;;
  shot)    shift; cmd_shot "$@" ;;
  targets) cmd_targets ;;
  hc)      shift; cmd_hc "$@" ;;
  spawn)   shift; cmd_spawn "$@" ;;
  log)     shift; cmd_log "$@" ;;
  check)   cmd_check ;;
  down)    cmd_down ;;
  *) sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ; exit 1 ;;
esac
