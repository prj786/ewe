# Table

A table lists items with several comparable values, such as installed packages with version, source and size.

## Anatomy
1. Container: `surface-raised`, 1px `border-subtle`, `rounded` radius.
2. Header row: 28px tall on `surface-base`, 12px weight 500 in `text-muted`. The sorted column is `text-primary` with an arrow.
3. Rows: 32px tall, 12px side padding, 1px `border-subtle` between rows.
4. Numbers: right-aligned, Geist Mono 12px, tabular.
5. Selection (optional): a checkbox column; the header checkbox selects all and shows the mixed state.

## States
- **Row hover:** `surface-hover`. **Selected row:** `accent-subtle`.
- **Focus:** a 1px `focus-ring` around the focused cell or row.

## Behavior
- Clicking a header sorts by that column; clicking again reverses the order.
- Long lists render only visible rows and keep the header in place.

## Do and don't
- Do put the most identifying column first and keep it left-aligned.
- Don't wrap cell text; truncate it and show the full value in a tooltip.

## Accessibility
- A grid when rows are selectable, otherwise a table. Sorted columns report their sort order.

## What a build provides
`columns` (key, label, align, sortable, mono) · `rows` · `sort` · `selectable` · `selected` · `onSort` · `onSelect` · `onRowClick`.
