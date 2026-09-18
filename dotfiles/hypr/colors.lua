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

-- Readable text on an accent fill, for a token file without `on-accent`:
-- Ewe's one black on light accents, its one white (neutral-0) on dark ones,
-- tipping at 0.55 luminance like the generator's fallback.
function M.on_accent(hex)
    local r, g, b = tonumber(hex:sub(1, 2), 16) / 255,
                    tonumber(hex:sub(3, 4), 16) / 255,
                    tonumber(hex:sub(5, 6), 16) / 255
    return (0.299 * r + 0.587 * g + 0.114 * b) > 0.55 and "020202" or "fefdfc"
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

-- The accent the token file resolved (the person's pick, or the active
-- scheme's), then user-theme.json's copy, then ewellow. on_accent() below is
-- only the fallback for a token file that predates `on-accent`.
local ut_accent = ut:match('"accent"%s*:%s*"#?(%x%x%x%x%x%x)"')
M.accent      = tok_color("accent", ut_accent or "eeb407")
M.accent_fg   = tok_color("on-accent", M.on_accent(M.accent))
M.accent_text = tok_color("accent-text", M.accent)       -- grouped windows' ring
M.accent_pressed = tok_color("accent-pressed", M.accent) -- a locked group's ring
-- Accent-tinted window ring (ewe.conf desktop.theme.tint_borders, mirrored
-- into user-theme.json as tintBorders). Absent -> on, the documented default.
M.tint_borders = ut:match('"tintBorders"%s*:%s*(%a+)') ~= "false"

-- Ewe roles (design system v3) that Hyprland-drawn chrome uses: plain
-- 6-digit hex, so rgb()/rgba()/mix() below take them unchanged. The
-- fallbacks are Ewe Dark's, for a token file that is missing or half-written.
M.surface_base   = tok_color("surface-base",   "0b0a08")  -- desktop / app base
M.surface_raised = tok_color("surface-raised", "151411")  -- popups, cards, an idle group tab
M.surface_hover  = tok_color("surface-hover",  "2c2a26")  -- hover fill
M.text_primary   = tok_color("text-primary",   "faf9f6")  -- primary text
M.text_muted     = tok_color("text-muted",     "a8a49d")  -- an idle tab's title
M.border_subtle  = tok_color("border-subtle",  "2c2a26")  -- other windows' ring
M.border_strong  = tok_color("border-strong",  "7f7b75")  -- the focused ring, untinted
M.danger         = tok_color("danger",         "ffa196")  -- an urgent window

-- The window rings as Hyprland rgb() strings (Window card): the focused
-- window's when borders are not accent-tinted, and every other window's.
M.ring_focused = M.rgb(M.border_strong)
M.ring_idle    = M.rgb(M.border_subtle)

-- Shape: `rounded` is the WINDOW corner (Window card; 10 at corner =
-- medium, 16 at large, 0 at none), `primary` the control radius.
M.rounded = math.floor(tok_number("rounded", 10))
M.radius  = math.floor(tok_number("primary", 8))

-- Sizes and weights the group tab strip draws with (Window card).
M.tab_height      = math.floor(tok_number("control-sm", 24))
M.tab_font_size   = math.floor(tok_number("font-size-s", 12))
M.tab_padding     = math.floor(tok_number("space-s", 8))
M.tab_seam        = math.floor(tok_number("space-xxs", 2))
M.weight_semibold = math.floor(tok_number("font-weight-semibold", 600))
M.weight_medium   = math.floor(tok_number("font-weight-medium", 500))

return M
