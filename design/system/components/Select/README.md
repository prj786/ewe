# Select

A select lets people pick one value from a list, such as a language, a keyboard layout or a screen resolution.

## When to use
- Use it for six or more options, or when the options are long.
- Use a Segmented control for two to five short options, and Radio buttons when every option needs a description.

## Anatomy
1. Trigger: the Text field box with the current value (or a placeholder) and a `chevron-down` icon in `text-secondary` at the end. An optional leading icon describes the setting.
2. Menu: opens `space-xs` (4px) below the trigger and is at least as wide as it. It uses the Menu component.
3. Selected option: a `check` icon in `accent-text` at the end of the row, and the label in weight 500.

## Sizes
The trigger uses the Text field sizes: sm 24, md 28 (default), lg 32, xl 40. Menu rows stay 28px tall at every size.

## States
| State | Trigger |
| --- | --- |
| Default | `surface-sunken` fill, 1px `border-strong`, placeholder in `text-muted` |
| Hover | border turns `text-muted` |
| Open | border turns `focus-ring` and the chevron points up |
| Focus | border turns `focus-ring` |
| Error | 1px `danger` border and an error message below |
| Disabled | `surface-raised` fill, `border-subtle`, `text-disabled` |

Options can be disabled with a short reason on the right ("Not installed").

## Behavior
- Click or Enter opens the menu with the selected option highlighted. Arrow keys move, Enter selects, Esc closes without changing the value.
- Typing jumps to the first option that starts with the typed letters.
- If the list has more than 12 options, add a search field at the top of the menu.

## Do and don't
- Do order options logically: alphabetically, or by how often they are used.
- Don't use a select for actions; use a Menu on a Button.

## Accessibility
- The trigger announces its label and current value. The menu is a listbox; the selected option is marked as selected.

## What a build provides
`label` · `options` (label, value, icon, disabled, reason) · `value` · `placeholder` · `size` · `error` · `disabled` · `onChange`.
