# Tag

A tag is a pill-shaped label that people can select, filter by or remove.

## When to use
- Use it in filter rows (package categories), for chosen items in a field (selected packages, keywords) and for removable values.
- Use a Badge instead for a status that people cannot act on.
- Use a Segmented control instead when exactly one of a few options must be chosen.

## Anatomy
1. Container: `fully-rounded` pill, 1px `border-strong`.
2. Leading icon (optional): Lucide.
3. Label: sentence case, 12px weight 500 (sm) or 13px weight 500 (md).
4. Remove button (optional): an `x` icon in an 18px circle; it gets a `surface-pressed` fill on hover.

## Sizes
| Size | Height | Side padding | Text | Icon |
| --- | --- | --- | --- | --- |
| sm (default) | `control-sm` (24) | `space-s` (8) | 12px / 500 | `icon-sm` (14) |
| md | `control-md` (28) | 12 | 13px / 500 | `icon-md` (16) |

A removable tag uses `space-xxs` padding on the right so the remove button sits evenly in the pill.

## States
- **Default:** transparent fill, `text-secondary` label.
- **Hover:** `surface-hover` fill, `text-primary` label.
- **Selected:** `accent-subtle` fill, `accent-text` border and label.
- **Focus:** 1px `focus-ring`, 1px outside the control.
- **Disabled:** `border-subtle` outline, `text-disabled` label.

## Do and don't
- Do space tags `space-s` (8px) apart and wrap them onto new lines instead of scrolling.
- Do put "All" first in a filter row, selected by default.
- Don't use more than one icon in a tag.
- Don't truncate tag labels; shorten the words instead.

## Accessibility
- Selectable tags report their selected state. A filter row behaves as a group of toggle buttons.
- The remove button has its own accessible name ("Remove linux-zen"), and Backspace or Delete removes a focused tag.

## What a build provides
`label` · `icon` · `size` · `selected` · `removable` with `onRemove` · `disabled` · `onClick`.
