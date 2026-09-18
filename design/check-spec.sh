#!/usr/bin/env bash
# design/system/tokens.json (the Ewe design system, version 3) is the
# reference; bin/ewe-theme DERIVES the token set from the two built-in
# schemes. This holds the two together: it builds the CSS for ewe-dark and
# ewe-light from the defaults and compares every token in tokens.json with
# what the engine emitted, so a change to the derivation that wanders off
# the design system is caught before it reaches the shell or the apps.
#
#   ./design/check-spec.sh            compare (builds into a temp dir; the
#                                     committed design/tokens.css and the
#                                     machine's live token file are untouched)
#
# Colours are compared per channel with a tolerance of 4/255 (and 0.02 in
# alpha): the engine derives every role through OKLCH and the design sheet
# rounded the same maths a little differently. A translucent colour only
# reaches the screen weighted by its alpha, so its channel difference is
# weighed by it too (|spec - engine| x alpha <= 4/255 — what is actually
# painted over any background). The colours inside shadows and gradients
# are compared the same way, stop by stop; everything else in them (offsets,
# blur, angle, stop positions) and all sizes, weights and radii must match
# exactly. Gradients are one value on the sheet, the default dark scheme's,
# so they are compared in the dark build only (in a light scheme night and
# ember follow its light surfaces). Anything tokens.json names that the
# engine does not emit is a failure; extra tokens the engine emits (the
# Fluent aliases, --bar-alpha) are not. The type styles are checked as
# classes (.body, .label …): size, line height, weight, tracking, italic.
#
# Nothing is tolerated. The light scrim and light shadows are the scheme's
# darkest ink (base05, #0b0a08) where the sheet writes rgba(20, 16, 8, a):
# 9/255 apart in red, which at 32% (scrim) and 8-10% (shadows) is under
# 3/255 on screen — inside the tolerance above. The engine keeps one ink
# instead of a second near-black.
#
# Exit 0 = on spec. Exit 1 = drift.
set -uo pipefail
cd "$(dirname "$0")/.."
SPEC="design/system/tokens.json"
[ -r "$SPEC" ] || { echo "missing $SPEC"; exit 1; }
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
export XDG_CONFIG_HOME="$SB/cfg" XDG_STATE_HOME="$SB/state" HOME="$SB/home"
mkdir -p "$SB/cfg/ewe" "$SB/home"
bin/ewe-theme build --json /dev/null --css "$SB/dark.css" --scheme ewe-dark >/dev/null \
    || { echo "ewe-theme build (ewe-dark) failed"; exit 1; }
bin/ewe-theme build --json /dev/null --css "$SB/light.css" --scheme ewe-light --selector ':root[data-theme="light"]' >/dev/null \
    || { echo "ewe-theme build (ewe-light) failed"; exit 1; }
# the committed file must be the ewe-dark default build, byte for byte
if ! cmp -s design/tokens.css "$SB/dark.css"; then
    echo "DRIFT      design/tokens.css is not the current ewe-dark build — run bin/ewe-theme build --json /dev/null"
    stale=1
else
    stale=0
fi

python3 - "$SPEC" "$SB/dark.css" "$SB/light.css" <<'PY' || exit 1
import json, re, sys
spec_path, dark_css, light_css = sys.argv[1:4]
TOL, ATOL = 4, 0.02
TOLERATED = set()                 # see the header: nothing is
spec = json.load(open(spec_path))

def block(path, sel):
    s = open(path).read()
    m = re.search(re.escape(sel) + r'\s*\{(.*?)\n\}', s, re.S)
    if not m:
        sys.exit("no %s block in %s" % (sel, path))
    d = {}
    for k, v in re.findall(r'(--[a-z0-9-]+)\s*:\s*([^;]+);', m.group(1)):
        d[k] = re.sub(r'\s+', ' ', v.strip())
    for k, v in d.items():          # --accent: var(--accent-default) compares as its value
        while re.fullmatch(r'var\((--[a-z0-9-]+)\)', v or ""):
            v = d.get(re.fullmatch(r'var\((--[a-z0-9-]+)\)', v).group(1), "")
        d[k] = v
    classes = {}
    for name, body in re.findall(r'\n\.([a-z0-9-]+)\s*\{([^}]*)\}', s):
        classes[name] = dict((a.strip(), b.strip()) for a, b in
                             (x.split(":", 1) for x in body.split(";") if ":" in x))
    return d, classes

def rgba(v):
    v = v.strip().lower()
    m = re.fullmatch(r'#([0-9a-f]{6})', v)
    if m:
        h = m.group(1); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4)) + (1.0,)
    m = re.fullmatch(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([0-9.]+))?\s*\)', v)
    if m:
        return (int(m[1]), int(m[2]), int(m[3]), float(m[4]) if m[4] else 1.0)
    return None

COLOR_RE = r'rgba?\([^)]*\)|#[0-9a-f]{6}'

def norm(v):
    """shadows/gradients: the text with every colour taken out"""
    v = re.sub(r'\s+', ' ', v.strip().lower())
    return re.sub(COLOR_RE, "C", v).replace(" ", "")

def colors_in(v):
    return [rgba(m) for m in re.findall(COLOR_RE, v.strip().lower())]

def color_ok(a, b):
    """per channel within TOL, weighed by alpha; alpha within ATOL"""
    if not (a and b):
        return False
    w = max(a[3], b[3])
    return all(abs(x - y) * w <= TOL for x, y in zip(a[:3], b[:3])) and abs(a[3] - b[3]) <= ATOL

def value_ok(want, got):
    """a shadow/gradient/size: same text around the colours, colours within tolerance"""
    if norm(want) != norm(got):
        return False
    cw, cg = colors_in(want), colors_in(got)
    return len(cw) == len(cg) and all(color_ok(a, b) for a, b in zip(cw, cg))

total = missing_n = drift_n = warn_n = 0
for theme, path, sel in (("dark", dark_css, ":root"), ("light", light_css, ':root[data-theme="light"]')):
    got, classes = block(path, sel)
    values = {t["name"]: t["value"][theme] for t in spec["color"]["tokens"]}
    def resolve(v):
        while isinstance(v, str) and v.startswith("{"):
            v = values[v[1:-1]]
        return v
    rows = []
    for t in spec["color"]["tokens"]:
        rows.append((t["name"], resolve(t["value"][theme]), True))
    for grp in ("fontSize", "lineHeight", "fontWeight", "letterSpacing", "spacing", "radius",
                "shadow", "gradient", "borderWidth", "size", "opacity"):
        if grp == "gradient" and theme != "dark":
            continue                  # one value on the sheet: the dark default's
        for t in spec[grp]["tokens"]:
            v = t["value"]
            rows.append((t["name"], v[theme] if isinstance(v, dict) else v, False))
    for name, want, is_color in rows:
        total += 1
        k = "--" + name
        if k not in got:
            print("MISSING    %-5s %-26s spec %s" % (theme, k, want)); missing_n += 1; continue
        gv = got[k]
        if is_color:
            ok = color_ok(rgba(str(want)), rgba(gv))
        else:
            ok = value_ok(str(want), gv)
        if not ok:
            if (theme, k) in TOLERATED:
                print("tolerated  %-5s %-26s spec %-28s engine %s" % (theme, k, want, gv)); warn_n += 1
            else:
                print("DRIFT      %-5s %-26s spec %-28s engine %s" % (theme, k, want, gv)); drift_n += 1
    # the type styles, once (they do not change with the scheme)
    if theme == "dark":
        for g in spec["type"]["groups"]:
            for st in g["styles"]:
                total += 1
                cl = classes.get(st["name"])
                if not cl:
                    print("MISSING    class .%s" % st["name"]); missing_n += 1; continue
                want = {"font-size": st["fontSize"], "line-height": st["lineHeight"],
                        "font-weight": str(st["fontWeight"])}
                if st.get("letterSpacing"):
                    want["letter-spacing"] = st["letterSpacing"]
                if st.get("fontStyle") == "italic":
                    want["font-style"] = "italic"
                bad = [(p, w, cl.get(p)) for p, w in want.items()
                       if norm(str(w)) != norm(str(cl.get(p, "")))]
                fam = "var(--font-mono)" if g["family"] == "mono" else "var(--font-sans)"
                if cl.get("font-family") != fam:
                    bad.append(("font-family", fam, cl.get("font-family")))
                if bad:
                    print("DRIFT      class .%-20s %s" % (st["name"], "; ".join("%s spec %s engine %s" % b for b in bad)))
                    drift_n += 1
print("%d of %d spec tokens on target, %d tolerated, %d missing, %d drifted"
      % (total - missing_n - drift_n - warn_n, total, warn_n, missing_n, drift_n))
sys.exit(1 if (missing_n or drift_n) else 0)
PY
exit $stale
