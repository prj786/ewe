# Authentication prompt

The authentication prompt asks for the user's password when an app needs administrator rights.

## Placement
- A small Dialog in the center of the focused screen, over `scrim`. It takes all keyboard input until answered. Clicking the scrim does nothing.

## Anatomy
1. Dialog, 378px wide: a `shield-check` icon on `accent-subtle`, the title "Authentication required" and a line explaining why.
2. Requester: a `surface-sunken` box with the app's name, what it wants, and the action id in Geist Mono.
3. Password field: labelled "Password for <user>", with a `lock-keyhole` icon; focused on open. Shows the text only if the system asks for a visible answer.
4. Buttons: Cancel (ghost) and Authenticate (primary).

## States
| State | Field | Helper | Authenticate |
| --- | --- | --- | --- |
| Asking | focused | none | enabled |
| Checking | disabled, Spinner at the end | "Checking…" | disabled |
| Wrong password | `danger` border, cleared | "Wrong password. Try again." in `danger` | enabled |
| Extra message from the system | as asked | the message in `text-muted` | enabled |

## Behavior
- Enter submits; Esc cancels. The prompt closes when the request finishes either way.

## Accessibility
- An alert dialog; the requester and reason are its description, so screen readers read who is asking before the field.

## Where it lives
`dotfiles/quickshell/Auth.qml` (polkit agent). The requester box is new.

## What a build provides
`message` · `requester` · `actionId` · `user` · `prompt` · `echo` · `error` · `onSubmit` · `onCancel`.
