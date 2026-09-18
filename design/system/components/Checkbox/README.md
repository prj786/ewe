# Checkbox

A checkbox turns an option on or off, usually as part of a form or a list that is applied or confirmed later.

## When to use
- Use it for independent options in a form, and to select several items in a list.
- Use a Switch for settings that apply immediately.
- Use a mixed (indeterminate) parent checkbox when some, but not all, of its children are checked.

## Anatomy
1. Box: a square with the `slight` radius (4px), 16px (`icon-md`), 1px `border-strong`, `surface-sunken` fill, placed 1px below the top of the label so it centers on the first line.
2. Label: 13px in `text-primary`, `space-s` (8px) after the control. Clicking the label toggles the control.
3. Description (optional): the `caption` style in `text-muted`, under the label.
4. Mark: a `check` (or `minus` when mixed) at `icon-xs` (12px) with a fixed 2px stroke, in `on-accent`.

## States
| State | Box |
| --- | --- |
| Unchecked | `surface-sunken` fill, `border-strong` |
| Hover | border turns `text-secondary` |
| Checked / mixed | `accent` fill and border; hover uses `accent-hover` |
| Focus | 1px `focus-ring`, 1px outside the box |
| Error | 1px `danger` border, with an error message below the group |
| Disabled | `surface-raised` fill, `border-subtle`; mark and label in `text-disabled` |

## Layout
- Stack checkboxes vertically with `space-s` (8px) between rows.
- Indent child checkboxes by 24px (box plus gap) under their parent.

## Do and don't
- Do write labels as positive statements ("Show battery percentage"), not negatives.
- Don't use a checkbox to trigger an action immediately.
- Don't explain a disabled checkbox only in a tooltip; use the description.

## Accessibility
- Space toggles the checkbox. A mixed checkbox reports its mixed state.
- The whole row (box and label) is the click target.

## What a build provides
`label` · `description` · `checked` · `indeterminate` · `error` · `disabled` · `onChange`.
