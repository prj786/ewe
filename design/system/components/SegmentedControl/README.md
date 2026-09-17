# Segmented control

A segmented control switches between two to five mutually exclusive options that apply immediately, such as a theme mode or a view.

## When to use
- Use it when every option fits on one line and the choice takes effect right away.
- Use a Select instead when there are more than five options or the labels are long.
- Use Tabs instead when each option shows a different page of content.
- Use the **accent** variant for the one primary filter in a view, such as All, Installed or Updates in the package manager.

## Anatomy
1. Well: `surface-sunken` fill, 1px `border-subtle`, `primary` radius (8px), `space-xxs` (2px) padding and gap.
2. Segments: `secondary` radius (6px), so the inner corners follow the outer ones evenly.
3. Selected segment: `surface-selected` fill, 1px `border-subtle`, `shadow-sm`.
4. Content: a label, an icon, or an icon followed by a label. Keep one style within a control.

## Sizes
| Size | Height | Segment padding | Text | Icon |
| --- | --- | --- | --- | --- |
| sm | `control-sm` (24) | `space-xs` (4) | 12px / 500 | `icon-sm` (14) |
| md (default) | `control-md` (28) | `space-s` (8) | 12px / 500 | `icon-sm` (14) |
| lg | `control-lg` (32) | 12 | 13px / 500 | `icon-md` (16) |

Icon-only segments are square. A full-width control splits its width equally between segments.

## States
- **Default:** label in `text-secondary`.
- **Hover:** label turns `text-primary`; the fill does not change.
- **Selected:** `surface-selected` fill and `text-primary` label. In the accent variant, `accent` fill and `on-accent` label.
- **Focus:** a 1px `focus-ring` drawn on the segment's edge.
- **Disabled:** `text-disabled` label; the segment cannot be selected.

## Do and don't
- Do keep segment labels short and similar in length.
- Do always have exactly one segment selected.
- Don't use a segmented control for actions; use buttons.
- Don't mix icon-only and text-only segments in one control.

## Accessibility
- The control behaves as a radio group: arrow keys move the selection, Tab moves in and out of the control.
- Icon-only segments have accessible names.

## What a build provides
`options` (label, icon, value, disabled) · `value` · `onChange` · `size` · `accent` · `fullWidth`.
