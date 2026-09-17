# Scheme card

A scheme card previews a color scheme so people can compare and pick one. See the Color schemes section for how schemes work.

## Anatomy
1. Card: 192px wide, 8px padding, `surface-raised`, 1px `border-subtle`, `rounded` radius.
2. Preview: a miniature desktop drawn with the scheme's own colors: base, bar, a window with text lines and an accent button, and a popup.
3. Name: 13px weight 500.
4. Dots: three 8px dots for the scheme's accent, success and danger colors.
5. Marker: a `check` when selected, a `lock` for built-in schemes, or an overflow Icon button (duplicate, export, remove) for custom ones.

## States
- **Hover:** `surface-hover`.
- **Selected:** a 2px `accent-text` edge (1px border plus 1px inset).
- **Focus:** 1px `focus-ring`, 1px outside the edge.
- **New scheme:** a dashed `border-strong` preview with a `plus`.

## Behavior
- Clicking applies the scheme to the whole desktop right away.
- The two built-in schemes, Ewe Dark and Ewe Light, always come first and can't be removed.
- Import from a file, generate from the wallpaper, or duplicate a scheme, export it as YAML, edit it and import it again.

## Accessibility
- A radio group of schemes; each is named by its scheme name and variant (“Kanagawa, dark”).

## What a build provides
`scheme` (slug, name, variant, palette) · `builtin` · `selected` · `onSelect` · `onDuplicate` · `onExport` · `onRemove`.
