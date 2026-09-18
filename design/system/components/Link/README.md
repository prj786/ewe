# Link

A link takes people to another page, app or website.

## Anatomy
- `accent-text`, weight 500, no underline at rest. A trailing `arrow-right` for the next page, or `external-link` for a website.
- The quiet form uses `text-secondary` with a `border-strong` underline, for links inside dense text.

## States
- **Hover:** a 1px underline, 3px below the text. **Focus:** 1px `focus-ring`, 1px outside the edge.

## Do and don't
- Do write link text that says where it goes (“Choose a provider”), never “click here”.
- Don't use a link for actions that change something; use a Button.

## Accessibility
- Links that open a browser say so (“opens in browser”).

## What a build provides
`label` · `href` · `external` · `quiet`.
