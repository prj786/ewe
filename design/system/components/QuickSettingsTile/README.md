# Quick settings tile

A quick settings tile toggles a feature and shows its state, with an optional button to open its details.

## Anatomy
1. Tile: 56px tall (`control-2xl` + 8px), `surface-overlay`, 1px `border-subtle`, `rounded` radius.
2. Icon: a 32px circle; `surface-hover` when off, `accent` with an `on-accent` icon when on.
3. Title (13px weight 500) and status (`caption`): the connected network, the device, “Off” or “Until 07:00”.
4. Details button (optional): a 28px zone on the right with a `chevron-right`, divided by a 1px line.
5. Small tile: 48px tall, icon only, for toggles without a status.

## States
| State | Look |
| --- | --- |
| Off | as above; status in `text-muted` |
| Hover | the pressed part fills with `surface-hover` |
| On | `accent-subtle` fill, no border; status in `accent-text` |
| Details open | 2px `accent-text` edge |
| Focus | 1px `focus-ring`, 1px outside the edge |
| Busy | the icon circle shows a Spinner while the change applies |
| Disabled | `text-disabled`, with the reason as the status (“No adapter”) |

## Behavior
- Clicking the tile toggles; clicking the details button (or right-clicking the tile) opens its detail page inside the panel.
- The change applies at once; the status updates when the system confirms it.

## Accessibility
- The tile is a toggle button named by its title and status; the details button is separate (“Wi-Fi details”).

## What a build provides
`title` · `status` · `icon` · `on` · `busy` · `details` · `disabled` · `onToggle` · `onDetails`.
