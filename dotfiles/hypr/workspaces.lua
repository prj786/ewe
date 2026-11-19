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
-- After a display arrives (`fresh`) an empty one is only that display's first
-- workspace (Hyprland hands a new display the lowest free id): it starts on
-- its own workspace 1. Otherwise an empty one keeps its number — something
-- asked for "workspace 3" by its raw id (a script, the swipe) on the wrong
-- display.
local function normalize(fresh)
    local moves, switch = {}, {}
    for _, w in ipairs(hl.get_workspaces() or {}) do
        if w.id >= 1 and not w.special and w.monitor and slots[w.monitor.name] ~= nil then
            local k = slots[w.monitor.name]
            if M.block_of(w.id) ~= k then
                local target = id_for(k, (fresh and (w.windows or 0) == 0) and 1 or M.number(w.id))
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

-- Launches you asked for (0.43). A window a rule sends to workspace N takes
-- you along only when you just launched something: a key bound to an app
-- (hyprland.lua's launch binds, your own keybinds) or a click in the shell
-- (launcher, dock, the app openers — they dispatch `_G.ewe_launched()`, a
-- Lua function, no process). Anything an app opens by itself goes to its
-- workspace quietly: before this every Steam toast — its own `steam`
-- window — dragged you to Steam's workspace. A launch names the app it
-- expects (the desktop entry's StartupWMClass or id; a bind's command) and
-- is spent on the first window of THAT app: a launch that opens nothing new
-- (Super+B with the browser already open) never hands its "you asked" to
-- the next toast. 30 s covers a slow start (Steam, JetBrains).
local LAUNCH_SECS = 30
local launch = nil   -- { at = os.time(), hint = "steam" } — the pending launch
local function norm(s)
    s = tostring(s or ""):lower():gsub("%.desktop$", ""):gsub("%.sh$", "")
    return s
end
local function last(s) return s:match("([^.]+)$") or s end
-- does a window's class belong to the app a launch named? ("" = any window)
function M.launch_matches(class, hint)
    local h = norm(hint)
    if h == "" then return true end
    local c = norm(class)
    if c == "" then return false end
    if c == h or last(c) == last(h) then return true end
    -- komble-google-chrome (a Komble AppImage) opens google-chrome;
    -- jetbrains-rustrover-<id> opens jetbrains-rustrover
    if #c >= 4 and h:find(c, 1, true) then return true end
    if #h >= 4 and c:find(h, 1, true) then return true end
    return false
end
-- `here` (0.43.1): the launch asked for THIS workspace — the desktop's "Open
-- terminal here", Files' "Open in Terminal" (ewe-terminal-here). Its window
-- stays where you are, focused, even when a Window Rule sends that app to
-- another workspace (the owner's kitty → 3 carried both off, unfocused, so
-- they looked like they did nothing).
function M.launched(hint, here)
    launch = { at = os.time(), hint = tostring(hint or ""), here = here == true }
end
_G.ewe_launched = M.launched
-- launch(cmd[, hint]): the dispatcher for a bind that starts an app; the hint
-- is the command's program unless given ("" = the next window of any app)
function M.launch(cmd, hint)
    if hint == nil then
        local bin = tostring(cmd):match("^%s*(%S+)") or ""
        hint = bin:match("([^/]+)$") or bin
    end
    return function()
        M.launched(hint)
        hl.dispatch(hl.dsp.exec_cmd(cmd))
    end
end
_G.ewe_launch = M.launch
-- the pending launch this window spends (nil when it was not asked for)
local function take_launch(win)
    if not launch then return nil end
    if os.time() - launch.at > LAUNCH_SECS then launch = nil; return nil end
    if not M.launch_matches(win.class or win.initial_class, launch.hint) then return nil end
    local l = launch
    launch = nil
    return l
end

-- a window opening: Settings → Window Rules tag it `ewe-ws-N` (ewe-conf) —
-- it goes to workspace N of the display it opens on, like Super+N. A window
-- that lands in another display's block anyway (a rule from before 0.35.1
-- that says `workspace = "3"`, a raw id) goes to the same number of the
-- display it is on: two "Workspace 3" on one display was the 0.35.0 bug.
--
-- A tagged window opens WITHOUT focus (hyprland.lua's `ewe-ws-quiet-N`
-- rules — `follow = false` alone is not enough: Hyprland focuses a new
-- window when it maps and switches to its workspace to do it; a tag added
-- here, at open_early, comes too late for a static rule, so the quiet rules
-- match the rule's own tag). It gets focus back on `window.open` when you
-- launched it — the view goes with it — or when it opens on the workspace
-- you are on (a dialog of the app you are using).
local focus_on_open = {}   -- address -> true: focus it once it has mapped
-- a window shown on every workspace stays where it opened: a pinned one
-- (picture-in-picture) and Steam's toasts (hyprland.lua "steam-toasts" pins
-- them; the title is matched too in case the pin is not applied yet)
local function shown_everywhere(win)
    if win.pinned then return true end
    for _, t in ipairs({ win.title, win.initial_title }) do
        if tostring(t or ""):match("^notificationtoasts_%d+_desktop$") then return true end
    end
    return false
end
function M.place(win)
    if not win or not win.monitor or not win.workspace or win.workspace.special then return end
    if shown_everywhere(win) then return end
    local asked = take_launch(win)
    -- "open it here": no rule moves it; it opens where you are, focused
    if asked and asked.here then focus_on_open[win.address] = true; return end
    if slots[win.monitor.name] == nil then return end   -- a display still settling
    local k = slots[win.monitor.name]
    local n
    for _, t in ipairs(win.tags or {}) do
        n = n or tonumber(tostring(t):match("^ewe%-ws%-(%d+)"))
    end
    local tagged = n ~= nil
    if not n and win.workspace.id >= 1 and M.block_of(win.workspace.id) ~= k then
        n = M.number(win.workspace.id)
    end
    if not n or n < 1 or n > SPAN then return end
    local target = id_for(k, n)
    if tagged then
        local here = hl.get_active_workspace()
        if asked or (here and here.id == target) then focus_on_open[win.address] = true end
    end
    if win.workspace.id == target then return end
    hl.dispatch(hl.dsp.window.move({ workspace = target, window = "address:" .. win.address, follow = not tagged }))
end
local function focus_placed(win)
    if not win or not focus_on_open[win.address] then return end
    focus_on_open[win.address] = nil
    hl.dispatch(hl.dsp.focus({ window = "address:" .. win.address }))
end
local function forget_placed(win)
    if win then focus_on_open[win.address] = nil end
end

-- ── wiring ─────────────────────────────────────────────────────────────────
local function settle()
    assign()
    normalize(true)
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
    hl.on("window.open_early", function(win) M.place(win) end)
    hl.on("window.open", focus_placed)
    hl.on("window.destroy", forget_placed)
    -- a workspace made by its raw id on the wrong display: re-home it once
    -- Hyprland has finished making it (displays not yet in `slots` are left
    -- to settle())
    hl.on("workspace.created", function()
        if not syncing then hl.timer(function() normalize(false) end, { timeout = 1, type = "oneshot" }) end
    end)
end

return M
