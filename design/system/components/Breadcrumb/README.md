# Breadcrumb

A breadcrumb shows where a page sits inside Settings or Komble and gives a way back up.

## Anatomy
1. Items: 12px in `text-secondary`, 2px × 4px padding, `slight` radius.
2. Separators: 14px `chevron-right` icons in `text-muted`.
3. Current page: last, in `text-primary` weight 500, not clickable.

## States
- **Hover:** `surface-hover` fill and `text-primary`. **Focus:** 1px `focus-ring`.

## Do and don't
- Do use it only when pages go three or more levels deep.
- Don't repeat the page title right under the breadcrumb.

## Accessibility
- A navigation landmark labeled “Breadcrumb”; the current page is marked.

## What a build provides
`items` (label, onClick) · `current`.
