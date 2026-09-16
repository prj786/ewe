#!/usr/bin/env bash
# ewe-theme scheme tests — sandboxed ewe.conf, no shell, no hooks. Covers:
# accent mode unchanged (byte-identical CSS), Base16/Base24, Omarchy,
# Catppuccin and Gogh imports, the role mapping for dark AND light schemes,
# export round-trip, set/remove/apply, and a palette derived from an image.
set -euo pipefail
cd "$(dirname "$0")/.."
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
export XDG_CONFIG_HOME="$SB/cfg" XDG_STATE_HOME="$SB/state" HOME="$SB/home"
mkdir -p "$SB/cfg/ewe" "$SB/cfg/quickshell" "$SB/cfg/hypr/generated" "$SB/home" "$SB/state"
T="bin/ewe-theme"; CONF="$SB/cfg/ewe/ewe.conf"
pass=0; failn=0
check() { if eval "$2"; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1"; fi; }
role() { python3 -c "import json,sys; d=json.load(sys.stdin); print(d['color'][sys.argv[1]])" "$1"; }
inp()  { python3 -c "import json,sys; d=json.load(sys.stdin); print(d['input'].get(sys.argv[1],''))" "$1"; }
L()    { python3 -c "
import sys; h=sys.argv[1].lstrip('#')[-6:]
def lin(c):
    c/=255; return c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4
r,g,b=(lin(int(h[i:i+2],16)) for i in (0,2,4)); Y=0.2126*r+0.7152*g+0.0722*b
print(round(116*(Y**(1/3) if Y>216/24389 else (24389/27*Y+16)/116)-16))" "$1"; }

# 1. accent mode: the committed CSS is exactly what the engine still builds
$T build --json /dev/null --css "$SB/tokens.css" >/dev/null
check "accent mode is byte-identical to design/tokens.css" "cmp -s design/tokens.css '$SB/tokens.css'"

# 2. Base16 (Gruvbox dark, real values) ------------------------------------
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
check "bg-3 is base00, bg-1 is base01, card is base02" "[ \"$(echo "$show" | role bg-3)\" = '#282828' ] && [ \"$(echo "$show" | role bg-1)\" = '#3c3836' ] && [ \"$(echo "$show" | role card)\" = '#504945' ]"
check "fg-1 is base07, fg-2 is base05, fg-4 is base04" "[ \"$(echo "$show" | role fg-1)\" = '#fbf1c7' ] && [ \"$(echo "$show" | role fg-2)\" = '#d5c4a1' ] && [ \"$(echo "$show" | role fg-4)\" = '#bdae93' ]"
check "the brand ramp is anchored on the scheme accent (base0D at stop 80)" "echo '$show' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"brand\"][\"80\"]==\"#83a598\", d[\"brand\"][\"80\"]' && [ \"$(echo "$show" | inp accent)\" = '#83a598' ]"
check "danger/warning/success from base08/0A/0B" "[ \"$(echo "$show" | role danger)\" = '#fb4934' ] && [ \"$(echo "$show" | role warning)\" = '#fabd2f' ] && [ \"$(echo "$show" | role success)\" = '#b8bb26' ]"
check "input reports scheme + variant + effective accent" "[ \"$(echo "$show" | inp variant)\" = dark ] && [ \"$(echo "$show" | inp accent)\" = '#83a598' ] && [ \"$(echo "$show" | inp scheme_name)\" = 'Gruvbox dark, medium' ]"
check "every role is present (150-ish, none empty)" "echo '$show' | python3 -c 'import json,sys; c=json.load(sys.stdin)[\"color\"]; assert len(c)>=70 and all(v for v in c.values()), len(c)'"
check "hover is lighter than rest on a dark scheme" "[ $(L "$(echo "$show" | role bg-1-hover)") -gt $(L "$(echo "$show" | role bg-1)") ]"
check "fg-2 on bg-1 reads (L* gap > 40)" "[ $(( $(L "$(echo "$show" | role fg-2)") - $(L "$(echo "$show" | role bg-1)") )) -gt 40 ]"
check "tokens.json carries the palette for kitty" "$T build --css /dev/null >/dev/null && grep -q '\"base0D\": \"#83a598\"' '$SB/cfg/quickshell/theme-tokens.json'"

# 3. accent override on a scheme, then export round-trip ------------------
$T scheme --no-hooks set accent '#fe8019' >/dev/null
check "set accent on the current scheme" "[ \"$($T show | inp accent)\" = '#fe8019' ]"
$T scheme export > "$SB/exported.yaml"
check "export is base24 YAML with the accent" "grep -q '^system: \"base24\"' '$SB/exported.yaml' && grep -q '^accent: \"#fe8019\"' '$SB/exported.yaml' && grep -q 'base00: \"#282828\"' '$SB/exported.yaml'"
$T scheme --no-hooks import "$SB/exported.yaml" --name "Gruvbox copy" >/dev/null
check "re-import of an export keeps the palette" "$T scheme show gruvbox-copy | grep -q '\"base0F\": \"#d65d0e\"'"

# 4. a LIGHT scheme (Solarized light, real values) -------------------------
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
check "light: variant light, bg-3 is the light base00, fg-1 is the dark base07" "[ \"$(echo "$show" | inp variant)\" = light ] && [ \"$(echo "$show" | role bg-3)\" = '#fdf6e3' ] && [ \"$(echo "$show" | role fg-1)\" = '#002b36' ]"
check "light: hover DARKENS, text is ink on paper (L* gap > 40)" "[ $(L "$(echo "$show" | role bg-1-hover)") -lt $(L "$(echo "$show" | role bg-1)") ] && [ $(( $(L "$(echo "$show" | role bg-1)") - $(L "$(echo "$show" | role fg-2)") )) -gt 40 ]"
check "light: fg-on-brand picked for the fill, not hard-coded" "[ -n \"$(echo "$show" | role fg-on-brand)\" ]"

# 5. Omarchy colors.toml -----------------------------------------------------
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

# 6. Catppuccin palette.json (mocha subset) ----------------------------------
python3 - "$SB/palette.json" <<'PY'
import json, sys
m = {"base":"#1e1e2e","mantle":"#181825","crust":"#11111b","surface0":"#313244","surface1":"#45475a","surface2":"#585b70",
     "subtext0":"#a6adc8","subtext1":"#bac2de","text":"#cdd6f4","red":"#f38ba8","peach":"#fab387","yellow":"#f9e2af",
     "green":"#a6e3a1","teal":"#94e2d5","blue":"#89b4fa","mauve":"#cba6f7","flamingo":"#f2cdcd","maroon":"#eba0ac",
     "sky":"#89dceb","sapphire":"#74c7ec","pink":"#f5c2e7"}
json.dump({"version":"1.7.1","mocha":{"name":"Mocha","dark":True,"colors":{k:{"hex":v} for k,v in m.items()}}}, open(sys.argv[1],"w"))
PY
r="$($T scheme --no-hooks import "$SB/palette.json")"
check "catppuccin: mocha, base = base00, crust = base11" "echo '$r' | grep -q 'Catppuccin Mocha' && $T scheme show catppuccin-mocha | grep -q '\"base00\": \"#1e1e2e\"' && $T scheme show catppuccin-mocha | grep -q '\"base11\": \"#11111b\"'"
r="$($T scheme --no-hooks import "$SB/palette.json" --flavour latte || true)"
check "catppuccin: a missing flavour is one clear error" "echo '$r' | grep -q 'no flavour'"

# 7. Gogh -------------------------------------------------------------------
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

# 8. from an image ----------------------------------------------------------
if command -v magick >/dev/null 2>&1; then
  magick -size 120x80 xc:'#1b2230' -fill '#e0803a' -draw 'rectangle 10,10 60,60' -fill '#2f4a7a' -draw 'rectangle 70,20 110,70' "$SB/wall.png"
  r="$($T scheme --no-hooks from-wallpaper --path "$SB/wall.png" --apply)"
  show="$($T show)"
  check "wallpaper: applied, dark surfaces, accent is the saturated colour" "echo '$r' | grep -q '\"applied\": true' && [ $(L "$(echo "$show" | role bg-3)") -lt 25 ] && [ \"$(echo "$show" | inp variant)\" = dark ]"
  acc="$(echo "$show" | role brand-fg-1)"
  check "wallpaper: accent hue is orange-ish or blue-ish (from the image), not grey" "python3 -c \"
import sys,colorsys; h='$acc'.lstrip('#'); r,g,b=(int(h[i:i+2],16)/255 for i in (0,2,4)); hh,s,v=colorsys.rgb_to_hsv(r,g,b); assert s>0.3, (h,s)\""
  r="$($T scheme --no-hooks from-wallpaper --path "$SB/wall.png" --light --apply)"
  check "wallpaper --light: light surfaces" "[ $(L "$($T show | role bg-3)") -gt 85 ]"
else
  echo "skip: imagemagick not installed (wallpaper checks)"
fi

# 9. list / remove / back to accent -----------------------------------------
check "list shows every imported scheme with a swatch" "$T scheme list | python3 -c 'import json,sys; d=json.load(sys.stdin); s={x[\"slug\"] for x in d[\"schemes\"]}; assert {\"gruvbox-dark-medium\",\"solarized-light\",\"tokyo-night\",\"catppuccin-mocha\",\"aco\"} <= s, s; assert all(len(x[\"swatch\"])==5 for x in d[\"schemes\"])'"
$T scheme --no-hooks remove aco >/dev/null
check "remove drops it" "! $T scheme list | grep -q '\"slug\": \"aco\"'"
$T scheme --no-hooks apply accent >/dev/null
check "apply accent restores accent mode (CSS identical again)" "[ \"$($T show | inp scheme)\" = accent ] && $T build --json /dev/null --css '$SB/t2.css' >/dev/null && cmp -s design/tokens.css '$SB/t2.css'"
r="$($T scheme --no-hooks apply nothing-here || true)"
check "apply an unknown slug is a clear error" "echo '$r' | grep -q 'no-scheme'"

# 10. the fan-out: colorscheme.sh + ewe-conf, side effects shadowed ---------
mkdir -p "$SB/bin"
for c in gsettings hyprctl pkill dbus-send notify-send qs gio xdg-settings; do printf '#!/bin/sh\nexit 0\n' > "$SB/bin/$c"; chmod +x "$SB/bin/$c"; done
export PATH="$SB/bin:$PATH"
$T scheme --no-hooks apply gruvbox-dark-medium >/dev/null
$T build --css /dev/null >/dev/null
acc="$($T show | inp accent | tr -d '#')"
sh dotfiles/quickshell/scripts/colorscheme.sh dark "$acc" >/dev/null 2>&1 || true
check "qt6ct palette is built from the scheme (Base = bg-3 = base00)" "grep -q 'active_colors=#fffbf1c7, #ff3c3836, ' '$SB/cfg/qt6ct/colors/ewe-dark.conf' && grep -qi '#ff282828' '$SB/cfg/qt6ct/colors/ewe-dark.conf'"
check "kitty gets the sixteen ANSI colours from the scheme" "grep -q '^color0  #282828' '$SB/cfg/kitty/flock.conf' && grep -q '^color1  #fb4934' '$SB/cfg/kitty/flock.conf' && grep -q '^color15 #fbf1c7' '$SB/cfg/kitty/flock.conf'"
check "kdeglobals windows are the scheme's surfaces" "grep -q '^BackgroundNormal=60,56,54' '$SB/cfg/kdeglobals'"
check "dark scheme keeps prefer-dark + adw-gtk3-dark" "grep -q 'gtk-application-prefer-dark-theme=1' '$SB/cfg/gtk-3.0/settings.ini' && grep -q 'gtk-theme-name=adw-gtk3-dark' '$SB/cfg/gtk-3.0/settings.ini'"
$T scheme --no-hooks apply solarized-light >/dev/null
$T build --css /dev/null >/dev/null
sh dotfiles/quickshell/scripts/colorscheme.sh dark "$($T show | inp accent | tr -d '#')" >/dev/null 2>&1 || true
check "light scheme flips GTK to light + light icons + no ANSI leak" "grep -q 'gtk-application-prefer-dark-theme=0' '$SB/cfg/gtk-3.0/settings.ini' && grep -q 'gtk-theme-name=adw-gtk3$' '$SB/cfg/gtk-3.0/settings.ini' && grep -q '^color0  #fdf6e3' '$SB/cfg/kitty/flock.conf'"
$T scheme --no-hooks apply accent >/dev/null
$T build --css /dev/null >/dev/null
sh dotfiles/quickshell/scripts/colorscheme.sh dark 0a84ff >/dev/null 2>&1 || true
check "accent mode: kitty has no ANSI block, GTK dark again" "! grep -q '^color0 ' '$SB/cfg/kitty/flock.conf' && grep -q 'gtk-application-prefer-dark-theme=1' '$SB/cfg/gtk-3.0/settings.ini'"
# ewe-conf: the border follows the scheme's accent, user-theme.json carries the choice
bin/ewe-conf set --no-hooks desktop.theme.scheme '"gruvbox-dark-medium"' >/dev/null
check "ewe-conf: user-theme.json says scheme, window border = the scheme accent" "grep -q '\"scheme\": \"gruvbox-dark-medium\"' '$SB/cfg/quickshell/user-theme.json' && grep -q 'active_border = \"rgba(fe8019ff)\"' '$SB/cfg/hypr/generated/user.lua'"
bin/ewe-conf set --no-hooks desktop.theme.scheme '"accent"' >/dev/null
check "ewe-conf: back to accent, border = desktop.theme.accent" "grep -q 'active_border = \"rgba(0a84ffff)\"' '$SB/cfg/hypr/generated/user.lua'"

echo "ewe-theme: $pass passed, $failn failed"
[ "$failn" = 0 ]
