# App shell

The app shell is the window layout shared by Settings, Komble and ewe-sync: a rail on the left and a content pane on the right.

## Anatomy
1. Window: `surface-base`, `rounded` radius, the Hyprland border.
2. Rail: Side navigation, 196px, on the window background.
3. Pane: inset 8px from the window's edges, `surface-raised`, 1px `border-subtle`, `rounded` radius. Lists inside it use `surface-overlay`.
4. Page: a page-title Header bar (16px × 24px padding), then content with 24px side padding and 8px between blocks.

## Layout
- Content is at most 720px wide and left-aligned; wider windows add space on the right.
- Below 720px of window width, the rail collapses to icons.

## Accessibility
- The rail is the navigation landmark, the pane the main landmark. Ctrl+F focuses the page's search, if it has one.

## What a build provides
`app` · `sections` · `current` · `content`.
