# Scrollbar

Ewe's scrollbars are thin overlays that stay out of the way until people reach for them.

## Anatomy
1. Thumb: 4px wide at rest, `border-strong` at 60% opacity, `fully-rounded`, 2px from the edge.
2. Track: appears on hover, 8px wide, `surface-hover`.
3. Fade (optional): a 32px fade into the surface color at the bottom of clipped lists.

## States
- **At rest:** visible while scrolling, fades out after 1 second.
- **Hover:** 8px track and a fully opaque thumb.
- **Dragging:** thumb turns `text-secondary`.

## Accessibility
- Scrollable areas are keyboard-scrollable; the scrollbar is not the only way to move.

## What a build provides
`orientation` · `autoHide` · `fade`.
