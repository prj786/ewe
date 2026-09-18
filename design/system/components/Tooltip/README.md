# Tooltip

A tooltip is a short label that explains a control when people hover over it or focus it with the keyboard.

## When to use
- Every Icon button gets a tooltip that names its action, plus the shortcut when there is one.
- Use the title-and-description form for bar modules that summarize a state (battery, network).
- Don't put essential information or interactive content in a tooltip; use a popup or the page itself.

## Anatomy
1. Container: `surface-overlay`, 1px `border-subtle`, `slight` radius (4px), `shadow-sm`. Padding is 2px × 8px (4px × 8px for two lines). At most 240px wide.
2. Text: 12px on a 16px line in `text-primary`. In the two-line form the title is weight 500 and the description is `text-secondary`.
3. Shortcut (optional): a Kbd combination, `space-s` after the text.

There is no arrow. The tooltip is placed `space-xs` (4px) from its target, centered on it.

## Behavior
- Appears after 500ms of hover, or right away on keyboard focus. Once one tooltip is showing, neighboring tooltips appear without the delay.
- Disappears when the pointer leaves or focus moves, or with Esc.
- In the bar, tooltips open below a top bar and above a bottom bar, and never cover the target.

## Do and don't
- Do keep the text to a few words, in sentence case, without a period.
- Don't repeat a visible label in a tooltip.

## Accessibility
- The tooltip describes its target; screen readers announce it with the target's name.
- Text contrast is at least 4.5:1 on `surface-overlay` in both themes.

## What a build provides
`label` · `description` · `shortcut` · `placement` · `delay`.
