# Glass

Glass is how Ewe makes the bar, the dock and the lock-screen card translucent, and how windows fade when transparency is on.

## Settings
| Setting | Range | Default | Effect |
| --- | --- | --- | --- |
| Bar opacity | 0–100 | 100 | The fill of the bar, the dock and the lock-screen card. Between 10 and 99 the wallpaper behind is blurred. The Glass preset sets 80. |
| App blur | on / off | off | Every window at `opacity-app` (85%) with the blur behind; fullscreen windows stay solid. |
| Window transparency | on / off | off | Unfocused windows at `opacity-inactive` (97%). |

## What turns translucent
- Only the fill. Text, glyphs, badges, app icons and the accent fills stay solid.
- Glass surfaces keep their outline (as `glass-border`) so their edge reads over any wallpaper, and keep `shadow-float` (the dock) or the line below (the bar).
- Panels, popups, menus, notifications and dialogs stay solid. They sit over windows, where a see-through fill would only add noise.

## Roles inside glass
A glass surface remaps the roles its content uses, so components need no glass variants:

| Role | Becomes | Why |
| --- | --- | --- |
| surface fill | `glass-base` (bar) or `glass-raised` (dock, lock card) | the surface at 80%, followed by the setting |
| `surface-hover` · `surface-pressed` | `glass-hover` · `glass-pressed` | tint the glass instead of covering it |
| `border-subtle` | `glass-border` | visible on light and dark wallpapers |
| `accent-text` | `glass-accent` | a deeper gold in Ewe Light, so accent text keeps 4.5:1 |
| `text-muted` | `text-secondary` | muted text can't hold 4.5:1 over a bright wallpaper |

Status colors on glass are used for glyphs only, never for text.

## Contrast
- From 80% up, `text-primary`, `text-secondary` and `glass-accent` hold 4.5:1, and status glyphs 3:1, over any wallpaper (checked against white, black, gold and mid-grey) in both built-in schemes. Custom schemes get the same check.
- Below 80%, the Settings slider shows a note: “Text can be hard to read on bright wallpapers.” Nothing is blocked.
- Where blur is unavailable (virtual machines, some NVIDIA setups), the fill is still translucent but sharp; the note suggests 90% or more.

## Blur
- `blur-glass` (about 24px): Hyprland blur size 6, 3 passes, with slight noise, applied to the bar and dock layers only.
- The layers' transparent shadow margin is not blurred.
- Blur turns on only when something needs it (bar opacity 10–99, or app blur).

## Do and don't
- Do keep the whole surface on the same opacity; never mix a solid module into a glass bar.
- Don't put glass on panels or menus, and don't lower opacity to make something look disabled.
- Don't add color to the glass. The wallpaper already does that.

## What a build provides
`barOpacity` (0–100) · `appBlur` · `windowTransparency` · `blurAvailable`.
