# Spinner

A spinner shows that something is happening and its length is unknown.

## When to use
- Use it for waits between 300 milliseconds and a few seconds: connecting to a network, refreshing a list, loading search results.
- Use a Progress bar instead when the length or percentage is known, or when a task takes longer than a few seconds.
- Don't show a spinner for actions that finish in under 300 milliseconds.

## Anatomy
A circle drawn with a 2px (`border-width-2`) stroke: the track is `border-subtle` and a quarter arc in the tone color rotates once every 800 milliseconds at a steady speed.

## Sizes
| Size | Diameter | Use |
| --- | --- | --- |
| sm | `icon-sm` (14) | Inside sm and md buttons, next to caption text |
| md (default) | `icon-md` (16) | Next to body text, in list rows |
| lg | `icon-lg` (20) | In panels and cards |
| xl | `icon-xl` (24) | Empty states of small panels |
| 2xl | `icon-2xl` (32) | Full-panel loading states |

## Tones
- **Accent (default):** `accent` arc.
- **Neutral:** `text-secondary` arc. Use it inside secondary and ghost buttons.
- **On accent:** `on-accent` arc on a faint `on-accent` track. Use it inside primary buttons.

## Do and don't
- Do put a short label next to the spinner ("Connecting…") whenever there is room.
- Do replace a button's leading icon with the spinner instead of adding a second icon.
- Don't show more than one spinner in the same view.
- Don't use a spinner as decoration.

## Accessibility
- With reduced motion enabled, the spinner turns three times slower instead of stopping, so the state stays visible.
- The region that is loading reports its busy state; the spinner itself is hidden from assistive technology.

## What a build provides
`size` · `tone` (accent, neutral, on-accent) · `label` (optional, for assistive technology).
