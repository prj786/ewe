# Textarea

A textarea is a text field for several lines, such as a description, a note or a bug report.

## When to use
- Use it when the answer may be longer than one line.
- Use a Text field for single-line values.

## Anatomy
1. Label and helper: as in the Text field.
2. Box: the Text field box with `space-s` (8px) padding on all sides. It is at least three lines tall (72px) and people can resize it vertically.
3. Text: 13px on an 18px line, wrapping.
4. Character count (optional): right-aligned in the helper row, tabular numbers ("104 / 500").

## States
| State | Box | Text |
| --- | --- | --- |
| Default | `surface-sunken` fill, 1px `border-strong` | value in `text-primary`, placeholder in `text-muted` |
| Hover | border turns `text-muted` | unchanged |
| Focus | the 1px border turns `focus-ring`; no extra ring | caret in `text-primary` |
| Error | 1px `danger` border | helper text in `danger` with a `circle-alert` icon |
| Disabled | `surface-raised` fill, `border-subtle` | `text-disabled` |
| Read-only | transparent fill, `border-subtle` | `text-primary`, still selectable |

## Do and don't
- Do show a character count only when there is a limit.
- Do let the box grow with its content up to about ten lines, then scroll.
- Don't use a textarea for code or commands; use a monospace editor.

## Accessibility
- Tab moves focus out of the textarea; it never inserts a tab character.
- When a limit is reached, the count turns `danger` and is announced.

## What a build provides
`label` · `value` · `placeholder` · `helper` · `error` · `maxLength` · `minRows` · `maxRows` · `disabled` · `readOnly` · `onChange`.
