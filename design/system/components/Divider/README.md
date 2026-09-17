# Divider

A divider is a 1px line that separates groups of content inside a panel, a menu or the bar.

## When to use
- Use it between groups of related items, not between every item.
- Prefer spacing (`space-md` and up) to separate sections when there is room; add a divider only when spacing alone is not clear enough.
- Use a labeled divider to title a group inside a list, such as "Earlier" in notifications.

## Variants
| Variant | Line | Notes |
| --- | --- | --- |
| Subtle (default) | 1px `border-subtle` | Most separations. |
| Strong | 1px `border-strong` | Rare. Use only where a divider must stay visible on busy backgrounds. |
| Inset | subtle, with `space-s` margin on both sides | Inside menus and lists, so the line does not touch the panel edge. Keep both margins equal. |
| Vertical | 1px wide | Between modules in the bar and between toolbar groups. Height is `icon-lg` (20px), centered; the full-height version stretches to its container. |
| With label | subtle lines on both sides of an overline label | The label uses the `overline` style in `text-muted`. Center it, or place it at the start with an 8px lead-in line. |

## Spacing
- In menus and lists, a divider has `space-xs` (4px) above and below.
- In panels, use `space-s` (8px) above and below.

## Do and don't
- Do keep dividers at `border-width-1`. Ewe never uses thicker separators.
- Don't place a divider at the top or bottom edge of a panel.
- Don't stack two dividers or combine a divider with a large gap.

## Accessibility
- Dividers are decorative. Mark them as separators only when they split groups in a menu.

## What a build provides
`orientation` (horizontal, vertical) · `fullHeight` · `inset` · `strong` · `label` with `align` (center, start).
