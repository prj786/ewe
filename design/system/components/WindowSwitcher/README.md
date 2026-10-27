# Window switcher

The window switcher shows the open windows while Alt+Tab is held, so people can pick one. It is the classic switcher: app icons, most recently used first.

## Anatomy
1. Panel: `surface-raised`, 1px `border-subtle`, `rounded` + 4px radius, `shadow-float`, 12px padding, centered on the focused display.
2. Icons: one 48px app icon (`icon-3xl`) per window in an 80px cell (`space-md` around the icon), 8px apart, up to eight a row; more wrap to further rows. A window on another workspace carries its number as a neutral Badge (with a ring) at the cell's top right.
3. Selected: a 2px `accent` ring with the `primary` radius and `surface-hover` behind the cell; a pointed-at cell takes `surface-hover` too.
4. Caption: under the icons, the selected window's title (`body-strong`, `text-primary`, elided in the middle) and its app and place ("kitty · Workspace 3", "Minimized") in `caption`, `text-muted`.
5. Hints: one `caption` line in `text-muted`: the scope ("This workspace", "This display", "Everywhere"), then "Tab next · Shift+Tab previous · Esc cancel".

## Behavior
- Alt+Tab selects the next window, Alt+Shift+Tab the previous one; the arrow keys move too, the pointer selects what it is over. Releasing Alt (or Enter, Space, a click on a cell) switches; Esc, or a click beside the panel, cancels. The first press lands on the previous window, so a tap swaps the two most recent.
- Windows are ordered by last use. Which windows: this workspace (the default), every workspace of this display, or everywhere — the plugin's `scope` setting. A minimized window is listed and comes back onto the workspace in view when picked; scratchpads are not listed.
- The panel fades in and out in `dur-fast` with a 0.96 → 1 scale (no scale under Reduce motion). A window that closes while the switcher is open leaves the row.
- No process is started per press: the keys are global shortcuts, and the Alt release reaches the switcher both as a transparent release bind and as the panel's own key event.

## Accessibility
- A list of windows; each item is named by app, title and place ("kitty, ~/src, Workspace 3"); the selected item is announced as selected.

## Where it lives
The `ewe.switcher` plugin (`plugins/ewe.switcher/Panel.qml`; IPC `ewe.switcher`: next, prev, commit, cancel, toggle, isOpen; setting `scope`). New in 0.36.

## What a build provides
`windows` (app, icon, title, workspace) · `selected` · `scope` · `onSelect` · `onCancel`.
