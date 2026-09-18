# List row

A list row shows one item in a list: a network, a device, a file or a setting with its control.

## When to use
- Use it for lists of similar items and for settings pages, grouped inside a list well.
- Use a Table when people need to compare several values across items.

## Anatomy
1. List well: `surface-raised`, 1px `border-subtle`, `rounded` radius, 4px padding. Rows are separated by a 1px `border-subtle` divider inset 8px, or by nothing in short lists.
2. Row: at least 32px tall (`control-lg`), 4px × 8px padding, `secondary` radius (6px) so it nests inside the well.
3. Leading (optional): a 16px icon in `text-secondary`, a 32px icon tile, an avatar or an app icon.
4. Title (13px, `text-primary`) and description (`caption`, `text-muted`), both truncated with an ellipsis.
5. Trailing: a value, a Switch, a Badge, a chevron, a check or a small button, 8px apart.

## Sizes
| Size | Minimum height | Use |
| --- | --- | --- |
| Dense | 28px (`control-md`) | Files, menus inside panels |
| Default | 32px (`control-lg`) | Settings, networks, devices |
| Tall | 48px (`control-2xl`) | Rows with app icons, launcher results |

## States
- **Hover** (clickable rows only): `surface-hover`. **Pressed:** `surface-pressed`.
- **Selected:** `accent-subtle`, leading icon in `accent-text`. The active item (the connected network) also uses weight 500.
- **Focus:** a 1px `focus-ring` on the row's edge.
- **Disabled:** everything in `text-disabled`, with the reason in the description.

## Do and don't
- Do put the setting's current value on the right, so people see it without opening anything.
- Do use a chevron only when the row opens another page.
- Don't put two switches in one row.

## Accessibility
- A list of rows is a list; clickable rows are buttons or links named by their title. Arrow keys move between rows in pickers.

## What a build provides
`title` · `description` · `leading` (icon, tile, avatar, app icon) · `trailing` · `density` · `selected` · `active` · `disabled` · `onClick`.
