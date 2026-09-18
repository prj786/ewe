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
#
# SANDBOX (default): the shell runs with HOME and every XDG_* dir under
# $HS_WORK/home, so it never reads or writes the live ~/.config (no live
# theme-tokens.json, ewe.conf, user-theme.json; ewe-conf and colorscheme.sh
# are not reachable, so no sync hook can push). `up` writes a sandbox ewe.conf
# and generates theme-tokens.json with THIS checkout's bin/ewe-theme:
#   HS_SCHEME=ewe-light          # [desktop.theme] scheme (default ewe-dark)
#   HS_CONF=<file>               # use this ewe.conf instead (HS_SCHEME ignored)
#   HS_WELCOME=1                 # let the first-run Welcome screen appear
#   HS_SANDBOX=0                 # old behaviour: the live HOME and config
#
# PARALLEL RUNS: HS_WORK=<dir> gives a run its own state, sandbox and logs
# (default /tmp/hs-driver — two checkouts driving at once must not share it).
# The nested compositor is a window on the HOST, so when two runs are up the
# host tiles them and each output shrinks (892x539 instead of 1920x1200).
# HS_HEADLESS=1 swaps the window's output for a headless 1920x1200 one (SHOT)
# before the shell starts, so screenshots keep their size whatever the host
# does with the window (the window itself then shows nothing).
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
QSDIR="$REPO/dotfiles/quickshell"
WORK="${HS_WORK:-/tmp/hs-driver}"
STATE="$WORK/state"
OUTDIR="${HS_OUT:-$WORK}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export AQ_DRM_DEVICES="${AQ_DRM_DEVICES:-/dev/dri/renderD128}"
# the nested shell tests THIS checkout's ewe-plugin, not the installed one
# (PluginHost.qml honours the override); reads real ~/.config/ewe/plugins
export EWE_PLUGIN_TOOL="${EWE_PLUGIN_TOOL:-$REPO/bin/ewe-plugin}"
mkdir -p "$WORK"
SANDBOX="${HS_SANDBOX:-1}"
SBHOME="$WORK/home"

die()  { echo "driver: $*" >&2; exit 1; }
load() { [ -f "$STATE" ] && . "$STATE" || die "not up — run 'driver.sh up' first"; }

# the sandbox: a throwaway HOME whose fontconfig is this checkout's (so the
# shipped Geist fonts resolve) and whose theme-tokens.json is generated here
sandbox_env() {
  [ "$SANDBOX" = "1" ] || return 0
  export HOME="$SBHOME" XDG_CONFIG_HOME="$SBHOME/.config" XDG_DATA_HOME="$SBHOME/.local/share" \
         XDG_STATE_HOME="$SBHOME/.local/state" XDG_CACHE_HOME="$SBHOME/.cache"
}
sandbox_prepare() {
  if [ "$SANDBOX" != "1" ]; then
    echo "driver: HS_SANDBOX=0 — the shell reads the LIVE ~/.config" >&2
    return 0
  fi
  rm -rf "$SBHOME"
  mkdir -p "$SBHOME/.config/quickshell" "$SBHOME/.config/ewe" "$SBHOME/.local/share" \
           "$SBHOME/.local/state" "$SBHOME/.cache"
  # Welcome shows once per fresh state dir and covers every screenshot;
  # HS_WELCOME=1 leaves the stamp off so it does appear.
  [ "${HS_WELCOME:-0}" = "1" ] || { mkdir -p "$SBHOME/.local/state/ewe"; : > "$SBHOME/.local/state/ewe/welcomed"; }
  ln -s "$REPO/dotfiles/fontconfig" "$SBHOME/.config/fontconfig"
  # fontconfig's relative <dir> resolves beside the linked fontconfig dir
  ln -s "$REPO/dotfiles/quickshell/fonts" "$SBHOME/.config/quickshell/fonts"
  if [ -n "${HS_CONF:-}" ]; then
    cp "$HS_CONF" "$SBHOME/.config/ewe/ewe.conf" || die "HS_CONF $HS_CONF unreadable"
  else
    printf '[desktop.theme]\nscheme = "%s"\n' "${HS_SCHEME:-ewe-dark}" > "$SBHOME/.config/ewe/ewe.conf"
  fi
  ( sandbox_env
    "$REPO/bin/ewe-theme" build --json "$XDG_CONFIG_HOME/quickshell/theme-tokens.json" --css /dev/null >"$WORK/theme.log" 2>&1
  ) || die "ewe-theme build failed — see $WORK/theme.log"
  echo "sandbox: $SBHOME ($(python3 -c "import json,sys;j=json.load(open(sys.argv[1]));print(j['input']['scheme'])" "$SBHOME/.config/quickshell/theme-tokens.json"))"
}

cmd_up() {
  # tear down any prior instance first — `up` is idempotent and never leaks an
  # orphaned nested compositor (the state file only tracks the most recent one).
  [ -f "$STATE" ] && cmd_down >/dev/null 2>&1
  [ -n "${WAYLAND_DISPLAY:-}" ] || die "no host WAYLAND_DISPLAY — need a parent Wayland session to nest into"
  command -v Hyprland >/dev/null || die "Hyprland not found"
  command -v qs >/dev/null       || die "qs (quickshell) not found"
  sandbox_prepare

  cat > "$WORK/hypr-min.lua" <<'EOF'
-- minimal compositor just to host the shell — no autostart, no keybinds.
-- Lua, not .conf: the .conf format warns (and dies in 0.57), and the banner
-- polluted every screenshot. The aquamarine Wayland-backend output is named
-- WAYLAND-1; the wildcard rule pins ANY output to a sane size so screenshots
-- are consistent (without it the nested output defaults to a tiny ~350x420
-- and panels render off-viewport).
hl.monitor({ output = "", mode = "1920x1200@60", position = "0x0", scale = 1 })
hl.config({
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        disable_watchdog_warning = true,
        force_default_wallpaper = 0,
    },
})
EOF
  # HS_EXTRA_LUA=<file>: appended to the nested config — e.g. the glass blur
  # block from `ewe-conf`'s GLASS_LUA, to see translucent panels for real
  [ -n "${HS_EXTRA_LUA:-}" ] && [ -f "$HS_EXTRA_LUA" ] && cat "$HS_EXTRA_LUA" >> "$WORK/hypr-min.lua"
  # HS_HEADLESS: the SHOT output's place, beside the window's output
  [ "${HS_HEADLESS:-0}" = "1" ] && echo 'hl.monitor({ output = "SHOT", mode = "1920x1200@60", position = "1920x0", scale = 1 })' >> "$WORK/hypr-min.lua"

  local before after sock
  before="$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null)"
  Hyprland --config "$WORK/hypr-min.lua" > "$WORK/hypr.log" 2>&1 &
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

  # HS_HEADLESS=1: a headless SHOT output replaces the window's own, BEFORE
  # the shell starts (it binds its windows to the screens it sees at load)
  local shotout=""
  if [ "${HS_HEADLESS:-0}" = "1" ]; then
    HYPRLAND_INSTANCE_SIGNATURE="$nestsig" hyprctl output create headless SHOT >/dev/null 2>&1
    sleep 0.5
    HYPRLAND_INSTANCE_SIGNATURE="$nestsig" hyprctl eval 'hl.monitor({ output = "WAYLAND-1", disabled = true })' >/dev/null 2>&1
    sleep 0.5
    shotout=SHOT
  fi

  # HS_PRIVATE_BUS=1: run the shell on its OWN session D-Bus (dbus-run-session).
  # The nested shell otherwise shares the host session bus + keyring, so panels
  # fill with the real user's calendar/mail/MPRIS/tray — exactly what must NOT
  # be in a README screenshot. A private bus renders every pane signed-out/empty.
  local qs_wrap=()
  [ "${HS_PRIVATE_BUS:-0}" = "1" ] && command -v dbus-run-session >/dev/null && qs_wrap=(dbus-run-session --)
  ( sandbox_env
    exec env WAYLAND_DISPLAY="$nestwd" HYPRLAND_INSTANCE_SIGNATURE="$nestsig" QT_QPA_PLATFORM=wayland \
      "${qs_wrap[@]}" qs -p "$QSDIR" ) > "$WORK/qs.log" 2>&1 &
  local qpid=$!
  for _ in $(seq 1 30); do
    sleep 0.3
    grep -q "Configuration Loaded" "$WORK/qs.log" 2>/dev/null && break
    kill -0 $qpid 2>/dev/null || die "qs died — see $WORK/qs.log"
  done

  # under dbus-run-session, $qpid is the wrapper — qs ipc needs the REAL qs pid
  local qwrap=""
  if [ ${#qs_wrap[@]} -gt 0 ]; then
    qwrap=$qpid
    for _ in $(seq 1 20); do
      local real; real="$(pgrep -P "$qpid" -x qs 2>/dev/null | head -1)"
      [ -n "$real" ] && { qpid=$real; break; }
      sleep 0.2
    done
  fi
  { echo "HYPR_PID=$hpid"; echo "QS_PID=$qpid"; echo "QS_WRAP_PID=$qwrap"; echo "NEST_WD=$nestwd"; echo "NEST_SIG=$nestsig"; echo "SHOT_OUT=$shotout"; } > "$STATE"
  echo "up: nested compositor on $nestwd (hypr pid $hpid, sig $nestsig), shell qs pid $qpid"
  echo "    config loaded — try: driver.sh open settings  |  driver.sh spawn foot"
}

cmd_ipc()     { load; WAYLAND_DISPLAY="$NEST_WD" qs ipc --pid "$QS_PID" call "$@"; }
cmd_targets() { load; WAYLAND_DISPLAY="$NEST_WD" qs ipc --pid "$QS_PID" show; }
cmd_shot()    { load; WAYLAND_DISPLAY="$NEST_WD" grim ${SHOT_OUT:+-o "$SHOT_OUT"} "$OUTDIR/${1:-shell.png}" && echo "wrote $OUTDIR/${1:-shell.png}"; }
cmd_log()     { tail -n "${1:-25}" "$WORK/qs.log"; }
cmd_hc()      { load; HYPRLAND_INSTANCE_SIGNATURE="$NEST_SIG" hyprctl "$@"; }
# Hyprland 0.56 (Lua config) rejects the old `dispatch exec <cmd>` form: a
# dispatch is a Lua expression, so the command goes in as a Lua string
# (backslashes and double quotes escaped).
cmd_spawn()   {
  load
  local cmd="$*"; cmd="${cmd//\\/\\\\}"; cmd="${cmd//\"/\\\"}"
  HYPRLAND_INSTANCE_SIGNATURE="$NEST_SIG" hyprctl dispatch "hl.dsp.exec_cmd(\"$cmd\")" >/dev/null && echo "spawned: $*"
}
cmd_check()   { command -v luac >/dev/null || die "luac not found"; ( cd "$REPO/dotfiles/hypr" && luac -p hyprland.lua colors.lua && echo "lua config: syntax OK" ); }

cmd_open() {
  load
  local tgt="$1" out="${2:-$1.png}"
  # NOTE: use `toggle`, not `show` — quickshell's `qs ipc call <tgt> show` collides
  # with the `ipc show` listing subcommand and just prints the target list. After
  # `up` every surface starts hidden, so toggle == open.
  WAYLAND_DISPLAY="$NEST_WD" qs ipc --pid "$QS_PID" call "$tgt" toggle
  sleep 2
  WAYLAND_DISPLAY="$NEST_WD" grim ${SHOT_OUT:+-o "$SHOT_OUT"} "$OUTDIR/$out" && echo "wrote $OUTDIR/$out"
  # close with `hide` (not a 2nd toggle — toggle can race) so the next open()/shot
  # starts from a hidden surface. The settle lets the close render before any
  # following screenshot.
  WAYLAND_DISPLAY="$NEST_WD" qs ipc --pid "$QS_PID" call "$tgt" hide >/dev/null 2>&1
  sleep 1
}

cmd_down() {
  [ -f "$STATE" ] && . "$STATE"
  [ -n "${QS_WRAP_PID:-}" ] && kill "$QS_WRAP_PID" 2>/dev/null
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
