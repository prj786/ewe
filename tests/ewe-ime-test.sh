#!/usr/bin/env bash
# ewe-ime: typing in other languages — the prefs through ewe-conf, what a
# computer without fcitx5 does with a synced ewe.conf, fcitx5's profile and
# config (the layout / Super+Space contract), the session env file, the
# Chromium/Electron flags blocks, start/stop (and the profile-on-exit race),
# the env push, the candidate theme in light and dark, absorb/import keeping
# [desktop.ime]. Everything runs against fakes on PATH and a fake /usr —
# never a real fcitx5, the live session bus, systemd or the shell.
set -u
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"
IME="$REPO/bin/ewe-ime"
CONFT="$REPO/bin/ewe-conf"
SB="$(mktemp -d)"
cleanup() { rm -rf "$SB"; }
trap cleanup EXIT
pass=0; failn=0
check() { if eval "$2"; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1"; fi; }
j() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2]))" "$1" "$2"; }

mkdir -p "$SB/bin" "$SB/usr/bin" "$SB/run" "$SB/cfg/ewe" "$SB/cfg/quickshell" "$SB/data" "$SB/state" "$SB/fx"
export HOME="$SB/home" XDG_CONFIG_HOME="$SB/cfg" XDG_RUNTIME_DIR="$SB/run" XDG_DATA_HOME="$SB/data" \
       XDG_STATE_HOME="$SB/state" XDG_CACHE_HOME="$SB/cache"
mkdir -p "$HOME"
export EWE_IME_ROOT="$SB/usr" EWE_IME_CONF="$CONFT" EWE_IME_NO_SCOPE=1
export WAYLAND_DISPLAY=wayland-test HYPRLAND_INSTANCE_SIGNATURE=test
unset DBUS_SESSION_BUS_ADDRESS XMODIFIERS QT_IM_MODULE QT_IM_MODULES SDL_IM_MODULE
LOG="$SB/log"; : > "$LOG"
FX="$SB/fx"            # the fake fcitx5's world: running, im

# ── fakes: every program that could reach the live session ─────────────────
for p in systemctl dbus-update-activation-environment busctl pkill qs hyprctl systemd-run fcitx5-configtool; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 0\n' "$p" "$LOG" > "$SB/bin/$p"
done
# fcitx5 -d: "starts" (a flag file); fcitx5-remote answers from it. -e is
# the real program's exit: it SAVES ITS PROFILE on the way out — the stale
# copy it had in memory — which apply must never leave behind.
cat > "$SB/bin/fcitx5" <<EOF
#!/bin/sh
echo "fcitx5 \$*" >> "$LOG"
cp "$XDG_CONFIG_HOME/fcitx5/profile" "$FX/profile.loaded" 2>/dev/null
echo 1 > "$FX/running"; echo keyboard-us > "$FX/im"
exit 0
EOF
cat > "$SB/bin/fcitx5-remote" <<EOF
#!/bin/sh
echo "fcitx5-remote \$*" >> "$LOG"
run=\$(cat "$FX/running" 2>/dev/null)
case "\$1" in
  --check) [ "\$run" = 1 ] ;;
  -e) if [ "\$run" = 1 ]; then cp "$FX/profile.loaded" "$XDG_CONFIG_HOME/fcitx5/profile" 2>/dev/null; echo 0 > "$FX/running"; fi ;;
  -n) [ "\$run" = 1 ] && cat "$FX/im" ;;
  -t) [ "\$run" = 1 ] || exit 1; if grep -q '^keyboard-' "$FX/im"; then echo pinyin > "$FX/im"; else echo keyboard-us > "$FX/im"; fi ;;
  -c) echo keyboard-us > "$FX/im" ;;
  *) [ "\$run" = 1 ] && echo 1 ;;
esac
EOF
chmod +x "$SB/bin"/*
export PATH="$SB/bin:/usr/bin:/bin"

install_core() {
    mkdir -p "$SB/usr/bin" "$SB/usr/lib/gtk-3.0/3.0.0/immodules" \
             "$SB/usr/lib/qt6/plugins/platforminputcontexts" "$SB/usr/share/fcitx5/inputmethod" \
             "$SB/usr/share/fcitx5/addon" "$SB/usr/share/m17n"
    : > "$SB/usr/bin/fcitx5"; : > "$SB/usr/bin/fcitx5-configtool"
    : > "$SB/usr/lib/gtk-3.0/3.0.0/immodules/im-fcitx5.so"
    : > "$SB/usr/lib/qt6/plugins/platforminputcontexts/libfcitx5platforminputcontextplugin.so"
}
conf() { XDG_CONFIG_HOME="$SB/cfg" "$CONFT" "$@"; }

# the tokens the theme reads (both variants, built by this checkout)
for s in ewe-dark ewe-light; do
    mkdir -p "$SB/tok-$s/ewe"
    printf '[desktop.theme]\nscheme = "%s"\n' "$s" > "$SB/tok-$s/ewe/ewe.conf"
    XDG_CONFIG_HOME="$SB/tok-$s" "$REPO/bin/ewe-theme" build --json "$SB/tok-$s/tokens.json" --css /dev/null >/dev/null 2>&1
done
cp "$SB/tok-ewe-dark/tokens.json" "$SB/cfg/quickshell/theme-tokens.json"
mkdir -p "$SB/cfg/quickshell/scripts"
ln -s "$REPO/dotfiles/quickshell/scripts/fcitx5-theme.sh" "$SB/cfg/quickshell/scripts/fcitx5-theme.sh"

# ── 1. a computer without fcitx5 ───────────────────────────────────────────
R="$("$IME" status)"; rc=$?
check "status exits 0 with JSON" "[ $rc = 0 ] && [ \"\$(j '$R' 'd[\"ok\"]')\" = True ]"
check "not installed, nothing on" "[ \"\$(j '$R' 'd[\"installed\"], d[\"on\"], d[\"enabled\"]')\" = '(False, False, False)' ]"
check "catalog: Chinese needs the core + chinese-addons" \
  "[ \"\$(j '$R' '[c[\"packages\"] for c in d[\"catalog\"] if c[\"id\"]==\"pinyin\"][0]')\" = \"['fcitx5', 'fcitx5-gtk', 'fcitx5-qt', 'fcitx5-configtool', 'fcitx5-chinese-addons']\" ]"
check "catalog: Japanese is Mozc (official repos)" "[ \"\$(j '$R' '[c[\"package\"] for c in d[\"catalog\"] if c[\"id\"]==\"mozc\"][0]')\" = fcitx5-mozc ]"
R="$("$IME" add pinyin)"
check "add without fcitx5: saved, not on" "[ \"\$(j '$R' 'd[\"enabled\"], d[\"on\"]')\" = '(True, False)' ]"
check "add without fcitx5: missing lists what to install" "[ \"\$(j '$R' 'd[\"missing\"]')\" = \"['fcitx5', 'fcitx5-gtk', 'fcitx5-qt', 'fcitx5-configtool', 'fcitx5-chinese-addons']\" ]"
check "ewe.conf holds [desktop.ime]" "[ \"\$(conf get desktop.ime)\" = '{\"enabled\": true, \"engines\": [\"pinyin\"]}' ]"
check "no env file, no fcitx5, no env push without fcitx5" \
  "[ ! -e '$SB/cfg/hypr/generated/ime.env' ] && ! grep -q '^fcitx5 ' '$LOG' && ! grep -q dbus-update '$LOG'"
check "no fcitx5 config written without fcitx5" "[ ! -e '$SB/cfg/fcitx5/profile' ]"

# ── 2. installed: on, the files, started, env pushed ───────────────────────
install_core
: > "$SB/usr/share/fcitx5/inputmethod/pinyin.conf"
: > "$SB/usr/bin/chromium"                       # a Chromium to give flags to
printf -- '--force-dark-mode\n' > "$SB/cfg/code-flags.conf"   # the user's own line
R="$("$IME" apply)"
check "apply: on" "[ \"\$(j '$R' 'd[\"on\"]')\" = True ]"
P="$SB/cfg/fcitx5/profile"
check "profile: one group on the first layout" "grep -qx 'Default Layout=us' '$P' && grep -qx 'DefaultIM=pinyin' '$P'"
check "profile: keyboard-us first, then pinyin, both following the group layout" \
  "[ \"\$(grep '^Name=' '$P' | tr '\n' ' ')\" = 'Name=Default Name=keyboard-us Name=pinyin ' ] && [ \"\$(grep -c '^Layout=\$' '$P')\" = 2 ]"
G="$SB/cfg/fcitx5/config"
check "config: Ctrl+Space toggles" "grep -qx '0=Control+space' '$G'"
check "config: Super+Space group keys cleared (Hyprland's)" \
  "awk '/^\\[Hotkey\\/EnumerateGroupForwardKeys\\]/{f=1;next} /^\\[/{f=0} f&&/=/{bad=1} END{exit bad}' '$G' && grep -qx '\\[Hotkey/EnumerateGroupBackwardKeys\\]' '$G' && ! grep -q 'Super' '$G'"
check "config: one state for all windows" "grep -qx 'ShareInputState=All' '$G'"
E="$SB/cfg/hypr/generated/ime.env"
check "ime.env: the four variables, no GTK_IM_MODULE" \
  "grep -qx 'XMODIFIERS=@im=fcitx' '$E' && grep -qx 'QT_IM_MODULE=fcitx' '$E' && grep -qx 'QT_IM_MODULES=wayland;fcitx' '$E' && grep -qx 'SDL_IM_MODULE=fcitx' '$E' && ! grep -q GTK_IM '$E'"
check "fcitx5 started as a daemon" "grep -q '^fcitx5 -d --replace' '$LOG'"
check "env pushed into systemd/D-Bus activation" "grep -q 'dbus-update-activation-environment --systemd XMODIFIERS=@im=fcitx QT_IM_MODULE=fcitx QT_IM_MODULES=wayland;fcitx SDL_IM_MODULE=fcitx' '$LOG'"
check "chromium-flags.conf gets the block" "grep -qx -- '--enable-wayland-ime' '$SB/cfg/chromium-flags.conf' && grep -qx -- '--wayland-text-input-version=3' '$SB/cfg/chromium-flags.conf'"
check "code-flags.conf keeps the user's line" "grep -qx -- '--force-dark-mode' '$SB/cfg/code-flags.conf' && grep -qx -- '--enable-wayland-ime' '$SB/cfg/code-flags.conf'"
check "no flags file for a browser that is not there" "[ ! -e '$SB/cfg/brave-flags.conf' ]"
check "candidate theme written (dark tokens)" \
  "grep -qx 'Color=#$(python3 -c "import json;print(json.load(open('$SB/tok-ewe-dark/tokens.json'))['color']['surface-overlay'].lstrip('#'))")' '$SB/data/fcitx5/themes/ewe/theme.conf' && grep -qx 'Theme=ewe' '$SB/cfg/fcitx5/conf/classicui.conf'"
R="$("$IME" status)"
check "status: on + running, needs sign-out (this session started without it)" "[ \"\$(j '$R' 'd[\"on\"], d[\"running\"], d[\"needs_signout\"]')\" = '(True, True, True)' ]"
: > "$LOG"
R="$("$IME" apply)"
check "apply again: nothing to do (no restart, no push, no re-theme)" "! grep -q '^fcitx5 ' '$LOG' && ! grep -q -- '-e' '$LOG' && ! grep -q dbus-update '$LOG' && ! grep -q busctl '$LOG'"

# ── 3. the bar's reading ───────────────────────────────────────────────────
R="$("$IME" current)"
check "current: plain layout → not active" "[ \"\$(j '$R' 'd[\"running\"], d[\"active\"], d[\"glyph\"]')\" = \"(True, False, '')\" ]"
R="$("$IME" toggle)"
check "toggle → pinyin, the bar's mark is 拼" "[ \"\$(j '$R' 'd[\"active\"], d[\"glyph\"], d[\"label\"]')\" = \"(True, '拼', 'Chinese — Pinyin')\" ]"

# ── 4. a second engine while running: stop, write, start (the exit race) ───
: > "$SB/usr/share/fcitx5/inputmethod/mozc.conf"
: > "$LOG"
R="$("$IME" add mozc)"
check "add mozc: fcitx5 stopped before the profile was written, then started" \
  "grep -n 'fcitx5-remote -e' '$LOG' | head -1 | grep -q . && grep -q '^fcitx5 -d' '$LOG'"
check "the profile is the new one, not fcitx5's saved copy" "grep -qx 'Name=mozc' '$P' && grep -qx 'Name=mozc' '$FX/profile.loaded'"
check "the env is not pushed twice" "! grep -q dbus-update '$LOG'"

# ── 5. the layout list changes: ewe-conf re-applies, fcitx5 follows ────────
: > "$LOG"
conf set --no-hooks desktop.input '{"kb_layout": "ru,us", "kb_variant": ",", "kb_options": ""}' >/dev/null 2>&1
check "first layout ru → group ru, keyboard-ru first" "grep -qx 'Default Layout=ru' '$P' && grep -qx 'Name=keyboard-ru' '$P'"
check "engines read Latin under a non-Latin layout (Layout=us)" "[ \"\$(grep -c '^Layout=us\$' '$P')\" = 2 ]"
check "fcitx5 restarted for the new group" "grep -q '^fcitx5 -d' '$LOG'"
conf set --no-hooks desktop.input '{"kb_layout": "de,us", "kb_variant": "nodeadkeys,", "kb_options": ""}' >/dev/null 2>&1
check "a variant: de-nodeadkeys, engines follow it (Latin)" "grep -qx 'Default Layout=de-nodeadkeys' '$P' && grep -qx 'Name=keyboard-de-nodeadkeys' '$P' && [ \"\$(grep -c '^Layout=\$' '$P')\" = 3 ]"
conf set --no-hooks desktop.input '{"kb_layout": "us", "kb_variant": "", "kb_options": ""}' >/dev/null 2>&1

# ── 6. absorb / import / validation keep [desktop.ime] ─────────────────────
conf absorb user-theme '{"accent": "#ff0000"}' --no-hooks >/dev/null 2>&1
check "absorb keeps [desktop.ime]" "[ \"\$(conf get desktop.ime.engines)\" = '[\"pinyin\", \"mozc\"]' ]"
conf import >/dev/null 2>&1
check "import keeps [desktop.ime]" "[ \"\$(conf get desktop.ime.enabled)\" = true ]"
conf set --no-hooks desktop.ime.engines '["bad id!"]' >/dev/null 2>&1; rc=$?
check "ewe-conf refuses a bad engine name" "[ $rc = 1 ] && [ \"\$(conf get desktop.ime.engines)\" = '[\"pinyin\", \"mozc\"]' ]"
conf set --no-hooks desktop.ime.enabled maybe >/dev/null 2>&1; rc=$?
check "ewe-conf refuses a non-boolean switch" "[ $rc = 1 ]"
R="$("$IME" add 'x;rm -rf /')"
check "add refuses an unknown language, JSON" "[ \"\$(j '$R' 'd[\"ok\"], d[\"code\"]')\" = \"(False, 'bad-id')\" ]"
R="$("$IME" frobnicate)"; rc=$?
check "unknown verb: ok false, exit 0" "[ $rc = 0 ] && [ \"\$(j '$R' 'd[\"code\"]')\" = bad-verb ]"

# ── 7. disable keeps the list; enable brings it back ───────────────────────
: > "$LOG"
R="$("$IME" disable)"
check "disable: off, list kept, fcitx5 stopped, env file gone" \
  "[ \"\$(j '$R' 'd[\"on\"], [e[\"id\"] for e in d[\"engines\"]]')\" = \"(False, ['pinyin', 'mozc'])\" ] && grep -q 'fcitx5-remote -e' '$LOG' && [ ! -e '$E' ]"
check "disable: env unset in systemd + emptied for D-Bus" \
  "grep -q 'systemctl --user unset-environment XMODIFIERS QT_IM_MODULE QT_IM_MODULES SDL_IM_MODULE' '$LOG' && grep -q 'dbus-update-activation-environment XMODIFIERS= ' '$LOG'"
R="$("$IME" enable)"
check "enable: on again" "[ \"\$(j '$R' 'd[\"on\"], d[\"running\"]')\" = '(True, True)' ] && [ -e '$E' ]"

# ── 8. the last one away turns it off — packages stay, said plainly ────────
"$IME" remove pinyin >/dev/null
: > "$LOG"
R="$("$IME" remove mozc)"
check "last removed: off and switched off in ewe.conf" "[ \"\$(j '$R' 'd[\"on\"], d[\"enabled\"]')\" = '(False, False)' ] && [ \"\$(conf get desktop.ime.enabled)\" = false ]"
check "says the programs stay installed" "j '$R' 'd[\"note\"]' | grep -q 'stay installed'"
check "nothing uninstalled" "[ -e '$SB/usr/bin/fcitx5' ] && ! grep -q pacman '$LOG'"
check "no fcitx5 process left" "[ \"\$(cat '$FX/running')\" = 0 ]"
check "flags blocks removed; a file that only held ours is gone" \
  "[ ! -e '$SB/cfg/chromium-flags.conf' ] && [ \"\$(cat '$SB/cfg/code-flags.conf')\" = '--force-dark-mode' ]"

# ── 9. a synced ewe.conf on a computer WITHOUT fcitx5 ──────────────────────
SB2="$SB/other"; mkdir -p "$SB2/cfg/ewe" "$SB2/usr" "$SB2/run"
printf '[desktop.ime]\nenabled = true\nengines = ["mozc", "m17n_hi_inscript2"]\n' > "$SB2/cfg/ewe/ewe.conf"
: > "$LOG"
R="$(XDG_CONFIG_HOME="$SB2/cfg" XDG_RUNTIME_DIR="$SB2/run" EWE_IME_ROOT="$SB2/usr" "$IME" apply)"
check "synced, not installed: nothing happens" \
  "[ \"\$(j '$R' 'd[\"on\"], d[\"did\"]')\" = '(False, [])' ] && [ ! -e '$SB2/cfg/hypr/generated/ime.env' ] && [ ! -s '$LOG' ]"
R="$(XDG_CONFIG_HOME="$SB2/cfg" XDG_RUNTIME_DIR="$SB2/run" EWE_IME_ROOT="$SB2/usr" "$IME" status)"
check "…and Settings learns what to install" \
  "[ \"\$(j '$R' 'd[\"missing\"]')\" = \"['fcitx5', 'fcitx5-gtk', 'fcitx5-qt', 'fcitx5-configtool', 'fcitx5-mozc', 'fcitx5-m17n']\" ]"
check "…labels for both" "[ \"\$(j '$R' '[e[\"label\"] for e in d[\"engines\"]]')\" = \"['Japanese — Mozc', 'Hindi — InScript']\" ]"
# start-hyprland.sh's reader ignores a stale ime.env when fcitx5 is gone
mkdir -p "$SB2/cfg/hypr/generated"; printf 'XMODIFIERS=@im=fcitx\n' > "$SB2/cfg/hypr/generated/ime.env"
OUT="$(env -i HOME="$SB2" XDG_CONFIG_HOME="$SB2/cfg" PATH=/usr/bin:/bin bash -c "
  $(sed -n '/^_ime_env=/,/^unset _ime_env/p' "$REPO/dotfiles/hypr/start-hyprland.sh")
  echo \"[\${XMODIFIERS:-}]\"")"
if command -v fcitx5 >/dev/null 2>&1; then
    check "(skipped: this machine has fcitx5)" "true"
else
    check "start-hyprland.sh: no fcitx5 → no IME env" "[ '$OUT' = '[]' ]"
fi
OUT="$(env -i HOME="$SB2" XDG_CONFIG_HOME="$SB2/cfg" PATH="$SB/bin:/usr/bin:/bin" bash -c "
  ln -sf /bin/true '$SB2/fcitx5' 2>/dev/null; PATH='$SB2':\$PATH
  $(sed -n '/^_ime_env=/,/^unset _ime_env/p' "$REPO/dotfiles/hypr/start-hyprland.sh")
  echo \"[\${XMODIFIERS:-}]\"")"
check "start-hyprland.sh: fcitx5 present → exported" "[ '$OUT' = '[@im=fcitx]' ]"

# ── 10. sign-in: the env came from start-hyprland.sh, nothing to push ───────
"$IME" add pinyin >/dev/null
SB3="$SB/login"; mkdir -p "$SB3/run" "$SB/login2/run"
: > "$LOG"
XDG_RUNTIME_DIR="$SB3/run" XMODIFIERS=@im=fcitx QT_IM_MODULE=fcitx QT_IM_MODULES='wayland;fcitx' SDL_IM_MODULE=fcitx \
    "$IME" apply --login >/dev/null
R="$(XDG_RUNTIME_DIR="$SB3/run" "$IME" status)"
check "sign-in with the env already set: no push, no sign-out asked" \
  "! grep -q 'dbus-update-activation-environment' '$LOG' && [ \"\$(j '$R' 'd[\"on\"], d[\"needs_signout\"]')\" = '(True, False)' ]"
XDG_RUNTIME_DIR="$SB/login2/run" "$IME" apply --login >/dev/null
R="$(XDG_RUNTIME_DIR="$SB/login2/run" "$IME" status)"
check "sign-in without it (ewe.conf synced while away): pushed, sign-out asked" \
  "grep -q 'dbus-update-activation-environment --systemd XMODIFIERS' '$LOG' && [ \"\$(j '$R' 'd[\"needs_signout\"]')\" = True ]"

# ── 11. the theme follows the variant (light) ───────────────────────────────
cp "$SB/tok-ewe-light/tokens.json" "$SB/cfg/quickshell/theme-tokens.json"
bash "$REPO/dotfiles/quickshell/scripts/fcitx5-theme.sh"
LIGHT_BG="$(python3 -c "import json;print(json.load(open('$SB/tok-ewe-light/tokens.json'))['color']['surface-overlay'].lstrip('#'))")"
LIGHT_FG="$(python3 -c "import json;print(json.load(open('$SB/tok-ewe-light/tokens.json'))['color']['text-primary'].lstrip('#'))")"
T="$SB/data/fcitx5/themes/ewe"
check "light: the card is the light surface, text the light ink" \
  "grep -qx 'Color=#$LIGHT_BG' '$T/theme.conf' && grep -qx 'NormalColor=#$LIGHT_FG' '$T/theme.conf' && grep -q 'fill=\"#$LIGHT_BG\"' '$T/panel.svg'"
check "no raw colour in the theme that is not a token" \
  "python3 - '$T/theme.conf' '$SB/tok-ewe-light/tokens.json' <<'PY'
import json, re, sys
toks = {v.lower()[-6:] for v in json.load(open(sys.argv[2]))['color'].values() if isinstance(v, str) and v.startswith('#')}
used = set(re.findall(r'#([0-9a-fA-F]{6})', open(sys.argv[1]).read()))
sys.exit(0 if used and used <= toks else 1)
PY"
check "font from the tokens (Geist)" "grep -q '^Font=\"Geist ' '$SB/cfg/fcitx5/conf/classicui.conf'"

echo "ewe-ime: $pass passed, $failn failed"
[ "$failn" = 0 ]
