# Dock

The dock floats at the bottom of the main screen with the shell's launchers and one group per workspace showing its windows.

## Placement
- Only on the main screen, centered, `window-gap` (8px) above the bottom edge. It sits above windows. It slides out of view while the Overview is open; its reserved strip stays, so windows never move.
- It reserves space only when auto-hide is off.

## Anatomy
1. Container: `surface-raised`, 1px `border-subtle`, `shadow-float`, 8px padding, 8px between items. Its radius is `primary` + 8px (16px) so it stays concentric with the 8px items inside. With transparency on, it is Glass (`glass-raised`).
2. Launchers, in order: the sheep (app launcher), `layers` (Overview), `store` (Komble), `folder` (Places), `music` (media player, only while something is playing). Glyphs are 24px `text-secondary`; the sheep uses the same color.
3. Divider: 1px `border-subtle`, 8px shorter than the items.
4. Stashed windows (the Pen): a group with a `package` glyph and one tile per stashed window. Shown only while windows are stashed.
5. Workspace groups: one per workspace that has windows, plus the current one even when empty, in number order.
   - Box: as tall as the items, 8px side padding, 4px between parts, `primary` radius, 1px `border-subtle`.
   - Label: the number and a colon, 12px weight 600, `text-muted`.
   - Window tiles: 36 × 32px, `secondary` radius, the app's 20px icon. "empty" in 12px `text-secondary` when there are none.

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
| Pen | Open | `accent-subtle` and `accent` border; the workspace groups hide |
| Any | Focus | 1px `focus-ring`, 1px outside the edge (tiles and launchers draw it on their edge) |

## Behavior
- Launchers toggle their panel; opening one closes the others.
- Clicking a group switches to that workspace; clicking a tile focuses that window.
- Pen: click the box to show or hide the stash; click a tile to focus it; middle-click brings that window to the current workspace.
- Auto-hide: the dock slides down, leaving a 6px peek, when the current workspace has a tiled or fullscreen window. It comes back when the pointer reaches the bottom edge (a strip as wide as the dock), while any of its panels is open, and for a moment after the pointer leaves.

## Accessibility
- A toolbar. Launchers are named (“Apps”, “Overview”); groups say their number and window count (“Workspace 3, 3 windows”); tiles say the app and window title.

## What a build provides
`size` · `autoHide` · `opacity` · `workspaces` (id, windows, current) · `stash` · `player` · `onLaunch` · `onWorkspace` · `onWindow`.
