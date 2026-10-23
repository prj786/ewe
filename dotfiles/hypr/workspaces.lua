-- workspaces.lua — workspaces on several displays, macOS-style (2026-10-23).
--
-- Every display owns a block of Hyprland workspace ids: the first display
-- 1–10, the second 11–20, the third 21–30 … (block k = k*10+1 .. k*10+10).
-- On screen they are always "Workspace 1, 2, 3 …" (the shell shows
-- ((id - 1) % 10) + 1). One display = exactly the ids 1–10 of before, so
-- nothing changes on a laptop alone.
--
-- Two modes, ewe.conf [desktop.workspaces] mode (ewe-conf writes
-- `_G.ewe_workspaces_mode` into generated/user.lua when it is not the
-- default; read lazily, so a `hyprctl reload` switches modes):
--   separate (default) — macOS "Displays have separate Spaces": every
--     display has its own workspaces; Super+N, Super+wheel and the swipes
--     act on the display you are on.
--   shared — one set of workspaces across every display: whatever switches
--     one display (a key, a swipe, the dock, the Overview) switches every
--     display to its own part of the same workspace.
-- The data model is the same in both, so switching modes moves no window.
--
-- Displays come and go: a new display gets the lowest free block; a display
-- that leaves frees its block, and the workspaces Hyprland moved off it give
-- their windows to the same-numbered workspace of the display they landed on
-- (macOS merges a gone display's spaces the same way). The same pass turns
-- the old global numbering (workspace 2 living on the second display) into
-- the second display's own workspace 2, once, on upgrade.
--
-- Everything runs inside the compositor: no process per key, no shell
-- round trip.

local M = {}
local SPAN = 10

local slots = {}        -- display name -> block index (0, 1, 2 …), for this session
local syncing = false   -- our own focus hops must not re-trigger the shared sync

function M.mode()
    return _G.ewe_workspaces_mode == "shared" and "shared" or "separate"
end
function M.block_of(id) return math.floor((id - 1) / SPAN) end
function M.number(id) return ((id - 1) % SPAN) + 1 end
local function id_for(block, n) return block * SPAN + n end

local function displays()
    local list = hl.get_monitors() or {}
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- give every connected display a block, keep the ones it already has, and
-- forget the displays that are gone
local function assign()
    local here, used = {}, {}
    local list = displays()
    for _, m in ipairs(list) do here[m.name] = true end
    for name in pairs(slots) do if not here[name] then slots[name] = nil end end
    for _, k in pairs(slots) do used[k] = true end
    -- a display keeps the block its current workspace belongs to, when free
    -- (after a reload, after the first start)
    for _, m in ipairs(list) do
        local ws = m.active_workspace
        if slots[m.name] == nil and ws and ws.id >= 1 and not used[M.block_of(ws.id)] then
            slots[m.name] = M.block_of(ws.id)
            used[slots[m.name]] = true
        end
    end
    for _, m in ipairs(list) do
        if slots[m.name] == nil then
            local k = 0
            while used[k] do k = k + 1 end
            slots[m.name] = k
            used[k] = true
        end
    end
end

local function block(m)
    if slots[m.name] == nil then assign() end
    return slots[m.name] or 0
end

-- Show these workspaces on these displays without taking the keyboard focus
-- or the pointer from where they are. Hyprland has no "switch that display
-- to a workspace that does not exist yet", so: focus each display, focus the
-- workspace there, and come back — all in one go, nothing is drawn between.
local function show(list)
    if #list == 0 then return end
    local cursor = hl.get_cursor_pos()
    local here = hl.get_active_monitor()
    local win = hl.get_active_window()
    syncing = true
    for _, it in ipairs(list) do
        hl.dispatch(hl.dsp.focus({ monitor = it.display.name }))
        hl.dispatch(hl.dsp.focus({ workspace = it.id }))
    end
    if here then hl.dispatch(hl.dsp.focus({ monitor = here.name })) end
    if win and here and win.monitor and win.monitor.name == here.name and win.workspace
       and here.active_workspace and win.workspace.id == here.active_workspace.id then
        hl.dispatch(hl.dsp.focus({ window = "address:" .. win.address }))
    end
    if cursor then hl.dispatch(hl.dsp.cursor.move({ x = cursor.x, y = cursor.y })) end
    syncing = false
end

-- every workspace lives in the block of the display it is on: one that sits
-- elsewhere gives its windows to the same-numbered workspace of that display.
-- An empty one is only a new display's first workspace (Hyprland hands a new
-- display the lowest free id): that display starts on its own workspace 1.
local function normalize()
    local moves, switch = {}, {}
    for _, w in ipairs(hl.get_workspaces() or {}) do
        if w.id >= 1 and not w.special and w.monitor and slots[w.monitor.name] ~= nil then
            local k = slots[w.monitor.name]
            if M.block_of(w.id) ~= k then
                local target = id_for(k, (w.windows or 0) > 0 and M.number(w.id) or 1)
                for _, win in ipairs(hl.get_workspace_windows(w.id) or {}) do
                    moves[#moves + 1] = { address = win.address, id = target }
                end
                local active = w.monitor.active_workspace
                if active and active.id == w.id then
                    switch[#switch + 1] = { display = w.monitor, id = target }
                end
            end
        end
    end
    for _, mv in ipairs(moves) do
        hl.dispatch(hl.dsp.window.move({ workspace = mv.id, window = "address:" .. mv.address, follow = false }))
    end
    show(switch)
end

-- shared mode: every other display follows the workspace number `ws` shows
function M.sync(ws)
    if syncing or M.mode() ~= "shared" then return end
    if not ws or ws.special or ws.id < 1 or not ws.monitor then return end
    local n = M.number(ws.id)
    local list = {}
    for _, m in ipairs(displays()) do
        if m.name ~= ws.monitor.name then
            local target = id_for(block(m), n)
            if not (m.active_workspace and m.active_workspace.id == target) then
                list[#list + 1] = { display = m, id = target }
            end
        end
    end
    show(list)
end

-- the workspace numbers in use: this display's (separate), or every display's (shared)
local function numbers(m)
    local seen, out = {}, {}
    local shared = M.mode() == "shared"
    for _, w in ipairs(hl.get_workspaces() or {}) do
        if w.id >= 1 and not w.special and w.monitor and (shared or w.monitor.name == m.name) then
            local n = M.number(w.id)
            if not seen[n] then seen[n] = true; out[#out + 1] = n end
        end
    end
    table.sort(out)
    return out
end

-- ── what the keys and gestures call ───────────────────────────────────────
-- Super+N: workspace N of the display you are on
function M.go(n)
    return function()
        local m = hl.get_active_monitor()
        if m then hl.dispatch(hl.dsp.focus({ workspace = id_for(block(m), n) })) end
    end
end

-- Super+Shift+N: the focused window to workspace N of its display (and follow)
function M.move(n)
    return function()
        local m = hl.get_active_monitor()
        if m then hl.dispatch(hl.dsp.window.move({ workspace = id_for(block(m), n) })) end
    end
end

-- Super+wheel off the scrolling layout: the next/previous workspace in use
-- on this display (shared: on any display), round the ends
function M.cycle(step)
    local m = hl.get_active_monitor()
    if not m or not m.active_workspace then return end
    local list = numbers(m)
    if #list == 0 then return end
    local cur, at = M.number(m.active_workspace.id), 1
    for i, n in ipairs(list) do if n == cur then at = i end end
    local next = list[((at - 1 + step) % #list) + 1]
    hl.dispatch(hl.dsp.focus({ workspace = id_for(block(m), next) }))
end

-- three fingers down: a new workspace on this display — never a pile of
-- empty ones: if the last workspace is empty, go there instead
function M.new_workspace()
    local m = hl.get_active_monitor()
    if not m then return end
    local k = block(m)
    local last = 0
    for _, n in ipairs(numbers(m)) do if n > last then last = n end end
    local target
    if last == 0 then
        target = 1
    else
        local w = hl.get_workspace(id_for(k, last))
        target = (w and w.is_empty) and last or math.min(last + 1, SPAN)
    end
    hl.dispatch(hl.dsp.focus({ workspace = id_for(k, target) }))
end

-- ── wiring ─────────────────────────────────────────────────────────────────
local function settle()
    assign()
    normalize()
    if M.mode() == "shared" then M.sync(hl.get_active_workspace()) end
end

function M.setup()
    -- a display arriving or leaving: let Hyprland place its workspaces first
    local function later() hl.timer(settle, { timeout = 300, type = "oneshot" }) end
    hl.on("monitor.added", later)
    hl.on("monitor.removed", later)
    hl.on("hyprland.start", later)
    -- a reload: at once, never through a timer — config.reloaded also fires
    -- while the config is first parsed, before Hyprland's event loop exists
    -- (`Hyprland --verify-config` segfaulted on an hl.timer from here)
    hl.on("config.reloaded", settle)
    hl.on("workspace.active", function(ws) M.sync(ws) end)
end

return M
