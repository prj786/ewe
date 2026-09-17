# Tabs

Tabs switch between pages of related content in the same place, such as Discover, Installed and Updates in Komble.

## When to use
- Use them for two to six views of the same subject.
- Use a Segmented control to change a value or a filter; use Side navigation for the main sections of an app.

## Anatomy
1. Tab list: a 1px `border-subtle` line across the bottom, 16px between tabs.
2. Tab: 32px tall, 13px weight 500, optional 16px icon and a count Badge.
3. Indicator: a 2px `accent` bar under the selected tab, sitting on the bottom line.

## Sizes
| Size | Height | Text | Icon |
| --- | --- | --- | --- |
| md (default) | 32px | 13px | 16px |
| sm | 28px | 12px | 14px |

## States
- **Default:** `text-secondary`. **Hover:** `text-primary`.
- **Selected:** `text-primary` with the accent indicator.
- **Focus:** 1px `focus-ring`, 1px outside the edge, with the `slight` radius.
- **Disabled:** `text-disabled`.

## Behavior
- Left and Right arrows move between tabs; the selected tab changes as focus moves. Ctrl+Tab moves to the next tab from inside the content.

## Accessibility
- A tab list with tabs and tab panels; the selected tab is marked selected.

## What a build provides
`tabs` (label, icon, count, disabled) · `value` · `size` · `onChange`.
