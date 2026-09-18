# Number stepper

A number stepper sets an exact number in small steps, such as the gap between windows, the number of workspaces or a timeout.

## When to use
- Use it for whole numbers in a small range where exact values matter.
- Use a Slider for large ranges or when the relative position matters more.

## Anatomy
1. Box: the Text field box with 2px (`space-xxs`) padding.
2. Decrease and increase buttons: ghost sm Icon buttons (24px) with `minus` and `plus`, at each end.
3. Value: centered, Geist Mono 12px weight 500, tabular numbers. People can also type into it.
4. Unit (optional): `text-muted` after the value ("px", "min").
5. Label and helper: as in the Text field. The helper states the allowed range ("0 to 32 px").

## Size
One size: 28px tall (`control-md`). Width fits the longest value plus the unit, usually 112 to 136px.

## States
| State | Box | Text |
| --- | --- | --- |
| Default | `surface-sunken` fill, 1px `border-strong` | value in `text-primary`, placeholder in `text-muted` |
| Hover | border turns `text-muted` | unchanged |
| Focus | the 1px border turns `focus-ring`; no extra ring | caret in `text-primary` |
| Error | 1px `danger` border | helper text in `danger` with a `circle-alert` icon |
| Disabled | `surface-raised` fill, `border-subtle` | `text-disabled` |
| Read-only | transparent fill, `border-subtle` | `text-primary`, still selectable |

At the minimum or maximum, the matching button is disabled; the other stays active.

## Behavior
- Up and Down arrow keys change the value by one step; holding a button repeats the step.
- A typed value outside the range shows an error and is not applied.

## Do and don't
- Do show the unit inside the field, not in the label.
- Don't use a stepper for values that change in large jumps.

## Accessibility
- The control is a spin button with its minimum, maximum and current value. The buttons have names ("Decrease gaps", "Increase gaps").

## What a build provides
`label` · `value` · `min` · `max` · `step` · `unit` · `helper` · `error` · `disabled` · `onChange`.
