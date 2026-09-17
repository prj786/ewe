# Settings page

A settings page groups related options with their current values and controls, applied as soon as they change.

## Anatomy
1. Page title with a one-line description and at most one page action (“Identify”).
2. An inline alert, only when something needs attention or explanation.
3. Groups: an overline Section header above a list well of List rows.
4. Rows: a 32px icon tile, the setting name and a description, and the control on the right: a Switch, a value with a chevron (opens a Select), a small Segmented control or a Slider with its value.
5. Advanced options inside an Accordion at the end.

## Rules
- Changes apply immediately; there is no Save button. Risky changes (display resolution) revert on their own unless confirmed within 15 seconds.
- Every row shows its current value.
- Write names as nouns (“Night light”), descriptions as the effect (“Warmer colors in the evening”).

## Accessibility
- Each control is labeled by its row's title and described by its description.

## What a build provides
`title` · `description` · `groups` (title, rows) · `alert` · `advanced`.
