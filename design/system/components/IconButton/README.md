# Icon button

An icon button runs an action or toggles a setting using only an icon, in places where space is tight.

## When to use
- Use it in toolbars, the bar, notification actions, media controls and window headers.
- Use it only when the icon is universally understood (close, search, settings, play). Otherwise use a Button with a label.
- Use the **selected** state for toggles such as Wi-Fi, Do Not Disturb or Mute.

## Anatomy
1. Square container: `primary` radius, or `fully-rounded` for the round variant.
2. Icon: one Lucide icon, centered.
3. Tooltip (required): names the action and shows its shortcut, if any.

## Variants
| Variant | Fill | Border | Icon |
| --- | --- | --- | --- |
| Ghost (default) | transparent | none | `text-secondary` |
| Secondary | `surface-raised` | `border-strong` | `text-primary` |
| Primary | `accent` | none | `on-accent` |
| Round | any variant with `fully-rounded` corners; use it for the main media control. | | |

## Sizes
| Size | Box | Icon |
| --- | --- | --- |
| sm | `control-sm` (24) | `icon-sm` (14) |
| md (default) | `control-md` (28) | `icon-md` (16) |
| lg | `control-lg` (32) | `icon-md` (16) |
| xl | `control-xl` (40) | `icon-lg` (20) |
| 2xl | `control-2xl` (48) | `icon-xl` (24) |

In the bar, use lg with `bar-height` (40px) and xl with `bar-height-lg` (48px).

## States
- **Hover:** ghost fills with `surface-hover` and the icon turns `text-primary`; secondary uses `surface-hover`; primary uses `accent-hover`.
- **Pressed:** `surface-pressed`, or `accent-pressed` for primary.
- **Selected (toggle on):** `accent-subtle` fill with an `accent-text` icon.
- **Focus:** 1px `focus-ring`, 1px outside the control.
- **Disabled:** `text-disabled` icon; secondary and primary also use a `surface-raised` fill and a `border-subtle` outline.

## Do and don't
- Do keep icon buttons in a row evenly spaced, 2px apart inside a panel and 8px apart elsewhere.
- Do show the selected state instead of swapping icons for simple on/off toggles. Swap icons only when the meaning changes (play and pause).
- Don't put two primary icon buttons in the same group.
- Don't use an icon button without a tooltip.

## Accessibility
- Every icon button has an accessible name that matches its tooltip.
- Toggles report their pressed state.
- Icons hold at least 3:1 against the surface in every theme.

## What a build provides
`icon` (Lucide name) · `label` (accessible name and tooltip) · `variant` · `size` · `round` · `selected` · `disabled` · `onClick`.
