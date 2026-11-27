#!/usr/bin/env bash
# The login screen's wrapper (system/greeter/ewe-greeter) — the ONE file every
# kind of install ends up running: phase 30 installs it, the ewe package
# refreshes it on every upgrade, the ISO's ewe-install copies it.
#
#   * the keyboards: XKB_DEFAULT_* from the machine's X11 keymap (the file the
#     ISO installer and localectl write) — one layout, several (Super+Space),
#     variants, no file, no layout, a value already in the environment;
#   * what it always did: the env cage and Qt need, software GL only in a VM,
#     the VT wiped and wlroots' chatter kept in a file, cage started even when
#     that file cannot be written;
#   * the ISO does not splice its own keyboard block into this file any more
#     (ewe-install skips a wrapper that already names XKB_DEFAULT_LAYOUT).
#
# Sealed like tests/ewe-wallpaper-test.sh: `env -i`, a PATH of a few plain
# tools and two fakes (cage, systemd-detect-virt). The keyboard file's path is
# absolute in the wrapper, so the test runs a copy with that one path pointed
# into the sandbox — and fails if the wrapper stops reading it (`_kb=<path>`).
# shellcheck disable=SC2015,SC2016  # `check && ok || no` reads as a table here
#                                     (ok/no never fail); the fakes' bodies are
#                                     sh source, meant to stay unexpanded
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
ok() { echo "ok    $*"; }
no() { echo "FAIL  $*"; fail=1; }

SRC=system/greeter/ewe-greeter
sh -n "$SRC" && ok "the wrapper parses as sh" || no "the wrapper does not parse"
[ "$(head -n 1 "$SRC")" = "#!/bin/sh" ] && ok "…and is a /bin/sh script" || no "the shebang changed: $(head -n 1 "$SRC")"

SB=$(mktemp -d); trap 'chmod -R u+w "$SB" 2>/dev/null; rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/etc" "$SB/cache"
for t in sh env sed head mkdir sort cat; do
    p="$(command -v "$t" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$SB/bin/$t"
done
cat > "$SB/bin/cage" <<'FAKE'
#!/bin/sh
echo "cage $*" >> "$FAKE_LOG"
env | sort > "$FAKE_ENV"
echo "wlroots chatter"          # stdout: must land in the log, not on the VT
echo "wlroots error chatter" >&2
FAKE
cat > "$SB/bin/systemd-detect-virt" <<'FAKE'
#!/bin/sh
[ "${FAKE_VM:-0}" = 1 ]
FAKE
chmod +x "$SB/bin/cage" "$SB/bin/systemd-detect-virt"

KB_REAL=/etc/X11/xorg.conf.d/00-keyboard.conf
KB="$SB/etc/00-keyboard.conf"
n="$(grep -cF "$KB_REAL" "$SRC")"
# once as the assignment the wrapper reads, and in its comments: point them all
sed "s|$KB_REAL|$KB|g" "$SRC" > "$SB/ewe-greeter"
grep -qxF "_kb=$KB" "$SB/ewe-greeter" && [ "$n" -ge 1 ] \
    && ok "the wrapper reads $KB_REAL (pointed into the sandbox for this test)" \
    || no "the keyboard file's path is not where the test expects it (_kb=…)"

LOG="$SB/cage.log"; ENVF="$SB/cage.env"; VT=""
greet() {   # greet [VAR=value…] — run the wrapper as greetd would; VT = what reached its stdout
    : > "$LOG"; rm -f "$ENVF" "$SB/cache/greeter.log" 2>/dev/null
    VT="$(env -i PATH="$SB/bin" XDG_CACHE_HOME="$SB/cache" FAKE_LOG="$LOG" FAKE_ENV="$ENVF" "$@" \
              sh "$SB/ewe-greeter" 2>&1)"
}
has() { grep -qxF -- "$1" "$ENVF" 2>/dev/null; }
lacks() { ! grep -q -- "^$1=" "$ENVF" 2>/dev/null; }
# the file as ewe-os's installer helper writes it (setkeymap), and as localectl does
iso_kb() {   # iso_kb <layouts> [variants]
    { printf '# Written by the ewe installer (keyboard screen) — localectl owns it now.\n'
      printf 'Section "InputClass"\n        Identifier "system-keyboard"\n        MatchIsKeyboard "on"\n'
      printf '        Option "XkbLayout" "%s"\n' "$1"
      [ -z "${2:-}" ] || printf '        Option "XkbVariant" "%s"\n' "$2"
      printf 'EndSection\n'; } > "$KB"
}

# 1 · no keyboard file: exactly what it always did
rm -f "$KB"; greet
grep -qxF 'cage -s -- sh -c qs -c ewe-greeter || regreet' "$LOG" \
    && ok "cage runs the greeter with ReGreet as its fallback" || no "cage was called as: $(cat "$LOG")"
has WLR_NO_HARDWARE_CURSORS=1 && has QT_QPA_PLATFORM=wayland && has QT_WAYLAND_DISABLE_WINDOWDECORATION=1 \
    && has XDG_CONFIG_DIRS=/etc/xdg && has "XDG_CACHE_HOME=$SB/cache" \
    && ok "the env cage and Qt need is set" || no "env: $(cat "$ENVF" 2>/dev/null)"
lacks XKB_DEFAULT_LAYOUT && lacks XKB_DEFAULT_VARIANT && lacks XKB_DEFAULT_OPTIONS \
    && ok "no keyboard file: no XKB_DEFAULT_* (libxkbcommon's default, as before)" || no "XKB set without a file: $(grep XKB "$ENVF")"
[ "$VT" = "$(printf '\033[H\033[2J\033[3J')" ] \
    && ok "the VT gets the wipe and nothing else" || no "the VT got: $(printf '%s' "$VT" | cat -v)"
grep -qx 'wlroots chatter' "$SB/cache/greeter.log" && grep -qx 'wlroots error chatter' "$SB/cache/greeter.log" \
    && ok "cage's stdout and stderr land in greeter.log" || no "greeter.log: $(cat "$SB/cache/greeter.log" 2>/dev/null)"

# 2 · one keyboard, as the installer writes it
iso_kb us; greet
has XKB_DEFAULT_LAYOUT=us && lacks XKB_DEFAULT_VARIANT && lacks XKB_DEFAULT_OPTIONS \
    && ok "one layout: XKB_DEFAULT_LAYOUT only" || no "us: $(grep XKB "$ENVF")"

# 3 · several: the first is where the screen starts, Super+Space switches
iso_kb us,ge; greet
has XKB_DEFAULT_LAYOUT=us,ge && has XKB_DEFAULT_OPTIONS=grp:win_space_toggle && lacks XKB_DEFAULT_VARIANT \
    && ok "two layouts: both, in order, with the Super+Space switch" || no "us,ge: $(grep XKB "$ENVF")"

# 4 · variants ride along, position for position
iso_kb us,ge ,qwerty; greet
has XKB_DEFAULT_LAYOUT=us,ge && has XKB_DEFAULT_VARIANT=,qwerty && has XKB_DEFAULT_OPTIONS=grp:win_space_toggle \
    && ok "variants are passed as written (,qwerty)" || no "us,ge ,qwerty: $(grep XKB "$ENVF")"

# 5 · the file as `localectl set-x11-keymap de pc105 nodeadkeys` leaves it
cat > "$KB" <<'CONF'
# Written by systemd-localed(8), read by systemd-localed and Xorg. It's
# probably wise not to edit this file manually. Use localectl(1) to
# update this file.
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "de"
        Option "XkbModel" "pc105"
        Option "XkbVariant" "nodeadkeys"
EndSection
CONF
greet
has XKB_DEFAULT_LAYOUT=de && has XKB_DEFAULT_VARIANT=nodeadkeys && lacks XKB_DEFAULT_OPTIONS \
    && ok "localectl's own file is read the same way" || no "localectl: $(grep XKB "$ENVF")"

# 6 · a file with no layout in it changes nothing
printf 'Section "InputClass"\n        Identifier "system-keyboard"\n        Option "XkbVariant" "nodeadkeys"\nEndSection\n' > "$KB"
greet
lacks XKB_DEFAULT_LAYOUT && lacks XKB_DEFAULT_VARIANT && lacks XKB_DEFAULT_OPTIONS \
    && ok "no layout in the file: nothing set (a variant alone means nothing)" || no "no layout: $(grep XKB "$ENVF")"

# 7 · what greetd's environment already says is left alone
iso_kb us,ge; greet XKB_DEFAULT_LAYOUT=fr
has XKB_DEFAULT_LAYOUT=fr && lacks XKB_DEFAULT_OPTIONS \
    && ok "a layout already in the environment wins" || no "preset: $(grep XKB "$ENVF")"

# 8 · software GL: a VM only, decided at run time
rm -f "$KB"; greet FAKE_VM=1
has WLR_RENDERER_ALLOW_SOFTWARE=1 && ok "in a VM: WLR_RENDERER_ALLOW_SOFTWARE=1" || no "VM: $(grep WLR "$ENVF")"
greet FAKE_VM=0
lacks WLR_RENDERER_ALLOW_SOFTWARE && ok "on metal: not set" || no "metal: $(grep WLR "$ENVF")"

# 9 · a log that cannot be written must not lock the login out
rm -f "$SB/cache/greeter.log"; chmod a-w "$SB/cache"
if [ -w "$SB/cache" ]; then
    echo "skip  unwritable-log case: this user can write anywhere (root?)"
else
    greet
    grep -q '^cage -s' "$LOG" && [ ! -e "$SB/cache/greeter.log" ] \
        && ok "an unwritable log: cage still starts (its chatter goes to /dev/null)" \
        || no "an unwritable log stopped the greeter: [$VT] $(cat "$LOG")"
    case "$VT" in *chatter*) no "…and the chatter reached the VT: $VT" ;; *) ok "…and the VT stays clean" ;; esac
fi
chmod u+w "$SB/cache"

# 10 · the ISO's ewe-install splices its keyboard block only into a wrapper
#      that has none (its test: the name XKB_DEFAULT_LAYOUT appears) — this
#      one has it, and the real exec line is still the ISO's anchor
grep -q 'XKB_DEFAULT_LAYOUT' "$SRC" && ok "ewe-install will not splice a second keyboard block into it" \
    || no "the wrapper no longer names XKB_DEFAULT_LAYOUT"
[ "$(grep -c '^exec cage ' "$SRC")" = 1 ] && [ "$(grep -c 'exec cage' "$SRC")" = 1 ] \
    && ok "'exec cage' appears once, as the last command (older ISOs anchor on it)" \
    || no "'exec cage' appears $(grep -c 'exec cage' "$SRC") times"

[ "$fail" = 0 ] && echo "all good" || echo "FAILED"
exit "$fail"
