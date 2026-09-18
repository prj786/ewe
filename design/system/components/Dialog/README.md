# Dialog

A dialog interrupts to ask for a decision or a small amount of input, such as confirming a restart or entering a Wi-Fi password.

## When to use
- Use it for decisions that need attention before continuing, and for short forms (one to three fields).
- Use a Notification or Toast for information that doesn't need a decision, and a full page for longer tasks.

## Anatomy
1. Scrim: `scrim` covers everything behind the dialog.
2. Container: `surface-raised`, 1px `border-subtle`, `rounded` radius (10px), `shadow-float`, `space-md` (16px) padding and `space-md` between sections.
3. Icon (optional): a 32px circle (`icon-2xl`) in `accent-subtle` with a 16px `accent-text` icon, or `danger-subtle` and `danger` for destructive dialogs. It sits 12px before the title.
4. Title: 18px weight 600 (`h3`), phrased as a question or a clear statement.
5. Description: 13px in `text-secondary`, `space-xs` below the title. Explain the consequence.
6. Close button (optional): a ghost sm Icon button (`x`) in the top-right corner.
7. Body (optional): form fields and checkboxes, 12px apart.
8. Footer: buttons aligned right, `space-s` apart, the primary action last. A secondary action that is not about the decision ("Share network") sits on the left.

## Sizes
| Size | Width | Use |
| --- | --- | --- |
| md (default) | 400px | Confirmations |
| lg | 560px | Short forms |

## Variants
- **Confirm:** a primary button with a specific verb ("Restart now"), and a ghost "Cancel" or "Later".
- **Destructive:** a danger icon and a danger button with a specific verb ("Remove"). The description says what will be lost and that it can't be undone.
- **Form:** fields in the body; the primary button stays disabled until the input is valid.

## Behavior
- The dialog opens centered on the active monitor. Focus moves to the first field, or to the primary button when there is no field (the Cancel button for destructive dialogs).
- Enter runs the primary action; Esc and the close button cancel. Clicking the scrim does nothing, so work isn't lost by accident.
- Focus stays inside the dialog until it closes, then returns to where it was.

## Do and don't
- Do label buttons with what they do, never "Yes" and "No" or "OK".
- Don't stack dialogs on top of each other.
- Don't use a dialog for success messages.

## Accessibility
- The container is a modal dialog, named by its title and described by its description.
- Destructive dialogs use the alert dialog role.

## What a build provides
`title` · `description` · `icon` · `tone` (default, danger) · `size` · `body` · `primaryAction` · `secondaryAction` · `extraAction` · `dismissible` · `onClose`.
