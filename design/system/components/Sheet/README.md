# Sheet

A sheet is a tall panel that slides in from the screen edge, for the notification center and other side panels.

## Anatomy
1. Container: 400px wide (`panel-md`), full height minus `window-gap`, `surface-raised`, 1px `border-subtle`, `rounded` radius, `shadow-float`.
2. Header: 48px tall, 15px weight 600 title, actions and a close button, a 1px line below.
3. Body: 12px padding, scrolls on its own.
4. Footer (optional): buttons aligned right, a 1px line above.

## Behavior
- Slides in from the right edge (the side of the status module) over 200ms; closes with Esc, the close button or a click outside.
- Doesn't dim the desktop, so people can keep working beside it.

## Accessibility
- A non-modal dialog named by its title. Focus moves to the first control and returns to the opener on close.

## What a build provides
`title` · `side` · `actions` · `content` · `footer` · `open` · `onClose`.
