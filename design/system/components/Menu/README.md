# Menu

A menu is a floating list of actions or options. It is the content of dropdowns, context menus, the user menu and Select.

## When to use
- Use it for actions on an item (right-click menus), for overflow actions (an `ellipsis` button) and as the list of a Select.
- Keep it short: up to about ten items. Group related items and separate groups with a divider.

## Anatomy
1. Container: `surface-overlay`, 1px `border-subtle`, `rounded` radius (10px), `space-xs` (4px) padding, `shadow-float`. At least 176px wide, at most 320px.
2. Item: 28px tall (`control-md`), `space-s` (8px) side padding, `secondary` radius (6px, so the corners nest evenly inside the 10px container with 4px padding).
3. Leading icon (optional): 16px in `text-secondary`, `space-s` before the label. If some items have icons, the others keep the space empty so labels line up.
4. Label: 13px in `text-primary`, truncated with an ellipsis.
5. Trailing content (optional): a shortcut (Kbd), a `chevron-right` for a submenu, a `check` in `accent-text` for the selected option, or a short note in `caption` `text-muted`.
6. Group label: the `overline` style in `text-muted`.
7. Divider: 1px `border-subtle` with `space-xs` above and below.

## Item states
| State | Look |
| --- | --- |
| Default | transparent |
| Hover | `surface-hover` fill; the icon turns `text-primary` |
| Focus (keyboard) | 1px `focus-ring` on the item's edge |
| Selected | `check` icon and weight 500 |
| Danger | label and icon in `danger`; hover fill `danger-subtle` |
| Disabled | `text-disabled`, no hover |

## Behavior
- Menus open next to their trigger, `space-xs` away, and flip to stay on screen.
- Arrow keys move between items, Enter runs the action, Esc closes. Submenus open on hover after a short pause, or with the Right arrow key.
- Choosing an item closes the whole menu.

## Do and don't
- Do put destructive items last, after a divider.
- Do use verbs for actions ("Copy path") and nouns for options ("Name").
- Don't nest submenus more than one level.
- Don't put form controls other than checks inside a menu.

## Accessibility
- The container is a menu; items are menu items, or menu item radios and checkboxes when they show a check.
- Disabled items stay focusable so their reason can be read.

## What a build provides
`items` (label, icon, shortcut, submenu, checked, danger, disabled, note) · `groups` · `onSelect` · `anchor` · `placement`.
