# Kbd

A Kbd shows a keyboard key or shortcut, so people learn the fastest way to do something.

## When to use
- Use it in tooltips, menus, settings (the keyboard shortcuts page) and onboarding.
- Use it only for real keys. Don't use it to style code or values; use the `mono` text style for those.

## Anatomy
1. Keycap: `surface-raised` fill, 1px `border-strong` with a 2px bottom border, `slight` radius (4px).
2. Key name: Geist Mono, 11px weight 500, in `text-secondary`.
3. Combination: keys joined by a "+" in `text-muted`, with `space-xs` (4px) between each part.

## Sizes
| Size | Text | Line height | Side padding |
| --- | --- | --- | --- |
| sm (default) | 11px mono | 16px | `space-xs` (4) |
| lg | 12px mono | 18px | `space-s` (8) |

Use sm inside tooltips, menus and lists, and lg on the shortcuts page and in onboarding.

## Key names
Write keys as people see them: Super, Ctrl, Alt, Shift, Tab, Esc, Enter, Space, and single capital letters (A, Q). Use arrows (← →) for arrow keys. Always list modifiers in the order Super, Ctrl, Alt, Shift.

## Do and don't
- Do right-align shortcuts in menus and lists.
- Don't show more than one shortcut for the same action.
- Don't use Kbd as a button; it is not interactive.

## Accessibility
- Key names use real text (not icons), so screen readers announce them.
- Text contrast is at least 4.5:1 on `surface-raised` in both themes.
- The 2px bottom edge (`border-width-2`) gives the key its depth; everything else is 1px.

## What a build provides
`keys` (a list of key names) · `size`.
