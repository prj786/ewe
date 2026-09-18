# Switch

A switch turns a setting on or off right away, such as Night light, Bluetooth or Do not disturb.

## When to use
- Use it for settings that take effect immediately, without a Save button.
- Use a Checkbox inside forms that are confirmed later.

## Anatomy
1. Track: `fully-rounded`, 1px border, `space-xxs` (2px) padding.
2. Thumb: a circle that sits left when off and right when on.
3. Thumb icon: a small `x` when off and `check` when on, with a fixed 1.5px stroke, so the state doesn't rely on color alone.
4. Label: in a settings row, the label and description sit on the left and the switch on the right.

## Sizes
| Size | Track | Thumb | Thumb icon |
| --- | --- | --- | --- |
| md (default) | `control-lg` × 18px (32 × 18) | `icon-xs` (12) | 8px |
| lg | `control-xl` × `control-sm` (40 × 24) | 18px | `icon-xs` (12) |

Use md in Settings and quick settings, and lg in the installer and on touch screens.

## States
| State | Track | Thumb |
| --- | --- | --- |
| Off | `surface-sunken` fill, `border-strong` | `text-secondary`, icon in `surface-sunken` |
| Off · hover | border turns `text-secondary` | unchanged |
| On | `accent` fill and border | `on-accent`, icon in `accent` |
| On · hover | `accent-hover` | unchanged |
| Focus | 1px `focus-ring`, 1px outside the track | |
| Disabled | `surface-raised` fill, `border-subtle` | `text-disabled` |

## Behavior
- Clicking anywhere on the settings row toggles the switch.
- The thumb slides in 120ms with an ease-out curve; with reduced motion it moves instantly.
- If the change takes time (turning Bluetooth on), keep the new position and show a Spinner in the description until it finishes.

## Do and don't
- Do label the setting, not the action: "Bluetooth", not "Turn on Bluetooth".
- Don't add "On" and "Off" text next to the switch.
- Don't use a switch when the choice needs a confirmation.

## Accessibility
- The control has the switch role and reports on or off. Space toggles it.
- The thumb holds at least 3:1 against the track in both states.

## What a build provides
`label` · `description` · `checked` · `size` · `busy` · `disabled` · `onChange`.
