pragma Singleton
import QtQuick

// Theme — single source of truth for colour, type, metrics and icons.
// Imported as `Theme.*`; components must never define their own.
//
// ONE look, built on FLUENT 2. Since 2026-09-04 there is no flock/blacksheep
// split and no theme file: every value here is DERIVED from the single accent
// in ewe.conf, by `ewe-theme`, which writes
// ~/.config/quickshell/theme-tokens.json. What you can change lives in
// ewe.conf next to everything else that describes your machine:
//
//   [desktop.theme]
//   accent       = "#ffcc00"      # THE seed — the brand ramp comes from this
//   corner       = "medium"       # none | small | medium | large
//   density      = "comfortable"  # compact | comfortable | roomy
//   stroke       = "thin"         # thin | thick
//   neutral_tint = 8              # how far the greys follow the accent
//
// WHY FLUENT. ewe had ONE `hover` and ONE `stroke`, so there was no way to say
// "hover on a card" apart from "hover on a bare row", or "divider" apart from
// "focus ring". Every border and hover bug came out of that missing vocabulary.
// Fluent names them, and the names below are its roles.
//
// PICKING A TOKEN. Ask what the thing IS, not what colour you want:
//
//   a surface at rest        bg-1 (panel) · bg-2 (a well) · bg-3 (the base)
//   a raised, FILLED thing   card / cardHover / cardPressed / cardSelected
//   no fill until you point  subtle / subtleHover / subtlePressed
//   an interactive border    stroke1        a card outline   stroke2
//   a divider between rows   stroke3        a border that MUST be seen
//                                           strokeAccessible
//   a filled brand control   accentFill + accentOn (never `accent` + white)
//   the accent AS a mark     accent (text, icon, dot, indicator)
//
// Hover a FILLED thing with its own level's hover; hover a bare row with
// subtleHover. Getting that pair the wrong way round is what made a hovered
// tile jump colour and square off over its own border.
//
// Every literal below is a FALLBACK for a machine whose token file is missing
// or unreadable; the file is authoritative whenever it is there.
//
// ewe is dark-only (decision 2026-09-01). Fonts are never themed.
QtObject {
    id: t

    // ── Which look ────────────────────────────────────────────────────────
    // There is ONE ewe. Nothing asks "which theme is on" any more — the last
    // component reading `blacksheep`/`pitchBlack` was migrated 2026-09-04 and
    // both flags are gone. Squareness is a TOKEN, not a look: `corner =
    // "none"` in ewe.conf zeroes the radius ramp and this follows.
    readonly property bool brutalist:    radius === 0

    // ── Where the values come from ────────────────────────────────────────
    // ewe-theme.conf is the source of truth; `ewe-theme build` writes
    // ~/.config/quickshell/theme-tokens.json and Globals loads it. Everything
    // below asks _c/_s/_v for its value and passes the shipped literal as the
    // FALLBACK, so the file is authoritative when present and the desktop
    // still comes up correctly when it is missing, stale or unparsable.
    // Three maps, straight off theme-tokens.json: colour, shape, size. Every
    // literal passed as `fb` below is a FALLBACK for a machine whose token
    // file is missing or unreadable — the file wins whenever it is there.
    readonly property var _fc: Globals.tokColor
    readonly property var _fs: Globals.tokShape
    readonly property var _fz: Globals.tokSize
    function _f(k, fb) { return (_fc && _fc[k]) || fb }
    function _s(k, fb) { return (_fs && _fs[k] !== undefined) ? _fs[k] : fb }
    function _z(k, fb) { return (_fz && _fz[k] !== undefined) ? _fz[k] : fb }

    // ══ FLUENT ROLES ══════════════════════════════════════════════════════
    // The vocabulary ewe was missing. Everything below comes straight off the
    // top level of theme-tokens.json; the literals are the DEFAULT accent's
    // values, used only when that file is absent. Components are migrating
    // onto these names — see the legacy aliases further down.

    // ── Backgrounds: six levels, each with its own four states ────────────
    // Pick the LEVEL by how deep the surface sits, then always take that
    // level's own -hover/-pressed. Never hover a filled surface with the
    // `subtle` tokens: that is what made hovered content jump colour and
    // paint over its container's border.
    //   bg-3  desktop / app base      bg-1  panel or popup on it
    //   bg-2  a well inside a panel   bg-6  a card or row raised on a panel
    //   bg-4/5  deeper than the base — scrims, the black end
    readonly property color bg1:         _f("bg-1", "#28292c")
    readonly property color bg1Hover:    _f("bg-1-hover", "#3c3d41")
    readonly property color bg1Pressed:  _f("bg-1-pressed", "#1e1f22")
    readonly property color bg1Selected: _f("bg-1-selected", "#37383c")
    readonly property color bg2:         _f("bg-2", "#1e1f22")
    readonly property color bg2Hover:    _f("bg-2-hover", "#323337")
    readonly property color bg2Pressed:  _f("bg-2-pressed", "#131417")
    readonly property color bg2Selected: _f("bg-2-selected", "#2d2e32")
    readonly property color bg3:         _f("bg-3", "#131417")
    readonly property color bg3Hover:    _f("bg-3-hover", "#28292c")
    readonly property color bg3Pressed:  _f("bg-3-pressed", "#090a0e")
    readonly property color bg3Selected: _f("bg-3-selected", "#232427")
    readonly property color bg4:         _f("bg-4", "#090a0e")
    readonly property color bg4Hover:    _f("bg-4-hover", "#1e1f22")
    readonly property color bg4Pressed:  _f("bg-4-pressed", "#000000")
    readonly property color bg4Selected: _f("bg-4-selected", "#191a1d")
    readonly property color bg5:         _f("bg-5", "#000000")
    readonly property color bg5Hover:    _f("bg-5-hover", "#131417")
    readonly property color bg5Pressed:  _f("bg-5-pressed", "#040509")
    readonly property color bg5Selected: _f("bg-5-selected", "#0e0f12")
    readonly property color bg6:         _f("bg-6", "#323337")
    readonly property color bgDisabled:  _f("bg-disabled", "#131417")

    // ── Card: a raised, FILLED surface that reacts to the pointer ─────────
    // A tile, a card, a filled row on a panel. Use THIS ladder, not `subtle`:
    // subtle is for something with no fill of its own, and reaching for it to
    // hover a filled thing is what made tiles jump to an unrelated colour.
    readonly property color card:         _f("card", "#323337")
    readonly property color cardHover:    _f("card-hover", "#46474b")
    readonly property color cardPressed:  _f("card-pressed", "#28292c")
    readonly property color cardSelected: _f("card-selected", "#414246")

    // ── Subtle: a thing with NO fill of its own until you point at it ─────
    // List rows, menu items, toolbar buttons, bar items. `subtle` really is
    // transparent, so the container's own colour shows through and only the
    // hover paints. THIS is the token every "hover a bare row" bug wanted.
    // Inset such a row by `hoverInset` so its hover can never cover a rule.
    readonly property color subtle:         _f("subtle", "transparent")
    readonly property color subtleHover:    _f("subtle-hover", "#37383c")
    readonly property color subtlePressed:  _f("subtle-pressed", "#2d2e32")
    readonly property color subtleSelected: _f("subtle-selected", "#323337")

    // ── Strokes: three weights, not one ───────────────────────────────────
    //   stroke-1  a real UI border — input, button, anything you interact with
    //   stroke-2  a subtle outline — a card, a panel edge
    //   stroke-3  a divider between rows; the quietest rule that still reads
    //   stroke-accessible  a border that MUST be seen (unchecked checkbox)
    //   stroke-focus-1/2   the two halves of a focus ring: dark inside,
    //                      light outside, so it lands on any background
    readonly property color stroke1:          _f("stroke-1", "#656668")
    readonly property color stroke1Hover:     _f("stroke-1-hover", "#757577")
    readonly property color stroke1Pressed:   _f("stroke-1-pressed", "#6a6b6d")
    readonly property color stroke1Selected:  _f("stroke-1-selected", "#707072")
    readonly property color stroke2:          _f("stroke-2", "#515255")
    readonly property color stroke3:          _f("stroke-3", "#3c3d41")
    readonly property color strokeAccessible: _f("stroke-accessible", "#adadad")
    readonly property color strokeDisabled:   _f("stroke-disabled", "#414246")
    readonly property color strokeFocus1:     _f("stroke-focus-1", "#000000")
    readonly property color strokeFocus2:     _f("stroke-focus-2", "#ffffff")

    // ── Foregrounds ───────────────────────────────────────────────────────
    //   fg-1 primary · fg-2 secondary · fg-3 tertiary, placeholder, icons
    //   fg-4 the quietest still-readable text · fg-inverted on a light fill
    //   fg-on-brand  text ON a brand fill. MEASURED, not assumed white —
    //                a yellow accent gets ink. (ewe's deviation from Fluent.)
    readonly property color fg1:        _f("fg-1", "#ffffff")
    readonly property color fg2:        _f("fg-2", "#d6d6d6")
    readonly property color fg2Hover:   _f("fg-2-hover", "#ffffff")
    readonly property color fg3:        _f("fg-3", "#adadad")
    readonly property color fg3Hover:   _f("fg-3-hover", "#d6d6d6")
    readonly property color fg4:        _f("fg-4", "#99999a")
    readonly property color fgDisabled: _f("fg-disabled", "#5b5c5f")
    readonly property color fgInverted: _f("fg-inverted", "#232427")
    readonly property color fgOnBrand:  _f("fg-on-brand", "#ffffff")

    // ── Brand ─────────────────────────────────────────────────────────────
    //   brand-bg*        a FILLED primary control
    //   brand-fg-1/link  the accent AS text or an icon on a dark ground
    //   compound-*       a control whose fill and stroke move together
    //                    (checkbox, radio, switch) — the one place Fluent
    //                    BRIGHTENS on hover so the control reads as live
    readonly property color brandBg:                _f("brand-bg", "#0a73db")
    readonly property color brandBgHover:           _f("brand-bg-hover", "#0a84ff")
    readonly property color brandBgPressed:         _f("brand-bg-pressed", "#1c467c")
    readonly property color brandBgSelected:        _f("brand-bg-selected", "#2065bb")
    readonly property color brandFg1:               _f("brand-fg-1", "#82aeff")
    readonly property color brandFg2:               _f("brand-fg-2", "#93b8ff")
    readonly property color brandFgLink:            _f("brand-fg-link", "#82aeff")
    readonly property color brandFgLinkHover:       _f("brand-fg-link-hover", "#93b8ff")
    readonly property color brandStroke1:           _f("brand-stroke-1", "#82aeff")
    readonly property color brandStroke2:           _f("brand-stroke-2", "#1b559c")
    readonly property color compoundBrandBg:        _f("compound-brand-bg", "#82aeff")
    readonly property color compoundBrandBgHover:   _f("compound-brand-bg-hover", "#93b8ff")
    readonly property color compoundBrandBgPressed: _f("compound-brand-bg-pressed", "#5c9aff")
    readonly property color compoundBrandFg:        _f("compound-brand-fg", "#82aeff")
    readonly property color compoundBrandStroke:    _f("compound-brand-stroke", "#82aeff")

    // ── Status backgrounds and borders ────────────────────────────────────
    // For a banner or badge that needs a tinted ground rather than just
    // coloured text. Deliberately NOT accent-derived: "this failed" must not
    // change meaning because you picked a red accent.
    readonly property color successBg:     _f("success-bg", "#052505")
    readonly property color successBorder: _f("success-border", "#9fd89f")
    readonly property color warningBg:     _f("warning-bg", "#332a00")
    readonly property color warningBorder: _f("warning-border", "#fbde3d")
    readonly property color dangerBg:      _f("danger-bg", "#3b0509")
    readonly property color dangerBorder:  _f("danger-border", "#f1707b")
    readonly property color infoBg:        _f("info-bg", "#222527")
    readonly property color infoBorder:    _f("info-border", "#9ea2a6")

    readonly property color shadow:      Qt.rgba(0, 0, 0, 0.28)

    // ── Bar shape ─────────────────────────────────────────────────────────
    // Identical stops render the gradient node flat — kept so Bar.qml needs
    // no conditional, and a future look can reintroduce a real gradient by
    // touching only these two tokens.
    readonly property color barTop:      bg3
    readonly property color barBottom:   bg3
    readonly property color barBorder:   stroke2
    // A bar item has no fill of its own until you point at it — `subtle` is
    // exactly that case, and the reason the two are the same token now.
    readonly property color barHover:    subtleHover
    readonly property color barActive:   subtleSelected
    readonly property int barItemRadius: radiusPill
    readonly property int barItemHeight: 22
    readonly property int barItemSpacing: 6
    // every glyph on the bar renders at this size — no per-site literals
    readonly property int barIconPx:     _z("icon", 18)

    // Accent — whatever Settings → Theme wrote into user-theme.json. The
    // user's in-shell pick always wins; until there is one this falls back to
    // the accent in ewe.conf [desktop.theme], which is the same seed the
    // whole token file above was derived from.
    readonly property color accent:      Globals.accentExplicit ? Globals.accentColor
                                         : _f("brand-fg-1", Globals.accentColor)
    // accentText auto-contrasts with the accent (white on dark accents, ink on
    // light ones) so foreground text on accent fills stays legible at any hue.
    // 0.55, not 0.6: mid-luminance accents (the system green) already lose
    // white text — tip to ink earlier.
    readonly property color accentText:  (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.55 ? "#1c1c1e" : "#ffffff"

    // Fluent splits what ewe had fused. `accent` is one value doing two jobs —
    // it marks text AND fills a button — and no single value is right for
    // both: dark enough to fill is too dark to read, light enough to read is
    // washed out as a fill. The two roles are published separately here, and
    // components move onto them as they are migrated:
    //
    //   accentFill / accentOn   a FILLED control (button, active tile, switch)
    //   accent                  the accent AS a mark (text, icon, indicator)
    //
    // Until a component is migrated it keeps using `accent`, which stays the
    // legible-on-dark one — a washed fill is ugly, an unreadable label is not
    // usable. Falls back to `accent` when the token file is missing.
    readonly property color accentFill: _f("brand-bg", accent)
    readonly property color accentOn:   _f("fg-on-brand", accentText)

    // ── Status cues (battery / vpn / connectivity / profile) ──────────────
    // Fluent's shared status hues at its dark-theme tints. NOT accent-derived
    // — "this failed" must not change meaning because you picked a red
    // accent. For a tinted ground rather than coloured text, use the
    // successBg / warningBorder / … roles above.
    readonly property color success:     _f("success", "#54b054")  // charging · connected
    readonly property color warning:     _f("warning", "#fdea3d")  // low-ish · performance
    readonly property color danger:      _f("danger", "#f1707b")  // critical / destructive
    // interactive: `link` reads on the ground, `linkSolid` is a fill
    readonly property color link:        _f("brand-fg-link", "#82aeff")
    readonly property color linkSolid:   _f("brand-bg", "#0a73db")

    // ── Type ──────────────────────────────────────────────────────────────
    // Ubuntu for body AND titles — one humanist face that reads equally well
    // in Latin and (via the fontconfig fallback to Noto Sans Georgian, see
    // dotfiles/fontconfig/) Georgian. SF Pro was never installed, so text
    // actually rendered through whatever fc-match picked.
    readonly property string fontText:    "Ubuntu"
    readonly property string fontDisplay: "Ubuntu"
    // real monospace TEXT (clipboard entries, kb hints) — ttf-jetbrains-mono-nerd
    readonly property string fontMono:    "JetBrainsMono Nerd Font"
    // icon glyphs — Lucide (vendored in fonts/, ISC). Icons are ALWAYS
    // rendered with fontIcons, never fontMono: the codepoints are private-use
    // and only exist in this face.
    readonly property FontLoader _icons: FontLoader { source: Qt.resolvedUrl("fonts/Lucide.ttf") }
    readonly property string fontIcons:   _icons.status === FontLoader.Ready ? _icons.name : "lucide"

    // The type ladder is a SIZE decision, so it comes from [<theme>.size] and
    // a look can breathe more without touching a single component.
    readonly property int fsSmall:  _z("fs-small", 12)
    readonly property int fsBody:   _z("fs-body", 14)
    readonly property int fsLarge:  _z("fs-large", 16)
    readonly property int fsTitle:  _z("fs-title", 24)

    // ── Metrics & shape ───────────────────────────────────────────────────
    // Radius is a THEME decision, not a per-component one. Bauhaus is square:
    // "no border-radius or minimal" — zero everywhere, no exceptions, because
    // a single rounded corner in a square system reads as a mistake.
    // Alexandria rounds softly (its own scale: 0.375rem / 0.5rem / 0.75rem).
    readonly property int radius:       _s("radius-panel", 8)   // panels / launcher
    readonly property int radiusInner:  _s("radius-card", 6)   // rows, input field
    readonly property int radiusPill:   _s("radius-pill", 4)

    // Border WIDTH travels with the border colour: Alexandria hairlines at
    // 1px, Bauhaus rules at 2-3px. Components use `Theme.border` rather than
    // a literal, so the same card is outlined in one look and drawn in the
    // other. borderThin is for dense rows where 3px would fill the row.
    readonly property int border:       _s("stroke-width", 1)
    readonly property int borderThin:   _s("stroke-width", 1)

    // Depth. Bauhaus forbids soft shadows — depth is a solid block offset
    // down-right ("offset shadows: 4-6px"). Zero here means "use the blurred
    // Elevation effect instead", which is what Alexandria wants.
    readonly property int shadowOffset: 0

    // Typographic voice — "uppercase buttons" is a Bauhaus rule about the
    // whole system, not a decision per control. Mirrors --label-* in
    // design/tokens.css.
    readonly property int labelCaps:     Font.MixedCase
                                             ? Font.AllUppercase : Font.MixedCase
    readonly property real labelTracking: 0
    readonly property int labelWeight:   Font.Medium

    // Corner scaler for the many one-off radii components carry (a 7px chip, a
    // 9px thumbnail). Bauhaus is square with NO exceptions, so flock collapses
    // every one of them to 0; Alexandria keeps the value it was given, so its
    // geometry is unchanged. Use it instead of a literal:  radius: Theme.r(8)
    //
    // TRUE CIRCLES are not radii in this sense — an avatar written as
    // `width: 38; height: 38; radius: 19` is geometry, and squaring it would
    // fight the user's own avatarShape preference. Those keep their literal.
    function r(n) { return brutalist ? 0 : n }

    // ── Overlays that sit inside something else ───────────────────────────
    // A hover or selection fill anchored flush to its container paints OVER
    // that container's own rule, so the card loses its outline exactly while
    // you point at it — and if the fill carries a smaller radius than the
    // container, the corners read as square inside a rounded box. Both are the
    // same mistake: an overlay must be inset by the rule it must not cover,
    // and carry the radius that inset leaves behind.
    //
    //   Rectangle {                       // the hovered fill
    //       anchors.fill: parent; anchors.margins: Theme.hoverInset
    //       radius: Theme.rIn(Theme.radiusInner)
    //   }
    //
    // hoverInset defaults to the border width, which is the value that makes
    // the rule survive by definition.
    readonly property int hoverInset: _s("stroke-width", border)
    // The radius an overlay needs to stay concentric with a container of
    // radius n once it has been inset. Concentric, not equal: an inset shape
    // that keeps the outer radius bulges at the corners.
    // Pass an explicit inset when the overlay sits inside something other than
    // a hover fill — a rail inside a panel is inset by the PANEL's border.
    function rIn(n, inset) {
        var i = (inset === undefined) ? hoverInset : inset
        return brutalist ? 0 : Math.max(0, r(n) - i)
    }

    // ── How a surface announces itself ────────────────────────────────────
    // Two honest answers, and the looks give different ones. Bauhaus DRAWS a
    // card — a visible rule around every block. Alexandria stacks tonal steps
    // and lets the lightness ladder separate them. Using the tonal answer in
    // flock is what made it look unfinished: `elevated` on `panel` is a 4%
    // step, which simply does not read on ink. Components ask for cardStroke /
    // cardBorder and get whichever answer the look gives.
    // A card's outline. Fluent gives a card the SUBTLE stroke — stroke-2, not
    // the interactive stroke-1 an input or button gets. One name so every
    // container in the shell agrees, instead of each picking its own weight.
    readonly property color cardStroke: stroke2
    readonly property int cardBorder:   borderThin

    // Focus ring width — one value, so every focusable control rings alike.
    readonly property int focusWidth: _s("focus-width", 2)

    readonly property int pad:          _z("pad", 12)
    readonly property int gap:          _z("gap", 8)
    readonly property int rowHeight:    _z("row", 36)      // list row / menu item
    readonly property int controlHeight: _z("control", 30) // button / input / chip
    readonly property int barHeight:    _z("bar-height", 30)

    // ── Motion (ms) — follows the Animations pane (animations.json, written
    //    by ewe-settings) when that file exists: every shell surface is a
    //    layershell layer, so the pane's "layers" leaf (global as fallback)
    //    sets the base duration and curve here, exactly as
    //    generated/animations.lua does for Hyprland — one pane, both halves.
    //    Without the file, the legacy Settings → Theme speed multiplier
    //    applies (Off/Fast/Normal/Slow = m 0/2/1/0.6 → durBase 0/150/300/500).
    readonly property var _aj: Globals.animPrefs
    readonly property var _ajLayers: _aj && _aj.anims ? _aj.anims.layers : null
    readonly property bool _animOff: _aj ? (_aj.enabled === false || (_ajLayers && _ajLayers.on === false))
                                         : Globals.animationSpeed <= 0
    readonly property int _msBase: _aj ? ((_ajLayers && _ajLayers.ms) || (_aj.global && _aj.global.ms) || 300)
                                       : Math.round(300 / Math.max(Globals.animationSpeed, 0.001))
    readonly property int durFast:   _animOff ? 0 : Math.max(1, Math.round(_msBase * 0.5))
    readonly property int durBase:   _animOff ? 0 : _msBase
    readonly property int durSlow:   _animOff ? 0 : Math.round(_msBase * 1.4)

    // The pane's Hyprland curve mapped to its closest stock QML easing — used
    // by every `easing.type: Theme.ease` Behavior so the shell's motion FEEL
    // matches the compositor's. Unset/unknown curve = the old OutCubic.
    readonly property string _curve: _aj ? String((_ajLayers && _ajLayers.curve) || (_aj.global && _aj.global.curve) || "") : ""
    readonly property int ease: _curve === "snap"           ? Easing.OutExpo
                              : _curve === "quick"          ? Easing.OutQuart
                              : _curve === "easeOutQuint"   ? Easing.OutQuint
                              : _curve === "easeInOutCubic" ? Easing.InOutCubic
                              : _curve === "overshoot"      ? Easing.OutBack
                              : _curve === "linear"         ? Easing.Linear
                              : _curve === "spring"         ? Easing.OutBack
                              : Easing.OutCubic

    // ── Icons — the SINGLE glyph table. Every component
    //    pulls its glyphs from here with font.family: Theme.fontIcons, so the
    //    same concept renders the same icon everywhere.
    //
    //    LUCIDE 1.40.0 (ISC), vendored as fonts/Lucide.ttf — the whole face,
    //    2077 glyphs, so any Lucide icon is reachable by codepoint without
    //    regenerating anything. Codepoints come from the package's own
    //    font/codepoints.json and are STABLE: across 40 minor releases and
    //    125 added icons exactly one established glyph moved, and that was a
    //    deprecated alias. Re-extract only if the vendored TTF is upgraded.
    //
    //    Lucide is STROKE art where Phosphor Fill was solid, so a glyph reads
    //    lighter at the same pixelSize. Sizes are tuned for that in the size
    //    ramp above, not per call site.
    //
    //    Names below are the Lucide names — paste one into lucide.dev/icons
    //    to see it. ────────────────────────────────────────────────────────
    function ic(code) { return String.fromCodePoint(code) }
    readonly property string icSearch:       ic(0xE151)  // search
    readonly property string icSearchOff:    ic(0xE4AD)  // search-x — no results
    readonly property string icClose:        ic(0xE1B2)  // x
    readonly property string icChevronDown:  ic(0xE06D)  // chevron-down
    readonly property string icChevronUp:    ic(0xE070)  // chevron-up
    readonly property string icChevronRight: ic(0xE06F)  // chevron-right
    readonly property string icWifi:         ic(0xE1AE)  // wifi
    readonly property string icWifiMed:      ic(0xE5F7)  // wifi-high
    readonly property string icWifiLow:      ic(0xE5F8)  // wifi-low
    readonly property string icWifiOff:      ic(0xE1AF)  // wifi-off
    readonly property string icEthernet:     ic(0xE620)  // ethernet-port
    readonly property string icBluetooth:    ic(0xE05C)  // bluetooth
    readonly property string icBluetoothOn:  ic(0xE1B8)  // bluetooth-connected
    readonly property string icVpn:          ic(0xE1FF)  // shield-check — bar AND control centre
    readonly property string icSsh:          ic(0xE20A)  // square-terminal
    readonly property string icWeb:          ic(0xE0E8)  // globe — browse / port-forward
    readonly property string icCamera:       ic(0xE064)  // camera
    readonly property string icClipboard:    ic(0xE14E)  // scissors — clipboard popup
    readonly property string icTrash:        ic(0xE18E)  // trash-2
    readonly property string icPencil:       ic(0xE1F9)  // pencil
    readonly property string icEye:          ic(0xE0BA)  // eye — insomnia / keep-awake
    readonly property string icEyeOff:       ic(0xE0BB)  // eye-off
    readonly property string icDnd:          ic(0xE11E)  // moon — do not disturb
    readonly property string icCast:         ic(0xE066)  // cast — cast to TV
    readonly property string icSun:          ic(0xE178)  // sun — brightness
    readonly property string icBolt:         ic(0xE1B4)  // zap — charging
    readonly property string icBattFull:     ic(0xE055)  // battery-full
    readonly property string icBatt80:       ic(0xE057)  // battery-medium
    readonly property string icBatt50:       ic(0xE056)  // battery-low
    readonly property string icBatt20:       ic(0xE3AC)  // battery-warning
    readonly property string icBattEmpty:    ic(0xE053)  // battery
    readonly property string icLeaf:         ic(0xE2DE)  // leaf — power-saver
    readonly property string icBalance:      ic(0xE212)  // scale — balanced
    readonly property string icSpeed:        ic(0xE1BF)  // gauge — performance
    readonly property string icVolHigh:      ic(0xE1AB)  // volume-2
    readonly property string icVolLow:       ic(0xE1AA)  // volume-1
    readonly property string icPlay:         ic(0xE13C)  // play
    readonly property string icPause:        ic(0xE12E)  // pause
    readonly property string icPrev:         ic(0xE15F)  // skip-back
    readonly property string icNext:         ic(0xE160)  // skip-forward
    readonly property string icMusic:        ic(0xE122)  // music
    readonly property string icMonitorOff:   ic(0xE11D)  // monitor — display states
    readonly property string icLock:         ic(0xE10B)  // lock
    readonly property string icPower:        ic(0xE140)  // power
    readonly property string icCog:          ic(0xE154)  // settings
    readonly property string icTiling:       ic(0xE0FF)  // layout-grid — tiling on
    readonly property string icFloating:     ic(0xE426)  // app-window — windows float
    readonly property string icCheck:        ic(0xE06C)  // check
    readonly property string icPhone:        ic(0xE163)  // smartphone — mobile connection
    readonly property string icMessage:      ic(0xE116)  // message-circle — SMS
    readonly property string icSend:         ic(0xE152)  // send
    readonly property string icBellRing:     ic(0xE224)  // bell-ring — find my phone / mail notify
    readonly property string icBell:         ic(0xE059)  // bell — bar: notification history
    readonly property string icCalendar:     ic(0xE063)  // calendar — bar: an event is near
    readonly property string icRefresh:      ic(0xE145)  // refresh-cw
    readonly property string icBack:         ic(0xE048)  // arrow-left
    readonly property string icMail:         ic(0xE10F)  // mail — Gmail
    readonly property string icFile:         ic(0xE0C0)  // file — overview file results
    readonly property string icFolder:       ic(0xE0D7)  // folder — places / dock
    readonly property string icHome:         ic(0xE0F5)  // house — places home
    readonly property string icPin:          ic(0xE259)  // pin — launcher pin
    readonly property string icUser:         ic(0xE19F)  // user — avatar fallback
    readonly property string icStar:         ic(0xE176)  // star — primary display
    readonly property string icCpu:          ic(0xE0A9)  // cpu — meter
    readonly property string icMemory:       ic(0xE445)  // memory-stick — meter
    readonly property string icImage:        ic(0xE0F6)  // image — wallpaper empty state
    readonly property string icWarning:      ic(0xE193)  // triangle-alert — danger rows
    readonly property string icApps:         ic(0xE0E9)  // grid-3x3 — dock app grid
    readonly property string icStack:        ic(0xE529)  // layers — dock overview
    readonly property string icPen:          ic(0xE129)  // package — dock: stashed windows
    readonly property string icDownload:     ic(0xE0B2)  // download — dock downloads
    readonly property string icKeyboard:     ic(0xE284)  // keyboard
    readonly property string icPlus:         ic(0xE13D)  // plus
}
