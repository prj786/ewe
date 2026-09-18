# Places

Places is a small file browser above the dock's folder button: pinned places first, then the current folder.

## Placement
- Above the folder button, 12px above the dock, kept 12px from the screen edges. Esc or the button closes it.

## Anatomy
1. Container: `panel-md` (400px), `surface-raised`, 1px `border-subtle`, `rounded` radius, `shadow-float`, 12px padding.
2. Address row: Back and Home (md ghost Icon buttons), the path in a small field (Geist Mono 12px, `~` for home), and Pin (`pin`, or a selected `star` when this folder is pinned).
3. "Pinned" overline, pinned rows, a divider, then the "Folder" overline and the entries: folders first, then files. Hidden files are left out.
4. Row: 32px, `primary` radius, 20px icon (folders in `accent-text`), 13px name, size in `caption` for files, `chevron-right` on folders. Pinned rows have a small `x` to unpin.

## States
- Row hover `surface-hover`; focus `focus-width` `focus-ring` inside the edge.
- Unpin hover: `danger-subtle` with a `danger` glyph.
- Dragging a row out: the row lifts (`surface-overlay`, `shadow-float`); it drops as a file on any app.
- Dropping files onto Places: the panel gets an `accent` outline; dropped items are pinned.
- Empty folder: "This folder is empty". Back is disabled at `/`.

## Behavior
- Click a folder to open it, a file to open it in its app. Arrow keys move between rows; Enter opens; Backspace goes back.

## Accessibility
- A dialog named “Places”; the list is a tree grid; rows say name, type and size.

## Where it lives
`dotfiles/quickshell/Places.qml` (IPC `places`). Keyboard navigation and the size column are new.

## What a build provides
`path` · `pinned` · `entries` · `onOpen` · `onPin` · `onUnpin` · `onDrop`.
