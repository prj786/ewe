#!/usr/bin/env bash
# ewe-theme tests — sandboxed ewe.conf, no shell, no hooks. Covers the Ewe
# design system v3 generator: the default build (byte-identical CSS, every
# token + the Fluent aliases in the JSON), the two built-in schemes (embedded
# = the shipped asset files; set/remove refused; duplicate/export), the
# pre-v3 conf values (scheme = accent, corner = round, bar icon_size), role
# derivation for dark AND light imports (Base16, Omarchy, Catppuccin, Gogh,
# a wallpaper), overrides + semantic, the guarantees, look presets,
# accessibility modes, the --scheme/--selector build, and the fan-out into
# colorscheme.sh + ewe-conf (validation, defaults).
set -euo pipefail
cd "$(dirname "$0")/.."
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
export XDG_CONFIG_HOME="$SB/cfg" XDG_STATE_HOME="$SB/state" XDG_DATA_HOME="$SB/data" HOME="$SB/home"
mkdir -p "$SB/cfg/ewe" "$SB/cfg/quickshell" "$SB/cfg/hypr/generated" "$SB/home" "$SB/state"
T="bin/ewe-theme"; CONF="$SB/cfg/ewe/ewe.conf"; TOK="$SB/cfg/quickshell/theme-tokens.json"
pass=0; failn=0
check() { if eval "$2"; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1"; fi; }
role() { python3 -c "import json,sys; d=json.load(sys.stdin); print(d['color'][sys.argv[1]])" "$1"; }
shape() { python3 -c "import json,sys; d=json.load(sys.stdin); print(d['shape'][sys.argv[1]])" "$1"; }
size() { python3 -c "import json,sys; d=json.load(sys.stdin); print(d['size'][sys.argv[1]])" "$1"; }
inp()  { python3 -c "import json,sys; d=json.load(sys.stdin); print(d['input'].get(sys.argv[1],''))" "$1"; }
jq_()  { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1], {'d': d}))" "$1"; }
L()    { python3 -c "
import sys; h=sys.argv[1].lstrip('#')[-6:]
def lin(c):
    c/=255; return c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4
r,g,b=(lin(int(h[i:i+2],16)) for i in (0,2,4)); Y=0.2126*r+0.7152*g+0.0722*b
print(round(116*(Y**(1/3) if Y>216/24389 else (24389/27*Y+16)/116)-16))" "$1"; }
CR()   { python3 -c "
import sys
def lin(c):
    c/=255; return c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4
def lum(h):
    h=h.lstrip('#')[-6:]; r,g,b=(lin(int(h[i:i+2],16)) for i in (0,2,4)); return 0.2126*r+0.7152*g+0.0722*b
a,b=lum(sys.argv[1]),lum(sys.argv[2]); print('%.2f'%((max(a,b)+0.05)/(min(a,b)+0.05)))" "$1" "$2"; }

# 1. the default build: Ewe Dark, the committed CSS byte for byte ----------
$T build --json "$TOK" --css "$SB/tokens.css" >/dev/null
check "default build is byte-identical to design/tokens.css" "cmp -s design/tokens.css '$SB/tokens.css'"
check "tokens.css names design system version 3" "grep -q 'Ewe design system, version 3' '$SB/tokens.css'"
show="$($T show)"
check "defaults: scheme ewe-dark, accent ewellow, corner medium, stroke thin" "[ \"$(echo "$show" | inp scheme_slug)\" = ewe-dark ] && [ \"$(echo "$show" | inp accent)\" = '#eeb407' ] && [ \"$(echo "$show" | inp corner)\" = medium ] && [ \"$(echo "$show" | inp stroke)\" = thin ]"
check "every Ewe colour role is emitted" "echo '$show' | python3 -c '
import json,sys; c=json.load(sys.stdin)[\"color\"]
need=[\"ewellow\",\"black\"]+[\"ewellow-%d\"%s for s in (50,100,200,300,400,500,600,700,800,900,950)]+[\"neutral-%d\"%s for s in (0,50,100,200,300,400,500,600,700,800,850,900,950)]
need+=[\"surface-base\",\"surface-raised\",\"surface-overlay\",\"surface-sunken\",\"surface-hover\",\"surface-pressed\",\"surface-selected\",\"scrim\",\"glass-base\",\"glass-raised\",\"glass-border\",\"glass-hover\",\"glass-pressed\",\"glass-accent\",\"border-subtle\",\"border-strong\",\"text-primary\",\"text-secondary\",\"text-muted\",\"text-disabled\",\"accent\",\"accent-hover\",\"accent-pressed\",\"on-accent\",\"accent-subtle\",\"accent-text\",\"focus-ring\",\"success\",\"warning\",\"danger\",\"info\",\"success-subtle\",\"warning-subtle\",\"danger-subtle\",\"info-subtle\",\"on-status\"]
miss=[k for k in need if not c.get(k)]; assert not miss, miss'"
check "the Fluent aliases are still emitted, onto the Ewe roles" "[ \"$(echo "$show" | role fg-1)\" = \"$(echo "$show" | role text-primary)\" ] && [ \"$(echo "$show" | role bg-1)\" = \"$(echo "$show" | role surface-raised)\" ] && [ \"$(echo "$show" | role brand-bg)\" = \"$(echo "$show" | role accent)\" ] && [ \"$(echo "$show" | role stroke-1)\" = \"$(echo "$show" | role border-strong)\" ] && [ \"$(echo "$show" | role card-selected)\" = \"$(echo "$show" | role accent-subtle)\" ] && [ \"$(echo "$show" | role subtle)\" = transparent ]"
check "the older aliases (bg/panel/fg/link) too" "[ \"$(echo "$show" | role panel)\" = \"$(echo "$show" | role surface-raised)\" ] && [ \"$(echo "$show" | role link)\" = \"$(echo "$show" | role accent-text)\" ]"
check "shape: v3 radii + widths, and the old names beside them" "[ \"$(echo "$show" | shape primary)\" = 8 ] && [ \"$(echo "$show" | shape rounded)\" = 10 ] && [ \"$(echo "$show" | shape border-width-1)\" = 1 ] && [ \"$(echo "$show" | shape focus-width)\" = 1 ] && [ \"$(echo "$show" | shape radius-control)\" = 8 ] && [ \"$(echo "$show" | shape radius-panel)\" = 10 ] && [ \"$(echo "$show" | shape outline-width)\" = 1 ]"
check "size: the type scale, controls, bar, icons, panels, and the old names" "[ \"$(echo "$show" | size font-size-md)\" = 13 ] && [ \"$(echo "$show" | size control-md)\" = 28 ] && [ \"$(echo "$show" | size bar-height)\" = 48 ] && [ \"$(echo "$show" | size icon-lg)\" = 20 ] && [ \"$(echo "$show" | size panel-lg)\" = 560 ] && [ \"$(echo "$show" | size blur-glass)\" = 24 ] && [ \"$(echo "$show" | size fs-body)\" = 13 ] && [ \"$(echo "$show" | size control)\" = 28 ] && [ \"$(echo "$show" | size pad)\" = 12 ] && [ \"$(echo "$show" | size gap)\" = 8 ]"
check "glass, opacity, motion, type styles, bar block in the JSON" "python3 -c '
import json; d=json.load(open(\"$TOK\"))
assert d[\"version\"]==3
assert d[\"color\"][\"glass-base\"].startswith(\"#cc\"), d[\"color\"][\"glass-base\"]   # 0.8 alpha as #AARRGGBB
assert d[\"color\"][\"scrim\"].startswith(\"#a3\"), d[\"color\"][\"scrim\"]           # 0.64
assert d[\"opacity\"][\"opacity-glass\"]==0.8 and d[\"opacity\"][\"opacity-app\"]==0.85
assert d[\"motion\"][\"durFast\"]==150 and d[\"motion\"][\"durBase\"]==200 and d[\"motion\"][\"durSlow\"]==250 and d[\"motion\"][\"durDim\"]==1500
assert d[\"motion\"][\"easing\"][\"slow\"]==\"InOutCubic\"
assert d[\"type\"][\"styles\"][\"body\"][\"size\"]==13 and d[\"type\"][\"styles\"][\"h1\"][\"weight\"]==600 and d[\"type\"][\"styles\"][\"mono\"][\"family\"]==\"mono\"
assert d[\"type\"][\"sans\"][0]==\"Geist\"
assert d[\"bar\"]=={\"size\":\"normal\",\"height\":48,\"module\":32,\"icon\":20}, d[\"bar\"]
assert d[\"shadow\"][\"shadow-float\"][\"y\"]==2 and d[\"gradient\"][\"gradient-ember\"][\"css\"].startswith(\"linear-gradient(160deg\")
assert d[\"scheme\"][\"slug\"]==\"ewe-dark\" and d[\"scheme\"][\"builtin\"] and d[\"scheme\"][\"palette\"][\"base00\"]==\"#0b0a08\"
assert d[\"adjusted\"]==[], d[\"adjusted\"]
assert \"flock\" in d[\"themes\"] and d[\"themes\"][\"flock\"][\"color\"][\"bg\"]==\"#0b0a08\"
assert d[\"input\"][\"variant\"]==\"dark\"
'"
check "the CSS carries the type-style classes and the font stacks" "grep -q '^\.body { font-family: var(--font-sans); font-size: 13px; line-height: 18px; font-weight: 400; }' '$SB/tokens.css' && grep -q '^\.overline .*letter-spacing: 0.06em' '$SB/tokens.css' && grep -q -- '--font-sans: \"Geist\", \"Noto Sans Georgian\"' '$SB/tokens.css'"
check "the CSS still says --accent: var(--accent-default)" "grep -q -- '--accent: var(--accent-default);' '$SB/tokens.css' && grep -q -- '--accent-default: #eeb407;' '$SB/tokens.css'"

# 2. the built-in schemes ---------------------------------------------------
check "built-ins are the shipped asset files, byte for byte" "python3 -c '
import json,sys
sys.argv=[\"x\"]; src=open(\"bin/ewe-theme\").read()
ns={\"__file__\": \"bin/ewe-theme\"}; exec(src.split(\"# ═══ the accent ramp\")[0], ns)
for slug in (\"ewe-dark\",\"ewe-light\"):
    a=json.load(open(\"design/system/assets/Schemes/%s.json\"%slug)); b=ns[\"BUILTIN_BY_SLUG\"][slug]
    for k in a: assert a[k]==b[k], (slug,k,a[k],b[k])
'"
lst="$($T scheme list)"
check "list: both built-ins first, marked builtin, ewe-dark current" "echo '$lst' | python3 -c 'import json,sys; d=json.load(sys.stdin); s=d[\"schemes\"]; assert [x[\"slug\"] for x in s[:2]]==[\"ewe-dark\",\"ewe-light\"]; assert all(x[\"builtin\"] for x in s[:2]); assert s[0][\"current\"] and not s[1][\"current\"]; assert d[\"current\"]==\"ewe-dark\"'"
r="$($T scheme --no-hooks set accent '#ff0000' || true)"
check "set on a built-in is refused" "echo '$r' | grep -q '\"builtin\"' && ! grep -q 'ff0000' '$CONF' 2>/dev/null"
r="$($T scheme --no-hooks remove ewe-light || true)"
check "remove on a built-in is refused" "echo '$r' | grep -q '\"builtin\"'"
r="$($T scheme --no-hooks set overrides.accent-text '#ff0000' --slug ewe-light || true)"
check "set overrides.<role> on a built-in is refused too" "echo '$r' | grep -q '\"builtin\"'"
$T scheme export ewe-light > "$SB/ewe-light.yaml"
check "export of a built-in is the asset YAML shape (builtin, semantic, overrides)" "grep -q '^builtin: true' '$SB/ewe-light.yaml' && grep -q '^semantic: true' '$SB/ewe-light.yaml' && grep -q '^  border-strong: \"#7f7b75\"' '$SB/ewe-light.yaml' && grep -q '^slug: \"ewe-light\"' '$SB/ewe-light.yaml'"
r="$($T scheme --no-hooks import "$SB/ewe-light.yaml" || true)"
check "importing it back under the built-in slug is refused" "echo '$r' | grep -q '\"builtin\"'"
r="$($T scheme --no-hooks import "$SB/ewe-light.yaml" --slug my-light)"
check "…but works under another slug, keeping overrides and not builtin" "echo '$r' | grep -q '\"slug\": \"my-light\"' && $T scheme show my-light | python3 -c 'import json,sys; d=json.load(sys.stdin)[\"scheme\"]; assert not d.get(\"builtin\"); assert d[\"overrides\"][\"border-strong\"]==\"#7f7b75\"'"
r="$($T scheme --no-hooks duplicate ewe-dark --name "My dark")"
check "duplicate a built-in: a user copy with the accent it wore" "echo '$r' | grep -q '\"slug\": \"my-dark\"' && $T scheme show my-dark | python3 -c 'import json,sys; d=json.load(sys.stdin)[\"scheme\"]; assert not d.get(\"builtin\") and d[\"accent\"]==\"#eeb407\" and d[\"palette\"][\"base00\"]==\"#0b0a08\"'"
$T scheme --no-hooks set accent '#7e9cd8' --slug my-dark >/dev/null
check "the copy can be changed (set accent)" "$T scheme show my-dark | grep -q '\"accent\": \"#7e9cd8\"'"
show="$($T scheme show ewe-light)"
check "show ewe-light: roles + the adjusted list (overlay pushed 2 L off raised)" "echo '$show' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"roles\"][\"surface-base\"]==\"#f4f2ee\" and d[\"roles\"][\"text-primary\"]==\"#0b0a08\"; assert [a[\"role\"] for a in d[\"adjusted\"]]==[\"surface-overlay\"], d[\"adjusted\"]'"
$T scheme --no-hooks apply ewe-light >/dev/null
show="$($T show)"
check "apply ewe-light: variant light, light roles, dark accent text, on-accent black" "[ \"$(echo "$show" | inp variant)\" = light ] && [ \"$(echo "$show" | role surface-base)\" = '#f4f2ee' ] && [ \"$(echo "$show" | role accent-text)\" = '#805708' ] && [ \"$(echo "$show" | role on-accent)\" = '#020202' ] && [ \"$(echo "$show" | role glass-accent)\" = '#5a3b09' ]"

# 3. pre-v3 conf values keep working ----------------------------------------
cat > "$CONF" <<'C'
schema = 1
[desktop.theme]
scheme = "accent"
accent = "#1b559c"
corner = "round"
stroke = "none"
[desktop.bar]
icon_size = "large"
C
show="$($T show)"
check "scheme = accent reads as ewe-dark wearing the person's accent" "[ \"$(echo "$show" | inp scheme)\" = accent ] && [ \"$(echo "$show" | inp scheme_slug)\" = ewe-dark ] && [ \"$(echo "$show" | role accent)\" = '#1b559c' ] && [ \"$(echo "$show" | role ewellow)\" = '#eeb407' ] && [ \"$(echo "$show" | role ewellow-500)\" = '#1b559c' ]"
check "a dark blue accent: the built-in's gold overrides step aside — ramp, accent-text, focus-ring are blue; on-accent flips to white" "[ \"$(echo "$show" | role on-accent)\" = '#ffffff' ] && python3 -c \"
import colorsys
for h in ('$(echo "$show" | role accent-text)', '$(echo "$show" | role ewellow-900)', '$(echo "$show" | role focus-ring)'):
    r,g,b=(int(h.lstrip('#')[i:i+2],16)/255 for i in (0,2,4)); hh,s,v=colorsys.rgb_to_hsv(r,g,b); assert 0.5<hh<0.7 and s>0.15, (h,hh,s)\""
check "corner = round maps to large (6/8/12/16)" "[ \"$(echo "$show" | inp corner)\" = large ] && [ \"$(echo "$show" | shape slight)\" = 6 ] && [ \"$(echo "$show" | shape primary)\" = 12 ] && [ \"$(echo "$show" | shape rounded)\" = 16 ] && [ \"$(echo "$show" | shape radius-control)\" = 12 ]"
check "stroke = none: outlines 0, hairlines (stroke-width alias) stay 1, thick 2" "[ \"$(echo "$show" | shape border-width-1)\" = 0 ] && [ \"$(echo "$show" | shape outline-width)\" = 0 ] && [ \"$(echo "$show" | shape stroke-width)\" = 1 ] && [ \"$(echo "$show" | shape border-width-2)\" = 2 ]"
check "bar icon_size = large is read as the large bar" "echo '$show' | jq_ 'd[\"bar\"][\"height\"]' | grep -qx 64 && echo '$show' | jq_ 'd[\"bar\"][\"icon\"]' | grep -qx 24"
$T scheme --no-hooks apply accent >/dev/null
check "apply accent writes ewe-dark" "grep -q 'scheme = \"ewe-dark\"' '$CONF'"

# 4. Base16 (Gruvbox dark, real values) ------------------------------------
cat > "$SB/gruvbox.yaml" <<'Y'
system: "base16"
name: "Gruvbox dark, medium"
author: "Dawid Kurek (dawikur@gmail.com), morhetz (https://github.com/morhetz/gruvbox)"
variant: "dark"
palette:
  base00: "#282828" # ----
  base01: "#3c3836"
  base02: "#504945"
  base03: "#665c54"
  base04: "#bdae93"
  base05: "#d5c4a1"
  base06: "#ebdbb2"
  base07: "#fbf1c7"
  base08: "#fb4934"
  base09: "#fe8019"
  base0A: "#fabd2f"
  base0B: "#b8bb26"
  base0C: "#8ec07c"
  base0D: "#83a598"
  base0E: "#d3869b"
  base0F: "#d65d0e"
Y
r="$($T scheme --no-hooks import "$SB/gruvbox.yaml" --apply)"
check "import base16 + apply" "echo '$r' | grep -q '\"applied\": true' && grep -q 'scheme = \"gruvbox-dark-medium\"' '$CONF'"
show="$($T show)"
check "surfaces: base = base00, raised = base01, hover = base02, overlay between 01 and 02" "[ \"$(echo "$show" | role surface-base)\" = '#282828' ] && [ \"$(echo "$show" | role surface-raised)\" = '#3c3836' ] && [ \"$(echo "$show" | role surface-hover)\" = '#504945' ] && [ $(L "$(echo "$show" | role surface-overlay)") -gt $(L '#3c3836') ] && [ $(L "$(echo "$show" | role surface-overlay)") -lt $(L '#504945') ]"
check "text: secondary = base06, disabled = base03; primary = base05 lifted for 4.5:1 on pressed, muted = base04 lifted for hover, both recorded" "echo '$show' | python3 -c 'import json,sys; d=json.load(sys.stdin); a=[x for x in d[\"adjusted\"] if x[\"role\"]==\"text-primary\"]; assert a and a[0][\"from\"]==\"#d5c4a1\" and \"pressed\" in a[0][\"why\"], d[\"adjusted\"]' && [ $(L "$(echo "$show" | role text-primary)") -gt $(L '#d5c4a1') ] && [ \"$(echo "$show" | role text-secondary)\" = '#ebdbb2' ] && [ \"$(echo "$show" | role text-disabled)\" = '#665c54' ] && [ $(L "$(echo "$show" | role text-muted)") -gt $(L '#bdae93') ] && echo '$show' | python3 -c 'import json,sys; d=json.load(sys.stdin); a=[x for x in d[\"adjusted\"] if x[\"role\"]==\"text-muted\"]; assert a and a[0][\"from\"]==\"#bdae93\", d[\"adjusted\"]'"
check "no accent in the file: base0A is the accent (the guide), ramp anchored on it" "[ \"$(echo "$show" | inp accent)\" = '#fabd2f' ] && [ \"$(echo "$show" | role accent)\" = '#fabd2f' ] && echo '$show' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"brand\"][\"500\"]==\"#fabd2f\"'"
check "semantic: danger/warning/success/info from base08/09/0B/0D (each verbatim, or lifted and recorded)" "echo '$show' | python3 -c '
import json,sys; d=json.load(sys.stdin); c=d[\"color\"]; adj={a[\"role\"]: a for a in d[\"adjusted\"]}
for role, want in ((\"danger\",\"#fb4934\"),(\"warning\",\"#fe8019\"),(\"success\",\"#b8bb26\"),(\"info\",\"#83a598\")):
    assert c[role]==want or (role in adj and adj[role][\"from\"]==want), (role, c[role], adj.get(role))'"
check "pressed is lighter than hover on a dark scheme; sunken darker than base" "[ $(L "$(echo "$show" | role surface-pressed)") -gt $(L "$(echo "$show" | role surface-hover)") ] && [ $(L "$(echo "$show" | role surface-sunken)") -lt $(L '#282828') ]"
check "guarantee: text-muted reads 4.5:1 on every resting surface" "python3 -c \"
import sys; assert float('$(CR "$(echo "$show" | role text-muted)" "$(echo "$show" | role surface-hover)")') >= 4.5\""
check "input reports scheme + variant + effective accent" "[ \"$(echo "$show" | inp variant)\" = dark ] && [ \"$(echo "$show" | inp scheme_name)\" = 'Gruvbox dark, medium' ]"
check "tokens.json carries the palette for kitty" "$T build --css /dev/null >/dev/null && grep -q '\"base0D\": \"#83a598\"' '$TOK'"
$T scheme --no-hooks set semantic false >/dev/null
check "semantic = false: Ewe's own status colours" "[ \"$($T show | role warning)\" = '#f9a870' ] && [ \"$($T show | role success)\" = '#69d6aa' ]"
$T scheme --no-hooks set semantic true >/dev/null

# 5. overrides: set, export, round-trip, clear ------------------------------
$T scheme --no-hooks set overrides.border-subtle '#ff00ff' >/dev/null
check "set overrides.<role> lands in the roles" "[ \"$($T show | role border-subtle)\" = '#ff00ff' ] && grep -q 'border-subtle = \"#ff00ff\"' '$CONF'"
r="$($T scheme --no-hooks set overrides.not-a-role '#ff00ff' || true)"
check "an unknown role is refused" "echo '$r' | grep -q 'bad-field'"
$T scheme --no-hooks set accent '#fe8019' >/dev/null
$T scheme export > "$SB/exported.yaml"
check "export is base24 YAML with slug, accent, semantic and overrides" "grep -q '^system: \"base24\"' '$SB/exported.yaml' && grep -q '^slug: \"gruvbox-dark-medium\"' '$SB/exported.yaml' && grep -q '^accent: \"#fe8019\"' '$SB/exported.yaml' && grep -q '^semantic: true' '$SB/exported.yaml' && grep -q '^overrides:' '$SB/exported.yaml' && grep -q '^  border-subtle: \"#ff00ff\"' '$SB/exported.yaml' && ! grep -q '^builtin' '$SB/exported.yaml'"
$T scheme --no-hooks import "$SB/exported.yaml" --name "Gruvbox copy" >/dev/null
check "re-import keeps palette, accent and overrides" "$T scheme show gruvbox-copy | python3 -c 'import json,sys; d=json.load(sys.stdin); s=d[\"scheme\"]; assert s[\"palette\"][\"base0F\"]==\"#d65d0e\" and s[\"accent\"]==\"#fe8019\" and s[\"overrides\"]=={\"border-subtle\":\"#ff00ff\"}; assert d[\"roles\"][\"border-subtle\"]==\"#ff00ff\"'"
$T scheme --no-hooks set overrides.border-subtle none >/dev/null
check "clearing an override goes back to the derived value" "[ \"$($T show | role border-subtle)\" = '#504945' ]"
cat > "$SB/ov.yaml" <<'Y'
system: "base24"
name: "Overridden"
variant: "dark"
semantic: false
palette:
  base00: "#101014"
  base01: "#1a1a20"
  base02: "#2a2a32"
  base03: "#50505a"
  base04: "#9a9aa4"
  base05: "#e0e0e6"
  base06: "#c8c8d0"
  base07: "#f4f4f8"
  base08: "#ff6b6b"
  base09: "#ffa94d"
  base0A: "#ffd43b"
  base0B: "#69db7c"
  base0C: "#66d9e8"
  base0D: "#74c0fc"
  base0E: "#da77f2"
  base0F: "#c0a080"
overrides:
  accent-text: "#a0c8ff"
  surface-overlay: "#33333c"
Y
$T scheme --no-hooks import "$SB/ov.yaml" >/dev/null
check "import reads semantic + overrides from the file" "$T scheme show overridden | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"scheme\"][\"semantic\"] is False and d[\"scheme\"][\"overrides\"][\"surface-overlay\"]==\"#33333c\"; assert d[\"roles\"][\"accent-text\"]==\"#a0c8ff\" and d[\"roles\"][\"surface-overlay\"]==\"#33333c\" and d[\"roles\"][\"warning\"]==\"#f9a870\"'"

# 6. a LIGHT scheme (Solarized light, real values) -------------------------
cat > "$SB/sol.yaml" <<'Y'
system: "base16"
name: "Solarized Light"
variant: "light"
palette:
  base00: "#fdf6e3"
  base01: "#eee8d5"
  base02: "#93a1a1"
  base03: "#839496"
  base04: "#657b83"
  base05: "#586e75"
  base06: "#073642"
  base07: "#002b36"
  base08: "#dc322f"
  base09: "#cb4b16"
  base0A: "#b58900"
  base0B: "#859900"
  base0C: "#2aa198"
  base0D: "#268bd2"
  base0E: "#6c71c4"
  base0F: "#d33682"
Y
$T scheme --no-hooks import "$SB/sol.yaml" --apply >/dev/null
show="$($T show)"
check "light: variant light, base = base00, raised = base01, text-primary = base05 or darker (recorded)" "[ \"$(echo "$show" | inp variant)\" = light ] && [ \"$(echo "$show" | role surface-base)\" = '#fdf6e3' ] && [ \"$(echo "$show" | role surface-raised)\" = '#eee8d5' ] && [ $(L "$(echo "$show" | role text-primary)") -le $(L '#586e75') ]"
check "light: hover DARKENS, text is ink on paper (4.5:1 on hover)" "[ $(L "$(echo "$show" | role surface-hover)") -lt $(L "$(echo "$show" | role surface-raised)") ] && python3 -c \"assert float('$(CR "$(echo "$show" | role text-primary)" "$(echo "$show" | role surface-hover)")') >= 4.5\""
check "light: a Base16-convention palette (base07 = darkest ink) still gets a light overlay and selected" "[ $(L "$(echo "$show" | role surface-overlay)") -ge $(L '#fdf6e3') ] && [ \"$(echo "$show" | role surface-selected)\" = \"$(echo "$show" | role surface-overlay)\" ]"
check "light: every text role reads 4.5:1 on hover (the guarantees did their job, and said so)" "python3 -c \"assert float('$(CR "$(echo "$show" | role text-muted)" "$(echo "$show" | role surface-hover)")') >= 4.5 and float('$(CR "$(echo "$show" | role accent-text)" "$(echo "$show" | role surface-hover)")') >= 4.5\" && echo '$show' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert any(a[\"role\"]==\"text-primary\" and \"could not\" not in a[\"why\"] for a in d[\"adjusted\"]), d[\"adjusted\"]'"
check "light: on-accent is picked for the fill" "[ -n \"$(echo "$show" | role on-accent)\" ]"

# 6b. a FLAT light scheme (surfaces two L* apart) still has visible layer steps
cat > "$SB/flat.yaml" <<'Y'
system: "base16"
name: "Flat light"
variant: "light"
palette:
  base00: "#ffffff"
  base01: "#fdfdfd"
  base02: "#fafafa"
  base03: "#d0d0d0"
  base04: "#7a7a7a"
  base05: "#3a3a3a"
  base06: "#202020"
  base07: "#ffffff"
  base08: "#d02020"
  base09: "#d07020"
  base0A: "#c0a000"
  base0B: "#308030"
  base0C: "#208090"
  base0D: "#2060c0"
  base0E: "#8040a0"
  base0F: "#806040"
Y
$T scheme --no-hooks import "$SB/flat.yaml" --apply >/dev/null
show="$($T show)"
check "flat light: raised, overlay and hover each sit at least 2 L off the surface below; base untouched" "echo '$show' | python3 -c '
import json,sys,math
d=json.load(sys.stdin); c=d[\"color\"]
def lin(x):
    x/=255; return x/12.92 if x<=0.04045 else ((x+0.055)/1.055)**2.4
def okL(h):
    h=h.lstrip(\"#\"); r,g,b=(lin(int(h[i:i+2],16)) for i in (0,2,4))
    l=(0.4122214708*r+0.5363325363*g+0.0514459929*b)**(1/3); m=(0.2119034982*r+0.6806995451*g+0.1073969566*b)**(1/3); s=(0.0883024619*r+0.2817188376*g+0.6299787005*b)**(1/3)
    return 100*(0.2104542553*l+0.7936177850*m-0.0040720468*s)
assert c[\"surface-base\"]==\"#ffffff\"
for below,role in ((\"surface-base\",\"surface-raised\"),(\"surface-raised\",\"surface-overlay\"),(\"surface-raised\",\"surface-hover\")):
    assert abs(okL(c[role])-okL(c[below]))>=1.9, (role, c[role], below, c[below])
roles=[a[\"role\"] for a in d[\"adjusted\"]]; assert \"surface-raised\" in roles, roles'"
$T scheme --no-hooks import "$SB/gruvbox.yaml" --apply >/dev/null
$T scheme --no-hooks set accent '#fe8019' >/dev/null      # the override the later ewe-conf check expects
show="$($T show)"
check "gruvbox (well spaced) is left alone by the surface step rule" "[ \"$(echo "$show" | role surface-raised)\" = '#3c3836' ] && [ \"$(echo "$show" | role surface-hover)\" = '#504945' ]"

# 6c. the warning-vs-accent rule ---------------------------------------------
$T scheme --no-hooks set accent '#fe8019' >/dev/null
show="$($T show)"
check "an orange accent: warning (base09, the same orange) turns toward red and is recorded" "echo '$show' | python3 -c 'import json,sys; d=json.load(sys.stdin); adj=[a for a in d[\"adjusted\"] if a[\"role\"]==\"warning\"]; assert adj and \"red\" in adj[0][\"why\"], d[\"adjusted\"]; assert d[\"color\"][\"warning\"]!=\"#fe8019\"'"

# 7. Omarchy colors.toml -----------------------------------------------------
mkdir -p "$SB/tokyo-night"; cat > "$SB/tokyo-night/colors.toml" <<'T2'
mode = "dark"
accent = "#7aa2f7"
selection = "#33467c"
muted = "#565f89"
background = "#1a1b26"
dark_background = "#16161e"
darker_background = "#101014"
lighter_background = "#24283b"
foreground = "#a9b1d6"
dark_foreground = "#787c99"
light_foreground = "#c0caf5"
bright_foreground = "#ffffff"
red = "#f7768e"
yellow = "#e0af68"
orange = "#ff9e64"
green = "#9ece6a"
cyan = "#7dcfff"
blue = "#7aa2f7"
magenta = "#bb9af7"
brown = "#c0a36e"
bright_red = "#ff7a93"
bright_yellow = "#ffcf7a"
bright_green = "#b9f27c"
bright_cyan = "#8fd6ff"
bright_blue = "#8fb8ff"
bright_magenta = "#d0aaff"
T2
r="$($T scheme --no-hooks import "$SB/tokyo-night/colors.toml")"
check "omarchy: named after the dir, base11 = darker_background, accent kept" "echo '$r' | grep -q '\"name\": \"tokyo-night\"' && $T scheme show tokyo-night | grep -q '\"base11\": \"#101014\"' && $T scheme show tokyo-night | grep -q '\"accent\": \"#7aa2f7\"'"

# 8. Catppuccin palette.json (the fixture) ----------------------------------
r="$($T scheme --no-hooks import tests/fixtures/catppuccin-palette.json)"
check "catppuccin: mocha, base = base00, crust = base11, accent blue" "echo '$r' | grep -q 'Catppuccin Mocha' && $T scheme show catppuccin-mocha | grep -q '\"base00\": \"#1e1e2e\"' && $T scheme show catppuccin-mocha | grep -q '\"base11\": \"#11111b\"' && $T scheme show catppuccin-mocha | grep -q '\"accent\": \"#89b4fa\"'"
r="$($T scheme --no-hooks import tests/fixtures/catppuccin-palette.json --flavour latte)"
check "catppuccin latte: a light variant" "$T scheme show catppuccin-latte | grep -q '\"variant\": \"light\"'"
r="$($T scheme --no-hooks import tests/fixtures/catppuccin-palette.json --flavour frappe || true)"
check "catppuccin: a missing flavour is one clear error" "echo '$r' | grep -q 'no flavour'"

# 9. Gogh -------------------------------------------------------------------
cat > "$SB/gogh.yml" <<'G'
name: "Aco"
author: "Gogh"
variant: "dark"
color_01: "#3F3F3F"
color_02: "#FF0883"
color_03: "#83FF08"
color_04: "#FF8308"
color_05: "#0883FF"
color_06: "#8308FF"
color_07: "#08FF83"
color_08: "#B6B6B6"
color_09: "#424242"
color_10: "#FF1E8E"
color_11: "#8EFF1E"
color_12: "#FF8E1E"
color_13: "#1E8EFF"
color_14: "#8E1EFF"
color_15: "#1EFF8E"
color_16: "#C0C0C0"
background: "#1F1305"
foreground: "#B4E1FD"
cursor: "#B4E1FD"
G
r="$($T scheme --no-hooks import "$SB/gogh.yml")"
check "gogh: background = base00, red = base08, blue = base0D" "$T scheme show aco | grep -q '\"base00\": \"#1f1305\"' && $T scheme show aco | grep -q '\"base08\": \"#ff0883\"' && $T scheme show aco | grep -q '\"base0D\": \"#0883ff\"'"

# 10. from an image ----------------------------------------------------------
if command -v magick >/dev/null 2>&1; then
  magick -size 120x80 xc:'#1b2230' -fill '#e0803a' -draw 'rectangle 10,10 60,60' -fill '#2f4a7a' -draw 'rectangle 70,20 110,70' "$SB/wall.png"
  r="$($T scheme --no-hooks from-wallpaper --path "$SB/wall.png" --apply)"
  show="$($T show)"
  check "wallpaper: applied, dark surfaces, accent is the saturated colour" "echo '$r' | grep -q '\"applied\": true' && [ $(L "$(echo "$show" | role surface-base)") -lt 25 ] && [ \"$(echo "$show" | inp variant)\" = dark ]"
  acc="$(echo "$show" | role accent)"
  check "wallpaper: accent hue is orange-ish or blue-ish (from the image), not grey" "python3 -c \"
import sys,colorsys; h='$acc'.lstrip('#'); r,g,b=(int(h[i:i+2],16)/255 for i in (0,2,4)); hh,s,v=colorsys.rgb_to_hsv(r,g,b); assert s>0.3, (h,s)\""
  r="$($T scheme --no-hooks from-wallpaper --path "$SB/wall.png" --light --apply)"
  check "wallpaper --light: light surfaces" "[ $(L "$($T show | role surface-base)") -gt 85 ]"
else
  echo "skip: imagemagick not installed (wallpaper checks)"
fi

# 11. list / remove / back to the default ------------------------------------
check "list shows every imported scheme after the built-ins, with a swatch" "$T scheme list | python3 -c 'import json,sys; d=json.load(sys.stdin); s={x[\"slug\"] for x in d[\"schemes\"]}; assert {\"ewe-dark\",\"ewe-light\",\"gruvbox-dark-medium\",\"solarized-light\",\"tokyo-night\",\"catppuccin-mocha\",\"catppuccin-latte\",\"aco\"} <= s, s; assert all(len(x[\"swatch\"])==5 for x in d[\"schemes\"])'"
$T scheme --no-hooks apply aco >/dev/null
$T scheme --no-hooks remove aco >/dev/null
check "remove drops it; removing the current scheme falls back to ewe-dark" "! $T scheme list | grep -q '\"slug\": \"aco\"' && grep -q 'scheme = \"ewe-dark\"' '$CONF'"
$T scheme --no-hooks apply ewe-dark >/dev/null
check "apply ewe-dark restores the default (CSS identical again)" "[ \"$($T show | inp scheme_slug)\" = ewe-dark ] && $T build --json /dev/null --css '$SB/t2.css' >/dev/null && cmp -s design/tokens.css '$SB/t2.css'"
r="$($T scheme --no-hooks apply nothing-here || true)"
check "apply an unknown slug is a clear error" "echo '$r' | grep -q 'no-scheme'"

# 12. look presets + accessibility modes -------------------------------------
cat > "$CONF" <<'C'
schema = 1
[desktop.theme]
corner = "small"
density = "roomy"
stroke = "thick"
bar_opacity = 80
[desktop.bar]
size = "large"
C
show="$($T show)"
check "corner small / density roomy / stroke thick" "[ \"$(echo "$show" | shape primary)\" = 4 ] && [ \"$(echo "$show" | shape rounded)\" = 6 ] && [ \"$(echo "$show" | size control-md)\" = 32 ] && [ \"$(echo "$show" | size control-lg)\" = 40 ] && [ \"$(echo "$show" | shape border-width-1)\" = 2 ] && [ \"$(echo "$show" | shape border-width-2)\" = 3 ] && [ \"$(echo "$show" | shape focus-width)\" = 1 ]"
check "presets never touch colours" "[ \"$(echo "$show" | role surface-raised)\" = '#151411' ]"
check "bar size large: 64 / 40 / 24" "echo '$show' | jq_ 'd[\"bar\"]' | grep -q \"'height': 64, 'module': 40, 'icon': 24\""
check "Glass at 80: glass roles carry the alpha, blur on, bar_alpha 0.8" "echo '$show' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"surface\"][\"bar_alpha\"]==0.8 and d[\"surface\"][\"blur\"] and d[\"surface\"][\"glass\"]; assert d[\"alpha\"][\"glass-base\"]==0.8 and d[\"alpha\"][\"glass-border\"]==0.1 and d[\"alpha\"][\"glass-pressed\"]==0.14; assert d[\"color\"][\"glass-border\"]==\"#fefdfc\"; assert d[\"css_vars\"][\"--glass-base\"]==\"rgba(11, 10, 8, 0.8)\" and d[\"css_vars\"][\"--bg-3-bar\"]==\"rgba(11, 10, 8, 0.8)\"'"
cat > "$CONF" <<'C'
schema = 1
[desktop.theme]
bar_opacity = 80
corner = "none"
[desktop.accessibility]
increase_contrast = true
C
show="$($T show)"
check "increase contrast: border-subtle = border-strong, text-muted = text-secondary, hover = pressed, focus 2px, glass solid" "[ \"$(echo "$show" | role border-subtle)\" = \"$(echo "$show" | role border-strong)\" ] && [ \"$(echo "$show" | role text-muted)\" = \"$(echo "$show" | role text-secondary)\" ] && [ \"$(echo "$show" | role surface-hover)\" = \"$(echo "$show" | role surface-pressed)\" ] && [ \"$(echo "$show" | shape focus-width)\" = 2 ] && [ \"$(echo "$show" | role glass-border)\" = \"$(echo "$show" | role border-subtle)\" ] && echo '$show' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"surface\"][\"bar_alpha\"]==1.0 and not d[\"surface\"][\"blur\"] and \"glass-base\" not in d[\"alpha\"]'"
check "corner none: every radius 0, pills square" "[ \"$(echo "$show" | shape primary)\" = 0 ] && [ \"$(echo "$show" | shape fully-rounded)\" = 0 ] && [ \"$(echo "$show" | shape radius-pill)\" = 0 ]"
cat > "$CONF" <<'C'
schema = 1
[desktop.theme]
bar_opacity = 60
app_blur = true
window_transparency = true
[desktop.accessibility]
reduce_transparency = true
reduce_motion = true
text_scale = 130
[desktop.animations]
speed = 2
C
show="$($T show)"
check "reduce transparency: bar solid, no blur, app blur and window transparency off" "echo '$show' | python3 -c 'import json,sys; d=json.load(sys.stdin); s=d[\"surface\"]; assert s[\"bar_alpha\"]==1.0 and not s[\"blur\"] and not s[\"app_blur\"] and s[\"app_alpha\"]==1.0 and s[\"inactive_alpha\"]==1.0 and s[\"solid\"]; assert d[\"color\"][\"glass-base\"]==d[\"color\"][\"surface-base\"] and d[\"color\"][\"glass-hover\"]==d[\"color\"][\"surface-hover\"]'"
check "reduce motion + speed 2: durations halved, then base/slow become fast fades, no slide" "echo '$show' | python3 -c 'import json,sys; d=json.load(sys.stdin); m=d[\"motion\"]; assert m[\"durFast\"]==75 and m[\"durBase\"]==75 and m[\"durSlow\"]==75 and m[\"durDim\"]==750 and m[\"reduceMotion\"] and m[\"slideOffset\"]==0, m'"
check "text size 130: the type scale grows, styles follow, the bar goes large, sizes stay" "[ \"$(echo "$show" | size font-size-md)\" = 17 ] && [ \"$(echo "$show" | size line-height-md)\" = 23 ] && [ \"$(echo "$show" | size fs-body)\" = 17 ] && echo '$show' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"type\"][\"styles\"][\"body\"][\"size\"]==17 and d[\"type\"][\"scale\"]==130; assert d[\"bar\"][\"height\"]==64; assert d[\"size\"][\"control-md\"]==28'"
cat > "$CONF" <<'C'
schema = 1
[desktop.animations]
speed = 0
C
check "speed 0: every duration 0" "$T show | python3 -c 'import json,sys; m=json.load(sys.stdin)[\"motion\"]; assert m[\"durFast\"]==0 and m[\"durDim\"]==0'"

# 13. a design-time build for another scheme under a selector ---------------
: > "$CONF"
$T build --json /dev/null --css "$SB/light.css" --scheme ewe-light --selector ':root[data-theme="light"]' >/dev/null
check "--scheme ewe-light --selector: light values under the selector, live JSON untouched" "grep -q '^:root\[data-theme=\"light\"\] {' '$SB/light.css' && grep -q -- '  --surface-base: #f4f2ee;' '$SB/light.css' && grep -q -- '  --accent-text: #805708;' '$SB/light.css' && grep -q 'scheme ewe-light' '$SB/light.css' && ! grep -q '^:root {' '$SB/light.css'"
$T build --json /dev/null --css "$SB/t3.css" >/dev/null
check "the default build is unchanged by that" "cmp -s design/tokens.css '$SB/t3.css'"
r="$($T build --json /dev/null --css "$SB/none.css" --scheme nothing-here || true)"
check "--scheme with an unknown slug is a clear error" "echo '$r' | grep -q 'no-scheme'"

# 14. the fan-out: colorscheme.sh + ewe-conf, side effects shadowed ---------
mkdir -p "$SB/bin"
for c in gsettings hyprctl pkill dbus-send notify-send qs gio xdg-settings; do printf '#!/bin/sh\nexit 0\n' > "$SB/bin/$c"; chmod +x "$SB/bin/$c"; done
export PATH="$SB/bin:$PATH"
$T scheme --no-hooks import "$SB/gruvbox.yaml" >/dev/null
$T scheme --no-hooks set accent '#fe8019' --slug gruvbox-dark-medium >/dev/null
$T scheme --no-hooks import "$SB/sol.yaml" >/dev/null
$T scheme --no-hooks apply gruvbox-dark-medium >/dev/null
$T build --css /dev/null >/dev/null
acc="$($T show | inp accent | tr -d '#')"
sh dotfiles/quickshell/scripts/colorscheme.sh dark "$acc" >/dev/null 2>&1 || true
fg1="$($T show | role text-primary | tr -d '#')"
check "qt6ct palette is built from the scheme (WindowText = text-primary, Button = surface-raised, Base = base00)" "grep -q \"active_colors=#ff$fg1, #ff3c3836, \" '$SB/cfg/qt6ct/colors/ewe-dark.conf' && grep -qi '#ff282828' '$SB/cfg/qt6ct/colors/ewe-dark.conf'"
check "kitty gets the sixteen ANSI colours from the scheme" "grep -q '^color0  #282828' '$SB/cfg/kitty/flock.conf' && grep -q '^color1  #fb4934' '$SB/cfg/kitty/flock.conf' && grep -q '^color15 #fbf1c7' '$SB/cfg/kitty/flock.conf'"
check "kdeglobals windows are the scheme's surfaces" "grep -q '^BackgroundNormal=60,56,54' '$SB/cfg/kdeglobals'"
check "dark scheme keeps prefer-dark + adw-gtk3-dark" "grep -q 'gtk-application-prefer-dark-theme=1' '$SB/cfg/gtk-3.0/settings.ini' && grep -q 'gtk-theme-name=adw-gtk3-dark' '$SB/cfg/gtk-3.0/settings.ini'"
$T scheme --no-hooks apply solarized-light >/dev/null
$T build --css /dev/null >/dev/null
sh dotfiles/quickshell/scripts/colorscheme.sh dark "$($T show | inp accent | tr -d '#')" >/dev/null 2>&1 || true
check "light scheme flips GTK to light + light icons + its own ANSI" "grep -q 'gtk-application-prefer-dark-theme=0' '$SB/cfg/gtk-3.0/settings.ini' && grep -q 'gtk-theme-name=adw-gtk3$' '$SB/cfg/gtk-3.0/settings.ini' && grep -q '^color0  #fdf6e3' '$SB/cfg/kitty/flock.conf'"
$T scheme --no-hooks apply ewe-dark >/dev/null
$T build --css /dev/null >/dev/null
sh dotfiles/quickshell/scripts/colorscheme.sh dark eeb407 >/dev/null 2>&1 || true
check "ewe-dark: kitty wears Ewe Dark's palette, GTK dark again" "grep -q '^color0  #0b0a08' '$SB/cfg/kitty/flock.conf' && grep -q 'gtk-application-prefer-dark-theme=1' '$SB/cfg/gtk-3.0/settings.ini'"
# ewe-conf: the border follows the scheme's accent, user-theme.json carries the choice
bin/ewe-conf set --no-hooks desktop.theme.scheme '"gruvbox-dark-medium"' >/dev/null
check "ewe-conf: user-theme.json says scheme, window border = the scheme accent" "grep -q '\"scheme\": \"gruvbox-dark-medium\"' '$SB/cfg/quickshell/user-theme.json' && grep -q 'active_border = \"rgba(fe8019ff)\"' '$SB/cfg/hypr/generated/user.lua'"
bin/ewe-conf set --no-hooks desktop.theme.scheme '"ewe-dark"' >/dev/null
check "ewe-conf: back to ewe-dark, border = desktop.theme.accent (ewellow by default)" "grep -q 'active_border = \"rgba(eeb407ff)\"' '$SB/cfg/hypr/generated/user.lua'"
check "ewe-conf get: an unwritten v3 key answers its default" "[ \"$(bin/ewe-conf get desktop.theme.corner)\" = medium ] && [ \"$(bin/ewe-conf get desktop.bar.size)\" = normal ] && [ \"$(bin/ewe-conf get desktop.accessibility.text_scale)\" = 100 ] && [ \"$(bin/ewe-conf get desktop.accessibility.reduce_motion)\" = false ]"
r="$(bin/ewe-conf set --no-hooks desktop.theme.corner '"blob"' 2>&1 || true)"
check "ewe-conf set: an unknown corner is refused, nothing written" "echo '$r' | grep -q 'bad-value' && ! grep -q 'blob' '$CONF'"
r="$(bin/ewe-conf set --no-hooks desktop.accessibility.text_scale 120 2>&1 || true)"
check "ewe-conf set: text_scale must be 100/115/130" "echo '$r' | grep -q 'bad-value'"
bin/ewe-conf set --no-hooks desktop.accessibility.increase_contrast true >/dev/null
check "ewe-conf set accessibility: routed to theme, tokens rebuilt with the remap" "grep -q 'increase_contrast = true' '$CONF' && python3 -c 'import json; d=json.load(open(\"$TOK\")); assert d[\"shape\"][\"focus-width\"]==2 and d[\"accessibility\"][\"increase_contrast\"]'"
bin/ewe-conf set --no-hooks desktop.accessibility.reduce_transparency true >/dev/null
bin/ewe-conf set --no-hooks desktop.theme.bar_opacity 80 >/dev/null
check "ewe-conf: reduce transparency keeps the compositor blur out of user.lua" "! grep -q 'ewe-bar-blur' '$SB/cfg/hypr/generated/user.lua'"
bin/ewe-conf set --no-hooks desktop.accessibility.reduce_transparency false >/dev/null
bin/ewe-conf set --no-hooks desktop.accessibility.increase_contrast false >/dev/null
check "ewe-conf: bar_opacity 80 alone blurs the bar and dock" "grep -q 'ewe-bar-blur' '$SB/cfg/hypr/generated/user.lua'"
bin/ewe-conf set --no-hooks desktop.theme.corner '"round"' >/dev/null
check "ewe-conf: the pre-v3 corner value still passes and reads as large" "[ \"$($T show | inp corner)\" = large ]"

echo "ewe-theme: $pass passed, $failn failed"
[ "$failn" = 0 ]
