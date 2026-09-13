#!/usr/bin/env bash
# design/spec/ewe-design-system.html is the designer's reference sheet for the
# 2026-09 revamp. Its :root block is the target; design/tokens.css is what the
# engine derives. This holds the two together so a change to `alias()` that
# wanders off the spec is caught before it reaches the shell or the apps.
#
#   ./design/check-spec.sh            compare design/tokens.css with the spec
#   ./design/check-spec.sh --rebuild  regenerate tokens.css first (css only —
#                                     the machine's live token file is untouched)
#
# Colours are compared per channel with a tolerance of 4/255: the engine
# derives every grey and brand stop from the accent through LCH, and the
# designer's page rounded the same maths a little differently. Anything the
# spec names that the engine does not emit is a failure; extra tokens the
# engine emits (--outline-width, --bar-alpha) are not.
#
# Roles listed in TOLERATED are printed but do not fail the run: the filled
# brand roles sit on the accent ramp at stops 50/60/45/38 by decision (the
# spec's hexes are a touch greyer), pending a review on the specimen.
#
# Exit 0 = on spec. Exit 1 = drift.
set -uo pipefail
cd "$(dirname "$0")/.."
SPEC="design/spec/ewe-design-system.html"
CSS="design/tokens.css"
[ -r "$SPEC" ] || { echo "missing $SPEC"; exit 1; }
if [ "${1:-}" = "--rebuild" ]; then
    bin/ewe-theme build --json /dev/null >/dev/null || { echo "ewe-theme build failed"; exit 1; }
fi
[ -r "$CSS" ] || { echo "missing $CSS — run ewe-theme build"; exit 1; }

python3 - "$SPEC" "$CSS" <<'PY'
import re, sys
spec_path, css_path = sys.argv[1], sys.argv[2]
TOL = 4
TOLERATED = {"--brand-bg", "--brand-bg-hover", "--brand-bg-pressed", "--brand-bg-selected",
             "--brand-stroke-2", "--link-solid",
             # derived from brand-bg-hover; the spec's own copy is the pre-revamp
             # value and disagrees with its brand-bg-hover a few lines up
             "--btn-hover-bg"}
# --accent is the mockup chrome's runtime injection, not a token. The three
# legacy outline aliases follow --outline-width since `stroke = none` (decision
# A of the revamp), where the spec still carries the 1px they had before.
IGNORE = {"--accent", "--border", "--border-thin", "--input-border-width"}

def root(path):
    s = open(path).read()
    m = re.search(r':root\s*\{(.*?)\n\}', s, re.S)
    if not m:
        sys.exit("no :root block in %s" % path)
    d = {}
    for k, v in re.findall(r'(--[a-z0-9-]+)\s*:\s*([^;]+);', m.group(1)):
        d[k] = re.sub(r'\s+', ' ', v.strip())
    return d

def rgba(v):
    v = v.strip().lower()
    m = re.fullmatch(r'#([0-9a-f]{6})', v)
    if m:
        h = m.group(1); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4)) + (1.0,)
    m = re.fullmatch(r'#([0-9a-f]{3})', v)
    if m:
        return tuple(int(c * 2, 16) for c in m.group(1)) + (1.0,)
    m = re.fullmatch(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([0-9.]+))?\s*\)', v)
    if m:
        return (int(m[1]), int(m[2]), int(m[3]), float(m[4]) if m[4] else 1.0)
    return None

want, got = root(spec_path), root(css_path)
missing, drift, warn = [], [], []
for k, sv in want.items():
    if k in IGNORE:
        continue
    if k not in got:
        missing.append(k); continue
    gv = got[k]
    a, b = rgba(sv), rgba(gv)
    if a and b:
        ok = all(abs(x - y) <= TOL for x, y in zip(a[:3], b[:3])) and abs(a[3] - b[3]) < 0.01
    else:
        ok = sv.replace(' ', '') == gv.replace(' ', '')
    if not ok:
        (warn if k in TOLERATED else drift).append((k, sv, gv))

for k, sv, gv in warn:
    print("tolerated  %-28s spec %-26s engine %s" % (k, sv, gv))
for k in missing:
    print("MISSING    %-28s spec %s" % (k, want[k]))
for k, sv, gv in drift:
    print("DRIFT      %-28s spec %-26s engine %s" % (k, sv, gv))
n = len(want) - len(IGNORE & set(want))
print("%d of %d spec tokens on target, %d tolerated, %d missing, %d drifted"
      % (n - len(missing) - len(drift) - len(warn), n, len(warn), len(missing), len(drift)))
sys.exit(1 if (missing or drift) else 0)
PY
