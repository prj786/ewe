# Card

A card groups related content and actions into one contained block, such as a storage summary, a setting with its switch or an update prompt.

## When to use
- Use it to separate one topic from the rest of a page, or to present items people can pick from (wallpapers, displays, schemes).
- Use a List row instead for long lists of similar items; a card per row is too heavy.
- Don't nest cards inside cards.

## Anatomy
1. Container: `surface-raised`, 1px `border-subtle`, `rounded` radius (10px), `space-md` (16px) padding and 12px between parts.
2. Icon (optional): a 32px tile (`control-lg`) with the `primary` radius, `surface-hover` fill, or `accent-subtle` with `accent-text` for the card's main subject.
3. Title (15px, weight 600), description (13px, `text-secondary`) and meta line (`caption`, `text-muted`).
4. Trailing control (optional): a Switch or an Icon button, aligned to the top.
5. Footer (optional): buttons aligned right.
6. Media (optional): an image across the top, 144px tall, with the top corners following the card.

## Variants
| Variant | Difference |
| --- | --- |
| Static (default) | Not clickable |
| Interactive | The whole card is one click target |
| Compact | 12px padding and 8px gaps, for grids |

## States
- **Hover:** `surface-hover`. **Pressed:** `surface-pressed`.
- **Selected:** `accent-subtle` fill with an `accent-text` border.
- **Focus:** 1px `focus-ring`, 1px outside the edge.
- **Disabled:** text in `text-disabled`; no hover.

## Do and don't
- Do keep one primary action per card at most.
- Do use the same card size throughout a grid.
- Don't use cards only for decoration, and don't add a colored stripe on one side.

## Accessibility
- An interactive card is one control, named by its title. Controls inside it (a switch) stay separately focusable only when the card itself isn't interactive.

## What a build provides
`title` · `description` · `meta` · `icon` · `accentIcon` · `media` · `trailing` · `actions` · `interactive` · `selected` · `compact` · `disabled` · `onClick`.
