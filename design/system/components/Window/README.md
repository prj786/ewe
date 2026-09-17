# Window

This is how Hyprland draws windows in Ewe: gaps, corners, borders and groups.

## Rules
| Part | Value |
| --- | --- |
| Gaps | `window-gap` (8px) between windows and around the screen edges (`gaps_in` 4, `gaps_out` 8) |
| Corners | `rounded` (10px) |
| Border | 2px (`border-width-2`) |
| Focused window | `accent` border |
| Other windows | `border-subtle` border |
| Grouped windows | `accent-text` border, and a tab strip on top with the active tab in `accent` |
| Urgent window | `danger` border until focused |
| Floating windows | `shadow-float` |
| Dim | none; unfocused windows stay fully bright |

## Notes
- Apps draw no title bars under Hyprland; the border and the bar's window title say which window is focused.
- The border follows the accent, so a custom accent changes it too.

## What a build provides
Hyprland `general` (gaps, border size, active and inactive border colors), `decoration` (rounding, shadow) and `group` colors.
