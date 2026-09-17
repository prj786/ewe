# Date and time picker

Date and time fields let people type a date or time, or pick a date from a calendar.

## Anatomy
1. Date field: a Text field with a `calendar` icon. Clicking it opens a Popover with the Calendar, `space-xs` below.
2. Time field: a Text field with a `clock` icon and segments for hours and minutes in Geist Mono. The focused segment is filled with `accent` and `on-accent` text.
3. Range: two time fields labeled From and To, with a helper that states the length (“11 h · ends tomorrow”).

## Behavior
- Up and Down change the focused segment; typing digits fills it and moves to the next. Left and Right move between segments.
- Dates are written the way the system locale writes them; times follow the 24-hour or 12-hour setting.

## Accessibility
- Each segment is a spin button named by its unit; the calendar popup is a dialog that returns focus to the field.

## What a build provides
`label` · `value` · `min` · `max` · `granularity` (date, time, both) · `hourCycle` · `helper` · `error` · `onChange`.
