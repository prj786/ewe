-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  hyprland.lua — Hyprland 0.55+ Lua configuration                           ║
-- ║                                                                            ║
-- ║  Ported from the previous Qtile `desktop_env` so muscle memory carries     ║
-- ║  over: Super is the mod, focus is vim hjkl, workspaces are 1–8, and the    ║
-- ║  laptop media / screenshot / lock keys behave identically.                 ║
-- ║                                                                            ║
-- ║  Reload:        Super + Ctrl + R   (Hyprland also auto-reloads on save)    ║
-- ║  All shortcuts: ~/.config/hypr/SHORTCUTS.md                                ║
-- ║  Colours:       ~/.config/hypr/colors.lua  (Gruvbox, single source)        ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local c        = require("colors")
local home     = os.getenv("HOME")
local scripts  = home .. "/.config/hypr/scripts"

-- Core programs (mirror the old settings.py defaults) ------------------------
local terminal    = "kitty"
local fileManager = "nemo"
-- Open whatever the user set as the default web browser (Settings → Default Apps
-- writes it via `xdg-settings set default-web-browser`). We resolve the .desktop
-- and launch it with `gio launch` (glib2, always present); fall back to firefox.
local browser     = 'b="$(xdg-settings get default-web-browser 2>/dev/null)"; '
                 .. 'f="$HOME/.local/share/applications/$b"; [ -f "$f" ] || f="/usr/share/applications/$b"; '
                 .. 'if [ -n "$b" ] && [ -f "$f" ]; then exec gio launch "$f"; else exec firefox; fi'
local applauncher = "qs ipc call applauncher toggle"  -- Quickshell launcher (QML)

local mainMod = "SUPER"   -- the Super / Windows key


-- ╭───────────────────────────────────────────────────────────────╮
-- │ MONITORS — https://wiki.hypr.land/Configuring/Basics/Monitors/  │
-- ╰───────────────────────────────────────────────────────────────╯
-- Dual display, with the external on the LEFT.
--   * DP-1 (Samsung 27", 2560x1440) anchored at the far left (0x0), scale 1.
--   * eDP-1 (laptop, 2880x1800 HiDPI) auto-placed to its right, scale 2 → 1440
--     logical px, so its left edge sits at x=2560 (DP-1's logical width).
-- Declaration order matters: DP-1 first claims 0x0, then eDP-1 "auto" lands to
-- its right. Unplug the external and eDP-1's "auto" falls back to 0x0 cleanly.
hl.monitor({ output = "DP-1",  mode = "preferred", position = "0x0",  scale = 1 })
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2 })

-- Catch-all for any other display plugged in later.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })


-- ╭───────────────────────────────────────────────────────────────╮
-- │ ENVIRONMENT                                                     │
-- ╰───────────────────────────────────────────────────────────────╯
-- The toolkit theming env (GTK_THEME, XCURSOR_THEME, GDK_BACKEND, the qt6ct
-- fallback, …) is exported in start-hyprland.sh BEFORE `exec Hyprland`, not here.
-- hl.env() applies to Hyprland's children but its propagation to apps launched
-- on-demand is unreliable — exporting in the wrapper puts the vars in the real
-- process environment of every descendant. See that file.


-- ╭───────────────────────────────────────────────────────────────╮
-- │ LOOK & FEEL — https://wiki.hypr.land/Configuring/Basics/        │
-- ╰───────────────────────────────────────────────────────────────╯
hl.config({
    general = {
        gaps_in     = 6,
        gaps_out    = 14,
        border_size = 1,           -- no chunky borders; the shadow carries the depth

        -- Active border: Gruvbox yellow → orange gradient. Inactive: a quiet
        -- surface tone so unfocused windows recede.
        col = {
            active_border   = { colors = { c.rgba(c.yellow, 0xee), c.rgba(c.orange, 0xee) }, angle = 45 },
            inactive_border = c.rgba(c.bg2, 0xaa),
        },

        resize_on_border = true,
        allow_tearing    = false,
        layout           = "dwindle",
    },

    decoration = {
        rounding       = 12,   -- Big Sur / Sequoia corner radius
        rounding_power = 2,

        active_opacity   = 1.0,
        inactive_opacity = 0.97,  -- a hair of depth on unfocused windows

        -- Big soft drop shadow — the single biggest depth cue.
        -- Large range, low alpha = a diffuse shadow (not a hard outline).
        shadow = {
            enabled      = true,
            range        = 26,
            render_power = 3,
            color        = 0x40000000,  -- 0xAARRGGBB: ~25% black, soft
        },

        -- Blur is OFF everywhere: every shell surface is solid, and the frosted
        -- scrims (Overview/Settings) read fine as plain translucent dims. Blur
        -- was also a constant multi-pass GPU cost on the whole desktop.
        blur = {
            enabled = false,
        },
    },

    dwindle = {
        preserve_split = true,
    },

    misc = {
        disable_hyprland_logo   = true,
        force_default_wallpaper = 0,
        -- Silence "Hyprland was started without start-hyprland." We launch via our
        -- own session wrapper (start-hyprland.sh) from greetd and propagate the
        -- systemd/DBus activation env in scripts/autostart.sh, so Hyprland's own
        -- start-hyprland watchdog wrapper isn't used — by design, not a mistake.
        disable_watchdog_warning = true,
    },

    -- Cursor on Lunar Lake / Arc 140V (`xe` driver). Two failure modes exist:
    --   * pure hardware cursor  → drmModeAtomicCommit "Invalid argument" freeze
    --     (the GPU cursor-buffer path on `xe` is broken / PSR2 selective-fetch);
    --   * pure software cursor (no_hardware_cursors=true) → a stale "ghost"
    --     copy of the pointer left stuck on screen (what you saw).
    -- The fix that avoids BOTH is a hardware cursor plane fed from a CPU-mapped
    -- (dumb) buffer: keep hardware cursors ON, but force the CPU buffer so we
    -- never touch the broken GPU cursor-buffer path.
    cursor = {
        no_hardware_cursors = false,
        use_cpu_buffer      = true,
        inactive_timeout    = 5,   -- hide the pointer after 5s idle
    },
})

-- Quiet the ecosystem startup nags (update news / donation popups).
hl.config({
    ecosystem = {
        no_update_news  = true,
        no_donation_nag = true,
    },
})


-- ╭───────────────────────────────────────────────────────────────╮
-- │ WINDOW GROUPS (tabbed stacks) — themed to match Theme.qml       │
-- ╰───────────────────────────────────────────────────────────────╯
-- Window grouping is intentionally unused in this DE — the Lua config doesn't
-- expose the merge dispatchers (moveintogroup/movewindoworgroup), so we removed
-- the group keybinds and chrome. Workspace navigation lives in the bottom dock.


-- ── Animations: smooth, slightly snappy; workspaces slide horizontally ───────
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1} } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1} } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1} } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })

hl.config({ animations = { enabled = true } })

hl.animation({ leaf = "global",     enabled = true, speed = 9,    bezier = "easeOutQuint" })
hl.animation({ leaf = "border",     enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",    enabled = true, speed = 5,    spring = "easy",         style = "popin 88%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3,    bezier = "linear",       style = "popin 88%" })
hl.animation({ leaf = "fade",       enabled = true, speed = 3.5,  bezier = "quick" })
hl.animation({ leaf = "layers",     enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5,    bezier = "easeOutQuint", style = "slide" })


-- ╭───────────────────────────────────────────────────────────────╮
-- │ INPUT                                                          │
-- ╰───────────────────────────────────────────────────────────────╯
hl.config({
    input = {
        -- English (US) only by default. To add a second layout, append it here
        -- (e.g. "us,ge") and a matching kb_variant, then re-enable the
        -- Super+Shift+Space toggle bind below.
        kb_layout    = "us",
        kb_variant   = "",
        kb_model     = "",
        kb_options   = "",
        kb_rules     = "",

        follow_mouse = 1,          -- focus follows the pointer (matches Qtile)
        sensitivity  = 0,          -- -1.0 .. 1.0, 0 = unmodified

        touchpad = {
            natural_scroll = true, -- "content follows fingers"
        },
    },
})

-- Three-finger horizontal swipe → switch workspaces.
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

-- Three-finger swipe up → Overview (GNOME muscle memory).
hl.gesture({
    fingers   = 3,
    direction = "up",
    action    = function() hl.dispatch(hl.dsp.exec_cmd("qs ipc call overview toggle")) end,
})

-- Three-finger swipe down → new desktop. Never stacks empties: if the highest
-- desktop is already empty, just go there instead of minting another one.
hl.gesture({
    fingers   = 3,
    direction = "down",
    action    = function()
        local last = nil
        for _, ws in ipairs(hl.get_workspaces()) do
            if ws.id >= 1 and ws.id < 100 and (not last or ws.id > last.id) then last = ws end
        end
        local maxid  = last and last.id or 1
        local target = (last and last.is_empty) and maxid or math.min(maxid + 1, 10)
        hl.dispatch(hl.dsp.focus({ workspace = target }))
    end,
})


-- ╭───────────────────────────────────────────────────────────────╮
-- │ KEYBINDINGS — ported from desktop_env/keys/keybindings.py       │
-- ╰───────────────────────────────────────────────────────────────╯

-- Launchers ------------------------------------------------------------------
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + D",      hl.dsp.exec_cmd(applauncher))  -- Launcher
-- Super+Space switches keyboard layout (cycles input sources). No-op with a single
-- layout; add a second to input.kb_layout above to make it useful.
hl.bind(mainMod .. " + Space",  hl.dsp.exec_cmd("hyprctl switchxkblayout current next"))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B",      hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + C",      hl.dsp.exec_cmd(scripts .. "/calendar.sh"))
hl.bind(mainMod .. " + N",      hl.dsp.exec_cmd("qs ipc call quicksettings toggle"))  -- Quick Settings
hl.bind(mainMod .. " + comma",  hl.dsp.exec_cmd("qs ipc call settings toggle")) -- Super+, Settings
-- Blind display recovery: works with a BLACK screen — forces every output's
-- dpms on and re-asserts the saved display profile. If a plug/unplug or the
-- xe driver ever blanks everything, press this instead of the power button.
-- (Super+Ctrl+R is taken by config reload below.)
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("qs ipc call display reset"))

-- Super tapped ALONE → Overview (GNOME-style window switcher). `release` fires on key-up;
-- with the modifier as its own key Hyprland only triggers it on a clean tap (no other key
-- pressed during the hold), so Super+<x> combos don't pop the overview.
hl.bind(mainMod .. " + Super_L", hl.dsp.exec_cmd("qs ipc call overview toggle"), { release = true })

-- Window focus (vim hjkl + arrow keys — arrows are aliases for hjkl) ----------
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))

-- Move the focused window (Shift + hjkl / Shift + arrows) — directional movewindow.
-- Lua config: the /dispatch IPC evaluates its arg as Lua, so exec_cmd "hyprctl
-- dispatch movewindow l" fails. Use the typed hl.dsp.* dispatchers directly.
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + SHIFT + J", hl.dsp.window.move({ direction = "d" }))
hl.bind(mainMod .. " + SHIFT + K", hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "d" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "u" }))

-- Resize the focused window (Ctrl + hjkl) ------------------------------------
hl.bind(mainMod .. " + CTRL + H", hl.dsp.window.resize({ x = -40, y = 0, relative = true }))
hl.bind(mainMod .. " + CTRL + L", hl.dsp.window.resize({ x = 40,  y = 0, relative = true }))
hl.bind(mainMod .. " + CTRL + K", hl.dsp.window.resize({ x = 0,  y = -40, relative = true }))
hl.bind(mainMod .. " + CTRL + J", hl.dsp.window.resize({ x = 0,  y = 40, relative = true }))
-- NOTE: the old Super+Shift+N "reset split" (splitratio exact 1.0) was removed — the
-- `splitratio` dispatcher isn't exposed by the Lua API (not in hl.dsp; exec_raw/global
-- silently no-op; the layoutmsg path rejects "exact"). Use Super+Ctrl+H/L to adjust the
-- split manually instead.

-- Window state ---------------------------------------------------------------
hl.bind(mainMod .. " + Q",         hl.dsp.window.close())
hl.bind(mainMod .. " + F",         hl.dsp.window.fullscreen({ mode = 0 }))  -- true fullscreen
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = 1 }))  -- maximise
hl.bind(mainMod .. " + V",         hl.dsp.window.float({ action = "toggle" }))  -- (moved off Space → Launcher)
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + T",         hl.dsp.layout("togglesplit"))                       -- dwindle split
hl.bind(mainMod .. " + Tab",         hl.dsp.window.cycle_next())
hl.bind(mainMod .. " + SHIFT + Tab", hl.dsp.window.cycle_next({ prev = true }))

-- Session --------------------------------------------------------------------
hl.bind(mainMod .. " + CTRL + R", hl.dsp.exec_cmd("hyprctl reload"))     -- reload config
hl.bind(mainMod .. " + CTRL + Q", hl.dsp.exit())                         -- quit / log out
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd("qs ipc call bar toggle"))  -- toggle bar
hl.bind(mainMod .. " + ALT + L",   hl.dsp.exec_cmd("qs ipc call lock lock"))  -- lock (Quickshell session lock)

-- Laptop lid (clamshell via lid.sh). logind is told to ignore the lid by
-- /etc/systemd/logind.conf.d/10-hypr-shell-lid.conf (installed by phase 30)
-- so the two suspend paths never race. `l` flag = fire even while locked.
hl.bind("switch:on:Lid Switch",  hl.dsp.exec_cmd(scripts .. "/lid.sh close"), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd(scripts .. "/lid.sh open"),  { locked = true })
-- Layout toggle disabled: single (US) layout. Re-enable with a second kb_layout.
-- hl.bind(mainMod .. " + SHIFT + Space", hl.dsp.exec_cmd("hyprctl switchxkblayout current next"))
hl.bind(mainMod .. " + period",        hl.dsp.exec_cmd("qs ipc call clipboard toggle"))          -- clipboard + emoji

-- Scratchpad (Hyprland "special" workspace) ----------------------------------
-- Super+grave kept from Qtile muscle memory; Super+S is the Hyprland default.
hl.bind(mainMod .. " + grave",     hl.dsp.workspace.toggle_special("scratch"))
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("scratch"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:scratch" }))

-- Workspaces 1–8 (Qtile groups) ----------------------------------------------
--   Super + N         → switch to workspace N
--   Super + Shift + N → move the focused window to workspace N (and follow)
for i = 1, 8 do
    hl.bind(mainMod .. " + " .. i,           hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i,   hl.dsp.window.move({ workspace = i }))
end

-- Scroll over an empty area / hold Super to cycle workspaces.
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Mouse: Super + drag to move (LMB) / resize (RMB) ---------------------------
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Media keys → WirePlumber / brightnessctl (fire while locked, auto-repeat) --
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     { locked = true })
-- Power button: logind ignores a short press (system/logind drop-in) so a stray
-- tap can't hard-poweroff; show the shutdown confirmation instead. Not `locked`
-- on purpose — while the session is locked the tap does nothing (long press
-- still powers off via logind).
hl.bind("XF86PowerOff",          hl.dsp.exec_cmd("qs ipc call quicksettings powerdialog"))
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+ && qs ipc call osd brightness"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%- && qs ipc call osd brightness"), { locked = true, repeating = true })
-- Keyboard backlight (0-3 on ASUS). The shell writes it through logind's
-- SetBrightness, so there is no udev rule or setuid helper for this one.
hl.bind("XF86KbdBrightnessUp",   hl.dsp.exec_cmd("qs ipc call power kbdUp"),   { locked = true, repeating = true })
hl.bind("XF86KbdBrightnessDown", hl.dsp.exec_cmd("qs ipc call power kbdDown"), { locked = true, repeating = true })
hl.bind("XF86KbdLightOnOff",     hl.dsp.exec_cmd("qs ipc call power kbdUp"),   { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- Screenshots → ~/Pictures/Screenshots + clipboard (grim/slurp/wl-copy) ------
hl.bind("Print",           hl.dsp.exec_cmd(scripts .. "/screenshot.sh full"))
hl.bind("SHIFT + Print",   hl.dsp.exec_cmd(scripts .. "/screenshot.sh region"))
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd(scripts .. "/screenshot.sh activewindow"))  -- focused window


-- ╭───────────────────────────────────────────────────────────────╮
-- │ WINDOW RULES — https://wiki.hypr.land/Configuring/Basics/...    │
-- ╰───────────────────────────────────────────────────────────────╯
-- Ignore maximize requests from all apps (keeps the tiling layout sane).
hl.window_rule({
    name           = "suppress-maximize",
    match          = { class = ".*" },
    suppress_event = "maximize",
})

-- Float + centre the usual transient/utility windows.
for _, klass in ipairs({
    "pavucontrol", "org.pulseaudio.pavucontrol",
    "nm-connection-editor", "blueman-manager",
    "org.gnome.Calculator", "engrampa",
}) do
    hl.window_rule({ name = "float-" .. klass, match = { class = klass }, float = true })
end

-- Firefox / browser picture-in-picture: small floating, pinned across spaces.
hl.window_rule({
    name  = "pip-float",
    match = { title = "Picture-in-Picture" },
    float = true,
    pin   = true,
})

-- The shell's Settings app is a real toplevel (so portals/DnD work) — float and
-- centre it so it still opens like the old overlay.
hl.window_rule({
    name   = "settings-window",
    match  = { title = "^ewe settings$" },
    float  = true,
    center = true,
    size   = { 880, 620 },
})

-- Fix XWayland drag ghosts (from the upstream example).
hl.window_rule({
    name     = "fix-xwayland-drags",
    match    = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})


-- ╭───────────────────────────────────────────────────────────────╮
-- │ LAYER RULES                                                     │
-- ╰───────────────────────────────────────────────────────────────╯
-- No blur rules: decoration.blur is disabled (see above). Every Quickshell
-- surface is solid (colours from Theme.qml); the Overview/Settings scrims are
-- plain translucent dims with nothing frosted behind them.


-- ╭───────────────────────────────────────────────────────────────╮
-- │ AUTOSTART — runs once when Hyprland finishes starting           │
-- ╰───────────────────────────────────────────────────────────────╯
-- All daemons live in scripts/autostart.sh (idempotent, run_once-guarded), so
-- a `hyprctl reload` never double-spawns them. See that file to add services.
hl.on("hyprland.start", function()
    hl.exec_cmd(scripts .. "/autostart.sh")
end)


-- ╭───────────────────────────────────────────────────────────────╮
-- │ USER OVERRIDES — written by the Quickshell Settings app        │
-- ╰───────────────────────────────────────────────────────────────╯
-- generated/user.lua holds hl.config{} calls the Settings app writes (gaps,
-- border, accent, animations). Sourced LAST so it wins over the hand-written
-- defaults above; this keeps this file clean and round-trips the GUI changes
-- across reloads/relogin. Missing/empty file is a no-op.
pcall(dofile, home .. "/.config/hypr/generated/user.lua")

-- One generated file per Settings domain, each atomically rewritten by the app
-- that owns it (never touch these by hand). Sourced after user.lua so the
-- dedicated files win over any stale lines an older user.lua may still carry.
--   input.lua    — Settings → Keyboard & Mouse (input{} + per-device blocks)
--   monitors.lua — Settings → Displays (per-monitor-set profiles, desc:-matched)
pcall(dofile, home .. "/.config/hypr/generated/input.lua")
pcall(dofile, home .. "/.config/hypr/generated/monitors.lua")
