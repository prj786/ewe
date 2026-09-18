#!/usr/bin/env bash
# The contrast rules of the Ewe design system, held against what bin/ewe-theme
# derives (design/system/guidelines/10-color-schemes.md "Guarantees", and the
# Glass card): for ewe-dark, ewe-light, a Catppuccin import (mocha + latte)
# and a scheme derived from a wallpaper in design/system/assets/Wallpapers:
#
#   - text-primary, text-secondary, text-muted, accent-text and the four
#     status colours reach 4.5:1 on every resting surface role (base, raised,
#     overlay, sunken, hover, selected); text-primary/secondary also on pressed
#     (the only text the cards put there);
#   - border-strong and focus-ring reach 3:1 on the same surfaces;
#   - on-accent 4.5:1 on accent; on-status 4.5:1 on each status fill;
#   - at the Glass preset (80%), text-primary, text-secondary and glass-accent
#     reach 4.5:1 over glass-base and glass-raised composited over white AND
#     black; status glyphs 3:1.
#
# Runs in a throwaway XDG_CONFIG_HOME — the live config is never touched.
# Exit 0 = every rule holds. Exit 1 = a failure (printed).
set -uo pipefail
cd "$(dirname "$0")/.."
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
export XDG_CONFIG_HOME="$SB/cfg" XDG_STATE_HOME="$SB/state" XDG_DATA_HOME="$SB/data" HOME="$SB/home"
mkdir -p "$SB/cfg/ewe" "$SB/cfg/quickshell" "$SB/home"
T=bin/ewe-theme
FIX=tests/fixtures/catppuccin-palette.json
WALL="${EWE_CONTRAST_WALLPAPER:-design/system/assets/Wallpapers/ewe-flock.jpg}"
cat > "$SB/cfg/ewe/ewe.conf" <<EOF
schema = 1
[desktop.theme]
bar_opacity = 80
EOF

$T scheme --no-hooks import "$FIX" --flavour mocha >/dev/null
$T scheme --no-hooks import "$FIX" --flavour latte >/dev/null
slugs="ewe-dark ewe-light catppuccin-mocha catppuccin-latte"
if [ -r "$WALL" ] && command -v magick >/dev/null 2>&1; then
    # from-wallpaper always writes the slug `wallpaper`: keep the dark one
    # under its own slug, then derive the light one
    $T scheme --no-hooks from-wallpaper --path "$WALL" --name "Wallpaper" >/dev/null
    $T scheme export wallpaper > "$SB/wallpaper-dark.yaml"
    $T scheme --no-hooks import "$SB/wallpaper-dark.yaml" --slug wallpaper-dark >/dev/null
    $T scheme --no-hooks from-wallpaper --path "$WALL" --light --name "Wallpaper light" >/dev/null
    slugs="$slugs wallpaper-dark wallpaper"
else
    echo "skip: wallpaper scheme ($WALL missing or no imagemagick)"
fi

fail=0
for slug in $slugs; do
    $T scheme show "$slug" > "$SB/$slug.json"
    python3 - "$SB/$slug.json" "$slug" <<'PY' || fail=1
import json, sys
d = json.load(open(sys.argv[1])); slug = sys.argv[2]
c = d["roles"]; sc = d["scheme"]
def lin(x):
    x /= 255.0
    return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
def rgb(h):
    h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
def lum(h):
    r, g, b = (lin(x) for x in rgb(h)); return 0.2126 * r + 0.7152 * g + 0.0722 * b
def cr(a, b):
    la, lb = lum(a), lum(b); hi, lo = max(la, lb), min(la, lb); return (hi + 0.05) / (lo + 0.05)
def over(fg, a, bg):
    f, b = rgb(fg), rgb(bg); return "#%02x%02x%02x" % tuple(round(f[i] * a + b[i] * (1 - a)) for i in range(3))
resting = ["surface-base", "surface-raised", "surface-overlay", "surface-sunken", "surface-hover", "surface-selected"]
bad = []
def need(role, surfaces, target, label):
    for s in surfaces:
        r = cr(c[role], c[s])
        if r < target - 1e-9:
            bad.append("%-14s %-16s on %-16s %.2f:1 < %g:1  (%s vs %s)" % (label, role, s, r, target, c[role], c[s]))
for role in ("text-primary", "text-secondary", "text-muted", "accent-text", "success", "warning", "danger", "info"):
    need(role, resting, 4.5, "text")
for role in ("text-primary", "text-secondary"):
    need(role, ["surface-pressed"], 4.5, "text")
for role in ("border-strong", "focus-ring"):
    need(role, resting, 3.0, "border")
if cr(c["on-accent"], c["accent"]) < 4.5:
    bad.append("on-accent on accent %.2f:1 < 4.5" % cr(c["on-accent"], c["accent"]))
for s in ("success", "warning", "danger", "info"):
    if cr(c["on-status"], c[s]) < 4.5:
        bad.append("on-status on %s %.2f:1 < 4.5 (%s vs %s)" % (s, cr(c["on-status"], c[s]), c["on-status"], c[s]))
# Glass at the preset: the fill over white and over black
a = 0.8
backs = [over(c[k], a, w) for k in ("surface-base", "surface-raised") for w in ("#ffffff", "#000000")]
for role in ("text-primary", "text-secondary", "glass-accent"):
    for b in backs:
        r = cr(c[role], b)
        if r < 4.5 - 1e-9:
            bad.append("glass 80%%     %-16s over %s  %.2f:1 < 4.5:1" % (role, b, r))
for role in ("success", "warning", "danger", "info"):
    for b in backs:
        r = cr(c[role], b)
        if r < 3.0 - 1e-9:
            bad.append("glass 80%%     %-16s over %s  %.2f:1 < 3:1 (glyph)" % (role, b, r))
adj = ", ".join("%s (%s)" % (x["role"], x["why"]) for x in d["adjusted"]) or "none"
if bad:
    print("FAIL %s (%s): %d rule(s) broken" % (slug, sc["variant"], len(bad)))
    for b in bad:
        print("    " + b)
    print("    adjusted: " + adj)
    sys.exit(1)
print("ok   %-18s %-5s  adjusted: %s" % (slug, sc["variant"], adj))
PY
done
[ "$fail" = 0 ] && echo "contrast: every rule holds for $slugs"
exit $fail
