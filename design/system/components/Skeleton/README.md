# Skeleton

Skeletons are placeholder shapes that stand in for content while it loads, so the layout doesn't jump.

## When to use
- Use them for loads over 300ms where the shape of the content is known: app grids, lists, cards.
- Use a Spinner for actions, and a Progress bar when the length is known.

## Anatomy
- Shapes use `surface-hover` with a soft `surface-pressed` band that sweeps across every 1.6 seconds.
- Text lines are 8px tall with 4px above and below; titles are 12px. Lines end at different widths (100%, 92%, 60%).
- Blocks use the `primary` radius; avatars are circles.

## Behavior
- Match the real layout exactly: the same number of rows, the same sizes.
- Replace skeletons all at once, not line by line.
- With reduced motion, the shapes stay still.

## Accessibility
- The loading region reports that it is busy; skeletons themselves are hidden from assistive technology.

## What a build provides
`shape` (text, title, circle, block) · `width` · `height` · `lines` · `animated`.
