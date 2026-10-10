# Desktop widgets

Desktop widgets are plugin cards placed on the wallpaper, below windows or kept above them.

## Anatomy
- Widgets draw their own content, on a Glass card by default: `glass-raised`, 1px `glass-border`, `rounded` radius, 12 × 16px padding.
- Content uses the normal type and components: large numbers in light weight, Meters for levels.

## Arrange mode
- Super+Shift+W, or "Arrange widgets" in Settings.
- Each widget gets a dashed 1px `accent` outline 4px outside it and becomes draggable; while dragged the outline is solid and the card lifts (`shadow-float`).
- A row of chips sits 12px above each widget: the name (solid `accent`), "Pinned" (keeps it above windows; `accent-subtle` when on), "Lock" (no dragging; `accent-subtle` when on) and "Hide".
- A Glass hint pill at the bottom: "Drag to move · Pinned stays above windows · Lock stops dragging · Esc Done".

## Outside arrange mode (every widget, always)
- Pointing at a widget shows a hover toolbar inside its top-right corner: a `surface-overlay` pill with a `border-subtle` edge and two `control-sm` buttons — the grip (drag to move; a lock glyph while locked, click unlocks) and the pin (`accent-subtle` with `accent-text` while pinned).
- A press anywhere on the card that the widget's own controls do not take drags it too; the card's edge turns `border-strong` while it is pointed at and movable.
- Pinned = the widget's pin level: above the windows (Top layer) or above everything, fullscreen too (Overlay layer). Unpinned = on the desktop, under the windows (Bottom layer).

## Behavior
- Positions are saved when a drag ends. Esc or the shortcut again leaves arrange mode.

## Accessibility
- In arrange mode, arrow keys move the focused widget by 8px (Shift for 32px).

## Where it lives
`dotfiles/quickshell/DesktopWidgets.qml` (IPC `widgets`). Keyboard moving is new.

## What a build provides
`widgets` (id, name, position, pinned, pin level, locked, visible) · `arranging` · `onMove` · `onPin` · `onLock` · `onHide`.
