# Notification

A notification tells people about something that happened outside what they're looking at: a message, a finished download, low battery. Desktop banners appear in a corner; toasts appear inside an app.

## When to use
- Use a **banner** for events from apps and the system. It also stays in the notification center.
- Use a **critical** banner only for events that need action soon (battery low, disk full). It stays until dismissed.
- Use a **toast** to confirm an action inside an app ("Settings saved"), optionally with Undo.
- Use a Dialog instead when people must decide before continuing.

## Anatomy (banner)
1. Container: `surface-raised`, 1px `border-subtle`, `rounded` radius (10px), `shadow-float`, 360px wide. Padding is 8px on top and 12px on the sides and bottom.
2. Header (24px tall): the app icon (16px), the app name in `caption` weight 500 `text-secondary`, a dot and the time in `text-muted`. A close button (ghost sm Icon button) appears on hover.
3. Title: 13px weight 500 in `text-primary`.
4. Body: 13px in `text-secondary`, at most three lines.
5. Media (optional): a 48px image (`icon-3xl`) on the right with the `primary` radius, such as album art or a photo.
6. Progress (optional): a Progress bar with its value.
7. Actions (optional): up to two sm buttons that share the width, secondary first, then ghost.

## Variants
| Variant | Difference |
| --- | --- |
| Default | as above |
| Critical | 1px `danger` border, and the title in `danger` with a `triangle-alert` icon |
| Progress | a Progress bar instead of actions, updated in place |
| Grouped | when an app sends more than one, the newest shows on top of two 4px layers, with "N more from App" below |

## Toast
- `surface-overlay`, 1px `border-subtle`, `rounded` radius, `shadow-float`, at least 40px tall (`control-xl`).
- A 16px status icon in its tone, a one-line message in 13px `text-primary`, an optional ghost sm action ("Undo", "Retry") and a close button.
- Toasts appear at the bottom center of the app window and disappear after 4 seconds, or 8 with an action. Hovering pauses the timer.

## Behavior
- Banners appear in the top-right corner, below the bar, 8px from the edges and 8px apart. They slide in over 200ms and hide after 5 seconds (critical banners stay).
- Hovering a banner pauses its timer and shows the close button. Clicking the banner opens the app.
- Do not disturb hides banners but keeps notifications in the center. Critical banners still appear.

## Do and don't
- Do write the title as the key fact ("Download complete") and the body as details.
- Don't use critical styling for anything that can wait.
- Don't show more than three banners at once; group the rest.

## Accessibility
- Banners are announced politely; critical banners are announced right away.
- Timers pause while a banner has keyboard focus.

## What a build provides
`app` (name, icon) · `time` · `title` · `body` · `media` · `progress` · `actions` · `urgency` (low, normal, critical) · `group` · `onClose` · `onClick`.
