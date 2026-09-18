# Slider

A slider picks a value from a continuous or stepped range, such as volume, brightness or display scale.

## When to use
- Use it when the exact number matters less than the relative position, and the result shows immediately.
- Use a Number stepper when people need an exact value.

## Anatomy
1. Track: `surface-hover`, `fully-rounded`, 4px tall (`space-xs`).
2. Fill: `accent`, from the start of the track to the thumb.
3. Thumb: a 12px circle (`icon-xs`) in `text-primary`, centered on the value.
4. Icons (optional): 16px in `text-secondary` at either end, showing low and high (`volume-1` and `volume-2`).
5. Value (optional): Geist Mono 12px weight 500, right-aligned in a 36px column so it doesn't shift.
6. Steps (optional): 1px × 4px tick marks in `border-strong` below the track, with `caption` labels under them.

## Sizes
| Size | Track | Thumb | Icons | Use |
| --- | --- | --- | --- | --- |
| md (default) | 4px | 12px | 16px | Settings, quick settings |
| lg | 8px | 16px | 20px | Volume and brightness popups |

## States
| State | Look |
| --- | --- |
| Default | as above |
| Hover | a 4px `surface-hover` halo around the thumb |
| Focus | 1px `focus-ring`, 1px outside the thumb |
| Dragging | same as hover; show the value in a Tooltip above the thumb if there is no value label |
| Disabled | fill, thumb and icons in `text-disabled` |

## Behavior
- Clicking the track moves the thumb there. Arrow keys change the value by one step; Page Up and Page Down by ten.
- Stepped sliders snap to their ticks.
- Changes apply live while dragging.

## Do and don't
- Do show the value next to the slider when it helps people decide (percentages, scale).
- Don't use a slider for ranges with fewer than three steps; use a Segmented control.

## Accessibility
- The control has the slider role with its minimum, maximum and current value, plus a text value ("64%").
- The fill and thumb hold at least 3:1 against the track in both themes.

## What a build provides
`value` · `min` · `max` · `step` · `ticks` (with labels) · `showValue` · `startIcon` · `endIcon` · `size` · `disabled` · `onChange`.
