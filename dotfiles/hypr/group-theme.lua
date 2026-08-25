-- group-theme.lua — the window-group look: the tab strip, the group borders,
-- and the square-while-grouped window corners.
--
-- Its own module for ONE reason: this is the only part of the Hyprland chrome
-- that has to be re-applied when the user changes accent or flips
-- flock/blacksheep, and re-applying it must not mean restating the palette in a
-- second language. `colorscheme.sh` (the single theming source) re-runs this
-- file live with:
--
--     hyprctl eval 'package.loaded["colors"]=nil
--                   package.loaded["group-theme"]=nil
--                   require("group-theme")'
--
-- which re-reads user-theme.json through colors.lua and re-applies everything
-- below — no config reload, no duplicated hex. hyprland.lua require()s it once
-- at startup; both paths run exactly this code. Re-running it is safe: the
-- event subscriptions at the bottom tear down their previous selves first.
--
-- THE SHAPE: a grouped window is not a floating card, it is the body of ONE
-- tabbed card whose top edge happens to be the tab strip. So while a window is
-- grouped everything about it goes square — the strip, its corners, its border
-- — and the strip sits flush on top with no gap. Rounded corners meeting a
-- square strip is what made the old design read as two mismatched shapes
-- stacked on each other. Ungrouped windows are untouched and keep the radius
-- from Settings → Layout.
--
-- THE COLOUR is still the live look: accent for the active tab, the
-- flock/blacksheep elevated surface with a 10% breath of accent for idle ones,
-- so the strip belongs to the same family as the rest of the shell.

package.loaded["colors"] = nil          -- always re-read the live accent/style
local c = require("colors")

local accent  = c.accent
local tabIdle = c.mix(c.s_elevated, accent, 0.10)
-- Locked group = "this stack won't take new windows". The same accent
-- lightened, so it reads as a STATE of the accent, not a different colour.
local locked  = c.mix(accent, "ffffff", 0.35)

hl.config({
    group = {
        col = {
            border_active          = c.rgba(accent,     0xee),
            border_inactive        = c.rgba(c.s_stroke, 0xaa),
            border_locked_active   = c.rgba(locked,     0xee),
            border_locked_inactive = c.rgba(c.s_stroke, 0xaa),
        },
        groupbar = {
            enabled          = true,
            height           = 22,
            indicator_height = 0,         -- the filled tab IS the indicator
            font_family      = "Ubuntu",  -- Theme.fontText — the DE face
            font_size        = 12,
            -- Ubuntu's regular is thin at this size against a saturated accent
            -- fill, so the strip gets a weight step instead of relying on
            -- colour alone: the active tab is the only bold thing on screen.
            -- NOTE: `hyprctl getoption` reports these as "invalid type
            -- (internal error)" — that is a getoption display bug, not a
            -- rejection. They apply; verified by rendering.
            font_weight_active   = 700,
            font_weight_inactive = 500,
            render_titles    = true,
            stacked          = false,
            -- `gradients` is what makes the groupbar paint a FILL behind each
            -- tab at all — with it off the strip is bare text on the desktop
            -- and col.* is never drawn. Single-stop colours render FLAT, so
            -- this is on for the fill, not for a gradient: the same one-stop
            -- trick Theme.qml uses for barTop/barBottom.
            gradients                 = true,
            -- Square, all of it. The strip is the top edge of the card.
            rounding                  = 0,
            gradient_rounding         = 0,
            round_only_edges          = false,
            gradient_round_only_edges = false,
            -- Flush: no gap under the strip, none to the window's side edges.
            -- gaps_in is the hairline seam BETWEEN tabs — 2px of desktop
            -- showing through, since Hyprland has no separator colour and
            -- adjacent idle tabs would otherwise fuse into one anonymous bar.
            gaps_in          = 2,
            gaps_out         = 0,
            keep_upper_gap   = false,
            text_padding     = 10,
            text_color          = c.rgb(c.accent_fg),
            text_color_inactive = c.rgb(c.s_fg_dim),
            col = {
                active          = c.rgba(accent,  0xff),
                inactive        = c.rgba(tabIdle, 0xdd),
                locked_active   = c.rgba(locked,  0xff),
                locked_inactive = c.rgba(tabIdle, 0xdd),
            },
        },
    },
})


-- ── Square while grouped ────────────────────────────────────────────────────
-- Hyprland has no "is grouped" window-rule match and fires no group event, so
-- the corners are driven per-window with setprop. `unset` (not the numeric
-- radius) is what we restore: it hands the window back to decoration.rounding,
-- so the Settings → Layout slider keeps working on ungrouped windows with no
-- further help from us.
local applied = {}   -- address -> value we last pushed; steady state costs nothing

local function sync_rounding()
    local seen = {}
    for _, w in ipairs(hl.get_windows()) do
        local want = w.group and 0 or "unset"
        seen[w.address] = true
        if applied[w.address] ~= want then
            applied[w.address] = want
            hl.dispatch(hl.dsp.window.set_prop({ window = w, prop = "rounding", value = want }))
        end
    end
    for addr in pairs(applied) do
        if not seen[addr] then applied[addr] = nil end
    end
end

-- Re-running this module must not stack a second set of subscriptions on the
-- first, so drop the previous ones. Kept on _G because a fresh require() gets
-- fresh locals but talks to the same compositor.
if _G.__ewe_group_subs then
    for _, sub in ipairs(_G.__ewe_group_subs) do pcall(function() sub:remove() end) end
end
-- window.active is the catch-all: it also covers grouping done by DRAGGING a
-- window onto a groupbar, which never touches our keybinds. open/close catch
-- auto_group pulling a new window in and a group collapsing as tabs close.
_G.__ewe_group_subs = {
    hl.on("window.open",   sync_rounding),
    hl.on("window.close",  sync_rounding),
    hl.on("window.active", sync_rounding),
}

-- The group keybinds in hyprland.lua call this the instant they change
-- membership, so corners flip in the same frame rather than on the next event.
_G.ewe_sync_group_rounding = sync_rounding

sync_rounding()
