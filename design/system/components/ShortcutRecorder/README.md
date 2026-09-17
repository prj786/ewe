# Shortcut recorder

A shortcut recorder captures a key combination, for the Keyboard shortcuts page.

## Anatomy
1. Field: 28px tall, at least 196px wide, `surface-sunken`, 1px `border-strong`, `primary` radius.
2. Content: the shortcut as Kbd keys, or “Not set” in `text-muted`.
3. Action: a ghost Icon button to clear (`x`) or reset to the default (`rotate-ccw`).

## States
| State | Look |
| --- | --- |
| Set | Kbd keys |
| Not set | “Not set” |
| Hover | border `text-muted` |
| Recording | `focus-ring` border, `accent-subtle` fill, an 8px `danger` dot and “Press the new shortcut…”; held modifiers appear as they are pressed |
| Conflict | `danger` border and a helper naming the action that already uses it |
| Disabled | `surface-raised`, `border-subtle`, `text-disabled` |

## Behavior
- Click or Enter starts recording. The first combination with a non-modifier key is saved. Esc cancels; Backspace clears.
- Shortcuts that the system reserves (Ctrl+Alt+Delete) can't be recorded.

## Accessibility
- The field announces the current shortcut and the recording state.

## What a build provides
`value` · `defaultValue` · `conflicts` · `disabled` · `onChange`.
