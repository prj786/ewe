# Progress ring

A progress ring shows progress in a small, square space: a download on an icon, a battery level, a timer.

## Sizes
| Size | Stroke | Content |
| --- | --- | --- |
| 24px | 2px | Icon only |
| 32px | 3px | Number without unit |
| 48px (default) | 4px | Percentage |
| 96px | 6px | Percentage and a `caption` word |

## Anatomy
- Track in `surface-hover`, fill in `accent` with round ends, starting at the top and running clockwise.
- The center shows the value in Geist Mono weight 500, or an icon in `text-secondary`.

## Tones
- `success` when done (with a `check`), `warning` and `danger` for levels that need attention.

## Accessibility
- Same as the Progress bar: a progress bar role with its value, or a meter role for levels.

## What a build provides
`value` · `size` · `tone` · `label` · `icon` · `indeterminate`.
