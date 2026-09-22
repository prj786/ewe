# Overview

The Overview shows every window on the screen, a search for apps, windows and files, and a pager to move between workspaces.

## Opening
- Tap Super, swipe up with three fingers, click the workspace chip in the bar, or the dock's `layers` button.
- One per screen; search appears on the focused screen only. It takes the whole screen: the bar slides up and the dock slides down out of view while it is open.

## Anatomy
1. Backdrop: the wallpaper, blurred (`blur-glass`) and darkened, full screen, edge to edge. Clicking it closes the Overview.
2. Search: `panel-lg` wide, 48px tall, Glass (`glass-raised`, `glass-border`), `rounded` radius, `shadow-float`, 64px from the top. A 16px `search` glyph, 15px text, a 2px `accent` caret. Placeholder: "Search apps, windows and files".
3. Results (while typing): the same glass box 8px below the search, with 40px result rows: up to 5 apps ("Application"), matching windows ("Jump to", with "Open window on workspace N"), up to 5 files (tagged with their folder).
4. Window cards: live thumbnails packed in 1 to 4 rows with 16px row and 24px column gaps. Each card has the `rounded` radius, a 1px `glass-border` and `shadow-float`, plus:
   - a title chip at the bottom (Glass, 12px, weight 600 when selected);
   - the app badge at the top right (20px app icon, and a `layers` glyph with the count when windows are grouped);
   - a close button at the top left, shown on hover.
5. Workspace pager: centered at the bottom, 64px above the bottom edge. Thumbnails are 56 × 36px with the `primary` radius, showing one block per window; the last one is an empty workspace with a `plus`.

## States
| Part | State | Look |
| --- | --- | --- |
| Search | Focused | border `focus-ring` |
| Card | Selected (keyboard or hover) | 2px `accent` outline, title in `text-primary` |
| Card | Dragging | half size, slightly transparent; drop on a pager thumbnail to move the window there |
| Card close | Hover | `danger` fill, `on-status` glyph |
| Cards | While searching | dimmed to 35% and not clickable |
| Pager | Current | `accent-subtle`, 1px `accent`, blocks in `accent` |
| Pager | Hover | `glass-pressed` |
| Pager | Drop target | 2px `accent` border and the workspace number |
| Any | Focus | `focus-width` `focus-ring` |

## Empty states
- No windows: "No open windows" in 22px `text-secondary`, centered.
- No results: an Empty state inside the results box: "Nothing matches “…”" with "Try an app name, a window title or a file name."

## Behavior
- Typing starts a search immediately; files are searched after a short pause (about 200ms).
- Arrow keys move the selection (cards without a query, results with one); Enter opens or focuses it; Esc closes.
- Opening an app, a window or a file closes the Overview. It opens wallpaper first: the bar and dock slide away and the backdrop fades in (`durFast`), then the cards zoom in and fade (`durSlow`). Closing is the reverse — the cards go, then the backdrop, then the bar and dock come back. Reduce motion: everything cross-fades at `fast`, nothing slides.

## Accessibility
- The search field is labelled; results are a list box; each card is a button named by app and title (“Zen, Ewe design system, workspace 1”).

## Where it lives
`dotfiles/quickshell/Overview.qml` (IPC `overview`: toggle, show, hide, find).

## What a build provides
`windows` · `workspaces` · `query` · `results` · `onActivate` · `onMoveWindow` · `onClose`.
