# Settings app — config backend

How the Settings app writes through to Hyprland, what files it owns, and what
it can (and honestly cannot) fix.

Two implementations follow this contract: the standalone **ewe-settings**
(Tauri, its own repo — THE settings UI when installed) and the in-shell
Quickshell panel (the fallback while the binary is absent). Both write the
same files with the same generators — byte-identical output — and the
standalone app then calls `qs ipc call settings reload`, which re-reads
user-theme.json/pinned lists **and display-profiles.json** (HyprMon must never
re-assert from a stale in-memory copy after an out-of-process commit).

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
| `~/.config/hypr/generated/user.lua` | Layout / Theme | gaps, border, corner radius, accent border, window transparency, animation overrides |
| `~/.config/hypr/generated/hypridle.conf` | Screensaver | full hypridle config: saver/lock listeners + battery idle-suspend; `autostart.sh` prefers it over the shipped default and Settings restarts hypridle on change |
| `~/.config/hypr/generated/kb-per-window.disabled` | Keyboard & Mouse | flag file: presence tells `autostart.sh` not to start the per-window-layout daemon |
| `~/.config/hypr/generated/windowrules.lua` | Window Rules *(standalone app only — no in-shell fallback pane)* | per-app `hl.window_rule{}` lines: open on workspace N, force float/tile; applied live via `hyprctl reload` (named rules, so reloads are idempotent) |
| `~/.config/quickshell/window-rules.json` | Window Rules | source of truth for the rules list (app name, window class, workspace, float/tile) |
| `~/.config/quickshell/display-profiles.json` | Displays | source of truth for the display profiles (below) |
| `~/.config/quickshell/input-devices.json` | Keyboard & Mouse | per-device pointer overrides (mirrors the `hl.device{}` lines) |
| `~/.config/quickshell/google-*` | User (Google) | OAuth client config + non-secret caches (profile, events, mail cursor/list, sync meta, restore bundle/package lists) — all gitignored; the refresh token is in the keyring only |
| `~/.config/quickshell/kdeconnect-state.json` | Mobile card | seen phone-notification ids (unread badge) + chosen device — pairing keys stay in kdeconnectd |
| `~/.config/quickshell/startup-apps.json` | Startup | user startup applications; `autostart.sh` launches the enabled entries via `jq` at login |

`hyprland.lua` sources `user.lua`, then `input.lua`, then `monitors.lua`, then
`windowrules.lua` (missing files are a no-op), so the dedicated files win over
any stale lines an older `user.lua` may still carry. All of these are
gitignored user state.

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
centres it (match: title `ewe settings`). All image/video input goes
through the shared `FileDropTarget` component (portal chooser + drop zone).

## Google account (User tab) — native OAuth

`Google.qml` is THE account service; sync and calendar are consumers:

- **Auth**: `scripts/google-auth.py` (stdlib Python) runs the OAuth 2.0
  installed-app flow — PKCE + a random-port `127.0.0.1` loopback redirect,
  browser via `xdg-open`. The **refresh token goes into the Secret Service
  keyring** (`secret-tool`, gnome-keyring); the client id/secret sit in the
  gitignored `google-oauth.json`; `google-profile.json` caches only
  name/email/avatar-URL. Access tokens live in shell memory, single-flight
  refreshed with queued waiters; `api()` injects the Bearer header and
  retries exactly once on 401. Sign-out revokes at Google and clears
  everything. Scopes: `openid email profile calendar.readonly drive.appdata`.
- **Settings sync**: `scripts/settings-bundle.py collect|apply` serializes /
  re-applies the files in the table above plus the avatar (`~/.face`,
  base64 in the bundle; apply also refreshes the AccountsService icon so the
  greeter picture survives a reinstall), `~/.ssh/config` (hosts only —
  **never keys**), the `ssh-browse/` tunnel scripts, VPN connection
  **names/types only** (the profiles are root-owned and can embed secrets —
  those never enter the bundle; restore lists them for manual re-import),
  and `pacman -Qqe`/`-Qqm` package lists; Google.qml stores the bundle as
  `hypr-shell-settings.json` in Drive's hidden `appDataFolder`. Restore is
  explicit (confirmation card, last-write-wins by `updatedAt`); after apply
  the shell re-reads its JSON state and reloads Hyprland/wallpaper/hypridle
  live. Auto-sync (off by default) pushes ~20 s after Settings closes when
  the content hash changed. Packages are never auto-installed: the
  "Packages from backup…" card diffs the bundle against `pacman -Qq` and
  installs the checked selection visibly in a kitty terminal
  (`sudo pacman -S --needed`, AUR via `paru`).
- **Calendar**: 14-day window over every selected calendar
  (`calendarList` → `events.list`, `singleEvents`, per-calendar colours),
  polled every 15 min + on sign-in + when Quick Settings opens stale;
  cached to `google-events.json` so offline shows the last sync. Boot-race
  safe: the signed-in probe retries with backoff (gnome-keyring may come up
  after the shell), a failed fetch retries every minute (Wi-Fi may connect
  after the shell), and Quick Settings renders the cached events without
  waiting for the probe — sign-out clears the cache so nothing stale leaks. Reminders
  honour per-event/calendar popup overrides (else 10 min lead), fire through
  the shell's own notification server via `notify-send`, and are de-duped
  across restarts in `google-notified.json`.
- **Gmail** (read-only): `labels.get(INBOX)` feeds the unread badge (bar
  envelope + Mail tile); `users.history.list` with a persisted `historyId`
  cursor detects genuinely new arrivals (404 → silent re-baseline; first sync
  marks existing unread as seen so sign-in never floods notifications); rows
  are metadata-only fetches (From/Subject/Date + snippet, never bodies) that
  deep-link to Gmail in the browser. Poll: 2 min + on QS open when stale.
  State in `google-mail.json`. Tokens minted before the `gmail.readonly`
  scope get `mailState=scope` → a "Reconnect Google" pill re-runs consent.
- **EDS** (`evolution-data-server`) remains an optional secondary source:
  `scripts/eds-query.py` still feeds the contacts list, and the Quick
  Settings calendar falls back to `Accounts.events` when no Google account
  is signed in. A native QtWebEngine OAuth webview (no browser round-trip)
  stays a later phase.

Everything degrades cleanly: not configured → actionable message (no
spinners), signed out/offline → cached or empty states, keyring missing →
explicit install hint.

## Mobile (KDE Connect) — the D-Bus bridge

Quickshell has no generic QML D-Bus client (its D-Bus features are compiled
C++ types), so `scripts/kdeconnect-bridge.py` (dbus-python + GLib) owns every
KDE Connect D-Bus call and speaks newline-delimited JSON over stdio to the
`KdeConnect.qml` singleton — events out (devices, pair state, battery,
notifications, messages), commands in (pair/accept/cancel/unpair, dismiss,
reply, request/send SMS, ring, share). Signals are subscribed globally with
the device id parsed from the object path, so device add/remove needs no
re-subscription. The bridge D-Bus-activates `kdeconnectd` (or spawns the
binary) and survives daemon restarts via a name-owner watch; the QML side
restarts the bridge if it dies. The Quick Settings Mobile card, the bar
phone indicator and the SMS panel are pure consumers of the singleton —
nothing else in the shell knows a D-Bus path. Interface signatures pinned
against kdeconnect 26.04 (conversations arrive as single message events;
the conversation list is "latest message per thread"; sends are echoed
optimistically and reconciled on the real signal).

## Screensaver (hypridle-driven)

Quickshell 0.3.0 has no `IdleMonitor`, so idle timing stays with **hypridle**:
the Screensaver pane writes `generated/hypridle.conf` (saver listener →
`qs ipc call saver show`/`hide`, optional straight-to-lock, delayed auto-lock,
battery idle-suspend always kept) and restarts hypridle. `Screensaver.qml`
renders a per-output overlay (clock/blank, pluggable), dismissed by any
key/click/motion — hypridle's `on-resume` is the backstop. Playing media or a
fullscreen focused window hold a wayland `IdleInhibitor` (same mechanism as
the bar's Insomnia toggle), which keeps saver, lock *and* suspend away.

## Runtime dependencies added in 0.3

Installed by `packages/common.list`: `awww` (swww), `mpvpaper`, `libsecret`
(secret-tool; gnome-keyring was already shipped), `kdeconnect` +
`python-dbus` + `python-gobject` (the Mobile card's daemon and bridge).
Optional (contacts/EDS fallback): `evolution-data-server`.

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
