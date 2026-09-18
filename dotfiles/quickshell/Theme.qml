pragma Singleton
import QtQuick

// Theme — single source of truth for colour, type, metrics, motion and icons.
// Imported as `Theme.*`; components must never define their own.
//
// ONE look: the EWE DESIGN SYSTEM v3 (design/system/). Every value here comes
// from `bin/ewe-theme`, which derives the whole token set from the scheme and
// the accent in ewe.conf and writes ~/.config/quickshell/theme-tokens.json.
// What you can change:
//
//   [desktop.theme]
//   scheme       = "ewe-dark"     # ewe-dark | ewe-light | a user scheme slug
//   accent       = "#eeb407"      # ewellow, the brand gold — any colour works
//   corner       = "medium"       # none | small | medium | large
//   density      = "comfortable"  # compact | comfortable | roomy
//   stroke       = "thin"         # none | thin | thick   (component outlines)
//   bar_opacity  = 100            # 0-100 — Glass on the bar, dock, lock card
//   app_blur     = false          # blur behind every window (Hyprland side)
//   [desktop.bar]            size = "normal"   # normal (48) | large (64)
//   [desktop.accessibility]  reduce_motion, reduce_transparency,
//                            increase_contrast, text_scale = 100|115|130
//
// THE WORKING RULES (design/system/README.md, restated for QML):
//
//   01  Ask for a ROLE, never a value. No raw colours, sizes or durations in
//       a component: if a role is missing, it is missing HERE. The literals
//       below are FALLBACKS mirroring the generator's Ewe Dark defaults, for
//       a machine whose token file is missing or unparsable.
//   02  Schemes, look presets, Glass and the accessibility modes are REMAPS
//       the generator applies. A component never asks which one is active.
//   03  State comes from the next role in the set, never from opacity or a
//       lighter()/darker() call:  surface → surfaceHover → surfacePressed.
//   04  Two line weights only: borderWidth1 and borderWidth2. Focus rings are
//       focusWidth (1px; Increase contrast makes it 2).
//   05  Corners by ROLE: radiusPrimary (8) controls, radiusRounded (10)
//       panels and cards, radiusFull only badges, tags and switches.
//   06  Motion confirms, never decorates: durFast 150 / durBase 200 /
//       durSlow 250 / durDim 1500 at Normal speed, OutCubic (InOutCubic for
//       slow). Nothing bounces — there is no OutBack anywhere.
//   07  Type comes from `type.<style>`; build custom text from the scale
//       tokens, always pairing a size with the line height of its step.
//       Georgian is NEVER uppercased (labelCaps is MixedCase, on purpose).
//   08  Icons are a font (Lucide, fontIcons): size and tint go through
//       pixelSize and color, never a per-icon asset.
//   09  Text, glyphs, badges and accent fills stay solid. Only bar, dock and
//       lock-card FILLS turn translucent, through the glass* roles.
//   10  The apps map their framework onto the same tokens (design/tokens.css),
//       so a QML surface and a Svelte pane are one design.
//
// The FLUENT names (bg1, card, brandBg, …) are still published at the bottom,
// each pointing at its Ewe role per the Migration guide, so unmigrated
// components keep working. Phase 6 deletes them.
QtObject {
    id: t

    // ── Which look ────────────────────────────────────────────────────────
    // Squareness is a TOKEN, not a look: `corner = "none"` in ewe.conf zeroes
    // the radius ramp and this follows.
    readonly property bool brutalist:    radiusRounded === 0

    // ── Where the values come from ────────────────────────────────────────
    // theme-tokens.json, block by block, through Globals. Every property asks
    // its block for a token and passes the shipped literal as the FALLBACK,
    // so the file is authoritative when present and the desktop still comes
    // up correctly when it is missing, stale or unparsable.
    readonly property var _fc: Globals.tokColor      // color
    readonly property var _fs: Globals.tokShape      // shape
    readonly property var _fz: Globals.tokSize       // size
    readonly property var _fi: Globals.tokInput      // what ewe.conf said
    readonly property var _ft: Globals.tokType       // families, weights, styles
    readonly property var _fm: Globals.tokMotion     // durations + easings
    readonly property var _fo: Globals.tokOpacity    // opacity
    readonly property var _fd: Globals.tokShadow     // shadow
    readonly property var _fg: Globals.tokGradient   // gradient
    readonly property var _fb: Globals.tokBar        // bar height/module/icon
    readonly property var _fa: Globals.tokA11y       // accessibility modes
    function _get(m, k, fb) { return (m && m[k] !== undefined && m[k] !== null) ? m[k] : fb }
    function _f(k, fb)  { return (_fc && _fc[k]) || fb }
    function _s(k, fb)  { return _get(_fs, k, fb) }
    function _z(k, fb)  { return _get(_fz, k, fb) }
    function _i(k, fb)  { return _get(_fi, k, fb) }
    function _o(k, fb)  { return _get(_fo, k, fb) }
    function _m(k, fb)  { return _get(_fm, k, fb) }
    function _w(k, fb)  { return _get(_ft && _ft.weight, k, fb) }
    function _tr(k, fb) { return _get(_ft && _ft.tracking, k, fb) }
    function _d(k, fb)  { return _get(_fd, k, fb) }
    function _gr(k, fb) { return _get(_fg, k, fb) }
    function _bz(k, fb) { return _get(_fb, k, fb) }
    function _ax(k, fb) { return _get(_fa, k, fb) }

    // ══ EWE TOKENS ════════════════════════════════════════════════════════
    // One property per token, named as design/system/guidelines/
    // 40-implementation.md's QML column: the token name in camelCase, with a
    // `radius` prefix on the corner tokens.

    // ── Colour ────────────────────────────────────────────────────────────
    //   surface-*  grounds      text-*    copy        border-*  lines
    //   accent*    primary actions and selection (on-accent for ink on them)
    //   glass-*    the bar, dock and lock card while Glass is on
    //   status     success · warning · danger · info (+ -subtle grounds)
    // The ewellow-* ramp is derived from the chosen accent; `ewellow` itself
    // stays the brand gold (logo, installer, wallpapers).
    readonly property color ewellow:         _f("ewellow", "#eeb407")
    readonly property color black:           _f("black", "#020202")
    readonly property color ewellow50:       _f("ewellow-50", "#fff6e4")
    readonly property color ewellow100:      _f("ewellow-100", "#ffedc6")
    readonly property color ewellow200:      _f("ewellow-200", "#ffdf9a")
    readonly property color ewellow300:      _f("ewellow-300", "#fdcf64")
    readonly property color ewellow400:      _f("ewellow-400", "#f8c23a")
    readonly property color ewellow500:      _f("ewellow-500", "#eeb407")
    readonly property color ewellow600:      _f("ewellow-600", "#ce9707")
    readonly property color ewellow700:      _f("ewellow-700", "#a77607")
    readonly property color ewellow800:      _f("ewellow-800", "#805708")
    readonly property color ewellow900:      _f("ewellow-900", "#5a3b09")
    readonly property color ewellow950:      _f("ewellow-950", "#352206")
    readonly property color neutral0:        _f("neutral-0", "#fefdfc")
    readonly property color neutral50:       _f("neutral-50", "#faf9f6")
    readonly property color neutral100:      _f("neutral-100", "#f4f2ee")
    readonly property color neutral200:      _f("neutral-200", "#e9e6e0")
    readonly property color neutral300:      _f("neutral-300", "#d5d2cb")
    readonly property color neutral400:      _f("neutral-400", "#a8a49d")
    readonly property color neutral500:      _f("neutral-500", "#7f7b75")
    readonly property color neutral600:      _f("neutral-600", "#5d5a55")
    readonly property color neutral700:      _f("neutral-700", "#423f3a")
    readonly property color neutral800:      _f("neutral-800", "#2c2a26")
    readonly property color neutral850:      _f("neutral-850", "#201e1a")
    readonly property color neutral900:      _f("neutral-900", "#151411")
    readonly property color neutral950:      _f("neutral-950", "#0b0a08")
    readonly property color surfaceBase:     _f("surface-base", "#0b0a08")
    readonly property color surfaceRaised:   _f("surface-raised", "#151411")
    readonly property color surfaceOverlay:  _f("surface-overlay", "#201e1a")
    readonly property color surfaceSunken:   _f("surface-sunken", "#020202")
    readonly property color surfaceHover:    _f("surface-hover", "#2c2a26")
    readonly property color surfacePressed:  _f("surface-pressed", "#423f3a")
    readonly property color surfaceSelected: _f("surface-selected", "#2c2a26")
    readonly property color scrim:           _f("scrim", "#a3000000")
    readonly property color glassBase:       _f("glass-base", "#cc0b0a08")
    readonly property color glassRaised:     _f("glass-raised", "#cc151411")
    readonly property color glassBorder:     _f("glass-border", "#1afefdfc")
    readonly property color glassHover:      _f("glass-hover", "#14fefdfc")
    readonly property color glassPressed:    _f("glass-pressed", "#24fefdfc")
    readonly property color glassAccent:     _f("glass-accent", "#f8c23a")
    readonly property color borderSubtle:    _f("border-subtle", "#2c2a26")
    readonly property color borderStrong:    _f("border-strong", "#7f7b75")
    readonly property color textPrimary:     _f("text-primary", "#faf9f6")
    readonly property color textSecondary:   _f("text-secondary", "#d5d2cb")
    readonly property color textMuted:       _f("text-muted", "#a8a49d")
    readonly property color textDisabled:    _f("text-disabled", "#5d5a55")
    readonly property color accentHover:     _f("accent-hover", "#f8c23b")
    readonly property color accentPressed:   _f("accent-pressed", "#cb9407")
    // on-accent, through a Binding on purpose. `onAccent: <expression>` next to
    // a property called `accent` parses as a SIGNAL HANDLER, not a property
    // initialiser: QML silently ran the expression on accentChanged and left
    // the colour at its default black. A bare declaration plus a Binding is
    // the same value, still reactive, and keeps the name the token has.
    property color onAccent
    readonly property Binding _onAccentBind: Binding {
        target: t; property: "onAccent"; value: t._f("on-accent", "#020202")
    }
    readonly property color accentSubtle:    _f("accent-subtle", "#352206")
    readonly property color accentText:      _f("accent-text", "#f8c23a")
    readonly property color focusRing:       _f("focus-ring", "#f8c23a")
    readonly property color success:         _f("success", "#69d6aa")
    readonly property color warning:         _f("warning", "#f9a870")
    readonly property color danger:          _f("danger", "#ffa196")
    readonly property color info:            _f("info", "#76c7ff")
    readonly property color successSubtle:   _f("success-subtle", "#0d2d21")
    readonly property color warningSubtle:   _f("warning-subtle", "#372010")
    readonly property color dangerSubtle:    _f("danger-subtle", "#3a1d1a")
    readonly property color infoSubtle:      _f("info-subtle", "#0f293a")
    readonly property color onStatus:        _f("on-status", "#020202")

    // The accent is the person's pick. It normally arrives in the tokens (the
    // whole ramp is derived from it); an in-shell pick from Settings → Theme
    // wins until a palette scheme is active, which carries its own accent.
    readonly property color accent: (Globals.accentExplicit && !Globals.schemeActive)
                                    ? Globals.accentColor : _f("accent", "#eeb407")

    // ── Type ──────────────────────────────────────────────────────────────
    // Geist for the interface, Geist Mono for code and for values that change
    // in place; both fall back to Noto Sans Georgian (Geist has no Georgian
    // glyphs) through dotfiles/fontconfig. Lucide stays the icon face.
    readonly property var _sansStack: (_ft && _ft.sans) || ["Geist", "Noto Sans Georgian"]
    readonly property var _monoStack: (_ft && _ft.mono) || ["Geist Mono", "Noto Sans Georgian"]
    readonly property string fontSans: _sansStack[0]
    readonly property string fontMono: _monoStack[0]
    readonly property FontLoader _icons: FontLoader { source: Qt.resolvedUrl("fonts/Lucide.ttf") }
    readonly property string fontIcons: _icons.status === FontLoader.Ready ? _icons.name : "lucide"

    // The type styles. `Theme.type.<style>` carries size, lineHeight, weight,
    // family, italic and tracking (em, as the token is written) plus
    // letterSpacing (the same tracking in px, what font.letterSpacing wants).
    // Both spellings resolve: type["body-strong"] and type.bodyStrong.
    //     Text { font.family: Theme.type.label.family
    //            font.pixelSize: Theme.type.label.size
    //            font.weight: Theme.type.label.weight }
    // Text size (accessibility) has already scaled size and lineHeight.
    readonly property var type: _styles(_ft, fontSans, fontMono)
    function _styles(ft, sans, mono) {
        var fb = {
        "display-xl": ["sans", 64, 72, 300, -0.03, false],
        "display-lg": ["sans", 48, 56, 400, -0.025, false],
        "display": ["sans", 36, 44, 500, -0.02, false],
        "h1": ["sans", 28, 34, 600, -0.02, false],
        "h2": ["sans", 22, 28, 600, -0.015, false],
        "h3": ["sans", 18, 24, 600, -0.01, false],
        "h4": ["sans", 15, 20, 600, 0, false],
        "h4-italic": ["sans", 15, 20, 600, 0, true],
        "body-lg": ["sans", 15, 22, 400, 0, false],
        "body": ["sans", 13, 18, 400, 0, false],
        "body-strong": ["sans", 13, 18, 500, 0, false],
        "body-italic": ["sans", 13, 18, 400, 0, true],
        "body-strong-italic": ["sans", 13, 18, 500, 0, true],
        "label": ["sans", 12, 16, 500, 0, false],
        "label-italic": ["sans", 12, 16, 500, 0, true],
        "caption": ["sans", 11, 14, 400, 0, false],
        "caption-italic": ["sans", 11, 14, 400, 0, true],
        "overline": ["sans", 11, 14, 600, 0.06, false],
        "mono": ["mono", 12, 16, 400, 0, false],
        "mono-strong": ["mono", 12, 16, 600, 0, false],
        "mono-italic": ["mono", 12, 16, 400, 0, true],
        "mono-numeric": ["mono", 12, 16, 500, 0, false],
        }
        var src = (ft && ft.styles) || {}
        var out = {}
        for (var k in fb) {
            var d = fb[k], j = src[k] || {}
            var fam = (j.family !== undefined ? j.family : d[0]) === "mono" ? mono : sans
            var size = j.size !== undefined ? j.size : d[1]
            var track = j.tracking !== undefined ? j.tracking : d[4]
            var o = { family: fam, size: size,
                      lineHeight: j.lineHeight !== undefined ? j.lineHeight : d[2],
                      weight: j.weight !== undefined ? j.weight : d[3],
                      tracking: track, letterSpacing: track * size,
                      italic: j.italic !== undefined ? j.italic : d[5] }
            out[k] = o
            out[k.replace(/-([a-z0-9])/g, function (m, c) { return c.toUpperCase() })] = o
        }
        return out
    }

    // ── Font size and line height (pair a size with its own step) ─────────
    readonly property int fontSizeXs:              _z("font-size-xs", 11)
    readonly property int fontSizeS:               _z("font-size-s", 12)
    readonly property int fontSizeMd:              _z("font-size-md", 13)
    readonly property int fontSizeLg:              _z("font-size-lg", 15)
    readonly property int fontSizeXl:              _z("font-size-xl", 18)
    readonly property int fontSize2xl:             _z("font-size-2xl", 22)
    readonly property int fontSize3xl:             _z("font-size-3xl", 28)
    readonly property int fontSize4xl:             _z("font-size-4xl", 36)
    readonly property int fontSize5xl:             _z("font-size-5xl", 48)
    readonly property int fontSize6xl:             _z("font-size-6xl", 64)
    readonly property int lineHeightXs:            _z("line-height-xs", 14)
    readonly property int lineHeightS:             _z("line-height-s", 16)
    readonly property int lineHeightMd:            _z("line-height-md", 18)
    readonly property int lineHeightLg:            _z("line-height-lg", 20)
    readonly property int lineHeightLgRelaxed:     _z("line-height-lg-relaxed", 22)
    readonly property int lineHeightXl:            _z("line-height-xl", 24)
    readonly property int lineHeight2xl:           _z("line-height-2xl", 28)
    readonly property int lineHeight3xl:           _z("line-height-3xl", 34)
    readonly property int lineHeight4xl:           _z("line-height-4xl", 44)
    readonly property int lineHeight5xl:           _z("line-height-5xl", 56)
    readonly property int lineHeight6xl:           _z("line-height-6xl", 72)

    // ── Font weight ───────────────────────────────────────────────────────
    // Interface text uses regular, medium and semibold; bold and heavier are
    // for branding and artwork only — hierarchy comes from size and colour.
    readonly property int fontWeightThin:          _w("font-weight-thin", 100)
    readonly property int fontWeightExtralight:    _w("font-weight-extralight", 200)
    readonly property int fontWeightLight:         _w("font-weight-light", 300)
    readonly property int fontWeightRegular:       _w("font-weight-regular", 400)
    readonly property int fontWeightMedium:        _w("font-weight-medium", 500)
    readonly property int fontWeightSemibold:      _w("font-weight-semibold", 600)
    readonly property int fontWeightBold:          _w("font-weight-bold", 700)
    readonly property int fontWeightExtrabold:     _w("font-weight-extrabold", 800)
    readonly property int fontWeightBlack:         _w("font-weight-black", 900)

    // ── Letter spacing (em; multiply by the size for font.letterSpacing) ──
    readonly property real trackingTightest:    _tr("tracking-tightest", -0.03)
    readonly property real trackingTighter:     _tr("tracking-tighter", -0.02)
    readonly property real trackingTight:       _tr("tracking-tight", -0.015)
    readonly property real trackingSnug:        _tr("tracking-snug", -0.01)
    readonly property real trackingNormal:      _tr("tracking-normal", 0)
    readonly property real trackingWide:        _tr("tracking-wide", 0.06)

    // ── Spacing ───────────────────────────────────────────────────────────
    readonly property int spaceXxs:                _z("space-xxs", 2)
    readonly property int spaceXs:                 _z("space-xs", 4)
    readonly property int spaceS:                  _z("space-s", 8)
    readonly property int spaceMd:                 _z("space-md", 16)
    readonly property int spaceLg:                 _z("space-lg", 32)
    readonly property int spaceXl:                 _z("space-xl", 64)

    // ── Radius ────────────────────────────────────────────────────────────
    //   radiusPrimary  buttons, inputs, switches, list rows, bar modules
    //   radiusRounded  panels, popups, cards, the dock
    //   radiusFull     badges, tags and switch tracks — nothing else
    readonly property int radiusSlight:      _s("slight", 4)
    readonly property int radiusSecondary:   _s("secondary", 6)
    readonly property int radiusPrimary:     _s("primary", 8)
    readonly property int radiusRounded:     _s("rounded", 10)
    readonly property int radiusFull:        _s("fully-rounded", 9999)

    // ── Border and focus width (two weights, nothing else) ────────────────
    readonly property int borderWidth1:      _s("border-width-1", 1)
    readonly property int borderWidth2:      _s("border-width-2", 2)
    readonly property int focusWidth:        _s("focus-width", 1)
    // A field, checkbox or switch keeps its outline even at `stroke = none`
    // (Look presets), where borderWidth1 is 0 — that is what this is for. It
    // is never 0, follows `stroke = thick` up, and is 2 under Increase
    // contrast. Nothing else uses it: cards, panels and buttons take
    // borderWidth1 and lose their rule with the preset, on purpose.
    readonly property int fieldBorderWidth:  _s("field-border-width", 1)

    // ── Control, icon and panel sizes ─────────────────────────────────────
    readonly property int controlSm:               _z("control-sm", 24)
    readonly property int controlMd:               _z("control-md", 28)
    readonly property int controlLg:               _z("control-lg", 32)
    readonly property int controlXl:               _z("control-xl", 40)
    readonly property int control2xl:              _z("control-2xl", 48)
    readonly property int barHeightLg:             _z("bar-height-lg", 64)
    readonly property int iconXs:                  _z("icon-xs", 12)
    readonly property int iconSm:                  _z("icon-sm", 14)
    readonly property int iconMd:                  _z("icon-md", 16)
    readonly property int iconLg:                  _z("icon-lg", 20)
    readonly property int iconXl:                  _z("icon-xl", 24)
    readonly property int icon2xl:                 _z("icon-2xl", 32)
    readonly property int icon3xl:                 _z("icon-3xl", 48)
    readonly property int icon4xl:                 _z("icon-4xl", 64)
    readonly property int panelSm:                 _z("panel-sm", 360)
    readonly property int panelMd:                 _z("panel-md", 400)
    readonly property int panelLg:                 _z("panel-lg", 560)
    readonly property int windowGap:               _z("window-gap", 8)
    readonly property int blurGlass:               _z("blur-glass", 24)

    // ── Opacity ───────────────────────────────────────────────────────────
    readonly property real opacitySolid:      _o("opacity-solid", 1)
    readonly property real opacityGlass:      _o("opacity-glass", 0.8)
    readonly property real opacityApp:        _o("opacity-app", 0.85)
    readonly property real opacityInactive:   _o("opacity-inactive", 0.97)

    // ── Shadow ────────────────────────────────────────────────────────────
    // Short and tight: shadowSm for tooltips, shadowFloat for layers floating
    // above other windows. Everything else is flat (shadowNone). Each is
    // {x, y, blur, color} — MultiEffect wants the parts, not a CSS string.
    readonly property var shadowNone:  null
    readonly property var shadowSm:    _d("shadow-sm", { x: 0, y: 1, blur: 2, color: "#66000000" })
    readonly property var shadowFloat: _d("shadow-float", { x: 0, y: 2, blur: 6, color: "#59000000" })

    // ── Gradient ──────────────────────────────────────────────────────────
    // Two close tones, never a blend; never on text or small controls.
    // {kind, angle|at, stops: [[colour, alpha, stop%], …], css}.
    readonly property var gradientEwellow: _gr("gradient-ewellow", { kind: "linear", angle: 135, stops: [["#f4bd28", 1, 0], ["#e6ab09", 1, 100]] })
    readonly property var gradientEmber:   _gr("gradient-ember",   { kind: "linear", angle: 160, stops: [["#1b150b", 1, 0], ["#0b0a08", 1, 100]] })
    readonly property var gradientNight:   _gr("gradient-night",   { kind: "linear", angle: 180, stops: [["#151411", 1, 0], ["#0b0a08", 1, 100]] })
    readonly property var gradientGlow:    _gr("gradient-glow",    { kind: "radial", at: "50% 0%", stops: [["#eeb407", 0.08, 0], ["#eeb407", 0, 60]] })

    // ── Motion (ms) ───────────────────────────────────────────────────────
    // The four durations of the README's motion table, already divided by
    // [desktop.animations] speed by the generator (speed 0 = off, so they
    // arrive as 0). Reduce motion has already collapsed base and slow onto
    // fast and zeroed the slide, so a component animates the same way in
    // every mode and only the numbers change.
    //   durFast  hover, pressed, focus, colour changes; menus/toasts closing
    //   durBase  panels, popups, launcher, toasts opening; the dock hiding
    //   durSlow  workspace switches, the Overview zoom, Welcome
    //   durDim   the pre-lock dim
    // The Animations pane (animations.json) can still switch the shell's
    // motion off; its per-layer ms and curve belong to Hyprland's windows —
    // shell surfaces follow the design system's table.
    readonly property var _aj: Globals.animPrefs
    readonly property var _ajLayers: _aj && _aj.anims ? _aj.anims.layers : null
    readonly property real _speed: _m("speed", Math.max(Globals.animationSpeed, 0))
    readonly property bool _animOff: (_speed <= 0)
                                     || (_aj ? (_aj.enabled === false || (_ajLayers && _ajLayers.on === false)) : false)
    function _dur(k, ms) { return _animOff ? 0 : _m(k, Math.round(ms / Math.max(_speed, 0.001))) }
    readonly property int durFast: _dur("durFast", 150)
    readonly property int durBase: _dur("durBase", 200)
    readonly property int durSlow: _dur("durSlow", 250)
    readonly property int durDim:  _dur("durDim", 1500)
    // A panel opens with a fade plus a slide of this many px from its edge;
    // Reduce motion makes it 0, i.e. a plain fade.
    readonly property int slideOffset: _m("slideOffset", 4)

    // Easing. OutCubic everywhere, InOutCubic for the slow ones, linear for
    // the dim. Nothing overshoots — OutBack is gone from the shell.
    function _ease(name, fb) {
        var e = _get(_fm && _fm.easing, name, fb)
        return e === "InOutCubic" ? Easing.InOutCubic
             : e === "Linear"     ? Easing.Linear
             : e === "OutCubic"   ? Easing.OutCubic
             : fb === "InOutCubic" ? Easing.InOutCubic
             : fb === "Linear"     ? Easing.Linear : Easing.OutCubic
    }
    readonly property int ease:     _ease("base", "OutCubic")
    readonly property int easeFast: _ease("fast", "OutCubic")
    readonly property int easeSlow: _ease("slow", "InOutCubic")
    readonly property int easeDim:  _ease("dim", "Linear")

    // ── Bar ───────────────────────────────────────────────────────────────
    // [desktop.bar] size: normal = 48px bar, 32px modules, 20px glyphs;
    // large = 64 / 40 / 24. Text size 130% moves the bar to large as well.
    readonly property int barHeight:   _bz("height", _z("bar-height", 48))
    readonly property int barModule:   _bz("module", controlLg)
    readonly property int barIcon:     _bz("icon", iconLg)
    readonly property bool barLarge:   _bz("size", "normal") === "large"

    // ── Bar and dock roles (Glass card, "Roles inside glass") ─────────────
    // The bar and the dock are the two glass surfaces: while Glass is on
    // (bar_opacity < 100, and neither Reduce transparency nor Increase
    // contrast) their fill, outline, hover and pressed tint the glass, accent
    // text deepens to glassAccent and muted text rises to textSecondary.
    // The remap is made ONCE here; the bar, the dock and whatever sits in
    // them (plugin widgets included) read these instead of the plain roles.
    readonly property color barGround:      glass ? glassBase : surfaceBase
    readonly property color dockGround:     glass ? glassRaised : surfaceRaised
    readonly property color barOutline:     glass ? glassBorder : borderSubtle
    readonly property color dockOutline:    barOutline
    readonly property color barHoverFill:   glass ? glassHover : surfaceHover
    readonly property color barPressedFill: glass ? glassPressed : surfacePressed
    readonly property color barAccentText:  glass ? glassAccent : accentText
    readonly property color barTextMuted:   glass ? textSecondary : textMuted
    // the dock's selected item (the focused window, the open Pen) and an open
    // dock panel: accentSubtle when solid; on glass the tint of hover/pressed
    readonly property color dockSelectedFill: glass ? glassHover : accentSubtle
    readonly property color dockOpenFill:     glass ? glassPressed : accentSubtle

    // ── Dock size ([desktop.dock] icon_size, Dock card "Sizes") ───────────
    // dockCell is a button/workspace box edge: small 40 · medium 48 · large
    // 64. The dock is that plus spaceS of padding above and below, and sits
    // windowGap above the screen edge — dockClearance is everything it takes
    // from the bottom of the screen, what the panels that open above it and
    // the Overview pager keep clear of.
    readonly property int dockCell: Globals.dockIconSize === "small" ? controlXl
                                  : Globals.dockIconSize === "large" ? barHeightLg : control2xl
    readonly property int dockHeight: dockCell + 2 * spaceS
    readonly property int dockClearance: dockHeight + windowGap

    // ── Glass and the accessibility modes ─────────────────────────────────
    // bar_opacity (0-100) drives Glass on the bar, the dock and the lock
    // card: `glass` says the glass roles are in use, `barAlpha` is the fill
    // opacity the generator resolved (the glass* colours already carry it),
    // and `glassBlur` says the compositor blurs behind them — false on the
    // machines that export EWE_NO_BLUR=1 (VMs, NVIDIA), where Glass still
    // applies, just without the blur. Reduce transparency and Increase
    // contrast make the generator hand back solid roles.
    readonly property var _surf: Globals.tokSurface
    readonly property real barAlpha:  _get(_surf, "bar_alpha", 1)
    readonly property bool glass:     _get(_surf, "glass", false)
    readonly property bool glassBlur: _get(_surf, "blur", false) && !Globals.noBlur
    readonly property real appAlpha:      _get(_surf, "app_alpha", 1)
    readonly property real inactiveAlpha: _get(_surf, "inactive_alpha", 1)
    // The four modes, for the components that must behave differently rather
    // than just look different (Phase 4).
    readonly property bool reduceMotion:      _ax("reduce_motion", false)
    readonly property bool reduceTransparency: _ax("reduce_transparency", false)
    readonly property bool increaseContrast:  _ax("increase_contrast", false)
    readonly property int  textScale:         _ax("text_scale", 100)

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // Corner scaler for the one-off radii components still carry (a 7px chip,
    // a 9px thumbnail): `corner = "none"` collapses them all. Use it instead
    // of a literal:  radius: Theme.r(8). TRUE CIRCLES are geometry, not radii
    // — an avatar written as `width: 38; height: 38; radius: 19` keeps its
    // literal, or it would fight the user's avatarShape preference.
    function r(n) { return brutalist ? 0 : n }
    // The radius an overlay needs to stay concentric with a container of
    // radius n once it has been inset by the rule it must not cover.
    function rIn(n, inset) {
        var i = (inset === undefined) ? hoverInset : inset
        return brutalist ? 0 : Math.max(0, r(n) - i)
    }

    // ══ FLUENT NAMES (Migration guide) ════════════════════════════════════
    // Every name the components used before the design system, pointing at
    // its Ewe role so the shell keeps working while Phase 4 restyles it file
    // by file. Phase 6 deletes this whole block — add nothing here.

    // Backgrounds: six levels collapse onto four surfaces.
    readonly property color bg1:         surfaceRaised
    readonly property color bg1Hover:    surfaceHover
    readonly property color bg1Pressed:  surfacePressed
    readonly property color bg1Selected: accentSubtle
    readonly property color bg2:         surfaceBase
    readonly property color bg2Hover:    surfaceHover
    readonly property color bg2Pressed:  surfacePressed
    readonly property color bg2Selected: accentSubtle
    readonly property color bg3:         surfaceBase
    readonly property color bg3Hover:    surfaceHover
    readonly property color bg3Pressed:  surfacePressed
    readonly property color bg3Selected: accentSubtle
    readonly property color bg4:         surfaceSunken
    readonly property color bg4Hover:    surfaceHover
    readonly property color bg4Pressed:  surfacePressed
    readonly property color bg4Selected: accentSubtle
    readonly property color bg5:         surfaceSunken
    readonly property color bg5Hover:    surfaceHover
    readonly property color bg5Pressed:  surfacePressed
    readonly property color bg5Selected: accentSubtle
    readonly property color bg6:         surfaceOverlay
    readonly property color bgDisabled:  surfaceRaised

    readonly property color card:         surfaceRaised
    readonly property color cardHover:    surfaceHover
    readonly property color cardPressed:  surfacePressed
    readonly property color cardSelected: accentSubtle

    readonly property color subtle:         "transparent"
    readonly property color subtleHover:    surfaceHover
    readonly property color subtlePressed:  surfacePressed
    readonly property color subtleSelected: accentSubtle

    readonly property color stroke1:          borderStrong
    readonly property color stroke1Hover:     textMuted
    readonly property color stroke1Pressed:   borderStrong
    readonly property color stroke1Selected:  accentText
    readonly property color stroke2:          borderSubtle
    readonly property color stroke3:          borderSubtle
    readonly property color strokeAccessible: borderStrong
    readonly property color strokeDisabled:   borderSubtle
    readonly property color strokeFocus1:     "transparent"   // removed: one ring, focusRing
    readonly property color strokeFocus2:     focusRing

    readonly property color fg1:        textPrimary
    readonly property color fg2:        textSecondary
    readonly property color fg2Hover:   textPrimary
    readonly property color fg3:        textMuted
    readonly property color fg3Hover:   textPrimary
    readonly property color fg4:        textMuted
    readonly property color fgDisabled: textDisabled
    readonly property color fgInverted: onAccent
    readonly property color fgOnBrand:  onAccent

    readonly property color brandBg:                accent
    readonly property color brandBgHover:           accentHover
    readonly property color brandBgPressed:         accentPressed
    readonly property color brandBgSelected:        accentPressed
    readonly property color brandFg1:               accentText
    readonly property color brandFg2:               accentText
    readonly property color brandFgLink:            accentText
    readonly property color brandFgLinkHover:       accentText
    readonly property color brandStroke1:           focusRing
    readonly property color brandStroke2:           ewellow900
    readonly property color compoundBrandBg:        accent
    readonly property color compoundBrandBgHover:   accentHover
    readonly property color compoundBrandBgPressed: accentPressed
    readonly property color compoundBrandFg:        accentText
    readonly property color compoundBrandStroke:    focusRing
    // a FILLED accent control and the ink on it
    readonly property color accentFill: accent
    readonly property color accentOn:   onAccent
    // interactive: `link` reads on the ground, `linkSolid` is a fill
    readonly property color link:      accentText
    readonly property color linkSolid: accent

    readonly property color successBg:     successSubtle
    readonly property color successBorder: success
    readonly property color warningBg:     warningSubtle
    readonly property color warningBorder: warning
    readonly property color dangerBg:      dangerSubtle
    readonly property color dangerBorder:  danger
    readonly property color infoBg:        infoSubtle
    readonly property color infoBorder:    info

    // Elevation's colour. A dim backdrop behind a dialog wants `scrim`
    // instead — Phase 4 moves those call sites.
    readonly property color shadow: _get(shadowFloat, "color", "#59000000")

    // ── Bar & dock surfaces ───────────────────────────────────────────────
    // Glass applies to the bar, the dock and the lock card only; every other
    // panel stays solid, which is what keeps Quick settings and the launcher
    // legible over a bright wallpaper.
    readonly property color panel:       surfaceRaised
    readonly property color barTop:      barGround
    readonly property color barBottom:   barGround
    readonly property color barFill:     barGround
    readonly property color barBorder:   barOutline
    readonly property color dockFill:    dockGround
    readonly property color dockStroke:  dockOutline
    // A bar module has no fill until you point at it; an OPEN one reads as
    // pressed (the Bar card), not as selected.
    readonly property color barHover:    barHoverFill
    readonly property color barActive:   barPressedFill
    readonly property int barItemRadius: radiusPrimary
    readonly property int barItemHeight: barModule
    // ONE rhythm for every glyph on the bar — status, tray apps, the tiling
    // switch, Komble, plugin widgets: a barIconPx glyph centred in a
    // barCellPx cell, barItemSpacing between cells. trayIconPx /
    // trayItemSpacing are the same numbers under the names the plugin
    // contract uses.
    readonly property int barIconPx:       barIcon
    readonly property int barCellPx:       barIconPx + spaceXxs
    readonly property int trayIconPx:      barIconPx
    readonly property int barItemSpacing:  spaceXs
    readonly property int trayItemSpacing: spaceXs
    readonly property int barItemPad:      spaceS

    // ── Type (legacy names) ───────────────────────────────────────────────
    readonly property string fontText:    fontSans
    readonly property string fontDisplay: fontSans
    readonly property int fsSmall: fontSizeS
    readonly property int fsBody:  fontSizeMd
    readonly property int fsLarge: fontSizeLg
    readonly property int fsTitle: fontSize2xl
    // NEVER uppercase: Qt would turn Georgian Mkhedruli into Mtavruli. Small
    // capitalised group headers are the `overline` style, which carries the
    // letter spacing and leaves the letters alone.
    readonly property int labelCaps:      Font.MixedCase
    readonly property real labelTracking: type.overline.letterSpacing
    readonly property int labelWeight:    fontWeightMedium

    // ── Metrics (legacy names) ────────────────────────────────────────────
    readonly property int radius:        radiusRounded
    readonly property int radiusInner:   radiusPrimary
    readonly property int radiusControl: radiusPrimary
    readonly property int radiusPill:    radiusFull
    readonly property int outline:     borderWidth1
    readonly property int border:      borderWidth1
    readonly property int borderThin:  borderWidth1
    readonly property int hairline:    borderWidth1
    readonly property color cardStroke: borderSubtle
    readonly property int cardBorder:   borderWidth1
    // An overlay is inset by the rule it must not cover; the inset is a
    // border width, never 0, or a hover fill kisses a divider.
    readonly property int hoverInset:   Math.max(1, borderWidth1)
    readonly property int shadowOffset: 0                      // removed: no offset shadows
    readonly property int pad:           spaceS + spaceXs      // 12
    readonly property int gap:           spaceS
    readonly property int rowHeight:     controlMd
    readonly property int controlHeight: controlMd

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
    readonly property string icVolOff:       ic(0xE1A9)  // volume — no waves: quiet
    readonly property string icVolMute:      ic(0xE1AC)  // volume-x — muted / silent
    readonly property string icMic:          ic(0xE118)  // mic — bar: something is recording
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
    readonly property string icStore:        ic(0xE3E4)  // store — dock: Komble, the software manager
    readonly property string icKeyboard:     ic(0xE284)  // keyboard
    // Bluetooth device kinds (bluez Icon strings → BtAgent.glyph)
    readonly property string icHeadphones:   ic(0xE0F1)  // headphones
    readonly property string icHeadset:      ic(0xE5BD)  // headset
    readonly property string icSpeaker:      ic(0xE166)  // speaker
    readonly property string icMouse:        ic(0xE28E)  // mouse
    readonly property string icGamepad:      ic(0xE0DF)  // gamepad-2
    readonly property string icTablet:       ic(0xE17E)  // tablet
    readonly property string icLaptop:       ic(0xE1CD)  // laptop
    readonly property string icPrinter:      ic(0xE141)  // printer
    // ewe-sync's state, shown on the bar (see Globals.syncState)
    readonly property string icCloudOk:      ic(0xE66E)  // cloud-check — everything is up to date
    readonly property string icCloudOff:     ic(0xE08D)  // cloud-off — signed out or unreachable
    readonly property string icCloudAlert:   ic(0xE633)  // cloud-alert — a conflict needs a decision
    readonly property string icPlus:         ic(0xE13D)  // plus
}
