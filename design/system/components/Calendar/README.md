# Calendar

The calendar shows a month with today, the selected day and days with events. It is the clock popup and the date picker.

## Anatomy
1. Header: month and year in 13px weight 600, with previous and next ghost Icon buttons.
2. Weekday row: `caption` in `text-muted`. Weeks start on Monday, or as the system locale says.
3. Day: 28px square cells with 2px gaps, Geist Mono 12px, `secondary` radius.
4. Event dot: 4px in `accent-text`, 2px above the cell's bottom edge.
5. Agenda (in the clock popup): the day's events beside the month, each with a time, a 2px colored bar, a title and a `caption` line.

## Day states
| State | Look |
| --- | --- |
| Weekend | `text-secondary` |
| Other month | `text-disabled` |
| Hover | `surface-hover` |
| Today | 1px `accent-text` ring and `accent-text` number |
| Selected | `accent` fill, `on-accent` number |
| In a range | `accent-subtle`, square corners |
| Focus | 1px `focus-ring` |
| Unavailable | `text-disabled`, struck through |

## Behavior
- Arrow keys move by day and week, Page Up and Page Down by month, Home and End to the week's edges. Enter selects.
- The current event in the agenda gets an `accent-subtle` fill.

## Accessibility
- A grid of days; each day is read with its full date and whether it has events.

## What a build provides
`month` · `value` · `range` · `events` · `min` · `max` · `firstDayOfWeek` · `onSelect` · `onMonthChange`.
