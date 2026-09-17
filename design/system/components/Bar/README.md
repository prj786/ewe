# Bar

The bar runs along the top of every screen: the focused workspace and app on the left, tray, updates, keyboard layout, the Quick settings button and the clock on the right.

## Placement
- One bar per screen, anchored to the top edge and running edge to edge. It reserves its own height, so windows start below it.
- It slides down from above when the session starts. Super+Shift+B hides and shows it; Settings can turn it off.
- Center is empty by default. A plugin placed there stays centered on the screen and hides itself if it would touch the left or right side.

## Anatomy
1. Strip: `bar-height` (48px), `surface-base`, a 1px `border-subtle` line below, 8px side padding. With transparency on, it is Glass (`glass-base` over a `blur-glass` blur).
2. Workspace chip: the focused workspace number, 13px weight 600 `text-primary`, in a 32px `primary` chip with a 16px × 2px `accent` underline. Click opens the Overview.
3. Focused app: its 20px icon and its name (from the app's id, not the window title) in 13px weight 600 `accent-text`. Hidden on a bare desktop.
4. Plugin slots: start (after the app), center, and end (after the tray). Plugins sit in install order.
5. Tray: app icons 20px wide with 2px between them. Single-color icons are tinted `text-secondary`; colored icons keep their colors.
6. Tiling toggle: `layout-grid` while tiling, `app-window` while floating.
7. Updates: `download` in `accent-text` with a count Badge; `check` in `text-muted` when everything is current; a spinning `refresh-cw` while updating.
8. Keyboard layout: two capitals ("US", "GE"), 12px weight 600.
9. Divider: 1px × 16px `border-subtle`, 4px margin on each side.
10. Quick settings button: one pill holding the status indicators, 12px side padding, 8px between glyphs. It opens Quick settings.
11. Divider, then the clock: date and time in 13px weight 600 `text-primary` with tabular numbers, 8px apart ("Thu 17 Sep  04:18 PM", following the locale's 12- or 24-hour setting).

## Status indicators
Each shows only while it applies, always in this order:

| Indicator | Glyph | Color |
| --- | --- | --- |
| Network busy | `loader-circle`, spinning | `accent-text` |
| Keep awake | `eye` | `text-secondary` |
| Casting | `cast` | `accent-text` while streaming |
| SSH tunnel · VPN | `square-terminal` · `shield-check` | `text-secondary` |
| Sync | `refresh-cw` spinning · `cloud-alert` · `cloud-off` | `accent-text` · `danger` · `text-muted` |
| Notifications | `bell` with a count Badge | `accent-text` |
| Mail | `mail` with a count Badge | `text-secondary` |
| Event within the hour | `calendar` | `text-secondary` |
| Phone (KDE Connect) | `smartphone`, a dot when it has unread items, and its battery % | `text-secondary` |
| Wired or Wi-Fi | `ethernet-port` or `wifi` | `text-secondary` |
| Sound | the output's glyph; `volume-x` when muted | `text-secondary`; `text-muted` when muted |
| Microphone in use | `mic` | `accent-text` |
| Bluetooth | `bluetooth`, or `bluetooth-connected` with a device | `text-secondary` |
| Power profile | `leaf` · `scale` · `gauge` | `text-secondary` |
| Battery | level glyph and %, `zap` while charging | `warning` at 20% or less, `danger` at 10% or less |

Settings can hide the tray, tiling, keyboard, sound, mic, network, Bluetooth, power, battery and each plugin. The others show whenever they apply.

## Badges
- Counts use the solid accent Badge (16px), pinned to the glyph's top-right corner: 8px above it and starting 8px before its right edge. Past 9 it reads "9+".
- A 2px ring in the bar's color separates it from the glyph; on Glass the ring is left out.
- A dot (8px) marks "something new" without a number, as on the phone indicator.

## Sizes
| Size | Bar | Modules | Glyphs | Text |
| --- | --- | --- | --- | --- |
| Default | `bar-height` 48px | `control-lg` 32px | `icon-lg` 20px | 13px, 12px for layout and % |
| Large | `bar-height-lg` 64px | `control-xl` 40px | `icon-xl` 24px | 15px, 13px |

## Module states
| State | Look |
| --- | --- |
| Default | glyphs `text-secondary`, no fill |
| Hover | `surface-hover`, `text-primary` |
| Popup open | `surface-pressed`, `text-primary` |
| Focus | 1px `focus-ring` on the edge |
| Needs attention | `accent-text` |
| Problem | `danger` |

## Behavior
- Quick settings button: click opens Quick settings; scrolling changes the volume by 3% and shows the volume popup.
- Updates: click opens Komble's updates (or the store); middle-click checks now.
- Keyboard layout: click switches to the next layout.
- Tray: left-click activates the app (or opens its menu if that is all it has), right-click opens its menu, middle-click activates, scroll passes through.
- Only one popup is open at a time; Esc or a second click closes it.

## Accessibility
- Each module is a button named with its state (“Battery, 72 percent, charging”, “Updates, 12 available”). Indicators that only show while they apply are announced when they appear.

## What a build provides
`screen` · `size` · `opacity` · `visible` · `show` (per-module) · `plugins` (start, center, end) · `onModuleClick`.
