# Toast

A toast confirms something that just happened and offers one quick way back, such as Undo.

## When to use
- After an action that can be reversed: moving to Trash, dismissing a notification, unpinning, moving windows. Offer Undo instead of asking first.
- For short confirmations that need no decision ("Copied to clipboard").
- Not for messages from apps: those are Notifications. Not for errors that need attention: use an Inline alert or a Dialog.

## Placement
- Centered at the bottom of the focused screen, 12px above the dock (or `window-gap` above the edge when the dock is hidden).
- One at a time. A new toast replaces the current one; the replaced action is no longer available.
- Layer: overlay, above popups, below the OSD.

## Anatomy
1. Container: `surface-overlay`, 1px `border-subtle`, `rounded` radius, `shadow-float`, at least 40px (`control-xl`) tall, at most `panel-lg` wide. 12px padding on the left, 4px elsewhere.
2. Icon (optional): 16px, `text-secondary`, or the status color for success, warning and danger. A small Spinner replaces it while something is in progress.
3. Message: 13px `text-primary`, one line, sentence case. Name the thing in weight 600 ("Moved **report.pdf** to Trash").
4. Action (optional, one): 13px weight 600 `accent-text`, 32px tall, 8px padding, `primary` radius.
5. Divider and close button: a 1px line, then a small ghost Icon button with `x`.
6. Timer: a 2px `accent` line along the bottom that shrinks while the toast waits.

## States
- **Action hover:** `surface-hover` behind the action. **Action focus:** `focus-width` `focus-ring` inside its edge.
- **Hover over the toast:** the timer pauses.

## Behavior
- Stays 5 seconds, or 8 seconds when it has an action. Hovering or focusing it pauses the timer.
- Esc closes it when it has focus. Super+Z runs its action while it is shown.
- Undo restores exactly what was changed and then shows "Restored".

## Accessibility
- Announced politely (`role=status`). The action is reachable with Tab; the toast never takes focus on its own.

## Where it lives
New. The shell has no toast yet; build it next to `Notifications.qml` as its own overlay window.

## What a build provides
`message` · `icon` · `tone` · `action` (label, run) · `timeout` · `onClose`.
