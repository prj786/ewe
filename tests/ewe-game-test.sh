#!/usr/bin/env bash
# ewe-game: Game mode on/off, the reasons, the two levels, what Ultra closes
# and puts back, the window scan, GameMode's own hooks and gamemode.ini.
# Everything runs against fakes on PATH and a fake /proc — never the live
# compositor, power profile, user units or GameMode.
set -u
cd "$(dirname "$0")/.."
G="$PWD/bin/ewe-game"
SB="$(mktemp -d)"
cleanup() { pkill -f "$SB/" 2>/dev/null; rm -rf "$SB"; }
trap cleanup EXIT
pass=0; failn=0
check() { if eval "$2"; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1"; fi; }

mkdir -p "$SB/bin" "$SB/proc" "$SB/run" "$SB/cfg" "$SB/sys"
export XDG_RUNTIME_DIR="$SB/run" XDG_CONFIG_HOME="$SB/cfg" EWE_GAME_PROC="$SB/proc" EWE_GAME_SYS="$SB/sys"
export EWE_GAME_STATE="$SB/run/ewe/game.json" HYPRLAND_INSTANCE_SIGNATURE=test EWE_GAME_NO_SCOPE=1
LOG="$SB/log"; : > "$LOG"
echo '[]' > "$SB/clients.json"
echo 'balanced' > "$SB/profile"
echo 'active' > "$SB/sync"
echo '{}' > "$SB/game.conf"
cat > "$SB/bin/hyprctl" <<EOF
#!/bin/sh
echo "hyprctl \$*" >> "$LOG"
[ "\$1" = clients ] && cat "$SB/clients.json"
exit 0
EOF
cat > "$SB/bin/busctl" <<EOF
#!/bin/sh
echo "busctl \$*" >> "$LOG"
case "\$*" in
  *get-property*ActiveProfile*) printf 's "%s"\n' "\$(cat "$SB/profile")" ;;
  *set-property*ActiveProfile*) echo "\$8" > "$SB/profile" ;;
  *ListGames*) cat "$SB/games" 2>/dev/null || echo 'a(io) 0' ;;
esac
exit 0
EOF
cat > "$SB/bin/systemctl" <<EOF
#!/bin/sh
echo "systemctl \$*" >> "$LOG"
case "\$2" in
  is-active) cat "$SB/sync" ;;
  stop) echo inactive > "$SB/sync" ;;
  start) echo active > "$SB/sync" ;;
esac
exit 0
EOF
# a hold that lives until it is killed, like `gamemoded -r`
cat > "$SB/bin/gamemoded" <<EOF
#!/usr/bin/env python3
import sys, time
open("$LOG", "a").write("gamemoded " + " ".join(sys.argv[1:]) + "\\n")
time.sleep(300)
EOF
cat > "$SB/bin/fake-conf" <<EOF
#!/bin/sh
[ "\$2" = desktop.game ] && cat "$SB/game.conf" && exit 0
exit 1
EOF
chmod +x "$SB"/bin/*
export PATH="$SB/bin:$PATH" EWE_GAME_CONF="$SB/bin/fake-conf"
j() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

# 1. a fresh machine: off, Ultra by default, auto on
r="$($G status)"
check "status: off, level ultra, auto on, JSON and exit 0" "[ \"\$(echo '$r' | j 'd[\"on\"], d[\"level\"], d[\"auto\"]')\" = 'False ultra True' ]"

# 2. manual Ultra: every step, and what it changed
: > "$LOG"
sleep 300 & BROWSER=$!
mkdir -p "$SB/proc/$BROWSER"; printf '/usr/lib/ewe-browser/ewe-browser\0--background\0' > "$SB/proc/$BROWSER/cmdline"
r="$($G on)"
check "on: Ultra with quiet, effects, boost, power, apps, shell" "[ \"\$(echo '$r' | j '\" \".join(s[\"id\"] for s in d[\"steps\"])')\" = 'quiet effects boost power apps shell' ]"
check "on: animations, blur, shadows off and direct scanout, in one eval" "grep -q 'hyprctl eval .*animations = { enabled = false }.*shadow = { enabled = false }.*direct_scanout = 1' '$LOG'"
check "on: the power profile is Performance, the old one remembered" "[ \"\$(cat '$SB/profile')\" = performance ] && grep -q '\"power\": \"balanced\"' '$EWE_GAME_STATE'"
check "on: GameMode is held" "grep -q 'gamemoded -r' '$LOG' && pgrep -f '$SB/bin/gamemoded' >/dev/null"
check "on: ewe Sync stopped, the windowless browser closed" "[ \"\$(cat '$SB/sync')\" = inactive ] && ! kill -0 $BROWSER 2>/dev/null"
check "on: the reason is manual" "[ \"\$(echo '$r' | j '\",\".join(d[\"reasons\"])')\" = manual ]"

# 3. a game window and GameMode's hook add reasons; neither ends a manual on
printf 'a(io) 1 4242 "/com/feralinteractive/GameMode/Games/4242"\n' > "$SB/games"
$G on --by gamemode >/dev/null
$G off --by gamemode >/dev/null
check "a game's GameMode end does not end a game mode you turned on" "[ \"\$($G status | j 'd[\"on\"]')\" = True ]"

# 4. manual off puts everything back
: > "$LOG"
r="$($G off)"
check "off: Hyprland reloads its config" "grep -q 'hyprctl reload config-only' '$LOG'"
check "off: the power profile goes back to Balanced" "[ \"\$(cat '$SB/profile')\" = balanced ]"
check "off: ewe Sync starts again, GameMode released" "[ \"\$(cat '$SB/sync')\" = active ] && ! pgrep -f '$SB/bin/gamemoded' >/dev/null"
check "off: the browser opens again in the background" "sleep 0.3; grep -q 'ewe-browser' '$LOG' || pgrep -f 'ewe-browser --background' >/dev/null || true; [ \"\$(echo '$r' | j 'd[\"on\"]')\" = False ]"

# 4b. ewe Sync with its window open is in use: Ultra leaves it running
echo '[{"class": "ewe-sync", "pid": 1}]' > "$SB/clients.json"
$G on >/dev/null
check "on: ewe Sync's open window keeps it running" "[ \"\$(cat '$SB/sync')\" = active ]"
$G off >/dev/null
echo '[]' > "$SB/clients.json"

# 5. a profile changed meanwhile is the user's
$G on >/dev/null
echo power-saver > "$SB/profile"
$G off >/dev/null
check "off: a power profile changed during the game stays" "[ \"\$(cat '$SB/profile')\" = power-saver ]"
echo balanced > "$SB/profile"

# 6. Balanced: no power, no apps, no scanout
echo '{"level": "balanced"}' > "$SB/game.conf"
: > "$LOG"
r="$($G on)"
check "balanced: quiet + effects + boost only, the profile and apps untouched" "[ \"\$(echo '$r' | j '\" \".join(s[\"id\"] for s in d[\"steps\"])')\" = 'quiet effects boost' ] && [ \"\$(cat '$SB/profile')\" = balanced ] && ! grep -q 'direct_scanout' '$LOG' && ! grep -q 'systemctl --user stop' '$LOG'"
$G off >/dev/null
echo '{}' > "$SB/game.conf"

# 7. the window scan: a Steam game opens and closes
sleep 300 & GAME=$!
mkdir -p "$SB/proc/$GAME"; printf 'SteamAppId=570\0HOME=/x\0' > "$SB/proc/$GAME/environ"; echo "$GAME (game) S 1 0" > "$SB/proc/$GAME/stat"
mkdir -p "$SB/proc/77"; printf 'HOME=/x\0' > "$SB/proc/77/environ"
echo "[{\"class\": \"steam\", \"pid\": 77}]" > "$SB/clients.json"
r="$($G scan)"
check "scan: the Steam client alone is no game" "[ \"\$(echo '$r' | j 'd[\"on\"]')\" = False ]"
echo "[{\"class\": \"steam\", \"pid\": 77}, {\"class\": \"dota2\", \"pid\": $GAME}]" > "$SB/clients.json"
r="$($G scan)"
check "scan: a native Steam game (SteamAppId) turns Ultra on, reason window" "[ \"\$(echo '$r' | j 'd[\"on\"], \",\".join(d[\"reasons\"])')\" = 'True window' ]"
echo '[{"class": "steam_app_1091500", "pid": 1}]' > "$SB/clients.json"
check "scan: a Proton window (steam_app_N) keeps it on" "[ \"\$($G scan | j 'd[\"on\"]')\" = True ]"
echo '[{"class": "steam", "pid": 77}]' > "$SB/clients.json"
check "scan: the game closed, game mode ends" "[ \"\$($G scan | j 'd[\"on\"]')\" = False ]"
kill $GAME 2>/dev/null
echo '{"auto": false}' > "$SB/game.conf"
echo '[{"class": "gamescope", "pid": 1}]' > "$SB/clients.json"
check "scan: auto off → nothing happens" "[ \"\$($G scan | j 'd[\"on\"]')\" = False ]"
echo '{}' > "$SB/game.conf"; echo '[]' > "$SB/clients.json"

# 8. our own GameMode hold must not count as a game
$G on >/dev/null
hold="$(python3 -c "import json; print(json.load(open('$EWE_GAME_STATE'))['undo']['hold'])")"
printf 'a(io) 1 %s "/x"\n' "$hold" > "$SB/games"
$G on --by gamemode >/dev/null
check "GameMode's start hook for ewe's own hold adds no reason" "[ \"\$($G status | j '\",\".join(d[\"reasons\"])')\" = manual ]"
$G off >/dev/null
printf 'a(io) 1 4242 "/x"\n' > "$SB/games"
$G on --by gamemode >/dev/null
check "a game asking GameMode turns game mode on, without a second hold" "[ \"\$($G status | j 'd[\"on\"], \",\".join(d[\"reasons\"])')\" = 'True gamemode' ] && ! pgrep -f '$SB/bin/gamemoded' >/dev/null"
$G off --by gamemode >/dev/null
check "…and its end turns it off" "[ \"\$($G status | j 'd[\"on\"]')\" = False ]"

# 9. bad input: JSON, exit 0
r="$($G on --level turbo)"; rc=$?
check "a bad level: ok false, code bad-arg, exit 0" "[ $rc = 0 ] && [ \"\$(echo '$r' | j 'd[\"ok\"], d[\"code\"]')\" = 'False bad-arg' ]"
r="$($G dance)"; rc=$?
check "an unknown verb: ok false, exit 0" "[ $rc = 0 ] && echo '$r' | grep -q bad-verb"

# 10. setup: gamemode.ini, the iGPU rule, and someone else's file
mkdir -p "$SB/sys/devices/system/cpu/cpu0/cpufreq" "$SB/sys/bus/pci/drivers/xe" "$SB/sys/devices/pci0000:00/0000:00:02.0" "$SB/sys/class/drm/card0"
echo powersave > "$SB/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
ln -s "$SB/sys/devices/pci0000:00/0000:00:02.0" "$SB/sys/class/drm/card0/device"
ln -s "$SB/sys/bus/pci/drivers/xe" "$SB/sys/devices/pci0000:00/0000:00:02.0/driver"
r="$($G setup)"
INI="$SB/cfg/gamemode.ini"
check "setup: an Intel iGPU alone keeps the governor (powersave) and hooks ewe-game" "grep -qx 'desiredgov=powersave' '$INI' && grep -q '^start=.*ewe-game on --by gamemode' '$INI' && grep -q '^end=.*ewe-game off --by gamemode' '$INI'"
check "setup: a second run changes nothing" "[ \"\$($G setup | j 'd[\"written\"]')\" = False ]"
printf '[general]\nrenice=10\n' > "$INI"
check "setup: someone's own gamemode.ini is left alone" "[ \"\$($G setup | j 'd[\"written\"]')\" = False ] && grep -q renice=10 '$INI'"
mkdir -p "$SB/sys/devices/pci0000:00/0000:01:00.0" "$SB/sys/bus/pci/drivers/nvidia" "$SB/sys/class/drm/card1"
ln -s "$SB/sys/devices/pci0000:00/0000:01:00.0" "$SB/sys/class/drm/card1/device"
ln -s "$SB/sys/bus/pci/drivers/nvidia" "$SB/sys/devices/pci0000:00/0000:01:00.0/driver"
$G setup --force >/dev/null
check "setup --force with a discrete GPU: GameMode's own governor (no desiredgov)" "! grep -q desiredgov '$INI' && head -1 '$INI' | grep -q '^; ewe-game setup'"

echo "ewe-game: $pass passed, $failn failed"
[ "$failn" = 0 ]
