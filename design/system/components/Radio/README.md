# Radio

Radio buttons let people choose exactly one option from a short list, where each option benefits from being visible at once.

## When to use
- Use them for two to six options, especially when options need a description.
- Use a Segmented control for short options that apply immediately, and a Select for long lists.

## Anatomy
1. Circle: `fully-rounded`, 16px (`icon-md`), 1px `border-strong`, `surface-sunken` fill, placed 1px below the top of the label so it centers on the first line.
2. Label: 13px in `text-primary`, `space-s` (8px) after the control. Clicking the label toggles the control.
3. Description (optional): the `caption` style in `text-muted`, under the label.
4. Dot: 6px (`space-xs` + `space-xxs`) in `on-accent`, centered, shown when selected.

## States
| State | Circle |
| --- | --- |
| Unselected | `surface-sunken` fill, `border-strong` |
| Hover | border turns `text-secondary` |
| Selected | `accent` fill and border with the dot; hover uses `accent-hover` |
| Focus | 1px `focus-ring`, 1px outside the circle |
| Error | 1px `danger` border |
| Disabled | `surface-raised` fill, `border-subtle`; dot and label in `text-disabled` |

## Layout
- Put a group label (12px weight 500) above the options.
- Stack options vertically with `space-s` (8px) between rows.

## Do and don't
- Do always have one option selected by default, usually the recommended one.
- Don't use a single radio button; use a Checkbox.

## Accessibility
- The options form a radio group named by the group label. Arrow keys move the selection; Tab enters and leaves the group.

## What a build provides
`label` (group) · `options` (label, description, value, disabled) · `value` · `error` · `onChange`.
