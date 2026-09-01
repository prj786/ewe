#!/usr/bin/env bash
# Round-trip test for ewe-conf (RFC-001 Phase 1): import the runtime files
# into ewe.conf, apply back out, and require SEMANTIC equality for every
# Phase-1 domain. Runs entirely inside a throwaway XDG_CONFIG_HOME — never
# touches the real config. Usage: tests/ewe-conf-roundtrip.sh [src-qs-dir]
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-dotfiles/quickshell}"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export XDG_CONFIG_HOME="$SANDBOX"
mkdir -p "$SANDBOX/quickshell"

for f in user-theme.json pinned-apps.json places.json startup-apps.json \
         animations.json display-profiles.json window-rules.json; do
    if [ -e "$SRC/$f" ]; then
        cp "$SRC/$f" "$SANDBOX/quickshell/$f"
    elif [ -e "$SRC/$f.default" ]; then
        cp "$SRC/$f.default" "$SANDBOX/quickshell/$f"
    fi
done

# wallpapers.conf import source (live machine's, when present)
GEN_SRC="${EWE_TEST_GEN:-$HOME/.config/hypr/generated}"
if [ -e "$GEN_SRC/wallpapers.conf" ]; then
    mkdir -p "$SANDBOX/hypr/generated"
    cp "$GEN_SRC/wallpapers.conf" "$SANDBOX/hypr/generated/"
fi
for gl in input.lua user.lua; do
    if [ -e "$GEN_SRC/$gl" ]; then
        mkdir -p "$SANDBOX/hypr/generated"
        cp "$GEN_SRC/$gl" "$SANDBOX/hypr/generated/"
    fi
done

./bin/ewe-conf import >/dev/null
python3 -c "import tomllib,sys; tomllib.load(open('$SANDBOX/ewe/ewe.conf','rb'))" \
    && echo "ok  ewe.conf is valid TOML"

# snapshot originals, wipe, regenerate from the file alone
mkdir -p "$SANDBOX/orig"
cp "$SANDBOX"/quickshell/*.json "$SANDBOX/orig/"
rm "$SANDBOX"/quickshell/*.json
./bin/ewe-conf apply --no-hooks

python3 - "$SANDBOX" <<'EOF'
import json, os, sys
sb = sys.argv[1]
fail = 0
for f in sorted(os.listdir(os.path.join(sb, "orig"))):
    a = json.load(open(os.path.join(sb, "orig", f)))
    bp = os.path.join(sb, "quickshell", f)
    if not os.path.exists(bp):
        print(f"FAIL {f}: not regenerated"); fail = 1; continue
    b = json.load(open(bp))
    # dicts compare as SUBSET: apply may fill absent keys with defaults,
    # but every key the user had must survive unchanged
    same = all(b.get(k) == v for k, v in a.items()) if isinstance(a, dict) and isinstance(b, dict) else a == b
    if same:
        print(f"ok  {f} round-trips")
    else:
        print(f"FAIL {f}: semantic drift"); fail = 1
        for k in set(list(a) if isinstance(a, dict) else []) | set(list(b) if isinstance(b, dict) else []):
            if isinstance(a, dict) and a.get(k) != b.get(k):
                print(f"      {k}: {a.get(k)!r} -> {b.get(k)!r}")
sys.exit(fail)
EOF

# Phase 4: generated artifacts must be BYTE-identical to what the UIs wrote.
# Goldens come from this machine's real generated files when present.
GEN="${EWE_TEST_GEN:-$HOME/.config/hypr/generated}"
for g in animations.lua windowrules.lua wallpapers.conf input.lua user.lua; do
    if [ -e "$GEN/$g" ] && [ -e "$SANDBOX/hypr/generated/$g" ]; then
        if diff -q "$GEN/$g" "$SANDBOX/hypr/generated/$g" >/dev/null; then
            echo "ok  $g byte-identical to the live UI-generated file"
        else
            echo "FAIL $g differs from golden:"; diff "$GEN/$g" "$SANDBOX/hypr/generated/$g" | head -8; exit 1
        fi
    fi
done

# set/get semantics
./bin/ewe-conf set desktop.theme.accent '"#ff0000"' >/dev/null 2>&1 || ./bin/ewe-conf set desktop.theme.accent '#ff0000'
[ "$(./bin/ewe-conf get desktop.theme.accent)" = "#ff0000" ] && echo "ok  set/get"
python3 -c "import json; d=json.load(open('$SANDBOX/quickshell/user-theme.json')); assert d['accent']=='#ff0000'" \
    && echo "ok  set propagates to user-theme.json"
echo "ALL PASS"
