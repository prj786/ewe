#!/usr/bin/env bash
# ewe.safe tests — no compositor, no safe. Four parts:
#   1. the manifest and entry points pass `ewe-plugin validate` (sandboxed)
#   2. logic.js in a real QML engine (qmltestrunner, offscreen)
#   3. the house rules over the QML: no raw colour / size / duration (rule
#      8), every call argv (never a shell), no password field (the master
#      password is never typed here — Safe PLAN.md S4), `reveal` only for
#      one-time codes (a password never enters the shell)
#   4. the fake `ewe-safe` the nested harness uses still speaks PROTOCOL.md
# EWE_REPO points at an ewe checkout (default ../ewe) for `ewe-plugin`.
set -euo pipefail
cd "$(dirname "$0")"

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf 'ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL  %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

# ── 1. validate ───────────────────────────────────────────────────────────
EWE_REPO="${EWE_REPO:-../ewe}"
if [ -x "$EWE_REPO/bin/ewe-plugin" ]; then
    mkdir -p "$SB/cfg" "$SB/state" "$SB/data" "$SB/run"
    v="$(XDG_CONFIG_HOME="$SB/cfg" XDG_STATE_HOME="$SB/state" XDG_DATA_HOME="$SB/data" XDG_RUNTIME_DIR="$SB/run" \
         HYPRLAND_INSTANCE_SIGNATURE='' WAYLAND_DISPLAY='' "$EWE_REPO/bin/ewe-plugin" validate . --first-party --json || true)"
    check "ewe-plugin validate" '[ "$(printf "%s" "$v" | python3 -c "import json,sys; print(json.load(sys.stdin).get(\"ok\"))")" = "True" ]'
else
    echo "skip  ewe-plugin validate (no $EWE_REPO/bin/ewe-plugin — set EWE_REPO)"
fi
check "keybind targets the plugin's own id" \
    'python3 -c "import json; m=json.load(open(\"manifest.json\")); assert all(k[\"ipc\"].split()[0]==m[\"id\"] for k in m[\"keybinds\"])"'

# ── 2. logic.js ───────────────────────────────────────────────────────────
# Qt 6's runner first: /usr/bin/qmltestrunner may be an older Qt's, which
# fails on Qt 6 imports without a word
QTR=/usr/lib/qt6/bin/qmltestrunner
[ -x "$QTR" ] || QTR="$(command -v qmltestrunner6 || command -v qmltestrunner || true)"
if [ -n "$QTR" ] && [ -x "$QTR" ]; then
    if QT_QPA_PLATFORM=offscreen timeout 60 "$QTR" -input tests/tst_logic.qml > "$SB/qtr.log" 2>&1; then
        ok "logic.js: $(grep -o 'Totals: [0-9]* passed' "$SB/qtr.log")"
    else
        bad "logic.js"; grep -E 'FAIL|Actual|Expected|Loc' "$SB/qtr.log" | head -20 || tail -5 "$SB/qtr.log"
    fi
else
    echo "skip  logic.js (no qmltestrunner)"
fi

# ── 3. the house rules over the QML ───────────────────────────────────────
qml=(*.qml)
check "no raw colours" '! grep -nE "#[0-9a-fA-F]{3,8}\b|Qt\.rgba?\(|\"(red|green|blue|white|black|gray|grey)\"" "${qml[@]}"'
check "no raw sizes" '! grep -nE "\b(width|height|radius|spacing|pixelSize|size|margins|leftMargin|rightMargin|topMargin|bottomMargin|implicitWidth|implicitHeight)\s*:\s*[0-9]+\s*($|;|\})" "${qml[@]}"'
check "no raw durations" '! grep -nE "\bduration\s*:\s*[0-9]+" "${qml[@]}"'
check "no shell in any command" '! grep -nE "\"(sh|bash|zsh)\"|\"-c\"|execDetached\(\[\"sh" "${qml[@]}" logic.js'
check "no password field (the master password is never typed here)" '! grep -nE "echoMode|TextInput\.Password|passwordCharacter" "${qml[@]}"'
check "reveal only for one-time codes" '[ "$(grep -c "\"reveal\"" logic.js)" = 1 ] && grep -q "\"reveal\", id, \"--field\", \"otp\"" logic.js && ! grep -n "\"reveal\"" "${qml[@]}"'
check "copies go through the daemon (no wl-copy here)" '! grep -n "wl-copy" "${qml[@]}" logic.js'

# ── 4. the fake still speaks the protocol ─────────────────────────────────
export FAKE_SAFE_DIR="$SB/fake"
F=tests/fake-ewe-safe
j() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
check "fake status: unlocked, 8 items" '[ "$($F status | j "d[\"locked\"], d[\"items\"]")" = "False 8" ]'
"$F" lock > /dev/null
check "fake lock → status locked, list refused" '[ "$($F status | j "d[\"locked\"]")" = True ] && [ "$($F list | j "d[\"error\"]")" = locked ]'
FAKE_UNLOCK_DELAY=0 "$F" unlock --ask > /dev/null
check "fake unlock → list" '[ "$($F list | j "len(d[\"items\"])")" = 8 ]'
check "fake reveal: one-time codes only" '[ "$($F reveal 4f9c0d1e-0000-4000-8000-000000000003 --field otp --json | j "d[\"value\"]")" = 481093 ] && [ "$($F reveal 4f9c0d1e-0000-4000-8000-000000000003 --field password --json | j "d[\"ok\"]")" = False ]'
timeout 2 "$F" watch > "$SB/watch.out" & wpid=$!
sleep 0.5; "$F" lock > /dev/null; sleep 0.6
printf '{"state":"error","message":"not signed in"}' > "$FAKE_SAFE_DIR/sync.json"; sleep 0.6
wait "$wpid" 2>/dev/null || true
check "fake watch: status, then locked, then sync" \
    '[ "$(python3 -c "import json; l=[json.loads(x) for x in open(\"$SB/watch.out\")]; print(\"set_up\" in l[0], l[1][\"event\"], l[2][\"event\"])")" = "True locked sync" ]'

printf '\newe.safe: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
