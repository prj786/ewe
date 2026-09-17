# Accessibility modes

Accessibility modes change how the whole desktop looks and moves, without changing its layout.

## Modes
| Mode | What changes |
| --- | --- |
| Reduce motion | Slides and zooms become 150ms fades; nothing bounces or scales. Spinners keep turning. |
| Reduce transparency | Glass roles become solid (`glass-*` take their `surface-*` and `border-subtle` values); no blur; app blur and window transparency are off. |
| Increase contrast | `border-subtle` becomes `border-strong`, `text-muted` becomes `text-secondary`, hover uses `surface-pressed`, `focus-width` becomes 2px, and Glass is solid. |
| Text size | 100%, 115% or 130%. Type scales; controls grow to fit their text instead of clipping. At 130% the bar uses its large size. |

## Rules
- Modes are role remaps, like Glass: components don't need their own variants.
- They combine with any scheme and any look preset.
- Display scaling (125%, 150%) is separate and handled by Hyprland; everything is specified on whole pixels at 100% and must stay centered at fractional scales (center text on cap height, not on the line box).

## Settings
Settings → Accessibility, stored in ewe.conf `[desktop.accessibility]`:
`reduce_motion` (false) · `reduce_transparency` (false) · `increase_contrast` (false) · `text_scale` (100, 115 or 130).

## Where it lives
New. None of these exist in the shell yet; `desktop.animations.speed = 0` is the closest to Reduce motion today.

## What a build provides
`reduceMotion` · `reduceTransparency` · `increaseContrast` · `textScale`.
