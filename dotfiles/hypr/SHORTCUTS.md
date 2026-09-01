# Hyprland Shortcuts

**Mod = Super (Windows key).** Defined in `~/.config/hypr/hyprland.lua`.
Edit that file and reload with **Super + Ctrl + R** (Hyprland also auto-reloads
on save). Ported from the old Qtile bindings so most muscle memory carries over.

## Launching apps

| Shortcut | Action | Program |
|---|---|---|
| `Super` + `Return` | Terminal | `kitty` |
| `Super` + `D` | **Launcher** — fuzzy app / file search (press again to close) | Quickshell |
| `Super` + `E` | File manager | `nemo` |
| `Super` + `B` | Web browser | default browser (Settings → Default Apps) |
| `Super` + `C` | Calendar | Quickshell popup |
| `Super` + `,` | **Settings** | Quickshell |
| `Super` + `N` | Toggle Quick Settings | Quickshell |
| `Super` + `Shift` + `C` | **Cast to TV** — toggle screen mirroring (Miracast / Chromecast); same as the Quick Settings tile | Quickshell → `gnome-network-displays` |

> The bar + launcher are now **Quickshell** (`~/.config/quickshell/`). The search
> glyph at the top-left opens the Launcher. (A Quickshell power menu is on the list.)

## Windows

| Shortcut | Action |
|---|---|
| `Super` + `H/J/K/L` *or* arrow keys | Focus left / down / up / right |
| `Super` + `Shift` + `H/J/K/L` *or* arrows | Move window (merges into a group if one is there) |
| `Super` + `G` | Group / ungroup the focused window (tabbed stack) |
| `Super` + `Shift` + `G` | Pull the active window out of its group |
| `Super` + `[` / `]` | Previous / next tab inside a group |
| `Super` + `Alt` + `1`…`9` | Jump straight to tab 1–9 of the group |
| `Super` + `Ctrl` + `H/J/K/L` | Resize the focused window |
| `Super` + `Shift` + `N` | Reset split ratio |
| `Super` + `Q` | Close focused window |
| `Super` + `F` | Fullscreen |
| `Super` + `Shift` + `F` | Maximise (keep bar/gaps) |
| `Super` + `V` | Toggle floating |
| `Super` + `Shift` + `V` | Pseudo-tile |
| `Super` + `T` | Toggle split direction (dwindle) |
| `Super` + `Alt` + `[` / `]` | Scrolling layout: scroll the tape one column left / right |
| `Super` + `Alt` + `,` / `.` | Scrolling layout: swap column with its left / right neighbour |
| `Super` + `Alt` + `R` | Scrolling layout: cycle the column width presets |
| `Super` + `Alt` + `F` | Scrolling layout: fit every visible column on screen |
| `Super` + `Alt` + `P` | Scrolling layout: give the window its own column |
| `Super` + `Alt` + `C` | Scrolling layout: merge into / split from the next column |
| `Super` + `Tab` / `Super` + `Shift` + `Tab` | Cycle to next / previous window |

### Mouse (hold `Super`)

| Action | Result |
|---|---|
| `Super` + drag **left button** | Move window |
| `Super` + drag **right button** | Resize window |
| `Super` + **scroll** | Cycle workspaces |

## Workspaces (1–8)

| Shortcut | Action |
|---|---|
| `Super` + `1`…`8` | Switch to workspace 1–8 |
| `Super` + `Shift` + `1`…`8` | Move focused window to workspace (and follow) |
| 3-finger horizontal swipe | Switch workspaces (touchpad) |

### Scratchpad (Hyprland "special" workspace)

| Shortcut | Action |
|---|---|
| `Super` + `` ` `` / `S` / `Z` | Show or hide the Pen (the hidden workspace) |
| `Super` + `Shift` + `S` / `Z` | Stash the window in the Pen (dock shows it) |

## Session

| Shortcut | Action |
|---|---|
| `Super` + `Ctrl` + `R` | Reload Hyprland config |
| `Super` + `Ctrl` + `Q` | Quit Hyprland (log out) |
| `Super` + `Shift` + `B` | Toggle the top bar |
| `Super` + `Space` | Switch keyboard layout (when more than one is configured) |
| `Super` + `Alt` + `L` | Lock session |

## Media & hardware keys (no modifier)

| Key | Action |
|---|---|
| `XF86AudioRaiseVolume` / `LowerVolume` | Volume ±5% (`wpctl`) |
| `XF86AudioMute` / `MicMute` | Toggle output / mic mute |
| `XF86AudioPlay` / `Next` / `Prev` | Media control (`playerctl`) |
| `XF86MonBrightnessUp` / `Down` | Brightness ±5% (`brightnessctl`) |

## Screenshots (saved to `~/Pictures/Screenshots` **and** clipboard)

| Shortcut | Action |
|---|---|
| `Print` | Focused monitor |
| `Shift` + `Print` | Select a region |
| `Super` + `Print` | Focused window (instant) |

> Also in the bar: the **camera icon** — Left = region · Right = focused monitor · Middle = focused window.

---

### What changed vs Qtile

- `Super` + `Tab` now **cycles windows** (Hyprland has one global layout, so there
  is no layout to cycle). New: `Super` + `T` toggles the dwindle split, `Super` + `V`
  pseudo-tiles, `Super` + `Shift` + `F` maximises.
- The dropdown terminal/file/music scratchpads became one Hyprland "special"
  workspace (`Super` + backtick / `Super` + `S`). Populate it with `Super` + `Shift` + `S`.
