# Accent picker

The accent picker sets the color that buttons, switches, the focus ring and window borders follow.

## Anatomy
1. Swatches: 28px circles, 8px apart, with a 1px `border-subtle` ring so dark colors stay visible.
2. Selected swatch: a `check` in black or white (whichever contrasts), and a double ring (2px of the surface color, then 2px `text-primary`).
3. Custom swatch: dashed `border-strong` outline with a `plus`; it opens the custom color popover.

## Preset colors
Ewellow (#eeb407, default), Amber, Coral, Rose, Iris, Sky, Teal, Moss and Stone. Presets are chosen so that each makes a readable accent in both built-in schemes.

## States
- **Hover:** a 2px `border-strong` ring outside a 2px gap.
- **Selected:** a 2px `text-primary` ring outside a 2px gap, plus the check.
- **Focus:** 1px `focus-ring`, 1px outside the edge outside the rings.

## Custom color
- A popover with a saturation and brightness field, a hue slider and a hex field (Geist Mono).
- If the color can't be used as-is, an inline warning says what will be adjusted (“Accent text will be darkened to stay readable”).

## Accessibility
- A radio group; each swatch is named by its color name, and custom colors by their hex value.

## What a build provides
`value` · `presets` · `allowCustom` · `onChange`.
