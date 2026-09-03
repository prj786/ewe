pragma Singleton
import QtQuick

// Theme — single source of truth for colour, type, metrics and icons.
// Imported as `Theme.*`; components must never define their own.
//
// TWO looks. They no longer differ only in surface darkness — since
// 2026-09-03 each carries its own SHAPE as well as its own colour, so a
// component that reads the tokens changes character with the theme:
//
//   "flock"      — Bauhaus / neo-brutalist, on a dark ground (the default).
//                  Form follows function: flat colour blocks, NO radius, thick
//                  solid borders, and depth from a hard offset block rather
//                  than a blur. Limited palette — paper + one accent per
//                  surface. Yellow is the high-energy state, red destroys,
//                  blue is interactive.
//   "blacksheep" — Alexandria. A tonal Material-style ladder on near-black,
//                  hairline outlines, soft 6-12px radii, ambient shadow.
//
// ewe stays dark-only (decision 2026-09-01), so Bauhaus is applied as its
// STRUCTURE inverted onto an ink ground, not as its paper-white canvas: the
// guide's #f5f0e8 becomes the ink colour rather than the background.
//
// Fonts and the user's accent are deliberately NOT theme-derived — the accent
// is whatever Settings → Theme wrote, in both looks.
// The shape/colour tokens the retired Unity 7 "Ambiance" look needed
// (barTop/barBottom, barItem*) remain as plain constants.
QtObject {
    id: t

    // ── Which look ────────────────────────────────────────────────────────
    readonly property bool blacksheep:   Globals.themeName === "blacksheep"
    readonly property bool brutalist:    !blacksheep          // flock is Bauhaus
    // kept: Globals.qml still reads it, and "is this the black look" is still
    // the question every caller was really asking
    readonly property bool pitchBlack:   blacksheep

    // ── Where the values come from ────────────────────────────────────────
    // ewe-theme.conf is the source of truth; `ewe-theme build` writes
    // ~/.config/quickshell/theme-tokens.json and Globals loads it. Everything
    // below asks _c/_s/_v for its value and passes the shipped literal as the
    // FALLBACK, so the file is authoritative when present and the desktop
    // still comes up correctly when it is missing, stale or unparsable.
    readonly property var _tok: (Globals.themeTokens && Globals.themeTokens[Globals.themeName]) || null
    function _c(k, fb) { return (_tok && _tok.color && _tok.color[k]) || fb }
    function _s(k, fb) { return (_tok && _tok.shape && _tok.shape[k] !== undefined) ? _tok.shape[k] : fb }
    function _v(k, fb) { return (_tok && _tok.voice && _tok.voice[k] !== undefined) ? _tok.voice[k] : fb }

    // ── Surfaces ──────────────────────────────────────────────────────────
    // flock: a WARM ink ladder — the Bauhaus ground is #f5f0e8 warm paper, so
    //   its inversion keeps the warmth rather than going neutral grey.
    // blacksheep: Alexandria's surface / surface-container-* ladder verbatim.
    readonly property color bg:          _c("bg", blacksheep ? "#121314" : "#14140f")   // desktop / app base
    readonly property color panel:       _c("panel", blacksheep ? "#1b1c1d" : "#1c1b15")   // popup / panel surface
    readonly property color elevated:    _c("elevated", blacksheep ? "#1f2021" : "#24231b")   // cards / rows on a panel
    readonly property color hover:       _c("hover", blacksheep ? "#292a2b" : "#2f2d22")
    // The border is where the two looks part company. Alexandria outlines a
    // shape with a hairline; Bauhaus DRAWS it — a thick solid rule in the ink
    // colour. Pair `stroke` with `border` below, never with a literal width.
    readonly property color stroke:      _c("stroke", blacksheep ? "#434653" : "#f5f0e8")
    readonly property color shadow:      Qt.rgba(0, 0, 0, blacksheep ? 0.45 : 0.85)

    // flock's ink IS the guide's paper colour; blacksheep uses on-surface.
    readonly property color fg:          _c("fg", blacksheep ? "#e3e2e3" : "#f5f0e8")
    readonly property color fgSecondary: _c("fg-secondary", blacksheep ? "#c3c6d5" : "#b8b2a4")
    readonly property color fgDim:       _c("fg-dim", blacksheep ? "#8d909e" : "#8a8478")

    // ── Bar shape ─────────────────────────────────────────────────────────
    // Identical stops render the gradient node flat — kept so Bar.qml needs
    // no conditional, and a future look can reintroduce a real gradient by
    // touching only these two tokens.
    readonly property color barTop:      bg
    readonly property color barBottom:   bg
    readonly property color barBorder:   stroke
    readonly property color barHover:    hover
    readonly property color barActive:   hover
    readonly property int barItemRadius: blacksheep ? 6 : 0
    readonly property int barItemHeight: 22
    readonly property int barItemSpacing: 6
    // every glyph on the bar renders at this size — no per-site literals
    readonly property int barIconPx:     14

    // Accent — whatever Settings → Theme wrote into user-theme.json.
    readonly property color accent:      Globals.accentColor
    // accentText auto-contrasts with the accent (white on dark accents, ink on
    // light ones) so foreground text on accent fills stays legible at any hue.
    // 0.55, not 0.6: mid-luminance accents (the system green) already lose
    // white text — tip to ink earlier.
    readonly property color accentText:  (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.55 ? "#1c1c1e" : "#ffffff"

    // ── Status cues (battery / vpn / connectivity / profile) ──────────────
    // flock keeps Bauhaus's LIMITED palette — yellow, red, blue and nothing
    // else — so "positive" is the interactive blue rather than a green the
    // guide never names. Both blues are given: the solid one is a fill with
    // white on top, the light one is what stays legible AS text or a dot on
    // the ink ground (#0055ff on #14140f is far too dark to read).
    // blacksheep takes Alexandria's error and tertiary verbatim; the guide has
    // no success colour, so it is derived in the same light-desaturated
    // register as its error (#ffb4ab).
    readonly property color success:     _c("success", blacksheep ? "#a6d6a8" : "#4d84ff")  // charging · connected
    readonly property color warning:     _c("warning", blacksheep ? "#dcc661" : "#ffcc00")  // low-ish · performance
    readonly property color danger:      _c("danger", blacksheep ? "#ffb4ab" : "#e63b2e")  // critical / destructive
    // interactive: `link` reads on the ground, `linkSolid` is a fill
    readonly property color link:        _c("link", blacksheep ? "#b1c5ff" : "#4d84ff")
    readonly property color linkSolid:   _c("link-solid", blacksheep ? "#3366cc" : "#0055ff")

    // ── Type ──────────────────────────────────────────────────────────────
    // Ubuntu for body AND titles — one humanist face that reads equally well
    // in Latin and (via the fontconfig fallback to Noto Sans Georgian, see
    // dotfiles/fontconfig/) Georgian. SF Pro was never installed, so text
    // actually rendered through whatever fc-match picked.
    readonly property string fontText:    "Ubuntu"
    readonly property string fontDisplay: "Ubuntu"
    // real monospace TEXT (clipboard entries, kb hints) — ttf-jetbrains-mono-nerd
    readonly property string fontMono:    "JetBrainsMono Nerd Font"
    // icon glyphs — Phosphor Fill (vendored in fonts/, MIT). Icons are ALWAYS
    // rendered with fontIcons, never fontMono: the Phosphor codepoints only
    // exist in this face.
    readonly property FontLoader _phosphor: FontLoader { source: Qt.resolvedUrl("fonts/Phosphor-Fill.ttf") }
    readonly property string fontIcons:   _phosphor.status === FontLoader.Ready ? _phosphor.name : "Phosphor-Fill"

    readonly property int fsSmall:  12
    readonly property int fsBody:   14
    readonly property int fsLarge:  17
    readonly property int fsTitle:  22

    // ── Metrics & shape ───────────────────────────────────────────────────
    // Radius is a THEME decision, not a per-component one. Bauhaus is square:
    // "no border-radius or minimal" — zero everywhere, no exceptions, because
    // a single rounded corner in a square system reads as a mistake.
    // Alexandria rounds softly (its own scale: 0.375rem / 0.5rem / 0.75rem).
    readonly property int radius:       _s("radius", blacksheep ? 12 : 0)   // panels / launcher
    readonly property int radiusInner:  _s("radius-inner", blacksheep ? 8  : 0)   // rows, input field
    readonly property int radiusPill:   _s("radius-pill", blacksheep ? 6  : 0)

    // Border WIDTH travels with the border colour: Alexandria hairlines at
    // 1px, Bauhaus rules at 2-3px. Components use `Theme.border` rather than
    // a literal, so the same card is outlined in one look and drawn in the
    // other. borderThin is for dense rows where 3px would fill the row.
    readonly property int border:       _s("border", blacksheep ? 1 : 3)
    readonly property int borderThin:   _s("border-thin", blacksheep ? 1 : 2)

    // Depth. Bauhaus forbids soft shadows — depth is a solid block offset
    // down-right ("offset shadows: 4-6px"). Zero here means "use the blurred
    // Elevation effect instead", which is what Alexandria wants.
    readonly property int shadowOffset: _s("shadow-offset", blacksheep ? 0 : 4)

    // Typographic voice — "uppercase buttons" is a Bauhaus rule about the
    // whole system, not a decision per control. Mirrors --label-* in
    // design/tokens.css.
    readonly property int labelCaps:     _v("label-transform", blacksheep ? "none" : "uppercase") === "uppercase"
                                             ? Font.AllUppercase : Font.MixedCase
    readonly property real labelTracking: blacksheep ? 0 : 0.8
    readonly property int labelWeight:   _v("label-weight", blacksheep ? 500 : 700) >= 700 ? Font.Bold : Font.Medium

    // Corner scaler for the many one-off radii components carry (a 7px chip, a
    // 9px thumbnail). Bauhaus is square with NO exceptions, so flock collapses
    // every one of them to 0; Alexandria keeps the value it was given, so its
    // geometry is unchanged. Use it instead of a literal:  radius: Theme.r(8)
    //
    // TRUE CIRCLES are not radii in this sense — an avatar written as
    // `width: 38; height: 38; radius: 19` is geometry, and squaring it would
    // fight the user's own avatarShape preference. Those keep their literal.
    function r(n) { return brutalist ? 0 : n }

    readonly property int pad:          12
    readonly property int gap:          8
    readonly property int barHeight:    30

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

    // ── Icons — the SINGLE glyph table (Phosphor Fill ONLY). Every component
    //    pulls its glyphs from here with font.family: Theme.fontIcons, so the
    //    same concept renders the same icon everywhere. Codepoints are from
    //    @phosphor-icons/web 2.1.1 fill/style.css (PUA, stable per release —
    //    re-extract if the vendored TTF is ever upgraded). ───────────────────
    function ic(code) { return String.fromCodePoint(code) }
    readonly property string icSearch:      ic(0xE30C)  // magnifying-glass
    readonly property string icSearchOff:   ic(0xE30E)  // magnifying-glass-minus (no results)
    readonly property string icClose:       ic(0xE4F6)  // x
    readonly property string icChevronDown: ic(0xE136)  // caret-down
    readonly property string icChevronUp:   ic(0xE13C)  // caret-up
    readonly property string icChevronRight:ic(0xE13A)  // caret-right
    readonly property string icWifi:        ic(0xE4EA)  // wifi-high
    readonly property string icWifiMed:     ic(0xE4EE)  // wifi-medium
    readonly property string icWifiLow:     ic(0xE4EC)  // wifi-low
    readonly property string icWifiOff:     ic(0xE4F2)  // wifi-slash
    readonly property string icEthernet:    ic(0xEDDE)  // network
    readonly property string icBluetooth:   ic(0xE0DA)  // bluetooth
    readonly property string icBluetoothOn: ic(0xE0DC)  // bluetooth-connected
    readonly property string icVpn:         ic(0xE40C)  // shield-check — bar AND control centre
    readonly property string icSsh:         ic(0xEAE8)  // terminal-window
    readonly property string icWeb:         ic(0xE288)  // globe (browse / port-forward)
    readonly property string icCamera:      ic(0xE10E)  // camera
    readonly property string icClipboard:   ic(0xEAE0)  // scissors (clipboard popup)
    readonly property string icTrash:       ic(0xE4A6)  // trash
    readonly property string icPencil:      ic(0xE3B4)  // pencil-simple
    readonly property string icEye:         ic(0xE220)  // eye (insomnia / keep-awake)
    readonly property string icEyeOff:      ic(0xE224)  // eye-slash
    readonly property string icDnd:         ic(0xE330)  // moon (do not disturb)
    readonly property string icCast:        ic(0xE404)  // screencast (cast to TV)
    readonly property string icSun:         ic(0xE472)  // sun (brightness)
    readonly property string icBolt:        ic(0xE2DE)  // lightning (charging)
    readonly property string icBattFull:    ic(0xE0C0)  // battery-full
    readonly property string icBatt80:      ic(0xE0C2)  // battery-high
    readonly property string icBatt50:      ic(0xE0C6)  // battery-medium
    readonly property string icBatt20:      ic(0xE0C4)  // battery-low
    readonly property string icBattEmpty:   ic(0xE0BE)  // battery-empty
    readonly property string icLeaf:        ic(0xE2DA)  // leaf (power-saver)
    readonly property string icBalance:     ic(0xE750)  // scales (balanced)
    readonly property string icSpeed:       ic(0xE628)  // gauge (performance)
    readonly property string icVolHigh:     ic(0xE44A)  // speaker-high
    readonly property string icVolLow:      ic(0xE44C)  // speaker-low
    readonly property string icPlay:        ic(0xE3D0)  // play
    readonly property string icPause:       ic(0xE39E)  // pause
    readonly property string icPrev:        ic(0xE5A4)  // skip-back
    readonly property string icNext:        ic(0xE5A6)  // skip-forward
    readonly property string icMusic:       ic(0xE33C)  // music-note
    readonly property string icMonitorOff:  ic(0xE32E)  // monitor (display states)
    readonly property string icLock:        ic(0xE2FA)  // lock
    readonly property string icPower:       ic(0xE3DA)  // power
    readonly property string icCog:         ic(0xE270)  // gear
    readonly property string icTiling:      ic(0xE464)  // squares-four (tiling on)
    readonly property string icFloating:    ic(0xE0F6)  // browsers (windows float)
    // check-fat, not plain check: Phosphor's Fill weight has no bare form for
    // stroke-only icons, so `check` (0xE182) draws as a filled badge with the
    // tick knocked out — indistinguishable from check-square, and wrong inside
    // the swatches/rows that already draw their own background. check-fat is
    // the bare tick. (Same limitation hits `x`/`plus`; they have no fat form.)
    readonly property string icCheck:       ic(0xEBA6)  // check-fat
    readonly property string icPhone:       ic(0xE1E0)  // device-mobile (mobile connection)
    readonly property string icMessage:     ic(0xE168)  // chat-circle (SMS)
    readonly property string icSend:        ic(0xE398)  // paper-plane-tilt
    readonly property string icBellRing:    ic(0xE5E8)  // bell-ringing (find my phone / mail notify)
    readonly property string icBell:        ic(0xE0CE)  // bell (bar: notification history)
    readonly property string icCalendar:    ic(0xE108)  // calendar (bar: an event is near)
    readonly property string icRefresh:     ic(0xE094)  // arrows-clockwise
    readonly property string icBack:        ic(0xE058)  // arrow-left
    readonly property string icMail:        ic(0xE214)  // envelope (Gmail)
    readonly property string icFile:        ic(0xE230)  // file (overview file results)
    readonly property string icFolder:      ic(0xE24A)  // folder (places / dock)
    readonly property string icHome:        ic(0xE2C2)  // house (places home)
    readonly property string icPin:         ic(0xE3E2)  // push-pin (launcher pin)
    readonly property string icUser:        ic(0xE4C2)  // user (avatar fallback)
    readonly property string icStar:        ic(0xE46A)  // star (primary display)
    readonly property string icCpu:         ic(0xE610)  // cpu (meter)
    readonly property string icMemory:      ic(0xE9C4)  // memory (meter)
    readonly property string icImage:       ic(0xE2CA)  // image (wallpaper empty state)
    readonly property string icWarning:     ic(0xE4E0)  // warning (danger rows)
    readonly property string icApps:        ic(0xE1FC)  // dots-nine (dock app grid)
    readonly property string icStack:       ic(0xE466)  // stack (dock overview)
    readonly property string icPen:         ic(0xE390)  // package — the Pen (dock: stashed windows)
    readonly property string icDownload:    ic(0xE20C)  // download-simple (dock downloads)
    readonly property string icKeyboard:    ic(0xE2D8)  // keyboard
    readonly property string icPlus:        ic(0xE3D4)  // plus
}
