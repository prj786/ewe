# Inline alert

An inline alert shows a message that belongs to a page or a section: a paused sync, a needed restart, a failed install.

## When to use
- Use it for a lasting state of the page. Use a Toast for a passing confirmation and a Notification for events from outside the app.

## Anatomy
1. Container: 8px × 12px padding, `primary` radius.
2. Icon: 16px, matching the tone.
3. Title: 13px weight 500 in the tone color.
4. Description: 13px in `text-primary`.
5. Actions (optional): secondary and ghost small buttons, 4px below the text.
6. Close (optional): a ghost Icon button, only for alerts that can be dismissed.

## Tones
| Tone | Fill | Icon and title |
| --- | --- | --- |
| Neutral | `surface-raised` with a `border-subtle` outline | `text-secondary` icon, `text-primary` title |
| Info | `info-subtle` | `info` |
| Success | `success-subtle` | `success` |
| Warning | `warning-subtle` | `warning` |
| Danger | `danger-subtle` | `danger` |
| Accent | `accent-subtle` | `accent-text`, for news about Ewe itself |

## Banner
- Across the top of a window: no radius, a 1px bottom border, centered vertically, one line.

## Do and don't
- Do say what happened and what to do next, with an action that does it.
- Don't show more than one alert per section; combine them.
- Don't use the danger tone for warnings people can ignore.

## Accessibility
- Info and success alerts are announced politely; warning and danger alerts are announced right away.

## What a build provides
`tone` · `title` · `description` · `icon` · `actions` · `dismissible` · `banner` · `onDismiss`.
