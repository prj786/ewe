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
| `~/.config/hypr/generated/wallpapers.conf` | Wallpaper | `mode=…`, `mute=…`, optional `backend=…`, `*=<default file>`, `<output>=<file>` lines read by `scripts/wallpaper.sh` (files may be images, GIFs or videos) |
| `~/.config/hypr/generated/user.lua` | Layout / Theme | gaps, border, corner radius, accent border, animation overrides |
| `~/.config/hypr/generated/kb-per-window.disabled` | Keyboard & Mouse | flag file: presence tells `autostart.sh` not to start the per-window-layout daemon |
| `~/.config/quickshell/display-profiles.json` | Displays | source of truth for the display profiles (below) |
| `~/.config/quickshell/input-devices.json` | Keyboard & Mouse | per-device pointer overrides (mirrors the `hl.device{}` lines) |

`hyprland.lua` sources `user.lua`, then `input.lua`, then `monitors.lua`
(missing files are a no-op), so the dedicated files win over any stale lines an
older `user.lua` may still carry. All of these are gitignored user state.

## Wallpaper backends (per file type)

`wallpaper.sh` picks the backend automatically from the file:

| Content | Backend | Notes |
|---|---|---|
| video (mp4/webm/mkv/mov/avi/m4v) | **mpvpaper** | one instance per output, looped, muted by default (`mute=` / UI toggle) |
| image / animated GIF | **swww** (Arch packages it as **`awww`**) | GIFs animate; transitions |
| image, no swww installed | **swaybg** | static only — GIFs show a warning |

Each connected output resolves its own file (per-output line or the `*`
default), so a video on one monitor and an image on the other coexist.
`backend=swaybg` in wallpapers.conf force-picks the static image backend.
The script prints `error:`/`note:` lines and exits non-zero on failure;
Settings surfaces them in the inline banner. Restore-on-login (autostart)
and hotplug re-apply (HyprMon) call `wallpaper.sh --reapply`.
(hyprpaper support was dropped in 0.3 in favour of this mapping.)

## Settings window

The Settings app is a real **xdg-toplevel** (`FloatingWindow`), not a layer
surface — required for the XDG portal file chooser to have a valid parent and
for file drag-and-drop to route to it. A `hyprland.lua` windowrule floats and
centres it (match: title `hypr-shell settings`). All image/video input goes
through the shared `FileDropTarget` component (portal chooser + drop zone).

## Online Accounts (User tab)

GNOME's daemons do the heavy lifting; the shell only talks D-Bus:

- **GOA** (`gnome-online-accounts`, `org.gnome.OnlineAccounts`) owns accounts
  and OAuth tokens. The `Accounts` singleton lists them via the ObjectManager
  (`busctl -j`), flips the per-service `…Disabled` properties, and removes
  accounts. **Adding** an account launches `gnome-control-center
  online-accounts` (with `XDG_CURRENT_DESKTOP=GNOME`) — reusing GNOME's
  working OAuth webflow. A native QtWebEngine flow driving `AddAccount`
  directly is a planned later phase, deliberately not part of 0.3.
- **EDS** (`evolution-data-server`) is the data layer GOA accounts register
  into. `scripts/eds-query.py` (python-gobject) dumps upcoming events and
  contacts as JSON; the Quick Settings calendar and the User tab's contacts
  list bind to `Accounts.events` / `Accounts.contacts`.

All of it is **optional**: with the daemons missing, the User tab shows what
to install and everything else keeps working.

## Runtime dependencies added in 0.3

Installed by `packages/common.list`: `awww` (swww), `mpvpaper`.
Optional (Online Accounts): `gnome-online-accounts`,
`evolution-data-server`, `python-gobject` (usually present), and
`gnome-control-center` for the add-account flow.

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
