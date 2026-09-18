# Power menu

The power menu offers lock, log out, suspend, restart and shut down, with a short countdown for actions that close apps.

## Anatomy
1. A full-screen `scrim` over the wallpaper; the menu always uses the Ewe Dark roles.
2. Account: a 48px avatar, name, machine name and uptime.
3. Buttons: five 96px squares, 12px apart, `surface-raised`, `rounded` radius, a 24px icon and a 13px weight-500 label.
4. Hints: keyboard hints in `caption` below.

## States
- **Hover:** `surface-hover`, `text-primary`.
- **Selected (keyboard):** `surface-hover` with a 2px `focus-ring` edge. Shut down and restart use a 2px `danger` edge and `danger` text instead.

## Confirm
- Log out, restart and shut down start a 10-second countdown with a `danger` progress bar and the number of apps with unsaved changes.
- Cancel is the default button; “Shut down now” skips the wait. Esc cancels.

## Accessibility
- A modal dialog; arrow keys move between buttons, and the countdown is announced every few seconds.

## What a build provides
`user` · `actions` · `selected` · `countdown` · `unsavedApps` · `onAction` · `onCancel`.
