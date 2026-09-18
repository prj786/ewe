# Implementation guide

This guide is for whoever updates the Ewe repositories to match this design system, including an AI coding session that has only this system to go on. Read it before touching code.

## Ground rules

1. **This system is the source of truth for how things look.** Where a card and the code disagree on color, size, spacing, type, radius, outline or motion, the card wins.
2. **The code is the source of truth for what things do.** Keep every feature, module, shortcut, IPC command and placement that exists today. Change behavior only where a card says so in its "Where it lives" section (marked "new").
3. **Use tokens, never raw values.** Every value in QML and CSS comes from a token (or the motion table in the README). If something needs a value that has no token, stop and add the token here first.
4. **Schemes, presets and modes are remaps.** Components never check which scheme, preset or mode is active; they read roles.
5. **Don't remove anything without asking.** If a card seems to drop a feature, it's an omission in the card, not a request.
6. **Work in the phases below, one commit (or PR) per phase,** and check each phase before the next.

## What to read, in order

1. The README: principles, UX values, color, type, layout, look presets, motion, layers, transparency, accessibility.
2. `tokens.json`: every token with its usage note. The tables below map each one to CSS and QML.
3. Color schemes: how the two built-in schemes and user schemes produce the role tokens.
4. The component cards for the files you are changing (table below): each has a preview (what it looks like in every state) and a README (anatomy, states, behavior, accessibility, where it lives).
5. `components/bundle.css`: the reference CSS for every component. The `ewe-*` rules are production-ready CSS; the `ds-*` rules only lay out the previews.
6. Writing, for every string you touch.
7. Migration: the table from today's Fluent token names to Ewe names.

## Repositories

| Repo | What changes |
| --- | --- |
| `prj786/ewe` | `bin/ewe-theme` and `bin/ewe-conf` (token generation, settings keys), `design/tokens.css` and `design/components.css` (the files copied into the apps), `dotfiles/quickshell/*.qml` (the shell), `dotfiles/hypr/hyprland.lua` (gaps, borders, blur), fonts, tests. |
| `prj786/ewe-settings` | `src/tokens.css` and `src/components.css` (copies), the Svelte wrappers in `src/lib/components/ui`, the Appearance page (schemes, accent, look presets, Glass) and a new Accessibility page. |
| `prj786/komble-arch` | The two CSS copies and its Svelte components (App card, hero, lists, update rows). |
| `prj786/ewe-sync` | The two CSS copies and its Svelte components. |

## Work plan

### Phase 1: tokens and generator
- `bin/ewe-theme` emits the Ewe token set for the active scheme: every token in the tables below, with color roles derived as Color schemes describes, the accent ramp from the chosen accent, `on-accent` by contrast, the `glass-*` roles, opacity and blur.
- Built-in schemes `ewe-dark` (default) and `ewe-light` are ordinary scheme entries marked `builtin` (the Schemes asset group has both as YAML and JSON). User and imported schemes go through the same derivation and the same contrast guarantees.
- Scheme files stay Base24 YAML and the `ewe-theme scheme` commands stay as they are. Extend them for the new keys: `slug`, `builtin` (refuse `set` and `remove` on built-in schemes), `semantic` and `overrides` (import, export, and `scheme set overrides.<role> <hex>`), and record which roles the generator adjusted so `scheme show` and Settings can list them.
- Look presets and accessibility modes are applied by the generator as remaps (Look presets and Accessibility modes cards).
- Keep emitting today's Fluent names as aliases of the Ewe names (Migration) until Phase 5 is finished, then delete them.
- Output: `theme-tokens.json` for QML and `design/tokens.css` for the apps. Update `tests/ewe-theme-test.sh` and `design/check-spec.sh` to the new names and values.
- **Check:** both built-in schemes, a Catppuccin import and a wallpaper scheme each pass the contrast rules (text 4.5:1, borders and focus 3:1; glass text at 80% over white and black).

### Phase 2: fonts and icons
- Ship Geist and Geist Mono (variable, with italics; OFL) and Noto Sans Georgian. `fontSans` = "Geist", "Noto Sans Georgian"; `fontMono` = "Geist Mono", "Noto Sans Georgian". Lucide stays the icon font.
- **Check:** Georgian strings render and fit; digits are tabular where the cards say so.

### Phase 3: Theme.qml
- Add one property per token, named as in the QML column below, read from `theme-tokens.json`, plus `type.<style>` objects for the type styles and the four motion values.
- Point every existing property at its new value (table "Theme.qml today"), so the shell keeps working, then move components to the new names in Phase 4 and delete the old ones.
- **Check:** the shell starts and looks consistent in both schemes before any component is restyled.

### Phase 4: shell components
- Restyle one file at a time using the cards in "Shell files and their cards". Keep placement and features; add what the cards mark as new (Toast, keyboard navigation in Places and Share picker, requester box in the authentication prompt, the passkey error, accessibility modes).
- Glass: when bar opacity is below 100, the bar, dock and lock card use the glass roles and Hyprland blurs their layers (Glass card).
- **Check:** screenshot each surface in both schemes, at Glass 80%, with Increase contrast on, and at text size 130%; compare with the card previews.

### Phase 5: app CSS and components
- Rewrite `design/components.css` from the `ewe-*` rules in `components/bundle.css` (they use only tokens). Copy it and `design/tokens.css` into the three apps; `design/check-tokens.sh` must pass.
- Update each app's Svelte wrappers to use the Ewe classes and states; shadcn-svelte and bits-ui stay for behavior only.
- Settings: Appearance gets Scheme cards with Import (a Sheet), Export, Duplicate and Remove, the Accent picker, Look presets and the bar opacity slider with the Glass preset; a new Accessibility page has the four modes. There is no scheme editor: people edit YAML files and import them.
- **Check:** each app in both schemes; keyboard focus visible everywhere.

### Phase 6: clean-up
- Remove the Fluent aliases, `Sheen.qml`, OutBack easings and any raw color left in QML or CSS.
- **Check:** grep for `#` colors and pixel literals in QML and app CSS; the only ones left are in the token generator.

## Tokens: CSS and QML names

- CSS custom properties are the token names: `--surface-raised`, `--control-md`. Type styles are classes: `.body`, `.label`.
- QML properties on `Theme` are the token names in camelCase: `surfaceRaised`, `controlMd`, `fontSizeMd`, `glassBase`, `opacityGlass`. Radius tokens get a `radius` prefix: `radiusPrimary`, `radiusRounded`, `radiusFull`.
- Type styles in QML: `Theme.type.<style>` with `size`, `lineHeight`, `weight`, `family`, `italic` and `tracking`. Styles: `display-xl`, `display-lg`, `display`, `h1`, `h2`, `h3`, `h4`, `h4-italic`, `body-lg`, `body`, `body-strong`, `body-italic`, `body-strong-italic`, `label`, `label-italic`, `caption`, `caption-italic`, `overline`, `mono`, `mono-strong`, `mono-italic`, `mono-numeric`.
- Motion (README): `durFast` 150, `durBase` 200, `durSlow` 250, `durDim` 1500, multiplied by the animation speed.

### Color (Ewe Dark / Ewe Light)

| Token | CSS | QML (`Theme.`) | Value |
| --- | --- | --- | --- |
| `ewellow` | `--ewellow` | `ewellow` | #eeb407 / #eeb407 |
| `black` | `--black` | `black` | #020202 / #020202 |
| `ewellow-50` | `--ewellow-50` | `ewellow50` | #fff6e4 / #fff6e4 |
| `ewellow-100` | `--ewellow-100` | `ewellow100` | #ffedc6 / #ffedc6 |
| `ewellow-200` | `--ewellow-200` | `ewellow200` | #ffdf9a / #ffdf9a |
| `ewellow-300` | `--ewellow-300` | `ewellow300` | #fdcf64 / #fdcf64 |
| `ewellow-400` | `--ewellow-400` | `ewellow400` | #f8c23a / #f8c23a |
| `ewellow-500` | `--ewellow-500` | `ewellow500` | {ewellow} / {ewellow} |
| `ewellow-600` | `--ewellow-600` | `ewellow600` | #ce9707 / #ce9707 |
| `ewellow-700` | `--ewellow-700` | `ewellow700` | #a77607 / #a77607 |
| `ewellow-800` | `--ewellow-800` | `ewellow800` | #805708 / #805708 |
| `ewellow-900` | `--ewellow-900` | `ewellow900` | #5a3b09 / #5a3b09 |
| `ewellow-950` | `--ewellow-950` | `ewellow950` | #352206 / #352206 |
| `neutral-0` | `--neutral-0` | `neutral0` | #fefdfc / #fefdfc |
| `neutral-50` | `--neutral-50` | `neutral50` | #faf9f6 / #faf9f6 |
| `neutral-100` | `--neutral-100` | `neutral100` | #f4f2ee / #f4f2ee |
| `neutral-200` | `--neutral-200` | `neutral200` | #e9e6e0 / #e9e6e0 |
| `neutral-300` | `--neutral-300` | `neutral300` | #d5d2cb / #d5d2cb |
| `neutral-400` | `--neutral-400` | `neutral400` | #a8a49d / #a8a49d |
| `neutral-500` | `--neutral-500` | `neutral500` | #7f7b75 / #7f7b75 |
| `neutral-600` | `--neutral-600` | `neutral600` | #5d5a55 / #5d5a55 |
| `neutral-700` | `--neutral-700` | `neutral700` | #423f3a / #423f3a |
| `neutral-800` | `--neutral-800` | `neutral800` | #2c2a26 / #2c2a26 |
| `neutral-850` | `--neutral-850` | `neutral850` | #201e1a / #201e1a |
| `neutral-900` | `--neutral-900` | `neutral900` | #151411 / #151411 |
| `neutral-950` | `--neutral-950` | `neutral950` | #0b0a08 / #0b0a08 |
| `surface-base` | `--surface-base` | `surfaceBase` | {neutral-950} / {neutral-100} |
| `surface-raised` | `--surface-raised` | `surfaceRaised` | {neutral-900} / {neutral-50} |
| `surface-overlay` | `--surface-overlay` | `surfaceOverlay` | {neutral-850} / {neutral-0} |
| `surface-sunken` | `--surface-sunken` | `surfaceSunken` | {black} / {neutral-200} |
| `surface-hover` | `--surface-hover` | `surfaceHover` | {neutral-800} / {neutral-200} |
| `surface-pressed` | `--surface-pressed` | `surfacePressed` | {neutral-700} / {neutral-300} |
| `surface-selected` | `--surface-selected` | `surfaceSelected` | {neutral-800} / {neutral-0} |
| `scrim` | `--scrim` | `scrim` | rgba(2, 2, 2, 0.64) / rgba(20, 16, 8, 0.32) |
| `glass-base` | `--glass-base` | `glassBase` | rgba(11, 10, 8, 0.8) / rgba(244, 242, 238, 0.8) |
| `glass-raised` | `--glass-raised` | `glassRaised` | rgba(21, 20, 17, 0.8) / rgba(250, 249, 246, 0.8) |
| `glass-border` | `--glass-border` | `glassBorder` | rgba(254, 253, 252, 0.1) / rgba(11, 10, 8, 0.1) |
| `glass-hover` | `--glass-hover` | `glassHover` | rgba(254, 253, 252, 0.08) / rgba(11, 10, 8, 0.06) |
| `glass-pressed` | `--glass-pressed` | `glassPressed` | rgba(254, 253, 252, 0.14) / rgba(11, 10, 8, 0.12) |
| `glass-accent` | `--glass-accent` | `glassAccent` | {ewellow-400} / {ewellow-900} |
| `border-subtle` | `--border-subtle` | `borderSubtle` | {neutral-800} / {neutral-300} |
| `border-strong` | `--border-strong` | `borderStrong` | {neutral-500} / {neutral-500} |
| `text-primary` | `--text-primary` | `textPrimary` | {neutral-50} / {neutral-950} |
| `text-secondary` | `--text-secondary` | `textSecondary` | {neutral-300} / {neutral-700} |
| `text-muted` | `--text-muted` | `textMuted` | {neutral-400} / {neutral-600} |
| `text-disabled` | `--text-disabled` | `textDisabled` | {neutral-600} / {neutral-400} |
| `accent` | `--accent` | `accent` | {ewellow} / {ewellow} |
| `accent-hover` | `--accent-hover` | `accentHover` | {ewellow-400} / {ewellow-600} |
| `accent-pressed` | `--accent-pressed` | `accentPressed` | {ewellow-600} / {ewellow-700} |
| `on-accent` | `--on-accent` | `onAccent` | {black} / {black} |
| `accent-subtle` | `--accent-subtle` | `accentSubtle` | {ewellow-950} / {ewellow-50} |
| `accent-text` | `--accent-text` | `accentText` | {ewellow-400} / {ewellow-800} |
| `focus-ring` | `--focus-ring` | `focusRing` | {ewellow-400} / {ewellow-700} |
| `success` | `--success` | `success` | #69d6aa / #047554 |
| `warning` | `--warning` | `warning` | #f9a870 / #964d09 |
| `danger` | `--danger` | `danger` | #ffa196 / #a04038 |
| `info` | `--info` | `info` | #76c7ff / #026a9d |
| `success-subtle` | `--success-subtle` | `successSubtle` | #0d2d21 / #dff7eb |
| `warning-subtle` | `--warning-subtle` | `warningSubtle` | #372010 / #ffece0 |
| `danger-subtle` | `--danger-subtle` | `dangerSubtle` | #3a1d1a / #ffebe8 |
| `info-subtle` | `--info-subtle` | `infoSubtle` | #0f293a / #e4f3fe |
| `on-status` | `--on-status` | `onStatus` | {black} / #ffffff |

### Font size

| Token | CSS | QML (`Theme.`) | Value |
| --- | --- | --- | --- |
| `font-size-xs` | `--font-size-xs` | `fontSizeXs` | 11px |
| `font-size-s` | `--font-size-s` | `fontSizeS` | 12px |
| `font-size-md` | `--font-size-md` | `fontSizeMd` | 13px |
| `font-size-lg` | `--font-size-lg` | `fontSizeLg` | 15px |
| `font-size-xl` | `--font-size-xl` | `fontSizeXl` | 18px |
| `font-size-2xl` | `--font-size-2xl` | `fontSize2xl` | 22px |
| `font-size-3xl` | `--font-size-3xl` | `fontSize3xl` | 28px |
| `font-size-4xl` | `--font-size-4xl` | `fontSize4xl` | 36px |
| `font-size-5xl` | `--font-size-5xl` | `fontSize5xl` | 48px |
| `font-size-6xl` | `--font-size-6xl` | `fontSize6xl` | 64px |

### Line height

| Token | CSS | QML (`Theme.`) | Value |
| --- | --- | --- | --- |
| `line-height-xs` | `--line-height-xs` | `lineHeightXs` | 14px |
| `line-height-s` | `--line-height-s` | `lineHeightS` | 16px |
| `line-height-md` | `--line-height-md` | `lineHeightMd` | 18px |
| `line-height-lg` | `--line-height-lg` | `lineHeightLg` | 20px |
| `line-height-lg-relaxed` | `--line-height-lg-relaxed` | `lineHeightLgRelaxed` | 22px |
| `line-height-xl` | `--line-height-xl` | `lineHeightXl` | 24px |
| `line-height-2xl` | `--line-height-2xl` | `lineHeight2xl` | 28px |
| `line-height-3xl` | `--line-height-3xl` | `lineHeight3xl` | 34px |
| `line-height-4xl` | `--line-height-4xl` | `lineHeight4xl` | 44px |
| `line-height-5xl` | `--line-height-5xl` | `lineHeight5xl` | 56px |
| `line-height-6xl` | `--line-height-6xl` | `lineHeight6xl` | 72px |

### Font weight

| Token | CSS | QML (`Theme.`) | Value |
| --- | --- | --- | --- |
| `font-weight-thin` | `--font-weight-thin` | `fontWeightThin` | 100 |
| `font-weight-extralight` | `--font-weight-extralight` | `fontWeightExtralight` | 200 |
| `font-weight-light` | `--font-weight-light` | `fontWeightLight` | 300 |
| `font-weight-regular` | `--font-weight-regular` | `fontWeightRegular` | 400 |
| `font-weight-medium` | `--font-weight-medium` | `fontWeightMedium` | 500 |
| `font-weight-semibold` | `--font-weight-semibold` | `fontWeightSemibold` | 600 |
| `font-weight-bold` | `--font-weight-bold` | `fontWeightBold` | 700 |
| `font-weight-extrabold` | `--font-weight-extrabold` | `fontWeightExtrabold` | 800 |
| `font-weight-black` | `--font-weight-black` | `fontWeightBlack` | 900 |

### Letter spacing

| Token | CSS | QML (`Theme.`) | Value |
| --- | --- | --- | --- |
| `tracking-tightest` | `--tracking-tightest` | `trackingTightest` | -0.03em |
| `tracking-tighter` | `--tracking-tighter` | `trackingTighter` | -0.02em |
| `tracking-tight` | `--tracking-tight` | `trackingTight` | -0.015em |
| `tracking-snug` | `--tracking-snug` | `trackingSnug` | -0.01em |
| `tracking-normal` | `--tracking-normal` | `trackingNormal` | 0 |
| `tracking-wide` | `--tracking-wide` | `trackingWide` | 0.06em |

### Spacing

| Token | CSS | QML (`Theme.`) | Value |
| --- | --- | --- | --- |
| `space-xxs` | `--space-xxs` | `spaceXxs` | 2px |
| `space-xs` | `--space-xs` | `spaceXs` | 4px |
| `space-s` | `--space-s` | `spaceS` | 8px |
| `space-md` | `--space-md` | `spaceMd` | 16px |
| `space-lg` | `--space-lg` | `spaceLg` | 32px |
| `space-xl` | `--space-xl` | `spaceXl` | 64px |

### Radius

| Token | CSS | QML (`Theme.`) | Value |
| --- | --- | --- | --- |
| `slight` | `--slight` | `radiusSlight` | 4px |
| `secondary` | `--secondary` | `radiusSecondary` | 6px |
| `primary` | `--primary` | `radiusPrimary` | 8px |
| `rounded` | `--rounded` | `radiusRounded` | 10px |
| `fully-rounded` | `--fully-rounded` | `radiusFull` | 9999px |

### Shadow

| Token | CSS | QML (`Theme.`) | Value |
| --- | --- | --- | --- |
| `shadow-none` | `--shadow-none` | `shadowNone` | none |
| `shadow-sm` | `--shadow-sm` | `shadowSm` | 0 1px 2px rgba(0, 0, 0, 0.40) / 0 1px 2px rgba(20, 16, 8, 0.08) |
| `shadow-float` | `--shadow-float` | `shadowFloat` | 0 2px 6px rgba(0, 0, 0, 0.35) / 0 2px 6px rgba(20, 16, 8, 0.10) |

### Gradient

| Token | CSS | QML (`Theme.`) | Value |
| --- | --- | --- | --- |
| `gradient-ewellow` | `--gradient-ewellow` | `gradientEwellow` | linear-gradient(135deg, #f4bd28 0%, #e6ab09 100%) |
| `gradient-ember` | `--gradient-ember` | `gradientEmber` | linear-gradient(160deg, #1b150b 0%, #0b0a08 100%) |
| `gradient-night` | `--gradient-night` | `gradientNight` | linear-gradient(180deg, #151411 0%, #0b0a08 100%) |
| `gradient-glow` | `--gradient-glow` | `gradientGlow` | radial-gradient(circle at 50% 0%, rgba(238, 180, 7, 0.08) 0%, rgba(238, 180, 7, 0) 60%) |

### Border width

| Token | CSS | QML (`Theme.`) | Value |
| --- | --- | --- | --- |
| `border-width-1` | `--border-width-1` | `borderWidth1` | 1px |
| `border-width-2` | `--border-width-2` | `borderWidth2` | 2px |
| `focus-width` | `--focus-width` | `focusWidth` | 1px |

### Size

| Token | CSS | QML (`Theme.`) | Value |
| --- | --- | --- | --- |
| `control-sm` | `--control-sm` | `controlSm` | 24px |
| `control-md` | `--control-md` | `controlMd` | 28px |
| `control-lg` | `--control-lg` | `controlLg` | 32px |
| `control-xl` | `--control-xl` | `controlXl` | 40px |
| `control-2xl` | `--control-2xl` | `control2xl` | 48px |
| `bar-height` | `--bar-height` | `barHeight` | 48px |
| `bar-height-lg` | `--bar-height-lg` | `barHeightLg` | 64px |
| `icon-xs` | `--icon-xs` | `iconXs` | 12px |
| `icon-sm` | `--icon-sm` | `iconSm` | 14px |
| `icon-md` | `--icon-md` | `iconMd` | 16px |
| `icon-lg` | `--icon-lg` | `iconLg` | 20px |
| `icon-xl` | `--icon-xl` | `iconXl` | 24px |
| `icon-2xl` | `--icon-2xl` | `icon2xl` | 32px |
| `icon-3xl` | `--icon-3xl` | `icon3xl` | 48px |
| `icon-4xl` | `--icon-4xl` | `icon4xl` | 64px |
| `panel-sm` | `--panel-sm` | `panelSm` | 360px |
| `panel-md` | `--panel-md` | `panelMd` | 400px |
| `panel-lg` | `--panel-lg` | `panelLg` | 560px |
| `window-gap` | `--window-gap` | `windowGap` | 8px |
| `blur-glass` | `--blur-glass` | `blurGlass` | 24px |

### Opacity

| Token | CSS | QML (`Theme.`) | Value |
| --- | --- | --- | --- |
| `opacity-solid` | `--opacity-solid` | `opacitySolid` | 1 |
| `opacity-glass` | `--opacity-glass` | `opacityGlass` | 0.8 |
| `opacity-app` | `--opacity-app` | `opacityApp` | 0.85 |
| `opacity-inactive` | `--opacity-inactive` | `opacityInactive` | 0.97 |

## Theme.qml today → Ewe

| Theme.qml today | Becomes |
| --- | --- |
| `bg1` | surfaceRaised |
| `bg2, bg3` | surfaceBase |
| `bg4, bg5` | surfaceSunken |
| `bg6` | surfaceOverlay |
| `bgDisabled` | surfaceRaised |
| `bg*Hover, cardHover, subtleHover, barHover` | surfaceHover (glassHover inside Glass) |
| `bg*Pressed, cardPressed, subtlePressed` | surfacePressed (glassPressed inside Glass) |
| `bg*Selected, cardSelected, subtleSelected, barActive` | accentSubtle; surfaceSelected inside a sunken well; surfacePressed for an open bar module |
| `card, panel` | surfaceRaised |
| `subtle` | transparent |
| `stroke1, stroke1Pressed, strokeAccessible` | borderStrong |
| `stroke1Hover` | textMuted |
| `stroke1Selected` | accentText |
| `stroke2, stroke3, strokeDisabled, cardStroke` | borderSubtle |
| `strokeFocus1` | (removed) |
| `strokeFocus2` | focusRing |
| `fg1` | textPrimary |
| `fg2` | textSecondary |
| `fg2Hover, fg3Hover` | textPrimary |
| `fg3, fg4` | textMuted |
| `fgDisabled` | textDisabled |
| `fgInverted, fgOnBrand, accentOn, accentText` | onAccent |
| `brandBg, accentFill, compoundBrandBg` | accent |
| `brandBgHover, compoundBrandBgHover` | accentHover |
| `brandBgPressed, brandBgSelected, compoundBrandBgPressed` | accentPressed |
| `brandFg1, brandFg2, brandFgLink, brandFgLinkHover, compoundBrandFg, link` | accentText |
| `brandStroke1, compoundBrandStroke` | focusRing |
| `brandStroke2` | ewellow900 (accent ramp) |
| `accent` | accent (still the person's pick) |
| `linkSolid` | accent |
| `success, warning, danger` | success, warning, danger (new values) |
| `successBg, warningBg, dangerBg, infoBg` | successSubtle, warningSubtle, dangerSubtle, infoSubtle |
| `successBorder, warningBorder, dangerBorder, infoBorder` | success, warning, danger, info |
| `shadow` | scrim for dim backdrops; shadowFloat for elevation |
| `Elevation.qml` | shadowFloat: 0 2px 6px, one short shadow |
| `Sheen.qml` | (removed: no gloss) |
| `barTop, barBottom, barFill` | surfaceBase, or glassBase when bar opacity < 100 |
| `dockFill` | surfaceRaised, or glassRaised |
| `barBorder, dockStroke` | borderSubtle, or glassBorder |
| `radius` | radiusRounded |
| `radiusInner, radiusControl` | radiusPrimary |
| `radiusPill, barItemRadius` | radiusPrimary for bar modules; radiusFull only for badges, tags, switches |
| `outline, border, borderThin, cardBorder, hairline` | borderWidth1 |
| `focusWidth` | focusWidth (1px) |
| `hoverInset, shadowOffset` | (removed) |
| `pad` | spaceS + spaceXs (12) |
| `gap` | spaceS |
| `controlHeight, rowHeight` | controlMd (28) |
| `barHeight` | barHeight (48) or barHeightLg (64) |
| `barItemHeight` | controlLg (32) or controlXl (40) |
| `barIconPx, trayIconPx` | iconLg (20) or iconXl (24) |
| `barItemSpacing, trayItemSpacing` | spaceXs between modules, spaceS inside the Quick settings button |
| `fontText, fontDisplay` | fontSans (Geist) |
| `fontMono` | fontMono (Geist Mono) |
| `fontIcons` | fontIcons (Lucide, unchanged) |
| `fsSmall` | fontSizeS (12) |
| `fsBody` | fontSizeMd (13) |
| `fsLarge` | fontSizeLg (15) |
| `fsTitle` | fontSize2xl (22) |
| `labelWeight` | fontWeightMedium |
| `labelCaps, labelTracking` | the overline style (never uppercase Georgian) |
| `durFast / durBase / durSlow` | durFast 150 / durBase 200 / durSlow 250 at Normal speed |
| `ease` | OutCubic; InOutCubic for durSlow; never OutBack |

## Shell files and their cards

| Shell file (`dotfiles/quickshell/`) | Follow these cards |
| --- | --- |
| Bar.qml, BarIcon.qml, BarPluginSlots.qml, TrayIcon.qml | Bar, Workspace indicator, Badge, Glass |
| Dock.qml | Dock, Glass |
| LauncherPanel.qml | Launcher panel |
| Launcher.qml | Launcher |
| Places.qml | Places |
| Overview.qml | Overview |
| QuickSettings.qml, Tile.qml, Toggle.qml, Slider.qml, ListRow.qml, ListWell.qml, SectionTitle.qml | Quick settings, Quick settings tile, Switch, Slider, List row, Section header, Agenda |
| Agenda.qml | Agenda |
| WifiPicker.qml | Wi-Fi picker |
| Notifications.qml | Notification, Notification center |
| (new) Toast.qml | Toast |
| Osd.qml | On-screen display |
| MediaPlayer.qml | Media player |
| Power.qml | Power menu |
| Lock.qml | Lock screen, Glass |
| Auth.qml | Authentication prompt |
| BtPairing.qml | Bluetooth pairing |
| SharePicker.qml | Share picker |
| TrayMenu.qml | Menu |
| Welcome.qml | Welcome, Wi-Fi picker, Step indicator |
| DesktopWidgets.qml | Desktop widgets |
| Screensaver.qml | Screensaver |
| AppStore.qml | App card, Card, Launcher panel |
| Avatar.qml, Badge.qml, Meter.qml, Spinner.qml | Avatar, Badge, Meter, Spinner |
| Settings.qml (in-shell pages) | Settings page, Accessibility modes, Look presets |
| hypr/hyprland.lua (decoration, gaps, borders) | Window, Glass |

## Settings keys

| Key | Default | Values and notes |
| --- | --- | --- |
| `[desktop.theme] scheme` | `ewe-dark` | `ewe-dark`, `ewe-light`, or a user scheme slug. Replaces `"accent"` and `color_scheme`. |
| `[desktop.theme] accent` | `#eeb407` | Any color. Was `#0a84ff`. |
| `[[desktop.theme.schemes]]` | two built-in entries | Base24 palette, `variant`, `accent`, `semantic`, `overrides`, `builtin`. Filled by `ewe-theme scheme import` and the Import button (see Color schemes). |
| `[desktop.theme] corner` | `medium` | `none` · `small` · `medium` · `large`. Was `round` (maps to `large`). |
| `[desktop.theme] density` | `comfortable` | `compact` · `comfortable` · `roomy` (new heights: 24 / 28 / 32). |
| `[desktop.theme] stroke` | `thin` | `none` · `thin` · `thick`. Was `none`. |
| `[desktop.theme] bar_opacity` | `100` | 0–100. The Glass preset is 80 (was 72). Settings warns below 80. |
| `[desktop.theme] app_blur`, `window_transparency` | `false` | Unchanged; windows use `opacity-app` and `opacity-inactive`. |
| `[desktop.bar] icon_size` | `normal` | `small` · `normal` · `large`. The bar is its icons plus `space-s` above and below (44 / 48 / 56). The v3 `size` key is no longer written; `size = large` still reads as `large`. |
| `[desktop.dock] icon_size` | `medium` | `small` (40) · `medium` (48) · `large` (64). |
| `[desktop.accessibility] reduce_motion` | `false` | New. |
| `[desktop.accessibility] reduce_transparency` | `false` | New. |
| `[desktop.accessibility] increase_contrast` | `false` | New. |
| `[desktop.accessibility] text_scale` | `100` | New: 100 · 115 · 130. |
| `[desktop.animations] speed` | `1` | Unchanged: 0 (off), 0.6 (slow), 1, 2 (fast). Motion durations are divided by it. |

## Done means

- Every surface matches its card in Ewe Dark and Ewe Light, at every look preset value and with each accessibility mode.
- No raw colors or sizes outside the token generator; no Fluent names left.
- Contrast checks pass for both built-in schemes and for imported schemes.
- Every feature that existed before still works the same way.
- The Changelog in this system lists the version the repos now follow.
