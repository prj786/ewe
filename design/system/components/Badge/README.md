# Badge

A badge is a small, non-interactive label that shows a status, a count or that something is new.

## When to use
- Use a **subtle** badge for status next to an item: Installed, Update, Failed.
- Use a **solid** badge when the status must stand out, and for counts on icons (unread notifications, pending updates).
- Use a **dot** when only presence matters, such as "there are updates", with no number.
- Use a Tag instead if people can click, select or remove it.

## Anatomy
1. Container: `fully-rounded` pill, 16px tall, `space-xs` (4px) side padding. It grows with its content, never with a fixed width.
2. Text: 11px on a 14px line, weight 500, tabular numbers. The label is centered on its cap height, not on the font's line box, because browsers and toolkits place the baseline differently (Firefox-based browsers sit it a pixel lower). In CSS, trim the label to cap height (`text-box: trim-both cap alphabetic`); in QML, center on `FontMetrics` cap height. Numbers and capitals then sit exactly in the middle at any scale.
3. Icon (optional): `icon-xs` (12px) with a fixed 1.5px stroke, placed before the text. It leaves an even 2px on the top, bottom and left, and `space-xxs` (2px) before the text.

## Tones
| Tone | Subtle fill / text | Solid fill / text |
| --- | --- | --- |
| Neutral | `surface-hover` / `text-secondary` | — |
| Accent | `accent-subtle` / `accent-text` | `accent` / `on-accent` |
| Success | `success-subtle` / `success` | `success` / `on-status` |
| Warning | `warning-subtle` / `warning` | `warning` / `on-status` |
| Danger | `danger-subtle` / `danger` | `danger` / `on-status` |
| Info | `info-subtle` / `info` | `info` / `on-status` |

## Counts and dots
- A count badge is at least 16px wide, so single digits form a circle. Show "99+" above 99.
- A dot is 8px (`space-s`).
- On an icon, place the badge at the top-right corner, offset by `space-xs` (a dot by `space-xxs`), and add a 2px ring in the surface color so it separates from the icon.
- Use danger for unread counts and accent for updates or new content.

## Do and don't
- Do keep badge text to one or two words.
- Do pair a status color with an icon or a word; never rely on color alone.
- Don't use more than one badge on an item.
- Don't make badges clickable.

## Accessibility
- Text contrast is at least 4.5:1 in every tone and theme.
- A count on an icon is included in the icon button's accessible name ("Notifications, 4 unread").

## What a build provides
`tone` · `solid` · `icon` · `label` or `count` (with `max`, default 99) · `dot`.
