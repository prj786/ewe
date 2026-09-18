# Step indicator

A step indicator shows progress through a multi-step flow, such as the installer or first-run setup.

## Anatomy
1. Step dot: a 24px circle with the step number in Geist Mono 11px.
2. Label: 13px; the vertical form adds a `caption` description.
3. Connector: a 1px line between steps, `accent-text` once the step before it is done.

## States
| State | Dot | Label |
| --- | --- | --- |
| Upcoming | 1px `border-strong` ring | `text-muted` |
| Current | `accent` fill, number in `on-accent` | `text-primary`, weight 500 |
| Done | `accent-subtle` fill, `check` in `accent-text` | `text-secondary` |
| Error | 1px `danger` ring, `x` in `danger` | `text-muted` |

## Do and don't
- Do keep labels to one or two words.
- Do let people go back to done steps by clicking them.
- Don't show more than seven steps.

## Accessibility
- An ordered list; the current step is marked as the current step, and done steps say “completed”.

## What a build provides
`steps` (label, description, state) · `orientation` · `onStepClick`.
