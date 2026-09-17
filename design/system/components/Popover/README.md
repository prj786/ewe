# Popover

A popover is a small panel anchored to the control that opened it, for details, a short form or an explanation.

## When to use
- Use it for content that relates to one control and doesn't need the whole screen.
- Use a Menu for lists of actions, a Tooltip for a short label, and a Dialog when people must decide before continuing.

## Anatomy
1. Container: `surface-raised`, 1px `border-subtle`, `rounded` radius, `shadow-float`, 12px padding, 176px to 400px wide.
2. Header (optional): 13px weight 600 title and a close button.
3. Body: any content; text in `text-secondary`.
4. Footer (optional): buttons aligned right.

## Behavior
- Opens `space-xs` from its anchor, below it unless there is no room. It has no arrow.
- Esc and clicking outside close it and return focus to the anchor. A popover with a form closes only with its buttons or Esc.

## Accessibility
- A dialog (non-modal) named by its title; focus moves into it when it opens.

## What a build provides
`anchor` · `placement` · `title` · `content` · `actions` · `dismissible` · `open` · `onClose`.
