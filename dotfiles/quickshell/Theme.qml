pragma Singleton
import QtQuick

// Theme — single source of truth for the "graphite dark + blue" look.
// Tuned for SF Pro and compact, polished metrics. Imported as `Theme.*`.
QtObject {
    // ── Palette: graphite dark — SINGLE SOURCE OF TRUTH for colour ─────────
    // Solid, no glass/transparency (we revisit theming later). Keep every colour
    // here and reference it as Theme.* — components should not define their own.
    readonly property color bg:          "#1c1c1e"   // desktop / app base
    readonly property color panel:       "#1d1d1f"   // popup / panel surface (solid)
    readonly property color elevated:    "#2c2c2e"   // cards / rows on a panel
    readonly property color hover:       "#3a3a3c"   // hover fill
    readonly property color stroke:      "#38383a"   // hairline border
    readonly property color shadow:      Qt.rgba(0, 0, 0, 0.45)

    readonly property color fg:          "#f2f2f7"   // primary text
    readonly property color fgSecondary: "#aeaeb2"
    readonly property color fgDim:       "#8e8e93"   // tertiary / placeholder

    // Accent is user-settable: it binds to Globals.accentColor (written by the
    // Settings → Theme pane, persisted in user-theme.json). Changing it recolours
    // every surface live. Default stays system blue.
    readonly property color accent:      Globals.accentColor
    // accentText auto-contrasts with the accent (white on dark accents, ink on
    // light ones) so foreground text on accent fills stays legible at any hue.
    readonly property color accentText:  (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.6 ? "#1c1c1e" : "#ffffff"

    // status cues (battery / vpn / connectivity / profile)
    readonly property color success:     "#30d158"   // charging · connected · power-saver
    readonly property color warning:     "#ff9f0a"   // low-ish · performance
    readonly property color danger:      "#ff453a"   // critical / low battery

    // ── Type (SF Pro) ─────────────────────────────────────────────────────
    // SF Pro Text for body/small, SF Pro Display for large/titles (the
    // optical-size split).
    readonly property string fontText:    "SF Pro Text"
    readonly property string fontDisplay: "SF Pro Display"
    // glyphs + mono fallback — ttf-jetbrains-mono-nerd from packages/common.list
    // (the old "Hurmit Nerd Font" was never installed; it only worked because
    // fontconfig silently fell back to a Nerd Font that happened to be present)
    readonly property string fontMono:    "JetBrainsMono Nerd Font"

    readonly property int fsSmall:  12
    readonly property int fsBody:   14
    readonly property int fsLarge:  17
    readonly property int fsTitle:  22

    // ── Metrics ───────────────────────────────────────────────────────────
    readonly property int radius:       14    // panels / launcher
    readonly property int radiusInner:  10    // rows, input field
    readonly property int radiusPill:   8
    readonly property int pad:          12
    readonly property int gap:          8
    readonly property int barHeight:    28

    // ── Motion (ms) — quick, ease-out. Scaled by the global
    //    animation-speed setting (>1 faster, 0 = instant) so the whole shell
    //    tracks the Settings → Theme → Animations control. ──────────────────
    readonly property real _animMul: Globals.animationSpeed
    readonly property int durFast:   _animMul <= 0 ? 0 : Math.round(120 / _animMul)
    readonly property int durBase:   _animMul <= 0 ? 0 : Math.round(180 / _animMul)
    readonly property int durSlow:   _animMul <= 0 ? 0 : Math.round(260 / _animMul)

    // ── Icons — the SINGLE glyph table (Nerd Font, Material Design set ONLY).
    //    Every component pulls its glyphs from here so the same concept renders
    //    the same icon everywhere (the old code mixed Font Awesome + Material,
    //    and e.g. VPN differed between the bar and the control centre).
    //    Codepoints are nf-md-* (0xF0000 + the old MDI webfont point). ────────
    function ic(code) { return String.fromCodePoint(code) }
    readonly property string icSearch:      ic(0xF0349)  // magnify
    readonly property string icSearchOff:   ic(0xF0980)  // magnify-close (no results)
    readonly property string icClose:       ic(0xF0156)  // close
    readonly property string icChevronDown: ic(0xF0140)  // chevron-down
    readonly property string icChevronRight:ic(0xF0142)  // chevron-right
    readonly property string icWifi:        ic(0xF05A9)  // wifi
    readonly property string icWifiOff:     ic(0xF092F)  // wifi-strength-off
    readonly property string icEthernet:    ic(0xF0200)  // ethernet
    readonly property string icBluetooth:   ic(0xF00AF)  // bluetooth
    readonly property string icBluetoothOn: ic(0xF00B1)  // bluetooth-connect
    readonly property string icVpn:         ic(0xF0BC4)  // shield-key — bar AND control centre
    readonly property string icSsh:         ic(0xF018D)  // console
    readonly property string icWeb:         ic(0xF01E7)  // earth (browse / port-forward)
    readonly property string icCamera:      ic(0xF0100)  // camera
    readonly property string icClipboard:   ic(0xF0190)  // content-cut (clipboard/scissors)
    readonly property string icTrash:       ic(0xF01B4)  // delete
    readonly property string icPencil:      ic(0xF03EB)  // pencil
    readonly property string icEye:         ic(0xF0208)  // eye (insomnia / keep-awake)
    readonly property string icEyeOff:      ic(0xF0209)  // eye-off
    readonly property string icDnd:         ic(0xF0594)  // weather-night (do not disturb)
    readonly property string icSun:         ic(0xF05A8)  // white-balance-sunny (brightness)
    readonly property string icBolt:        ic(0xF0241)  // flash (charging)
    readonly property string icBattFull:    ic(0xF0079)  // battery
    readonly property string icBatt80:      ic(0xF0081)  // battery-80
    readonly property string icBatt50:      ic(0xF007E)  // battery-50
    readonly property string icBatt20:      ic(0xF007B)  // battery-20
    readonly property string icBattEmpty:   ic(0xF008E)  // battery-outline
    readonly property string icLeaf:        ic(0xF032A)  // leaf (power-saver)
    readonly property string icBalance:     ic(0xF05D1)  // scale-balance (balanced)
    readonly property string icSpeed:       ic(0xF04C5)  // speedometer (performance)
    readonly property string icVolHigh:     ic(0xF057E)  // volume-high
    readonly property string icVolLow:      ic(0xF057F)  // volume-low
    readonly property string icPlay:        ic(0xF040A)  // play
    readonly property string icPause:       ic(0xF03E4)  // pause
    readonly property string icPrev:        ic(0xF04AE)  // skip-previous
    readonly property string icNext:        ic(0xF04AD)  // skip-next
    readonly property string icMusic:       ic(0xF0387)  // music-note
    readonly property string icMonitorOff:  ic(0xF03A1)  // monitor-off (empty desktop)
    readonly property string icLock:        ic(0xF033E)  // lock
    readonly property string icPower:       ic(0xF0425)  // power
    readonly property string icCog:         ic(0xF0493)  // cog
    readonly property string icCheck:       ic(0xF012C)  // check
    readonly property string icPhone:       ic(0xF011C)  // cellphone (mobile connection)
    readonly property string icMessage:     ic(0xF0361)  // message (SMS)
    readonly property string icSend:        ic(0xF048A)  // send
    readonly property string icBellRing:    ic(0xF009E)  // bell-ring (find my phone / mail notify)
    readonly property string icRefresh:     ic(0xF0450)  // refresh
    readonly property string icBack:        ic(0xF004D)  // arrow-left
    readonly property string icMail:        ic(0xF01EE)  // email (Gmail)
}
