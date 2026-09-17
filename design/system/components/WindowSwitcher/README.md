# Window switcher

The window switcher shows open windows while Alt+Tab is held, so people can pick one.

## Anatomy
1. Panel: `surface-raised`, 1px `border-subtle`, `rounded` + 4px radius, `shadow-float`, 12px padding, centered on the focused monitor.
2. Thumbnails: 152px wide, a 96px live preview with the `primary` radius, and a label with the 16px app icon and the window title.
3. Selected: a 2px `accent` border around the thumbnail and its label, `surface-hover` behind it, title in `text-primary` weight 500.
4. Hints: keyboard hints below.

## Behavior
- Alt+Tab selects the next window, Alt+Shift+Tab the previous one; releasing Alt switches. Esc cancels.
- Windows are ordered by last use. More than six windows wrap to a second row.

## Accessibility
- A listbox of windows; the selected window is announced with its app and title.

## What a build provides
`windows` (app, title, preview) · `selected` · `onSelect` · `onCancel`.
