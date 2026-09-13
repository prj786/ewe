-- colors.lua — the Hyprland side of the look (window ring, group chrome).
--
-- The surfaces, strokes and radius come from the token file `ewe-theme build`
-- writes (~/.config/quickshell/theme-tokens.json) — the same file the shell
-- reads — so Hyprland-drawn chrome never drifts from the shell. The Gruvbox
-- block below is the old Qtile port, kept for the named hues only.
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

-- ── Live look: accent + tokens ──────────────────────────────────────────────
-- Two files, both plain-string matched (Hyprland's Lua has no JSON library,
-- and every key we need is unique across the file, so no parsing is needed):
--
--   user-theme.json    — the shell's persisted look (accent, tintBorders).
--   theme-tokens.json  — `ewe-theme build`'s output: every surface, stroke and
--                        radius, derived from ewe.conf [desktop.theme]. The
--                        same file Theme.qml reads, so the window ring and the
--                        groupbar sit on the SAME greys as the shell.
--
-- Missing or half-written file (first boot, before either has ever been
-- written) -> the shipped defaults, which are design/tokens.css's values under
-- the default preset. Re-read on every `hyprctl reload`.
local function read_json(path)
    local home = os.getenv("HOME")
    if not home then return "" end
    local f = io.open(home .. path, "r")
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s or ""
end

local ut  = read_json("/.config/quickshell/user-theme.json")
local tok = read_json("/.config/quickshell/theme-tokens.json")

-- Lua pattern for a JSON key (the token names carry `-`, a magic character).
local function key(name)
    return '"' .. name:gsub("%-", "%%-") .. '"%s*:%s*'
end

-- A colour token -> 6-digit hex + alpha (0-255). The token file writes
-- strokes as `#AARRGGBB` (alpha 0.5 = 0x80) and fills as `#RRGGBB`.
local function tok_color(name, fallback_hex, fallback_alpha)
    local h = tok:match(key(name) .. '"#(%x+)"')
    if h and #h == 8 then return h:sub(3), tonumber(h:sub(1, 2), 16) end
    if h and #h == 6 then return h, 0xff end
    return fallback_hex, fallback_alpha or 0xff
end

local function tok_number(name, fallback)
    return tonumber(tok:match(key(name) .. "(%-?[%d%.]+)")) or fallback
end

local function tok_bool(name, fallback)
    local v = tok:match(key(name) .. "(%a+)")
    if v == "true" then return true end
    if v == "false" then return false end
    return fallback
end

-- The user's accent, or the shipped system blue.
M.accent    = ut:match('"accent"%s*:%s*"#?(%x%x%x%x%x%x)"') or "0a84ff"
M.accent_fg = M.on_accent(M.accent)
-- Accent-tinted window ring (ewe.conf desktop.theme.tint_borders, mirrored
-- into user-theme.json as tintBorders). Absent -> on, the documented default.
M.tint_borders = ut:match('"tintBorders"%s*:%s*(%a+)') ~= "false"

-- Neutral surfaces — the token roles Hyprland-drawn chrome uses. Plain 6-digit
-- hex, so rgb()/rgba()/mix() below take them unchanged.
M.s_bg       = tok_color("bg-3",         "090a0e")  -- desktop / app base
M.s_panel    = tok_color("bg-1",         "131417")  -- popup / panel surface
M.s_elevated = tok_color("card",         "191a1d")  -- cards / inactive tab
M.s_hover    = tok_color("subtle-hover", "1b1c1f")  -- hover fill
M.s_fg       = tok_color("fg-1",         "ffffff")  -- primary text
M.s_fg_dim   = tok_color("fg-3",         "adadad")  -- dim text

-- Strokes carry their own alpha (0.5 by default): hex + alpha as a pair, and
-- the ready-made Hyprland `rgba(RRGGBBAA)` string for the ring/group borders.
M.s_stroke,  M.s_stroke_alpha  = tok_color("stroke-2", "515255", 0x80)  -- hairline
M.s_stroke3, M.s_stroke3_alpha = tok_color("stroke-3", "3c3d41", 0x80)  -- quieter hairline
M.stroke2 = M.rgba(M.s_stroke,  M.s_stroke_alpha)
M.stroke3 = M.rgba(M.s_stroke3, M.s_stroke3_alpha)

-- Shape: the control radius IS the window corner radius (12 under `round`).
M.radius = math.floor(tok_number("radius-control", 12))

-- The two [desktop.theme] knobs the compositor acts on (see hyprland.lua).

return M
