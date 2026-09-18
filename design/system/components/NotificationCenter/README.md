# Notification center

The notification center lists every notification, grouped by app and day, with Do not disturb.

## Anatomy
1. A Sheet (400px) that opens from the bell in the bar.
2. Header: “Notifications” and a ghost “Clear all”.
3. Do not disturb row: a `bell-off` icon, the label and a Switch.
4. Day groups: “Today”, “Yesterday”, “Earlier” as labeled Dividers.
5. Notifications: flat cards (`surface-overlay`, no shadow). Several from one app stack, with “N more from App” below.
6. Empty state: the compact Empty state; during Do not disturb it explains that banners are hidden.

## Behavior
- Clicking a stack expands it. Dismissing a notification slides it out and offers Undo in a Toast.
- Opening the center marks everything as read and removes the bell's dot.

## Accessibility
- A dialog; notifications are a list, each announcing its app, time and title.

## What a build provides
`notifications` · `groups` · `dnd` · `onDismiss` · `onClearAll` · `onDndChange`.
