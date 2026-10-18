# Hyprland Shortcuts

**Mod = Super (Windows key).** Defined in `~/.config/hypr/hyprland.lua`; a
plugin's own keys come from its manifest (`generated/plugin-keybinds.lua`) and
exist only while that plugin is installed and on. Settings → Shortcuts shows
this file: a row or heading that names a plugin (`ewe.<id>`) appears only
while that plugin is on. Your own launch keys live in ewe.conf
(`ewe-conf set desktop.keybinds '[{"combo": "SUPER + T", "exec": "kitty"}]'`).

<!-- Settings parses this file: `## ` headings, then table rows whose first
     cell is the keys ("Super + D") and whose second is what it does. Keep
     every table's header cell "Shortcut", or the header shows as a row.
     Checked against hyprland.lua and a live `hyprctl binds -j`, 2026-10-14. -->

## Launching apps

| Shortcut | Action | Program |
|---|---|---|
| `Super` | **Overview** (tap it alone): every window and workspace, type to search | Quickshell |
| `Super` + `D` | **Launcher**: fuzzy app and file search (press again to close) | Quickshell |
| `Super` + `Return` | Terminal | `kitty` |
| `Super` + `E` | File manager | `nemo` |
| `Super` + `B` | Web browser | default browser (Settings → Default apps), else ewe browser |
| `Super` + `C` | Calendar: GNOME Calendar when installed, else this month as a notification | `calendar.sh` |
| `Super` + `,` | **Settings** | `ewe-settings` |
| `Super` + `N` | Quick settings | Quickshell |
| `Super` + `Shift` + `W` | Arrange desktop widgets (drag, pin, lock, hide; Esc ends it) | Quickshell |

> The workspace number at the top-left of the bar opens the Overview, and the
> pill with the clock at the right opens Quick settings.

## Windows

| Shortcut | Action |
|---|---|
| `Super` + `H/J/K/L` / arrows | Focus left / down / up / right |
| `Super` + `Shift` + `H/J/K/L` / arrows | Move window (merges into a group if one is there) |
| `Super` + `G` | Group / ungroup the focused window (tabbed stack) |
| `Super` + `Shift` + `G` | Pull the active window out of its group |
| `Super` + `[` / `]` | Previous / next tab inside a group |
| `Super` + `Alt` + `1`…`9` | Jump straight to tab 1–9 of the group |
| `Super` + `Ctrl` + `H/J/K/L` | Resize the focused window (also how to even out a split) |
| `Super` + `Q` | Close focused window |
| `Super` + `F` | Fullscreen |
| `Super` + `Shift` + `F` | Maximise (keep bar/gaps) |
| `Super` + `V` | Toggle floating |
| `Super` + `Shift` + `V` | Pseudo-tile |
| `Super` + `T` | Toggle split direction (dwindle) |
| `Super` + `Tab` / `Super` + `Shift` + `Tab` | Cycle to next / previous window |
| `Super` + left-drag | Move window |
| `Super` + right-drag | Resize window |

## Scrolling layout (Settings → Layout → Tiling style: Scrolling)

| Shortcut | Action |
|---|---|
| `Super` + `Alt` + `[` / `]` | Scroll the strip one column left / right |
| `Super` + `Alt` + `,` / `.` | Swap the column with its left / right neighbour |
| `Super` + `Alt` + `R` | Cycle the column width presets |
| `Super` + `Alt` + `F` | Fit every visible column on screen |
| `Super` + `Alt` + `P` | Give the window its own column |
| `Super` + `Alt` + `C` | Merge into / split from the next column |

## Workspaces (1–8) and the Pen

| Shortcut | Action |
|---|---|
| `Super` + `1`…`8` | Switch to workspace 1–8 |
| `Super` + `Shift` + `1`…`8` | Move focused window to workspace (and follow) |
| `Super` + scroll | Cycle workspaces (on the scrolling layout: scroll the strip) |
| `Super` + `S` / `Z` | Enter / leave the Pen, the hidden workspace for stashed windows (Super + the key above Tab too) |
| `Super` + `Shift` + `S` / `Z` | Stash ⇄ unstash: to the Pen from a desktop, back home from the Pen |

## Touchpad

| Shortcut | Action |
|---|---|
| 3-finger swipe left / right | Switch workspaces |
| 3-finger swipe up | Overview |
| 3-finger swipe down | A new empty desktop (never piles up empty ones) |
| 4-finger swipe left / right | In ewe browser: its next / previous workspace (nothing elsewhere) |
| 2-finger swipe left / right | In ewe browser: back / forward (the browser's own gesture) |

## Session

| Shortcut | Action |
|---|---|
| `Super` + `Alt` + `L` | Lock session |
| `Super` + `Shift` + `B` | Show / hide the top bar |
| `Super` + `Space` | Switch keyboard layout (when more than one is configured) |
| `Super` + `Shift` + `R` | Display recovery: every screen back on, the saved arrangement reapplied (works on a black screen) |
| `Super` + `Ctrl` + `R` | Reload Hyprland config |
| `Super` + `Ctrl` + `Q` | Quit Hyprland (log out) |

## Media & hardware keys (no modifier)

| Shortcut | Action |
|---|---|
| `XF86AudioRaiseVolume` / `LowerVolume` | Volume ±5% (also on the lock screen) |
| `XF86AudioMute` / `MicMute` | Toggle output / mic mute |
| `XF86AudioPlay` / `Next` / `Prev` | Media control (`playerctl`) |
| `XF86MonBrightnessUp` / `Down` | Brightness ±5%, with the on-screen indicator |
| `XF86KbdBrightnessUp` / `Down` | Keyboard backlight up / down |
| `XF86PowerOff` (short press) | Asks "Shut down this computer?" (holding it still powers off; nothing while locked) |

## Plugin keys

| Shortcut | Action |
|---|---|
| `Print` | Screenshot of the focused monitor (the `ewe.screenshot` plugin; saved to `~/Pictures/Screenshots` and the clipboard) |
| `Shift` + `Print` | Screenshot of a region (`ewe.screenshot`) |
| `Super` + `Print` | Screenshot of the focused window (`ewe.screenshot`) |
| `Super` + `P` | **Passwords**: fill a login from your manager (the `ewe.passwords` plugin) |
| `Super` + `Shift` + `C` | **Cast to TV**: the TV list, or hang up (the `ewe.cast` plugin) |
| `Super` + `A` | **Shaun** (the companion): open or close the notch (the `ewe.companion` plugin) |

> The screenshot plugin's camera in the bar: Left = region · Right = focused
> monitor · Middle = focused window. Clipboard history (`ewe.clipboard`) has no
> key: it is the scissors in the bar.

---

### What changed vs Qtile

- `Super` + `Tab` now **cycles windows** (Hyprland has one global layout, so there
  is no layout to cycle). New: `Super` + `T` toggles the dwindle split, `Super` + `V`
  floats, `Super` + `Shift` + `V` pseudo-tiles, `Super` + `Shift` + `F` maximises.
- The dropdown terminal/file/music scratchpads became the Pen, one Hyprland
  "special" workspace (`Super` + backtick / `Super` + `S`). Fill it with
  `Super` + `Shift` + `S`.
- The old `Super` + `Shift` + `N` "reset split" is gone: Hyprland's Lua API has
  no `splitratio`. Even a split out with `Super` + `Ctrl` + `H/L`.
