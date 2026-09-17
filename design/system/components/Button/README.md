# Button

A button starts an action: installing a package, saving settings or closing a dialog.

## When to use
- Use **primary** for the one main action in a view or dialog. Never place two primary buttons side by side.
- Use **secondary** for other actions of equal weight, such as "Settings" or "Options".
- Use **ghost** for low-emphasis actions like "Cancel", and for buttons inside toolbars and panels.
- Use **danger** only for destructive actions that cannot be undone, such as deleting or uninstalling. Always confirm first.
- For an action shown only as an icon, use **Icon button**.

## Anatomy
1. Container: `primary` radius (8px), 1px border (transparent unless the variant draws one).
2. Leading icon (optional): Lucide, see sizes below.
3. Label: sentence case, one to three words, a verb first ("Install", "Restart now").
4. Trailing icon (optional): usually `chevron-down` for a button that opens a menu.

## Variants
| Variant | Fill | Border | Label |
| --- | --- | --- | --- |
| Primary | `accent` | none | `on-accent` |
| Secondary | `surface-raised` | `border-strong` | `text-primary` |
| Ghost | transparent | none | `text-primary` |
| Danger | `danger` | none | `on-status` |

## Sizes
| Size | Height | Side padding | Text | Icon | Gap |
| --- | --- | --- | --- | --- | --- |
| sm | `control-sm` (24) | `space-s` (8) | 12px / 500 | `icon-sm` (14) | `space-xs` |
| md (default) | `control-md` (28) | 12 (`space-s` + `space-xs`) | 13px / 500 | `icon-md` (16) | `space-xs` |
| lg | `control-lg` (32) | `space-md` (16) | 13px / 500 | `icon-md` (16) | `space-xs` |
| xl | `control-xl` (40) | `space-md` (16) | 15px / 500 | `icon-lg` (20) | `space-s` |
| 2xl | `control-2xl` (48) | 24 (`space-md` + `space-s`) | 15px / 500 | `icon-lg` (20) | `space-s` |

Use md in panels and dialogs, sm in dense toolbars, and xl or 2xl in the installer and the launcher.

## States
- **Hover:** primary uses `accent-hover`; secondary and ghost use `surface-hover`; danger mixes 12% of `text-primary` into `danger`.
- **Pressed:** primary uses `accent-pressed`; secondary and ghost use `surface-pressed`; danger mixes 24%.
- **Focus:** a 1px `focus-ring` outline, 1px outside the button. Shown for keyboard focus only.
- **Disabled:** `surface-raised` fill, `border-subtle` outline, `text-disabled` label. Ghost stays transparent.
- **Loading:** a small Spinner replaces the leading icon, the label changes to the ongoing action ("Installing…"), and the button ignores clicks. Keep the width stable.

## Do and don't
- Do keep one primary button per view.
- Do put the primary button on the right in dialog footers, with "Cancel" (ghost) to its left.
- Don't use a primary button for destructive actions; use danger.
- Don't write labels in all capitals or end them with punctuation.
- Don't stretch buttons to full width, except in the installer and narrow popups.

## Accessibility
- Minimum target is 24×24px (`control-sm`).
- Label contrast is at least 4.5:1 in every variant and theme.
- Enter and Space activate the button. A loading button reports its busy state to assistive technology.

## What a build provides
`variant` (primary, secondary, ghost, danger) · `size` (sm, md, lg, xl, 2xl) · `icon` / `trailingIcon` (Lucide name) · `label` · `disabled` · `loading` · `onClick`.
