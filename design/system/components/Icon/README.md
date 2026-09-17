# Icon

Icons in Ewe come from Lucide, an open-source set (ISC license) of simple outlined icons drawn on a 24px grid.

## When to use
- Use icons to make actions and states faster to recognize, always next to a label unless the icon is universally understood.
- Use the same icon for the same meaning everywhere: `settings` always means settings, and `x` always means close or remove.

## Style
- Outline only, with a 2px stroke on the 24px grid and round caps and joins. Never fill Lucide icons.
- Up to 24px, the stroke scales with the icon, which gives thinner lines at small sizes. From 32px up, the stroke stays 2px so large icons don't look heavy.
- Icons take their color from the text around them (`currentColor`).
- In the shell and the apps, icons are glyphs from a Lucide subset font. The same sizes and tones apply; only add the glyphs a surface uses to the subset.

## Sizes
| Token | Size | Use |
| --- | --- | --- |
| `icon-xs` | 12px | Inside badges, checkbox checks and switch thumbs (fixed 1.5px stroke) |
| `icon-sm` | 14px | Inside `label` and `caption` text, sm buttons, tags |
| `icon-md` | 16px | Default: buttons, menus, list rows |
| `icon-lg` | 20px | Bar modules in `bar-height`, xl buttons, notification actions |
| `icon-xl` | 24px | Bar modules in `bar-height-lg`, tray and notification app icons |
| `icon-2xl` | 32px | App icons in launcher rows and the window switcher |
| `icon-3xl` | 48px | Launcher grid, empty states |
| `icon-4xl` | 64px | About page, installer, app details |

The sizes from 32px up are mostly for app icons, which are full-color images rather than Lucide icons.

## Tones
| Tone | Token | Use |
| --- | --- | --- |
| Default | `text-secondary` | Resting icons in toolbars, lists and the bar |
| Active | `text-primary` | Hovered or active items |
| Accent | `accent-text` | Selected or enabled states |
| Muted | `text-disabled` | Disabled items only |
| Success / Warning / Danger / Info | status tokens | Status messages, always next to text |

## Core set
The Icons asset group holds the 34 icons used most across the desktop, drawn in `neutral-500` so they read on any background as images. Other Lucide icons may be used as long as they follow the same style.

## Do and don't
- Do align icons to the center of the text line next to them.
- Do keep `space-xs` (4px) between an icon and its label, and `space-s` (8px) at xl and 2xl sizes.
- Don't mix Lucide with other icon sets.
- Don't rotate, stretch or recolor parts of an icon.

## Accessibility
- Decorative icons are hidden from assistive technology. An icon that works alone (in an Icon button) takes its name from the button.
- Icons that carry meaning hold at least 3:1 contrast in every theme.

## What a build provides
`name` (Lucide name) · `size` · `tone`.
