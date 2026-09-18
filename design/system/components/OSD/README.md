# On-screen display

The on-screen display confirms hardware keys and quick changes: volume, brightness, microphone, keyboard layout and Caps Lock.

## Anatomy
1. Pill: 48px tall (`control-2xl`), 280px wide, `surface-overlay`, 1px `border-subtle`, `fully-rounded`, `shadow-float`, 16px side padding.
2. Icon: 20px, reflecting the level (`volume-1`, `volume-2`, `volume-x`).
3. Level: a Slider, or a short message (“Georgian”, “Caps Lock on”).
4. Value: Geist Mono 12px on the right: the percentage, “Muted”, or the layout code.

## States
- **Muted / off:** the icon in `danger`, the slider in `text-disabled`.

## Behavior
- Appears 48px above the bottom edge, centered on the focused monitor, for 1.5 seconds after the last change. Repeated presses update it in place.
- Hovering keeps it open and lets people drag the slider.

## Accessibility
- Changes are announced politely (“Volume 64 percent”).

## What a build provides
`kind` (volume, brightness, mic, layout, capslock) · `value` · `muted` · `label` · `timeout`.
