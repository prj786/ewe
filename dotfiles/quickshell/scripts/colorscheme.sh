#!/bin/bash
# colorscheme.sh <dark|light> [accent-hex] — apply a light/dark appearance,
# tinted with the shell accent, across the whole app ecosystem:
#   • GTK 3/4 + libadwaita   (settings.ini + gsettings)        ← PRIMARY (first-party apps)
#   • Qt 5/6                 (qt6ct/qt5ct, Fusion + dark palette) ← any stray Qt app
#   • KDE / KF6              (kdeglobals)                       ← only if you add a KDE app
#   • Icon theme             (Reversal, accent-matched colour variant)
#   • Cursor                 (Mocu, forced everywhere so it never flips per-toolkit)
#
# Called by: Settings → Theme (live), Quickshell at startup (re-sync), phase 60
# (install default). Writes config files always; gsettings is a best-effort live
# nudge for already-running apps.
#
# First-party apps are GTK now, so the GTK config is what matters; the qt6ct/kdeglobals
# writes just keep any stray Qt/KDE app you install dark too. `set -u` only (NOT -e),
# so a stray non-zero line never aborts before every file is written.
set -u

MODE="${1:-dark}"
case "$MODE" in dark|light) ;; *) MODE=dark ;; esac

# accent → 6 lowercase hex (fallback system blue) + decimal R,G,B
ACC="$(printf '%s' "${2:-}" | tr -dc 'a-fA-F0-9' | tr 'A-F' 'a-f')"
if [ "${#ACC}" -ge 6 ]; then ACC="${ACC: -6}"; else ACC="0a84ff"; fi
AR=$((16#${ACC:0:2})); AG=$((16#${ACC:2:2})); AB=$((16#${ACC:4:2}))

# map any accent to the nearest Reversal colour variant (by HSV hue/saturation)
reversal_color() {
    local r=$AR g=$AG b=$AB max=$AR min=$AR
    [ $g -gt $max ] && max=$g; [ $b -gt $max ] && max=$b
    [ $g -lt $min ] && min=$g; [ $b -lt $min ] && min=$b
    local d=$((max - min))
    if [ $d -eq 0 ] || [ $(( d * 100 / (max > 0 ? max : 1) )) -lt 15 ]; then echo grey; return; fi
    local hue
    if   [ $max -eq $r ]; then hue=$(( ( (g - b) * 60 / d + 360) % 360 ))
    elif [ $max -eq $g ]; then hue=$(( ( (b - r) * 60 / d + 120 + 360) % 360 ))
    else                       hue=$(( ( (r - g) * 60 / d + 240 + 360) % 360 )); fi
    if   [ $hue -lt 12 ];  then echo red
    elif [ $hue -lt 70 ];  then echo orange    # incl. yellow → orange (no yellow variant)
    elif [ $hue -lt 160 ]; then echo green
    elif [ $hue -lt 195 ]; then echo cyan
    elif [ $hue -lt 235 ]; then echo blue
    elif [ $hue -lt 300 ]; then echo purple
    elif [ $hue -lt 352 ]; then echo pink
    else echo red; fi
}
RC="$(reversal_color)"
# Mocu theme names are Mocu-{White,Black}-{Right,Left}; white reads best on dark.
CURSOR="Mocu-White-Right"; CURSOR_SIZE=24

if [ "$MODE" = "dark" ]; then
    GTK_THEME="adw-gtk3-dark"; PREFER_DARK=1; CS="prefer-dark"; ICONS="Reversal-${RC}-dark"
else
    GTK_THEME="adw-gtk3";      PREFER_DARK=0; CS="default";     ICONS="Reversal-${RC}"
fi

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"

# Shell style — read from user-theme.json (the single source both the shell
# and ewe-settings write) so every caller stays two-arg. "blacksheep" remaps
# the GTK neutrals below to the DE's absolute-black surface tokens.
STYLE="$(sed -n 's/.*"themeName": *"\([a-z]*\)".*/\1/p' "$CFG/quickshell/user-theme.json" 2>/dev/null | head -n1)"

# the style's neutral surface tokens (mirrors Theme.qml flock/pitchBlack) —
# consumed by kitty + Fresh below so the terminal/editor follow the shell style
if [ "$STYLE" = "blacksheep" ]; then
    S_BG="020202"; S_PANEL="0a0a0c"; S_ELEV="101012"; S_STROKE="222225"
else
    S_BG="1c1c1e"; S_PANEL="1d1d1f"; S_ELEV="2c2c2e"; S_STROKE="38383a"
fi
S_BG_R=$((16#${S_BG:0:2}));    S_BG_G=$((16#${S_BG:2:2}));    S_BG_B=$((16#${S_BG:4:2}))
S_PN_R=$((16#${S_PANEL:0:2})); S_PN_G=$((16#${S_PANEL:2:2})); S_PN_B=$((16#${S_PANEL:4:2}))
S_EL_R=$((16#${S_ELEV:0:2}));  S_EL_G=$((16#${S_ELEV:2:2}));  S_EL_B=$((16#${S_ELEV:4:2}))
S_ST_R=$((16#${S_STROKE:0:2}));S_ST_G=$((16#${S_STROKE:2:2}));S_ST_B=$((16#${S_STROKE:4:2}))

# ── universal cursor: ~/.icons/default is the fallback every toolkit reads ──
mkdir -p "$HOME/.icons/default"
cat > "$HOME/.icons/default/index.theme" <<EOF
[Icon Theme]
Name=Default
Comment=Default cursor theme
Inherits=$CURSOR
EOF

# ── GTK3 / GTK4 settings.ini ──────────────────────────────────────────────────
for v in 3.0 4.0; do
    mkdir -p "$CFG/gtk-$v"
    cat > "$CFG/gtk-$v/settings.ini" <<EOF
[Settings]
gtk-theme-name=$GTK_THEME
gtk-icon-theme-name=$ICONS
gtk-font-name=Ubuntu 11
gtk-application-prefer-dark-theme=$PREFER_DARK
gtk-cursor-theme-name=$CURSOR
gtk-cursor-theme-size=$CURSOR_SIZE
gtk-decoration-layout=:
EOF
done

# ── GTK accent — adw-gtk3 and libadwaita both read these named colors from
#    gtk.css, so Nemo/Engrampa selections follow the shell accent instead of
#    staying stock blue. Managed file: rewritten on every scheme apply. ──
# accent_fg follows luminance like the shell's Theme.accentText — white text
# on a yellow selection is unreadable. Threshold 140 (~0.55), matching the
# shell: mid-luminance accents (system green) already need ink, not white.
if [ $(( (AR * 299 + AG * 587 + AB * 114) / 1000 )) -gt 140 ]; then ACC_FG="1c1c1e"; else ACC_FG="ffffff"; fi
# Black Sheep — absolute-black surfaces (mirrors the shell's Theme.pitchBlack).
# libadwaita and adw-gtk3 both read these named colors; flock leaves them stock.
BS_CSS=""
if [ "$MODE" = "dark" ] && [ "$STYLE" = "blacksheep" ]; then
    BS_CSS='
/* Black Sheep surfaces */
@define-color window_bg_color #020202;
@define-color headerbar_bg_color #020202;
@define-color headerbar_backdrop_color #020202;
@define-color view_bg_color #0a0a0c;
@define-color sidebar_bg_color #060607;
@define-color sidebar_backdrop_color #040405;
@define-color secondary_sidebar_bg_color #040405;
@define-color secondary_sidebar_backdrop_color #030304;
@define-color card_bg_color rgba(255, 255, 255, 0.04);
@define-color dialog_bg_color #101012;
@define-color popover_bg_color #101012;
@define-color thumbnail_bg_color #101012;'
fi
for v in 3.0 4.0; do
    cat > "$CFG/gtk-$v/gtk.css" <<EOF
/* ewe accent — managed by colorscheme.sh; edits here are overwritten */
@define-color accent_color #${ACC};
@define-color accent_bg_color #${ACC};
@define-color accent_fg_color #${ACC_FG};${BS_CSS}
EOF
done

# ── kitty — the style + accent chrome lives in flock.conf (included at the
#    end of kitty.conf, so it overrides the committed fallbacks). The terminal
#    is DE chrome: it follows the shell style (flock greys / blacksheep black)
#    and the accent, staying dark in both modes. SIGUSR1 makes every running
#    kitty re-read its config live. ──
mkdir -p "$CFG/kitty"
# selection: accent blended 35 % into the terminal background
SR=$(( (AR * 35 + S_BG_R * 65) / 100 )); SG=$(( (AG * 35 + S_BG_G * 65) / 100 )); SB=$(( (AB * 35 + S_BG_B * 65) / 100 ))
SEL="$(printf '%02x%02x%02x' "$SR" "$SG" "$SB")"
cat > "$CFG/kitty/flock.conf" <<EOF
# GENERATED by colorscheme.sh — style + accent colours (edits are overwritten)
background            #${S_BG}
cursor                #${ACC}
cursor_text_color     #${S_BG}
url_color             #${ACC}
selection_background  #${SEL}
active_tab_background   #${ACC}
active_tab_foreground   #${ACC_FG}
inactive_tab_background #${S_PANEL}
active_border_color     #${ACC}
EOF
pkill -USR1 -x kitty 2>/dev/null || true

# ── zathura — style palette + accent; zathurarc includes this file ──
mkdir -p "$CFG/zathura"
cat > "$CFG/zathura/flock-colors" <<EOF
# GENERATED by colorscheme.sh — style palette (edits are overwritten)
set default-bg              "#${S_BG}"
set default-fg              "#f2f2f7"
set statusbar-bg            "#${S_PANEL}"
set statusbar-fg            "#aeaeb2"
set inputbar-bg             "#${S_PANEL}"
set inputbar-fg             "#f2f2f7"
set completion-bg           "#${S_ELEV}"
set completion-fg           "#f2f2f7"
set completion-group-bg     "#${S_PANEL}"
set completion-group-fg     "#8e8e93"
set completion-highlight-bg "#${ACC}"
set completion-highlight-fg "#${ACC_FG}"
set index-bg                "#${S_BG}"
set index-fg                "#f2f2f7"
set index-active-bg         "#${ACC}"
set index-active-fg         "#${ACC_FG}"
set highlight-color         "rgba(${AR},${AG},${AB},0.35)"
set highlight-active-color  "rgba(${AR},${AG},${AB},0.55)"
set notification-bg         "#${S_PANEL}"
set notification-fg         "#f2f2f7"
set notification-error-bg   "#${S_PANEL}"
set notification-error-fg   "#ff453a"
set notification-warning-bg "#${S_PANEL}"
set notification-warning-fg "#ff9f0a"
set recolor-lightcolor      "#${S_BG}"
set recolor-darkcolor       "#f2f2f7"
EOF

# ── Fresh (the terminal IDE) — generated theme following style + accent.
#    config.json (committed) points at ewe.json; this file is gitignored like
#    kitty's flock.conf. Fresh reads the theme at startup — running sessions
#    keep the old palette until relaunched. Syntax colours stay Gruvbox (same
#    ANSI family as kitty); only the chrome + accent follow the shell. ──
mkdir -p "$CFG/fresh/themes"
if [ "$ACC_FG" = "1c1c1e" ]; then ACC_FG_DEC="28, 28, 30"; else ACC_FG_DEC="255, 255, 255"; fi
cat > "$CFG/fresh/themes/ewe.json" <<EOF
{
  "name": "ewe",
  "editor": {
    "bg": [$S_BG_R, $S_BG_G, $S_BG_B],
    "fg": [242, 242, 247],
    "cursor": [$AR, $AG, $AB],
    "selection_bg": [$SR, $SG, $SB],
    "line_number": [99, 99, 102],
    "line_number_active": [242, 242, 247],
    "current_line_bg": [$S_EL_R, $S_EL_G, $S_EL_B]
  },
  "syntax": {
    "keyword": [251, 73, 52],
    "string": [184, 187, 38],
    "comment": [142, 142, 147],
    "function": [131, 165, 152],
    "type": [250, 189, 47],
    "number": [211, 134, 155],
    "constant": [254, 128, 25],
    "operator": [213, 196, 161],
    "variable": [242, 242, 247],
    "property": [142, 192, 124],
    "tag": [251, 73, 52],
    "attribute": [250, 189, 47],
    "punctuation": [142, 142, 147]
  },
  "ui": {
    "panel_bg": [$S_PN_R, $S_PN_G, $S_PN_B],
    "border": [$S_ST_R, $S_ST_G, $S_ST_B],
    "accent": [$AR, $AG, $AB],
    "status_bar_bg": [$S_EL_R, $S_EL_G, $S_EL_B],
    "status_bar_fg": [242, 242, 247],
    "tab_active_bg": [$S_EL_R, $S_EL_G, $S_EL_B],
    "tab_active_fg": [242, 242, 247],
    "tab_inactive_bg": [$S_PN_R, $S_PN_G, $S_PN_B],
    "tab_inactive_fg": [142, 142, 147],
    "menu_bg": [$S_PN_R, $S_PN_G, $S_PN_B],
    "menu_fg": [242, 242, 247],
    "menu_selected_bg": [$AR, $AG, $AB],
    "menu_selected_fg": [$ACC_FG_DEC]
  },
  "search": {
    "match_bg": [250, 189, 47],
    "match_fg": [$S_BG_R, $S_BG_G, $S_BG_B],
    "current_match_bg": [254, 128, 25],
    "current_match_fg": [$S_BG_R, $S_BG_G, $S_BG_B]
  },
  "diagnostics": {
    "error": [251, 73, 52],
    "warning": [250, 189, 47],
    "info": [131, 165, 152],
    "hint": [142, 142, 147]
  }
}
EOF

# ── gsettings — live nudge for libadwaita/GTK + cursor ──
if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface color-scheme "$CS"        2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme    "$GTK_THEME" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme   "$ICONS"     2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR"    2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-size  "$CURSOR_SIZE" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface font-name    "Ubuntu 11"  2>/dev/null || true
    gsettings set org.gnome.desktop.interface document-font-name "Ubuntu 11" 2>/dev/null || true
    # no close/min/max buttons in headerbars — Hyprland has no titlebars and
    # windows close via Super+Q; GTK3 reads gtk-decoration-layout from
    # settings.ini, GTK4/libadwaita follows this key
    gsettings set org.gnome.desktop.wm.preferences button-layout ':' 2>/dev/null || true
fi

# ── Qt (qt6ct + qt5ct) — dark Fusion palette for any stray Qt app ──
# First-party apps are GTK; this just keeps a Qt app you install (and the Quickshell
# shell's own Qt dialogs) on a dark palette instead of blinding white. Style = Fusion
# (QT_QPA_PLATFORMTHEME=qt6ct is set in start-hyprland.sh).
COLORS="$CFG/qt6ct/colors"
mkdir -p "$COLORS"
cat > "$COLORS/ewe-dark.conf" <<EOF
[ColorScheme]
active_colors=#ffdcdcdc, #ff2d2d2d, #ff3a3a3a, #ff333333, #ff1a1a1a, #ff262626, #ffdcdcdc, #ffffffff, #ffdcdcdc, #ff1e1e1e, #ff2a2a2a, #ff000000, #ff${ACC}, #ffffffff, #ff${ACC}, #ffb38aff, #ff242424, #ff2d2d2d, #ffdcdcdc, #ff7f7f7f
inactive_colors=#ffdcdcdc, #ff2d2d2d, #ff3a3a3a, #ff333333, #ff1a1a1a, #ff262626, #ffdcdcdc, #ffffffff, #ffdcdcdc, #ff1e1e1e, #ff2a2a2a, #ff000000, #ff3a3a3a, #ffdcdcdc, #ff${ACC}, #ffb38aff, #ff242424, #ff2d2d2d, #ffdcdcdc, #ff7f7f7f
disabled_colors=#ff6f6f6f, #ff2d2d2d, #ff3a3a3a, #ff333333, #ff1a1a1a, #ff262626, #ff6f6f6f, #ffffffff, #ff6f6f6f, #ff1e1e1e, #ff2a2a2a, #ff000000, #ff3a3a3a, #ff9f9f9f, #ff${ACC}, #ffb38aff, #ff242424, #ff2d2d2d, #ff6f6f6f, #ff5f5f5f
EOF
cat > "$COLORS/ewe-light.conf" <<EOF
[ColorScheme]
active_colors=#ff1a1a1a, #ffefefef, #ffffffff, #fff5f5f5, #ffb0b0b0, #ffc8c8c8, #ff1a1a1a, #ffffffff, #ff1a1a1a, #ffffffff, #ffefefef, #ff000000, #ff${ACC}, #ffffffff, #ff${ACC}, #ff6f42c1, #fff7f7f7, #ffffffdc, #ff1a1a1a, #ff808080
inactive_colors=#ff1a1a1a, #ffefefef, #ffffffff, #fff5f5f5, #ffb0b0b0, #ffc8c8c8, #ff1a1a1a, #ffffffff, #ff1a1a1a, #ffffffff, #ffefefef, #ff000000, #ff${ACC}, #ffffffff, #ff${ACC}, #ff6f42c1, #fff7f7f7, #ffffffdc, #ff1a1a1a, #ff808080
disabled_colors=#ffa0a0a0, #ffefefef, #ffffffff, #fff5f5f5, #ffb0b0b0, #ffc8c8c8, #ffa0a0a0, #ffffffff, #ffa0a0a0, #ffffffff, #ffefefef, #ff000000, #ff${ACC}, #ffe0e0e0, #ff${ACC}, #ff6f42c1, #fff7f7f7, #ffffffdc, #ffa0a0a0, #ffb0b0b0
EOF
SCHEME="$COLORS/ewe-$MODE.conf"
# migrate: drop the pre-rename scheme files so qt6ct never lists both
rm -f "$COLORS/hyprshell-dark.conf" "$COLORS/hyprshell-light.conf" 2>/dev/null
for q in qt6ct qt5ct; do
    mkdir -p "$CFG/$q"
    cat > "$CFG/$q/$q.conf" <<EOF
[Appearance]
custom_palette=true
color_scheme_path=$SCHEME
icon_theme=$ICONS
standard_dialogs=default
style=Fusion
EOF
done

# ── KDE / KF6 fallback — kdeglobals (only matters if you add a KDE app) ──
# We ship no KDE apps, but writing this keeps any KColorScheme-aware app you install
# later dark (incl. its item views) instead of falling back to a light default.
# Accent = Selection + Decoration*.
if [ "$MODE" = "dark" ]; then
    C_WIN="42,42,42";  C_WINA="36,36,36";  C_VIEW="30,30,30";  C_VIEWA="36,36,36"
    C_BTN="45,45,45";  C_FG="220,220,220";  C_FGI="130,130,130"; C_TIP="45,45,45"
    C_VIS="150,120,200"
else
    C_WIN="239,239,239"; C_WINA="247,247,247"; C_VIEW="255,255,255"; C_VIEWA="247,247,247"
    C_BTN="232,232,232"; C_FG="26,26,26";       C_FGI="130,130,130"; C_TIP="255,255,220"
    C_VIS="100,80,160"
fi
A="$AR,$AG,$AB"
_cgroup() {  # $1 bg  $2 bgAlt
    cat <<EOF
BackgroundNormal=$1
BackgroundAlternate=$2
ForegroundNormal=$C_FG
ForegroundInactive=$C_FGI
ForegroundActive=$A
ForegroundLink=$A
ForegroundVisited=$C_VIS
ForegroundNegative=218,68,83
ForegroundNeutral=246,116,0
ForegroundPositive=39,174,96
DecorationFocus=$A
DecorationHover=$A
EOF
}
{
    echo "[General]";  echo "ColorScheme=Ewe"; echo
    echo "[KDE]";      echo "widgetStyle=Fusion";    echo
    echo "[Icons]";    echo "Theme=$ICONS";          echo
    echo "[Colors:Window]";        _cgroup "$C_WIN"  "$C_WINA";  echo
    echo "[Colors:View]";          _cgroup "$C_VIEW" "$C_VIEWA"; echo
    echo "[Colors:Button]";        _cgroup "$C_BTN"  "$C_WINA";  echo
    echo "[Colors:Tooltip]";       _cgroup "$C_TIP"  "$C_TIP";   echo
    echo "[Colors:Complementary]"; _cgroup "$C_VIEW" "$C_VIEWA"; echo
    echo "[Colors:Selection]"
    echo "BackgroundNormal=$A"; echo "BackgroundAlternate=$A"
    echo "ForegroundNormal=255,255,255"; echo "ForegroundInactive=220,220,220"
    echo "ForegroundActive=255,255,255"; echo "ForegroundLink=255,255,255"
    echo "ForegroundVisited=235,235,235"; echo "ForegroundNegative=255,255,255"
    echo "ForegroundNeutral=255,255,255"; echo "ForegroundPositive=255,255,255"
    echo "DecorationFocus=$A"; echo "DecorationHover=$A"
} > "$CFG/kdeglobals"

# ── live update: nudge any already-running KDE app to re-read kdeglobals ──
# Legacy KGlobalSettings signal; a harmless no-op when no KDE app is listening.
if command -v dbus-send >/dev/null 2>&1; then
    dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32 0 int32 0 2>/dev/null || true
fi

exit 0
