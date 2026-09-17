# Text field

A text field lets people enter or edit a single line of text, such as a device name, a username or a URL.

## When to use
- Use it for short, free-form text.
- Use a Search field for searching, a Number stepper for small numbers, a Textarea for more than one line and a Select when the value comes from a fixed list.

## Anatomy
1. Label (optional but recommended): 12px weight 500 in `text-primary`, `space-xs` above the box. An "Optional" note in italic `text-muted` sits on the right.
2. Box: `primary` radius (8px), 1px border, `space-s` (8px) side padding.
3. Leading icon (optional): `text-muted`, `space-xs` before the text.
4. Value or placeholder: 13px on an 18px line. Placeholders give an example, never the label again.
5. Suffix or trailing action (optional): a unit in `text-muted`, or a small ghost Icon button (clear, show password).
6. Helper text (optional): the `caption` style in `text-muted`, `space-xs` below the box. An error replaces it.

## Sizes
| Size | Height | Side padding | Text | Icon |
| --- | --- | --- | --- | --- |
| sm | `control-sm` (24) | `space-xs` (4) | 12px | `icon-sm` (14) |
| md (default) | `control-md` (28) | `space-s` (8) | 13px | `icon-md` (16) |
| lg | `control-lg` (32) | `space-s` (8) | 13px | `icon-md` (16) |
| xl | `control-xl` (40) | 12 | 15px | `icon-lg` (20) |
| 2xl | `control-2xl` (48) | `space-md` (16) | 15px | `icon-lg` (20) |

Use md in Settings and dialogs, xl in the launcher and 2xl in the installer.

## States
| State | Box | Text |
| --- | --- | --- |
| Default | `surface-sunken` fill, 1px `border-strong` | value in `text-primary`, placeholder in `text-muted` |
| Hover | border turns `text-muted` | unchanged |
| Focus | the 1px border turns `focus-ring`; no extra ring | caret in `text-primary` |
| Error | 1px `danger` border | helper text in `danger` with a `circle-alert` icon |
| Disabled | `surface-raised` fill, `border-subtle` | `text-disabled` |
| Read-only | transparent fill, `border-subtle` | `text-primary`, still selectable |

## Validation
- Validate when the field loses focus, not on every keystroke. Clear the error as soon as the value becomes valid.
- Error messages say what to do: "Use lowercase letters, numbers and dashes only," not "Invalid input."

## Do and don't
- Do keep labels short and in sentence case, without a colon.
- Do size the field to the expected length of the value.
- Don't use the placeholder as the only label.
- Don't disable a field without explaining why in the helper text.

## Accessibility
- The label is linked to the field; the helper and error text are its description.
- The focus border holds at least 3:1 against every surface.

## What a build provides
`label` · `value` · `placeholder` · `helper` · `error` · `optional` · `size` · `leadingIcon` · `suffix` · `trailingAction` · `disabled` · `readOnly` · `onChange`.
