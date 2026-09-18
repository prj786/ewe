# Ewe design system

Ewe is the design language of the Ewe desktop, built on the Hyprland compositor with a Quickshell (QML) shell. It covers every surface of the desktop: the bar, panels, notifications, launcher, settings and installer. The same task looks and behaves the same way wherever it appears.

The goal is a sense of calm. Ewe pairs a warm gold with near-black, keeps layouts compact and readable, and avoids anything glossy or loud.

## Principles

- **Modern, but restrained.** Contemporary without following trends. Flat, solid colors; no gloss, glow or heavy shadows.
- **Symmetric.** Layout, padding and spacing mirror across opposite sides. A control with 4px on the left has 4px on the right.
- **Consistent.** An action looks and behaves the same everywhere. The volume slider in the bar popup and the one in Settings are the same component.
- **Softly rounded.** Corners are gentle. Full pills are reserved for badges and tags.
- **Two line weights.** Borders are 1px (`border-width-1`) or 2px (`border-width-2`), nothing else.
- **Readable first, then compact.** Legible text comes before density; density never costs comfort.

## UX values

Ewe treats Jakob Nielsen's 10 usability heuristics (Nielsen Norman Group) as its core UX values. Every component and screen is checked against them.

1. **Visibility of system status.** Every action answers within 100ms with a hover, pressed or selected state. Waits over 300ms show a Spinner; tasks with a known length show a Progress bar. The bar always shows network, audio, battery and pending updates, and hardware keys show a volume or brightness popup.
2. **Match between the system and the real world.** Use the words people use: "Wi-Fi", "Restart", "Updates", never command or service names. Show app names before package names, sizes in MB and GB, and times in minutes. Pick Lucide icons whose metaphor is familiar.
3. **User control and freedom.** Esc closes every menu, popup and dialog. Every dialog has a way out ("Cancel", "Later"), and clicking the `scrim` never throws work away. Reversible actions (moving to trash, removing a notification) offer Undo in a Toast instead of asking first.
4. **Consistency and standards.** One component per job, used the same way everywhere. Follow Linux desktop conventions: Super opens the launcher, Ctrl+C copies, the primary action sits on the right. One icon means one thing, and all labels are in sentence case.
5. **Error prevention.** State limits before people type (the helper text says "0 to 32 px"). Keep a primary button disabled until its input is valid. Confirm irreversible actions with a danger Dialog that names what will be lost.
6. **Recognition rather than recall.** Show current values in Select triggers and settings rows. Show shortcuts in Tooltips and Menus with Kbd. The launcher lists recent and frequent apps before anyone types, and placeholders show an example value.
7. **Flexibility and efficiency of use.** Everything works from the keyboard. The launcher opens apps, settings pages and commands. Shortcuts are always shown, never required, and the bar and controls offer larger sizes (`bar-height-lg`, `control-xl`) for people who want more room.
8. **Aesthetic and minimalist design.** One primary action per view. Surfaces are flat (`shadow-none`), gradients are slight, and rarely used options sit behind an "Advanced" section instead of cluttering the page.
9. **Help users recognize, diagnose and recover from errors.** Errors say what happened and what to do next, in plain words: "Disk is full. Free up 2.1 GB and try again." Error codes go in a details section, never the headline. Errors use `danger` with an icon, and offer a way to recover ("Retry", "Open settings").
10. **Help and documentation.** Explain settings in their description line, right where they are. Empty states say what to do next. Tooltips name every icon-only control, and longer topics link to local help that works offline.

## Color

- `ewellow` (#eeb407) is the brand hue, a gold that sits between yellow and orange without leaning into either, and the default accent. Every other color steps from it: the `ewellow-*` scale and the warm `neutral-*` greys tinted toward it.
- People can choose their own accent in ewe.conf. The `accent` roles and the `ewellow-*` ramp are then generated from their pick, and `on-accent` switches between black and white to keep 4.5:1. `ewellow` itself stays the brand color for the logo, installer and wallpapers.
- `black` (#020202) is the deepest ground. Together, gold and near-black define the palette.
- Build interfaces from role tokens, not raw scale steps: `surface-*` for backgrounds, `text-*` for copy, `border-*` for lines, and the `accent` set for primary actions and selection.
- Use `accent` sparingly: one primary action per view, the active workspace, on-states. Text and icons on any gold fill use `on-accent`.
- Pair status colors (`success`, `warning`, `danger`, `info`) with an icon or a word; never rely on color alone. `warning` is orange so it is never mistaken for the brand gold.
- Gradients are part of the identity, but they stay slight: two close tones, never a multi-color blend. Use `gradient-ember` for the wallpaper and lock screen, `gradient-night` and `gradient-glow` for panel backgrounds, and `gradient-ewellow` for large accent areas only. Never apply them to text or small controls.
- Ewe ships two built-in schemes: **Ewe Dark**, the default, and **Ewe Light**. Both are accent-led and use the same role tokens, so components never check which scheme is active.
- Schemes are open. People can switch scheme, change the accent, import a palette (Base16/24, Catppuccin, Gogh, a wallpaper) or write their own. Every scheme is a Base24 palette plus an accent, and the generator derives all role tokens from it while keeping the contrast rules below. See **Color schemes** for the model.

## Typography

- Set interface text in Geist and code in Geist Mono. Both ship as variable fonts (weights 100–900) with matching italics.
- Geist has no Georgian glyphs, so both stacks fall back to Noto Sans Georgian. Install it alongside Geist on every system.
- `body` (13px) is the default. Use `label` for controls and `caption` for timestamps and helper text; use `body-lg` for longer reading text.
- Headings run `h1` (28px) to `h4` (15px). The `display` styles are for large moments only: `display-xl` (64px) for the lock screen clock, `display-lg` (48px) and `display` (36px) for welcome screens and page headers. Use `overline` for small capitalized group headers.
- Italic is for secondary emphasis (file names, hints, pending states) through the `*-italic` styles. Never set whole paragraphs in italic.
- Use `mono-numeric` for values that change in place (clock, battery, network) so digits do not shift.
- Build custom text from the scale tokens (`font-size-*`, `line-height-*`, `font-weight-*`, `tracking-*`), always pairing a size with the line height of the same step.
- Interface text uses `font-weight-regular`, `font-weight-medium` and `font-weight-semibold`. Headings use semibold. `font-weight-bold` and heavier are for branding and artwork only; hierarchy comes from size and color, not heavy type.

## Layout and components

- Icons come from Lucide (the core set is in the Icons group; the shell and apps draw them from a Lucide subset font), sized with `icon-sm` to `icon-xl` in the interface. App icons use `icon-xl` to `icon-4xl`.
- Form controls (inputs, switches, buttons, checkboxes) use the `primary` radius (8px); panels, popups and cards use `rounded` (10px).
- Padding inside controls is 2–4px (`space-xxs`, `space-xs`). Panels use `space-s`; groups and sections are separated with `space-md` and above.
- Control heights follow `control-sm` to `control-lg` in panels and dialogs; `control-xl` and `control-2xl` are for the launcher and installer.
- The bar runs edge to edge along the top: the workspace chip and the focused app on the left, then tray, updates, keyboard layout, the Quick settings button and the clock on the right. The dock floats at the bottom of the main screen with the launchers and one group per workspace. Keep that placement; restyle, don't rearrange.
- The bar is `bar-height` (48px) by default, or `bar-height-lg` (64px) for a roomier layout. Size bar modules and their icons to match: `control-lg` with `icon-lg` in the 48px bar, `control-xl` with `icon-xl` in the 64px bar.
- Separate surfaces with color and a `border-subtle` outline. The logo is the sheep line art in the Logos group; never redraw or recolor it. Shadows are short and tight: `shadow-sm` for tooltips, `shadow-float` for layers that float above other windows.
- Dialogs sit on `scrim`. Menus and tooltips use `surface-overlay`; panels, popups, dialogs and notifications use `surface-raised`.
- Each component in this system is a design spec: its variants, sizes, states and the exact tokens it uses. Implementations, such as the QML components of the shell, follow these specs; behavior and accessibility come from headless primitives, appearance from Ewe.
- Side panels (quick settings, notification center) are `panel-sm` (360px) or `panel-md` (400px) wide; the launcher and wide popups use `panel-lg` (560px). Tiled windows keep `window-gap` (8px) between each other and the screen edge.
- The lock screen and the power menu always use Ewe Dark roles, whatever scheme is active, so they read the same over any wallpaper.
- Components come in four groups: **Core** (buttons, badges, icons, type), **Forms and feedback** (inputs, selects, dialogs, notifications), **Content and navigation** (cards, lists, tabs, tables, pickers) and **Shell and apps** (bar, dock, glass, overview, launcher, places, quick settings, agenda, toasts, prompts, share picker, welcome, widgets, lock screen, screensaver, window, app pages), plus **Foundations** (look presets, accessibility modes).
- Pressed rows and buttons use `surface-pressed`. The selected item inside a `surface-sunken` well (a segmented control, a switch) uses `surface-selected`.

## Look presets

The ewe.conf `corner`, `density` and `stroke` settings stay available to people who want a different feel. The Ewe look is the default of each:

| Setting | Ewe default | What it gives |
| --- | --- | --- |
| `corner` | medium | `primary` (8px) for controls, `rounded` (10px) for panels, `fully-rounded` only for badges, tags and switches. Also none, small, large. |
| `density` | comfortable | `control-md` (28px) controls and rows. Compact is 24px, roomy 32px. |
| `stroke` | thin | a 1px outline on controls, cards and panels (`border-width-1`). Also none and thick. |

Components are specified at these defaults. A preset is a remap of a few tokens; it changes radii, heights and outlines, never colors or type. The Look presets card has every value.

## Motion

Motion confirms, it never decorates. Nothing bounces or overshoots.

| Name | Duration | Easing | Used for |
| --- | --- | --- | --- |
| fast | 150ms | ease-out (OutCubic) | hover, pressed, focus and other color changes; menus and toasts closing |
| base | 200ms | ease-out (OutCubic) | panels, popups, the launcher and toasts opening: a fade plus a 4px slide from their edge; the dock hiding |
| slow | 250ms | ease-in-out (InOutCubic) | workspace switches (a full-width slide), the Overview zoom, Welcome |
| dim | 1500ms | linear | the screen dimming before it locks |

- These are the Normal speed. The animation speed setting divides them (Fast halves them, Slow makes them about 1.7× longer); Off makes them 0.
- Reduce motion turns slides and zooms into fades at `fast`. Motion can't be a design token here, so implementations define these four values once, next to the tokens.

## Layers

The shell draws its surfaces on layer-shell layers, so stacking is always the same:

| Layer | Surfaces |
| --- | --- |
| background | Wallpaper |
| bottom | Desktop widgets |
| top | Bar, dock (the dock moves to overlay while the Overview is open) |
| overlay | Popups, menus, launcher, quick settings, notification center, notifications, OSD |
| overlay (exclusive) | Lock screen, power menu |

Within the overlay layer, OSD sits above notifications, and notifications above popups.

## Transparency

People can make the shell translucent. Ewe treats it as a first-class look, called **Glass**, not an afterthought:

- The bar opacity setting (0–100, default 100) sets the fill of the bar, the dock and the lock-screen card; between 10 and 99 the wallpaper behind is blurred (`blur-glass`). The Glass preset is 80 (`opacity-glass`).
- App blur puts every window at `opacity-app` (85%); window transparency puts unfocused windows at `opacity-inactive` (97%).
- Only fills turn translucent. Text, glyphs, badges and accent fills stay solid, and panels, menus and dialogs always stay solid.
- A glass surface remaps its roles (`glass-base`, `glass-raised`, `glass-border`, `glass-hover`, `glass-pressed`, `glass-accent`), so components work unchanged. From 80% up, text keeps 4.5:1 over any wallpaper in both schemes; below it, Settings warns but doesn't block. The Glass card has the full rules.

## Writing

Ewe writes in plain, calm, US English, in sentence case. The Writing guide has the voice, word list, formats and the rules for Georgian.

## Accessibility

- Ewe targets WCAG 2.2 AA in both themes. Text holds at least 4.5:1 against the surfaces its token is meant for. Control borders, focus rings and meaningful icons hold at least 3:1.
- Focus indicators are clear but understated: a solid 1px `focus-ring`, never a glow. Buttons and other controls draw it 1px outside their edge; text fields and other boxed inputs turn their own border `focus-ring`.
- Every interactive element is reachable and operable by keyboard.
- Accessibility modes (reduce motion, reduce transparency, increase contrast, text size) are role remaps that work with every scheme and preset. See the Accessibility modes card.
- Everything is drawn on whole pixels at 100% and must stay centered at fractional display scales: center text on its cap height, not on the font's line box.

## Implementing this system

The shell and the three apps are updated from this system, not the other way round. The Implementation guide says what to read first, which files change, how every token maps to QML and CSS, and how to check the result.
