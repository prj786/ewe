#!/usr/bin/env bash
# Workspaces on several displays (0.35): dotfiles/hypr/workspaces.lua against
# a fake `hl` API (no compositor), and the ewe.conf key that picks the mode.
# Every display owns ten Hyprland ids (1–10, 11–20 …) and shows 1, 2, 3 …;
# separate = each display its own, shared = switching one switches all.
# Hermetic: a throwaway XDG_CONFIG_HOME, stub qs and hyprctl on PATH.
set -u
cd "$(dirname "$0")/.."
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
fail=0
ok() { echo "ok    $*"; }
no() { echo "FAIL  $*"; fail=1; }

# ── 1. the Lua module, against a fake Hyprland ──────────────────────────────
LUA=$(command -v lua5.4 || command -v lua)
[ -n "$LUA" ] || { echo "no lua interpreter"; exit 1; }
cat > "$S/fake.lua" <<'EOF'
package.path = "dotfiles/hypr/?.lua;" .. package.path
-- a tiny Hyprland: displays, workspaces, windows; every dispatch is recorded
local W = {}            -- workspaces by id: { id, monitor = name, windows = { addr… } }
local D = {}            -- displays in id order: { id, name, active = ws id }
local focused = 1       -- index into D
local log = {}
local function mon(d)
  if not d then return nil end
  return { id = d.id, name = d.name, focused = (D[focused] == d), x = 0, y = 0,
           active_workspace = W[d.active] and { id = d.active, special = false, name = tostring(d.active),
                                                monitor = { name = d.name }, windows = #W[d.active].windows } or nil }
end
local function byname(n) for i, d in ipairs(D) do if d.name == n then return d, i end end end
local function ensure(id, dname) W[id] = W[id] or { id = id, monitor = dname, windows = {} }; return W[id] end
_G.hl = {
  get_monitors = function() local out = {} for _, d in ipairs(D) do out[#out + 1] = mon(d) end return out end,
  get_active_monitor = function() return mon(D[focused]) end,
  get_active_workspace = function() local d = D[focused]; return { id = d.active, special = false, monitor = { name = d.name } } end,
  get_active_window = function() return nil end,
  get_cursor_pos = function() return { x = 5, y = 5 } end,
  get_workspaces = function()
    local out = {}
    for id, w in pairs(W) do
      local d = byname(w.monitor)
      out[#out + 1] = { id = id, special = false, windows = #w.windows, is_empty = #w.windows == 0,
                        monitor = d and mon(d) or nil }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
  end,
  get_workspace = function(id) local w = W[id]; return w and { id = id, is_empty = #w.windows == 0 } or nil end,
  get_workspace_windows = function(id) local out = {} for _, a in ipairs((W[id] or {}).windows or {}) do out[#out + 1] = { address = a } end return out end,
  dispatch = function(d) d.fn(d) end,
  dsp = {
    focus = function(a) return { fn = function()
      if a.monitor then local _, i = byname(a.monitor); focused = i; log[#log + 1] = "focus mon " .. a.monitor
      elseif a.workspace then
        local d = D[focused]; ensure(a.workspace, d.name); d.active = a.workspace
        log[#log + 1] = "focus ws " .. a.workspace .. " on " .. d.name
      end end } end,
    window = { move = function(a) return { fn = function()
      local addr = a.window and a.window:gsub("^address:", "") or "active"
      for _, w in pairs(W) do for i, x in ipairs(w.windows) do if x == addr then table.remove(w.windows, i) break end end end
      local target = W[a.workspace] or ensure(a.workspace, D[focused].name)
      table.insert(target.windows, addr)
      log[#log + 1] = "move " .. addr .. " -> " .. a.workspace
    end } end },
    cursor = { move = function() return { fn = function() end } end },
  },
  on = function() end,
  timer = function() end,
}
local ws = require("workspaces")
local function reset(displays, workspaces)
  W, D, log, focused = {}, {}, {}, 1
  for i, d in ipairs(displays) do D[i] = { id = i - 1, name = d[1], active = d[2] } end
  for _, w in ipairs(workspaces) do W[w[1]] = { id = w[1], monitor = w[2], windows = w[3] or {} } end
end
local function active(name) return (byname(name)).active end
local function check(cond, what) print((cond and "ok    " or "FAIL  ") .. what) if not cond then FAILED = true end end

-- numbering
check(ws.number(1) == 1 and ws.number(10) == 10 and ws.number(11) == 1 and ws.number(23) == 3, "ids show as 1–10 on every display")
check(ws.block_of(10) == 0 and ws.block_of(11) == 1 and ws.block_of(30) == 2, "ten ids per display")

-- one display: exactly the ids of before
reset({ { "eDP-1", 1 } }, { { 1, "eDP-1" } })
ws.go(3)()
check(active("eDP-1") == 3, "one display: Super+3 is workspace 3, as always")

-- separate: Super+N on the second display stays on it
_G.ewe_workspaces_mode = nil
reset({ { "eDP-1", 1 }, { "DP-1", 11 } }, { { 1, "eDP-1" }, { 11, "DP-1" } })
focused = 2
ws.go(3)()
check(active("DP-1") == 13 and active("eDP-1") == 1, "separate: Super+3 on the second display → its own 3 (id 13), the first stays")
ws.move(2)()
check(W[12] and #W[12].windows == 1, "separate: Super+Shift+2 moves to the second display's 2 (id 12)")

-- shared: a switch on one display carries the others
_G.ewe_workspaces_mode = "shared"
reset({ { "eDP-1", 1 }, { "DP-1", 11 } }, { { 1, "eDP-1" }, { 11, "DP-1" } })
ws.go(2)()
ws.sync({ id = 2, special = false, monitor = { name = "eDP-1" } })   -- what workspace.active delivers
check(active("eDP-1") == 2 and active("DP-1") == 12, "shared: Super+2 → both displays on their 2")
check(D[focused].name == "eDP-1", "shared: the focus stays on the display you were on")
_G.ewe_workspaces_mode = nil

-- the old global numbering, and a display that left: windows go to the
-- same-numbered workspace of the display they sit on
reset({ { "eDP-1", 1 }, { "DP-1", 4 } }, { { 1, "eDP-1", { "a" } }, { 4, "DP-1", { "b" } } })
-- a reload settles at once (config.reloaded is not routed through a timer)
_G.hl.timer = function() error("no timer on reload") end
_G.hl.on = function(ev, fn) if ev == "config.reloaded" then RELOAD = fn end end
ws.setup()
RELOAD()
check(W[14] and W[14].windows[1] == "b" and active("DP-1") == 14, "upgrade: the second display's workspace 4 becomes its own 4 (id 14)")
check(active("eDP-1") == 1 and W[1].windows[1] == "a", "upgrade: the first display is untouched")

-- unplug the second display: Hyprland moved its workspace 14 to the first
D[2] = nil
W[14].monitor = "eDP-1"
RELOAD()
check(W[4] and W[4].windows[1] == "b", "unplugged: its windows merge into the first display's 4")

-- a new display gets the next free block and starts on its workspace 1
D[2] = { id = 1, name = "HDMI-A-1", active = 2 }
W[2] = { id = 2, monitor = "HDMI-A-1", windows = {} }
RELOAD()
check(active("HDMI-A-1") == 11, "plugged: a new display starts on its own workspace 1 (id 11)")

-- three fingers down: a new workspace on this display, never a pile of empties
reset({ { "eDP-1", 1 } }, { { 1, "eDP-1", { "a" } }, { 2, "eDP-1" } })
ws.new_workspace()
check(active("eDP-1") == 2, "new workspace: the last one is empty — go there")
W[2].windows = { "b" }
ws.new_workspace()
check(active("eDP-1") == 3, "new workspace: otherwise the next number")

os.exit(FAILED and 1 or 0)
EOF
"$LUA" "$S/fake.lua" || fail=1

# ── 2. the ewe.conf key ─────────────────────────────────────────────────────
mkdir -p "$S/bin"
printf '#!/bin/sh\necho "qs $*" >> "%s/calls.log"\n' "$S" > "$S/bin/qs"
printf '#!/bin/sh\necho "hyprctl $*" >> "%s/calls.log"\n' "$S" > "$S/bin/hyprctl"
chmod +x "$S/bin/qs" "$S/bin/hyprctl"
export PATH="$S/bin:$PATH" HOME="$S/home" XDG_CONFIG_HOME="$S/cfg" XDG_STATE_HOME="$S/state"
export HYPRLAND_INSTANCE_SIGNATURE=test-only-stub
mkdir -p "$S/home" "$S/cfg/quickshell" "$S/cfg/hypr/generated"
USERLUA="$S/cfg/hypr/generated/user.lua"
UT="$S/cfg/quickshell/user-theme.json"
mode_in_ut() { python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('workspacesMode'))" "$UT"; }

[ "$(bin/ewe-conf get desktop.workspaces.mode 2>/dev/null)" = "separate" ] \
  && ok "the default is separate" || no "the default is not separate"
: > "$S/calls.log"
bin/ewe-conf set desktop.workspaces.mode shared >/dev/null || no "set shared exited non-zero"
grep -qx '_G.ewe_workspaces_mode = "shared"' "$USERLUA" && ok "shared reaches user.lua" || no "user.lua has no shared line"
[ "$(mode_in_ut)" = "shared" ] && ok "the shell's copy says shared" || no "user-theme.json not updated"
grep -q "hyprctl reload" "$S/calls.log" && ok "Hyprland reloads" || no "no hyprctl reload"
grep -q "colorscheme" "$S/calls.log" && no "a workspace switch re-ran the colorscheme" || ok "no theme rebuild for a workspace switch"
bin/ewe-conf set desktop.workspaces.mode separate >/dev/null
grep -q "ewe_workspaces_mode" "$USERLUA" && no "separate left a line in user.lua" || ok "separate writes nothing (the default)"
[ "$(mode_in_ut)" = "separate" ] && ok "the shell's copy says separate" || no "user-theme.json not back to separate"
bin/ewe-conf set desktop.workspaces.mode sideways 2>"$S/err" && no "a bad mode was accepted" || {
  grep -q '"bad-value"' "$S/err" && ok "a bad mode is refused" || no "no bad-value error"
}

exit $fail
