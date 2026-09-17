# Share picker

The share picker lets people choose which display, window or region an app may see.

## Placement
- A large panel centered on the focused screen over `scrim`, at most 880px wide and 80px from the screen edges. Clicking the scrim cancels.

## Anatomy
1. Panel: `surface-raised`, 1px `border-subtle`, `rounded` radius, `shadow-float`, 24px padding, 18px between sections.
2. Title "Share your screen" (18px weight 600) and a line naming the app.
3. "Displays": cards two per row (three when there are more than two screens), each a live 16:9 thumbnail, the display's name and "connector · resolution".
4. "Windows": cards four per row with the app icon, the window title and the app name. Hidden when no windows are open.
5. Footer, above a divider: "Remember for <app>. Don't ask next time." checkbox, "Select a region…" (secondary, `scan`) and Cancel (ghost).

## States
- Card: `surface-sunken`, 1px `border-subtle`. Hover: `surface-hover` and an `accent` border. Focus: `focus-width` `focus-ring` outside the edge.
- Picking a card shares immediately; there is no separate confirm step.
- Region: the picker hides while the region is drawn and comes back if it is cancelled.

## Behavior
- Arrow keys move between cards; Enter shares the focused one; Esc cancels.

## Accessibility
- A dialog named after the app; cards are buttons named “Share Built-in display”, “Share window Ewe design system”.

## Where it lives
`dotfiles/quickshell/SharePicker.qml` (IPC `picker`, used by xdg-desktop-portal-hyprland). Keyboard selection is new.

## What a build provides
`app` · `displays` · `windows` · `remember` · `onPick` (screen, window, region) · `onCancel`.
