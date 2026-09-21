# Launcher

The launcher opens apps, settings pages, files and commands from the keyboard. Super+Space opens it.

## Anatomy
1. Panel: 560px wide (`panel-lg`), `surface-raised`, 1px `border-subtle`, `rounded` + 4px radius, `shadow-float`, centered in the upper third of the screen.
2. Search: the xl Search field (40px, 15px text), borderless inside the panel, with Esc as its hint.
3. Filters: a small Segmented control: All, Apps, Settings, Files, Commands.
4. Results: grouped under `overline` headers. Each result is 48px tall with a 32px icon, a 13px weight-500 title, a `caption` description and a trailing hint.
5. Before typing: a six-column grid of pinned apps (48px icons, `caption` names) and a list of recent files.
6. Footer: keyboard hints on `surface-base`.

## Result states
- **Selected (keyboard):** `surface-hover`; the trailing hint shows the key that runs it.
- **Hover:** a lighter `surface-hover`.
- **Grid selected:** `surface-hover` with a 1px `focus-ring` edge.

## Behavior
- Results update as people type; the first result is selected. Up and Down move, Enter opens, Tab changes the filter, Esc clears and then closes.
- Commands run in a terminal with Ctrl+Enter. Settings results open the exact page.
- Frequently used apps rank higher.
- It fades in and out (`durBase`). Dock panels and the launcher never slide.

## Accessibility
- A dialog with a combobox and a listbox of results; the number of results is announced.

## What a build provides
`query` · `filter` · `results` (kind, icon, title, description, hint) · `pinned` · `recent` · `onRun` · `onClose`.
