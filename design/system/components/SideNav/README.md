# Side navigation

Side navigation is the rail on the left of Settings, Komble and ewe-sync. It lists the app's main sections.

## Anatomy
1. Rail: 196px wide, on the window's `surface-base`, 12px × 8px padding, 16px between groups.
2. Brand: the sheep mark (24px) and the app name, 15px weight 600.
3. Group heading (optional): the `overline` style in `text-muted`.
4. Item: 28px tall, 8px side padding, `secondary` radius, 16px icon, 13px label truncated with an ellipsis, and an optional count Badge.
5. Footer: Help and the version in Geist Mono `caption`.

## States
- **Default:** `text-secondary`. **Hover:** `surface-hover`, `text-primary`.
- **Selected:** `accent-subtle` fill, `text-primary` weight 500, the icon in `accent-text`. No edge bar: the fill alone marks it, and it stays distinct from hover (`surface-hover`).
- **Focus:** a 1px `focus-ring` on the item's edge.
- **Disabled:** `text-disabled`.

## Behavior
- Up and Down arrows move between items. Ctrl+1 to Ctrl+9 jump to the first nine sections.
- Below 720px of window width, the rail collapses to icons only (48px wide) with tooltips.

## Accessibility
- A navigation landmark; the selected item is marked as the current page.

## What a build provides
`brand` · `groups` (heading, items: label, icon, badge, disabled) · `value` · `footer` · `collapsed` · `onNavigate`.
