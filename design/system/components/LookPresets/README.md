# Look presets

Look presets change the feel of the desktop (corners, density and outlines) by remapping a few tokens.

## Corner
| Value | `slight` | `secondary` | `primary` | `rounded` | Pills |
| --- | --- | --- | --- | --- | --- |
| none | 0 | 0 | 0 | 0 | square |
| small | 2 | 2 | 4 | 6 | round |
| **medium** (default) | 4 | 6 | 8 | 10 | round |
| large | 6 | 8 | 12 | 16 | round |

The old `round` value maps to large.

## Density
| Value | Controls and rows (`control-md`) | Large controls (`control-lg`) |
| --- | --- | --- |
| compact | 24px | 28px |
| **comfortable** (default) | 28px | 32px |
| roomy | 32px | 40px |

The bar and dock have their own size settings and don't follow density.

## Stroke
| Value | Outlines (`border-width-1`) | Heavy lines (`border-width-2`) |
| --- | --- | --- |
| none | 0 on cards, panels and buttons | 2px |
| **thin** (default) | 1px | 2px |
| thick | 2px | 3px |

Fields, checkboxes and switches always keep a 1px outline, and `focus-width` never changes with the stroke preset.

## Rules
- Presets never change colors or type. Every component is specified at the defaults and must hold up at every value.

## Where it lives
`bin/ewe-theme` (`corner`, `density`, `stroke` in `[desktop.theme]`). The values above replace the current ramps.

## What a build provides
`corner` · `density` · `stroke`.
