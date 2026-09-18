# File drop zone

A file drop zone accepts files that people drop or choose, such as a scheme to import or a wallpaper to add.

## Anatomy
1. Zone: at least 144px tall, 16px padding, `surface-sunken`, 1px dashed `border-strong`, `rounded` radius.
2. Icon (24px, `text-muted`), a 13px weight-500 title, and a `caption` hint with the accepted types and size.
3. Button: a small secondary “Choose file”, for people who don't drag.
4. File rows: each file with an icon, name, a progress bar while importing, or its size once done, and a remove button.

## States
- **Hover:** border `text-muted`.
- **Dragging over:** solid `focus-ring` border and `accent-subtle` fill; the title says what will happen (“Release to import”).
- **Error:** `danger` border on `danger-subtle`, and a title and hint that say why and what to try.

## Accessibility
- The Choose file button is the keyboard path; the zone itself isn't focusable.

## What a build provides
`accept` · `maxSize` · `multiple` · `files` · `onFiles` · `onRemove`.
