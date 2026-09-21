# Launcher panel

The launcher panel opens above the dock's sheep button with pinned apps and a quick app search.

## Placement
- Above the sheep button, 12px above the dock, kept 12px from the screen edges. Clicking outside closes it.
- Opening it closes the other dock panels (Places, media, store).

## Anatomy
1. Container: `panel-sm` (360px), `surface-raised`, 1px `border-subtle`, `rounded` radius, `shadow-float`, 12px padding and gap.
2. Search: a Text field with `search`, focused on open. Placeholder "Search apps".
3. Section label: "Pinned", or "Results" while searching (overline style).
4. Grid: 4 columns of Grid app tiles (40px icon, 11px name). Up to 24 results.
5. Pin badge: a 22px circle at the tile's top right, shown on hover; always shown and `accent` on pinned apps while searching.

## States
- Tile hover: `surface-hover`, pin badge visible.
- Pin badge: `surface-overlay` with a `pin` glyph; hover raises it to `text-primary`; pinned is `accent` with `on-accent`.
- No pinned apps: an Empty state, "No pinned apps yet" / "Search for an app and use its pin to keep it here."
- No results: "No apps match “…”" with an "Open Komble" button.

## Behavior
- Enter opens the first result; arrow keys move between tiles; Esc closes.
- Click opens the app or focuses it if it is running; middle-click opens a new window.
- The full launcher (Super+D) is the Launcher card; this panel is the dock's quick version.
- It fades in and out (`durBase`). Dock panels and the launcher never slide.

## Accessibility
- A dialog named “Apps”; tiles are buttons named by app; the pin badge says “Pin Zen” or “Unpin Zen”.

## Where it lives
`dotfiles/quickshell/LauncherPanel.qml` (IPC `launcher`). Pinned apps come from `apps.pinned` in ewe.conf.

## What a build provides
`pinned` · `query` · `results` · `onLaunch` · `onTogglePin`.
