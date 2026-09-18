# Bluetooth pairing

The pairing dialog confirms codes, asks for PINs and grants access when a Bluetooth device connects.

## Placement
- A small Dialog in the center of the focused screen, over `scrim`, holding keyboard input until answered.

## Anatomy
1. Dialog, 378px: a `bluetooth` icon on `accent-subtle` and a title that names the device.
2. Device box: `surface-sunken`, the device's icon, name in weight 600, and its address in Geist Mono.
3. Code box (confirm and display): 56px, `surface-sunken`, 1px `border-strong`, Geist Mono 28px weight 600 with wide spacing.
4. Input (PIN or passkey): a Text field in Geist Mono; passkeys take 6 digits, PINs up to 16 characters.
5. Hint line: 12px `text-secondary`, centered.
6. Buttons: Cancel or Deny (ghost), Pair or Allow (primary).

## Requests
| Request | Title | Content | Buttons |
| --- | --- | --- | --- |
| Confirm | Pair with <device>? | the code, "Check that the same code shows on the device." | Cancel · Pair |
| PIN | Enter the PIN for <device> | PIN field, "Often 0000 or 1234." | Cancel · Pair |
| Passkey | Enter the code shown on <device> | 6-digit field | Cancel · Pair |
| Display | Type this code on <device> | the code with typed digits in `accent-text` and the rest in `text-disabled`; "4 of 6 typed…" | Cancel (full width) |
| Authorize | Allow <device> to connect? | the service it wants | Deny · Allow |

## Behavior
- Enter accepts; Esc denies. A passkey that isn't 1–6 digits shows “Use up to 6 digits” under the field instead of being ignored.

## Accessibility
- An alert dialog; the code is read digit by digit.

## Where it lives
`dotfiles/quickshell/BtPairing.qml` with `BtAgent.qml`. The device box and the passkey error are new.

## What a build provides
`kind` · `device` (name, address, icon) · `code` · `typed` · `service` · `onAccept` · `onReject`.
