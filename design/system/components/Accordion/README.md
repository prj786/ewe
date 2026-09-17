# Accordion

An accordion hides sections of content until people open them. Ewe uses it for “Advanced” options and troubleshooting.

## When to use
- Use it for options most people never need, so pages stay short.
- Don't hide settings people change often.

## Anatomy
1. Container: `surface-raised`, 1px `border-subtle`, `rounded` radius. Items are divided by 1px `border-subtle` lines.
2. Trigger: 40px tall (`control-xl`), 12px side padding, a 16px icon, a 13px weight-500 title, and a `chevron-down` on the right that turns when open.
3. Panel: content with 12px padding at the sides and bottom.

## States
- **Hover:** trigger fill `surface-hover`.
- **Focus:** a 1px `focus-ring` on the trigger's edge.
- **Open:** chevron points up; the panel shows. Several items may be open at once.

## Behavior
- Enter or Space toggles an item. The open state is remembered per page.

## Accessibility
- Each trigger is a button that reports whether it is expanded and controls its panel.

## What a build provides
`items` (title, icon, content, open) · `multiple` · `onToggle`.
