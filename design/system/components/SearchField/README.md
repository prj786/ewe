# Search field

A search field filters or finds content: apps in the launcher, pages in Settings, packages in the package manager.

## When to use
- Use it wherever people look something up. Results update as they type.
- Use a Text field for any other text entry.

## Anatomy
1. Box: identical to the Text field.
2. `search` icon, always first, in `text-muted`.
3. Query or placeholder: "Search", or say what is searched ("Search for a city or time zone").
4. Trailing slot: the keyboard shortcut (Kbd) while empty; a clear button (`x`, ghost sm Icon button) once there is text.

## Sizes
| Size | Height | Use |
| --- | --- | --- |
| sm | `control-sm` (24) | Filters inside toolbars and panel headers |
| md (default) | `control-md` (28) | Settings, file and package lists |
| xl | `control-xl` (40) | The launcher. Text is 15px, icon 20px, 12px side padding. |
| 2xl | `control-2xl` (48) | Installer and welcome screens |

## States
| State | Box | Text |
| --- | --- | --- |
| Default | `surface-sunken` fill, 1px `border-strong` | value in `text-primary`, placeholder in `text-muted` |
| Hover | border turns `text-muted` | unchanged |
| Focus | the 1px border turns `focus-ring`; no extra ring | caret in `text-primary` |
| Error | 1px `danger` border | helper text in `danger` with a `circle-alert` icon |
| Disabled | `surface-raised` fill, `border-subtle` | `text-disabled` |
| Read-only | transparent fill, `border-subtle` | `text-primary`, still selectable |

## Behavior
- Esc clears the query; a second Esc closes the surface (launcher, popup).
- Show the shortcut only while the field is empty and not focused, or always in the launcher (Esc).
- With no results, say so below the field and suggest what to try.

## Do and don't
- Do focus the field automatically when the launcher opens.
- Don't add a separate "Search" button; results update as people type.
- Don't make the search field fully rounded; it uses the `primary` radius like every other input.

## Accessibility
- The field has the search role and an accessible name even when the placeholder is visible.
- The number of results is announced as it changes.

## What a build provides
`value` · `placeholder` · `size` · `shortcut` · `onChange` · `onClear` · `disabled`.
