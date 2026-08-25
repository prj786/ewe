-- colors.lua — Gruvbox (dark, medium contrast) palette for the Hyprland side
-- (window borders), ported from the old Qtile `desktop_env/theme/colors.py`.
-- NOTE: the shell (bar + launcher) is now Quickshell under ~/.config/quickshell/
-- — the bar replica carries its own gruvbox hex; the shell redesign uses
-- Theme.qml (graphite + SF Pro). This file only feeds hyprland.lua now.
--
-- Hyprland wants colours as `rgba(RRGGBBAA)` / `rgb(RRGGBB)` strings, or as
-- 0xAARRGGBB integers (shadows). We store the raw 6-digit hex and build the
-- string forms with the helpers below, so a colour is written exactly once.

local M = {}

-- Backgrounds, darkest -> lightest -------------------------------------------
M.bg0_h   = "1d2021"  -- bar / deepest background
M.bg0     = "282828"  -- main background
M.bg1     = "3c3836"  -- raised surface (pills, cards)
M.bg2     = "504945"  -- second surface / inactive border
M.bg3     = "665c54"  -- dividers
M.bg4     = "7c6f64"  -- stronger divider / inactive icon

-- Foregrounds ---------------------------------------------------------------
M.fg1     = "ebdbb2"  -- primary text
M.fg2     = "d5c4a1"  -- secondary text
M.fg3     = "bdae93"  -- tertiary / dimmed
M.gray    = "928374"  -- disabled / placeholder

-- Accents + named hues ------------------------------------------------------
M.yellow  = "fabd2f"  -- accent
M.yellow2 = "d79921"  -- accent (dim)
M.red     = "fb4934"
M.green   = "b8bb26"
M.blue    = "83a598"
M.purple  = "d3869b"
M.aqua    = "8ec07c"
M.orange  = "fe8019"

-- graphite theme — MIRRORS ~/.config/quickshell/Theme.qml (the shell's single
-- source of truth). Kept here so Hyprland-drawn chrome (group bar / borders) matches the
-- shell. If a token changes in Theme.qml, change it here too.
M.t_bg          = "1c1c1e"  -- desktop / app base
M.t_panel       = "1d1d1f"  -- popup / panel surface
M.t_elevated    = "2c2c2e"  -- cards / inactive tab
M.t_hover       = "3a3a3c"  -- hover fill
M.t_stroke      = "38383a"  -- hairline border
M.t_fg          = "f2f2f7"  -- primary text
M.t_fg_dim      = "8e8e93"  -- dim text
M.t_accent      = "0a84ff"  -- system blue (active tab)
M.t_accent_text = "ffffff"

-- Helpers -------------------------------------------------------------------
-- rgba("fabd2f", 0xee) -> "rgba(fabd2fee)"
function M.rgba(hex, alpha)
    return string.format("rgba(%s%02x)", hex, alpha)
end

-- rgb("fabd2f") -> "rgb(fabd2f)"
function M.rgb(hex)
    return string.format("rgb(%s)", hex)
end

-- Blend two hex colours. mix("1c1c1e", "0a84ff", 0.10) -> a hair of accent.
function M.mix(a, b, t)
    local function ch(h, i) return tonumber(h:sub(i, i + 1), 16) end
    local out = {}
    for _, i in ipairs({ 1, 3, 5 }) do
        out[#out + 1] = math.floor(ch(a, i) + (ch(b, i) - ch(a, i)) * t + 0.5)
    end
    return string.format("%02x%02x%02x", out[1], out[2], out[3])
end

-- Readable text on an accent fill. MIRRORS Theme.accentText: white on dark
-- accents, ink on light ones, tipping at 0.55 (mid-luminance accents like the
-- system green already lose white text before 0.6).
function M.on_accent(hex)
    local r, g, b = tonumber(hex:sub(1, 2), 16) / 255,
                    tonumber(hex:sub(3, 4), 16) / 255,
                    tonumber(hex:sub(5, 6), 16) / 255
    return (0.299 * r + 0.587 * g + 0.114 * b) > 0.55 and "1c1c1e" or "ffffff"
end

-- ── Live look: accent + surface variant ─────────────────────────────────────
-- The shell owns the look, and Settings persists it to user-theme.json. Read it
-- here so Hyprland-drawn chrome (window borders, the groupbar) tracks the SAME
-- accent and the SAME flock/blacksheep surfaces as the shell, instead of
-- drifting to the hardcoded system blue on flock grey. Missing or half-written
-- file (first boot, before Settings has ever run) -> the shipped defaults.
-- Re-read on every `hyprctl reload`, which is what Settings triggers.
local function user_theme()
    local home = os.getenv("HOME")
    if not home then return "" end
    local f = io.open(home .. "/.config/quickshell/user-theme.json", "r")
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s or ""
end

local ut = user_theme()

-- The user's accent, or the shipped system blue.
M.accent     = ut:match('"accent"%s*:%s*"#?(%x%x%x%x%x%x)"') or M.t_accent
M.accent_fg  = M.on_accent(M.accent)
M.pitchBlack = ut:match('"themeName"%s*:%s*"(%a+)"') == "blacksheep"

-- Neutral surfaces — MIRRORS Theme.qml's flock / pitchBlack pair.
M.s_bg       = M.pitchBlack and "020202" or "1c1c1e"  -- desktop / app base
M.s_panel    = M.pitchBlack and "020202" or "1d1d1f"  -- popup / panel surface
M.s_elevated = M.pitchBlack and "101012" or "2c2c2e"  -- cards / inactive tab
M.s_hover    = M.pitchBlack and "1a1a1c" or "3a3a3c"  -- hover fill
M.s_stroke   = M.pitchBlack and "222225" or "38383a"  -- hairline border
M.s_fg       = "f2f2f7"                               -- primary text
M.s_fg_dim   = "8e8e93"                               -- dim text

return M
