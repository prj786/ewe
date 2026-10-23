# Dock

The dock floats at the bottom of the main screen with the shell's launchers, one group per workspace showing its windows, your minimized windows and the browser's downloads.

## Placement
- Only on the main screen, centered, `window-gap` (8px) above the bottom edge. It sits above windows. It slides out of view while the Overview is open; its reserved strip stays, so windows never move.
- It reserves space only when auto-hide is off.

## Anatomy
1. Container: `surface-raised`, 1px `border-subtle`, `shadow-float`, 8px padding, 8px between items. Its radius is `primary` + 8px (16px) so it stays concentric with the 8px items inside. With transparency on, it is Glass (`glass-raised`).
2. Launchers, in order: the sheep (app launcher), `layers` (Overview), `store` (Komble), `folder` (Places), `music` (media player, only while something is playing). Glyphs are 24px `text-secondary`; the sheep uses the same color.
3. Divider: 1px `border-subtle`, 8px shorter than the items.
4. Workspace groups: one per workspace that has windows, plus the current one even when empty, in number order. With several displays: the focused display's own workspaces (separate), or one group per number holding every display's windows (shared); always numbered 1, 2, 3 …
   - Box: as tall as the items, 8px side padding, 4px between parts, `primary` radius, 1px `border-subtle`.
   - Label: the number and a colon, 12px weight 600, `text-muted`.
   - Window tiles: 36 × 32px, `secondary` radius, the app's 20px icon. "empty" in 12px `text-secondary` when there are none.
5. A second divider, shown while either of the next two is.
6. Minimized windows: one tile per window Super+Z minimized, as tall and wide as the items, oldest first and the newest at the right end (like macOS). The tile is the window's picture fitted inside the cell with `space-xs` around it, `slight` radius, a 1px `border-subtle` hairline and `shadow-float`, with the app's 16px icon over its bottom-right corner. The picture is one frame captured when the window arrives, kept as a small image; until it arrives, the app's icon. Shown only while a window is minimized.
7. Downloads: a launcher with the `download` glyph. While a download runs, the glyph steps down to 12px inside a Progress ring (the glyph size, 2px stroke, `surface-hover` track, `accent` fill from the top, clockwise; a quarter arc spins while the size is unknown). Shown only while a download runs or one finished in the last day.

## Sizes
| Size | Items | Glyphs | Tiles | App icons |
| --- | --- | --- | --- | --- |
| Small | 40px | 20px | 32 × 28px | 16px |
| Normal (default) | 48px | 24px | 36 × 32px | 20px |
| Large | 64px | 32px | 48 × 40px | 24px |

## States
| Part | State | Look |
| --- | --- | --- |
| Launcher | Hover | `surface-hover`, `text-primary` |
| Launcher | Pressed | `surface-pressed` |
| Launcher | Its panel is open | `accent-subtle`, glyph in `accent-text` |
| Workspace group | Current | `accent-subtle` fill, 1px `accent` border, label in `accent-text` |
| Workspace group | Hover | `surface-hover` |
| Window tile | Focused window | solid `accent` behind the app icon |
| Window tile | Hover | `surface-hover` |
| Minimized tile | Hover / pressed | `surface-hover` / `surface-pressed` behind it, like a launcher |
| Minimized tile | A window arrives | it grows in from 60% and fades in at `base` (Reduce motion: it just appears) |
| Downloads | One just finished | lit like an open launcher for `dim` |
| Any | Focus | 1px `focus-ring`, 1px outside the edge (tiles and launchers draw it on their edge) |

## Behavior
- Launchers toggle their panel; opening one closes the others.
- Clicking a group switches to that workspace; clicking a tile focuses that window.
- Minimized: click a tile to bring that window back to the current workspace, focused. There is no group and no panel.
- Downloads: click for the Downloads panel (`panel-sm` wide): "Downloads" with a folder button (the Downloads folder) and "Clear"; up to eight 48px rows, each with the file's icon, its name (middle-elided), a 4px progress bar while it runs, and a caption: "950 MB of 1.2 GB", "Paused · …", "2.4 MB · 29 min ago", "Cancelled", or "Failed" in `danger`. A finished row opens the file and has a folder button that shows it in the file manager; a running row brings the browser forward.
- Auto-hide: the dock slides down, leaving a 6px peek, when the current workspace has a tiled or fullscreen window. It comes back when the pointer reaches the bottom edge (a strip as wide as the dock), while any of its panels is open, and for a moment after the pointer leaves.

## Accessibility
- A toolbar. Launchers are named (“Apps”, “Overview”, “Downloads, 34%”); groups say their number and window count (“Workspace 3, 3 windows”); a minimized tile says “Minimized: ” and the window title; tiles say the app and window title.

## What a build provides
`size` · `autoHide` · `opacity` · `workspaces` (id, windows, current) · `minimized` · `downloads` (name, status, received, total, ended) · `player` · `onLaunch` · `onWorkspace` · `onWindow` · `onRestore`.
