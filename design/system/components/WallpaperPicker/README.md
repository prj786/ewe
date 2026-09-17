# Wallpaper picker

The wallpaper picker shows the current desktop and lets people choose or add a picture.

## Anatomy
1. Preview: the wallpaper at 16:9 with a miniature bar on top, `rounded` radius.
2. Grid: four columns of 16:10 thumbnails, 12px apart, `primary` radius, with the name below in 12px.
3. Selected: a 2px `accent` border with a 2px inner gap, and a 18px `accent` check badge in the top-right corner.
4. Add picture: a dashed `border-strong` tile with a `plus`.
5. Options: a list with Fit, Follow the scheme (take colors from the wallpaper) and a change interval.

## States
- **Hover:** the thumbnail border turns `text-muted`.
- **Selected:** as above; the name turns `text-primary` weight 500.
- **Focus:** 1px `focus-ring`, 1px outside the edge.

## Accessibility
- A radio group of images, each named by its file or title.

## What a build provides
`wallpapers` (name, src) · `value` · `fit` · `followScheme` · `interval` · `onChange` · `onAdd`.
