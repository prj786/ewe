# Meter

A meter shows how full something is: CPU, memory, disk, battery or storage by category.

## When to use
- Use it for levels that are not a task. Use a Progress bar for tasks that finish.

## Anatomy
1. Header: a 14px icon, a 12px label in `text-secondary`, and the value in Geist Mono 12px weight 500, right-aligned.
2. Track: 6px tall, `surface-hover`, `fully-rounded`.
3. Fill: `accent` by default.

## Thresholds
| Level | Fill | Value |
| --- | --- | --- |
| Normal | `accent` | `text-primary` |
| Warning (default above 70%) | `warning` | `text-primary` |
| Critical (default above 90%) | `danger` | `danger` |

The thresholds depend on the resource: battery is critical below 10%, not above 90%.

## Variants
- **Breakdown:** several segments with 2px gaps and a legend of 8px swatches below. Use `accent`, `info`, `success` and `warning` in that order; free space stays `surface-hover`.
- **Segmented:** ten equal segments, for the battery in quick settings.

## Accessibility
- A meter role with its value, minimum and maximum; the value text includes the unit (“71% of memory used”).

## What a build provides
`label` · `icon` · `value` · `max` · `valueText` · `thresholds` · `segments` · `segmented`.
