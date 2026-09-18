# Workspace indicator

The workspace chip at the start of the bar shows the number of the focused workspace.

## Anatomy
- 32px (`control-lg`) chip, `primary` radius, 8px side padding.
- The number: 13px weight 600 `text-primary`, tabular numbers.
- Underline: 16px × 2px `accent`, rounded, 4px above the chip's bottom edge. It is always there: it marks the chip as "where you are".

## States
| State | Look |
| --- | --- |
| Default | no fill |
| Hover | `surface-hover` |
| Overview open | `surface-pressed` |
| Focus | 1px `focus-ring` on the edge |

In the large bar the chip is 40px and the number 15px.

## Behavior
- Click opens or closes the Overview.
- The full list of workspaces lives in the Dock's workspace groups, not in the bar.

## Accessibility
- A button named “Workspace 1, open overview”.

## What a build provides
`workspace` (id) · `overviewOpen` · `onClick`.
