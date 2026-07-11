# Settings app — config backend

How the Quickshell Settings app writes through to Hyprland, what files it owns,
and what it can (and honestly cannot) fix.

## Two-layer apply model

Every control follows the same contract:

1. **Live** — the change is applied immediately via `hyprctl eval 'hl.…'`
   (this DE's Hyprland is Lua-configured; plain `hyprctl keyword` is rejected).
   Any non-`ok` reply is shown in the inline error banner — no silent failures.
2. **Persist** — the same value is rewritten into a generated file that
   `hyprland.lua` sources, so it survives reboot and `hyprctl reload`. Writes
   are atomic (temp file + rename) and idempotent (stable ordering, no churn).

For display changes that can black out a screen (mode, scale, rotation,
mirror, enable/disable) a **confirm-or-revert** dialog runs after the live
apply: unless "Keep" is clicked within 10 seconds, the previous known-good
configuration is restored automatically.

## Files the app owns (never edit by hand — they are rewritten wholesale)

| File | Written by | Contents |
|---|---|---|
| `~/.config/hypr/generated/monitors.lua` | Displays | per-monitor-set profiles, `desc:`-matched `hl.monitor{}` rules + boot-time profile matching |
| `~/.config/hypr/generated/input.lua` | Keyboard & Mouse | the full `input { … }` block + per-device `hl.device{}` overrides |
| `~/.config/hypr/generated/wallpapers.conf` | Wallpaper | `mode=…`, `*=<default image>`, `<output>=<image>` lines read by `scripts/wallpaper.sh` |
| `~/.config/hypr/generated/user.lua` | Layout / Theme | gaps, border, corner radius, accent border, animation overrides |
| `~/.config/hypr/generated/kb-per-window.disabled` | Keyboard & Mouse | flag file: presence tells `autostart.sh` not to start the per-window-layout daemon |
| `~/.config/quickshell/display-profiles.json` | Displays | source of truth for the display profiles (below) |
| `~/.config/quickshell/input-devices.json` | Keyboard & Mouse | per-device pointer overrides (mirrors the `hl.device{}` lines) |

`hyprland.lua` sources `user.lua`, then `input.lua`, then `monitors.lua`
(missing files are a no-op), so the dedicated files win over any stale lines an
older `user.lua` may still carry. All of these are gitignored user state.

## Display profiles

- One profile per **unique set of connected outputs**, keyed by the sorted
  monitor **descriptions** (e.g. `Samsung Display Corp. 0x419D || Samsung
  Electric Company LS27D60xU HNBXC00938`), falling back to the connector name
  when a description is missing. Matching by description means the config
  survives connector renames (`DP-1` → `DP-3`) across reboots and docks.
- A profile stores a complete, explicit line per monitor — resolution, refresh,
  position, scale, plus transform/VRR/bit-depth/mirror/disabled where set.
  `preferred`/`auto` are never used for a configured monitor.
- `monitors.lua` first asserts the **last-committed** profile unconditionally
  (at boot the monitor list may not be populated yet; `desc:` rules only bind
  to outputs that are actually present), then — when `hl.get_monitors()` shows
  a different connected set with its own profile — that profile's rules are
  emitted after and win.
- The `HyprMon` singleton (Quickshell) re-asserts the matching profile at shell
  startup, on `monitoradded`/`monitorremoved`/`configreloaded` events
  (debounced), and on UPower AC↔battery transitions. Wallpapers are re-applied
  on hotplug too. "Reset displays" on the Displays page forces a re-apply plus
  `dpms on` — the escape hatch when a screen goes black.
- "Primary" is a shell-level marker (Wayland has no primary display); it
  anchors auto-arrange at 0,0 and is stored in the profile.

## The honest caveat: charger plug/unplug blanking the built-in panel

On Lunar Lake (`xe` driver) the panel can blank on AC↔battery transitions —
the driver re-probes the panel and its self-refresh (PSR) path is flaky
kernel-side. The applet **mitigates** this: on every power transition it forces
`dpms on` and re-asserts the saved profile a couple of seconds later, which
recovers the common case. It cannot fix the driver: if the panel still stays
black, use "Reset displays" (or re-plug), and consider booting with
`xe.enable_psr=0`. That part is a kernel issue, not a shell issue.
