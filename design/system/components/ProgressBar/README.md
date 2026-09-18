# Progress bar

A progress bar shows how far a task has gone when its length is known, such as a download, an install or a disk that is filling up.

## When to use
- Use it for tasks longer than a few seconds, and for levels that change over time (battery, disk, memory).
- Use the **indeterminate** version when work has started but its length is not known yet; switch to a determinate bar as soon as it is.
- Use a Spinner instead for short waits.

## Anatomy
1. Label (optional): what is happening, 12px weight 500 in `text-primary`.
2. Value (optional): percentage or amount, Geist Mono 12px weight 500 in `text-secondary`, right-aligned.
3. Track: `surface-hover`, `fully-rounded`.
4. Fill: the tone color, `fully-rounded`, growing from the left.
5. Hint (optional): remaining time, size or an error, in the `caption` style and `text-muted`.

The label and value sit `space-xs` (4px) above the track; the hint sits `space-xs` below it.

## Sizes
| Size | Track height | Use |
| --- | --- | --- |
| Default | `space-xs` (4px) | Downloads, installs, list rows |
| Large | `space-s` (8px) | Levels (battery, disk) and the installer |

## Tones
- **Accent (default):** tasks in progress.
- **Success:** a finished task. Keep it visible briefly, then remove the bar.
- **Danger:** a failed task. Always add a hint that explains what happened and what to do.
- **Neutral:** `text-secondary` fill, for levels that are not a task (disk usage, memory).

## Do and don't
- Do keep the value in tabular numbers so it does not jitter while updating.
- Do write hints that help: "84.2 MB of 136 MB · 12 s left".
- Don't let progress move backwards. If a task restarts, reset the bar and say so in the hint.
- Don't show a percentage for an indeterminate bar.

## Accessibility
- The bar reports its current value, minimum and maximum. The label is its accessible name.
- With reduced motion enabled, the indeterminate fill moves three times slower.
- The fill holds at least 3:1 against the track in every tone and theme.

## What a build provides
`value` (0–100) or `indeterminate` · `label` · `valueText` · `hint` · `size` · `tone` (accent, success, danger, neutral).
