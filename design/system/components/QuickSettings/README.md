# Quick settings

Quick settings is the control center that opens from the status module: account, toggles, sliders, media and battery.

## Anatomy
1. Panel: 360px wide (`panel-sm`), `surface-raised`, 1px `border-subtle`, `rounded` radius, `shadow-float`, 12px padding and 12px between sections.
2. Header: avatar, name and uptime, then screenshot, settings, lock and power Icon buttons.
3. Tiles: a two-column grid of Quick settings tiles, 8px apart, then a row of small tiles.
4. Sliders: volume and brightness, each with its icon and value.
5. Media: the compact Media player, when something plays.
6. Footer: battery state and a power mode Segmented control (Power saver, Balanced, Performance).

## Detail pages
- Opening a tile's details replaces the content in place: a back button, the feature's switch, a list (networks, devices, outputs) and links to Settings.
- The panel keeps its width; its height follows the content, up to 80% of the screen.

## Behavior
- Opens below the status module, aligned to the right edge, `space-xs` below the bar.
- Esc goes back from a detail page, then closes the panel.

## Accessibility
- A dialog named “Quick settings”; focus starts on the first tile.

## What a build provides
`user` · `tiles` · `smallTiles` · `sliders` · `media` · `battery` · `powerMode` · `detail` · `onClose`.
