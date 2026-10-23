# Overview

The Overview spreads out every window on the workspace, with your workspaces along the top. It works like macOS Mission Control: the windows fly from where they are into the spread, and back again when it closes.

## Opening
- Tap Super, swipe up with three fingers, click the workspace chip in the bar, or the dock's `layers` button.
- One per screen; each shows that screen's workspace. The screen that was focused when it opened takes the keyboard. It takes the whole screen: the bar slides up and the dock slides down out of view while it is open.

## Anatomy
1. Backdrop: the wallpaper, full screen, edge to edge, under half the `scrim` once open. No blur. Clicking it closes the Overview.
2. Window cards: one captured frame of each window, `rounded` radius, `shadow-float`. Every window keeps its proportions and its size against the others (one scale for the workspace, never larger than the window), arranged in 1 to 4 rows ordered by where the windows sit; 32px between cards, 44px between rows. A close button (24px, `fully-rounded`, Glass) shows at the top left on hover.
3. Title: under the pointed-at or selected card, a Glass pill (`fully-rounded`, 28px) with the app icon and the window title.
4. Workspace strip: at the top, one label per workspace on this screen ("Workspace 1"; Glass pill, 28px, `fully-rounded`). Every display numbers its own workspaces from 1; with shared workspaces every screen lists every number in use on any display. Pointing at it, or dragging a window up to it, slides it down into thumbnails (a ninth of the screen tall; the wallpaper with the workspace's windows drawn as shapes with their app icons) over a `glass-base` band, and the spread shrinks down to make room. There is no button to add a workspace.

## States
| Part | State | Look |
| --- | --- | --- |
| Card | Pointed at or selected | 2px `accent` ring, the title pill under it |
| Card | Dragging | half size, at `opacity-glass`; drop it on a workspace to move the window there |
| Card close | Hover | `danger` fill, `on-status` glyph |
| Label | Current workspace | `accent-subtle`, 1px `accent`, `accent-text` |
| Thumbnail | Current workspace | 2px `accent` frame |
| Thumbnail | Hover or drop target | `glass-hover` over it; a drop target takes the 2px `accent` frame |

## Behavior
- Opening: the shell captures one frame of each window first (a frame or two, never longer than `durFast`), then every card starts exactly over its window, so the first frame looks like the desktop, and flies to its place in `durSlow` with the base easing. Under each window's real place a patch of wallpaper hides the live window; the backdrop, the dim and the strip come in with the flight, and the bar and dock leave on the same frame.
- Closing flies every card back onto its window in `durBase`; the bar and dock come back meanwhile, and the Overview unmaps under the cards. After switching workspace it cross-fades out instead, since the cards have nowhere to fly to.
- Click a card to focus its window; click a workspace to go there. Arrow keys and Tab move the selection; Enter focuses it; Esc closes.
- Reduce motion: nothing flies; the whole Overview cross-fades at `durFast`.
- There is no search: the app launcher (Super+D) searches apps and files. The `overview find` command opens the launcher with its query.
- Performance: one animation drives everything; nothing is captured continuously or while the Overview is closed; no blur; no process is started on open.

## Accessibility
- Each card is a button named by app, title and workspace ("kitty, ~/src, workspace 1"); each label and thumbnail is a button named by its workspace.

## Where it lives
`dotfiles/quickshell/Overview.qml` (IPC `overview`: toggle, show, hide, find).

## What a build provides
`windows` (with their real geometry) · `workspaces` · `onActivate` · `onMoveWindow` · `onWorkspace` · `onClose`.
