# Migrating from the Fluent token layer

The shell and the three apps currently read about 150 Fluent 2 role names from the generated token file (`design/tokens.css`, copied into ewe-settings, Komble and ewe-sync). Ewe replaces them with its own names. This table maps every current name to what replaces it, so components can move over one at a time.

## How to migrate
- Keep generating the old names while components move, as an alias layer on top of the Ewe names, then delete them once nothing reads them.
- Where several old roles collapse into one Ewe token, the component usually only needs the one token. Where a value changes (radius, sizes, font sizes), check the component against its Ewe spec, not just the name.
- The accent still comes from ewe.conf. `ewellow` is the default; the `accent` roles and the `ewellow-*` ramp follow whatever accent is chosen, and `on-accent` switches between black and white to keep 4.5:1.
- The font stack changes from Inter to Geist (`--font-sans`) and to Geist Mono (`--font-mono`), both still followed by Noto Sans Georgian.
- The two built-in schemes are Ewe Dark (the default, today's `flock`) and Ewe Light. Both are ordinary entries in `[[desktop.theme.schemes]]` marked built-in, so user and imported schemes go through the same generator. See Color schemes for how roles are derived.
- Transparency: the `glass` preset moves from 72% to 80% (`opacity-glass`), the lowest value where text keeps 4.5:1 over any wallpaper. Inside the bar and dock, hover and pressed fills, outlines and accent text switch to the `glass-*` roles, and the badges on bar glyphs use the accent Badge instead of `brand-bg`.


## Foreground

| Current | Value today | Ewe | Note |
| --- | --- | --- | --- |
| `--fg-1` | #ffffff | `text-primary` |  |
| `--fg-2` | #d6d6d6 | `text-secondary` |  |
| `--fg-2-hover` | #ffffff | `text-primary` | Hover brightens secondary text to primary. |
| `--fg-3` | #adadad | `text-muted` | Ewe has three text levels; both tertiary and quaternary become muted. |
| `--fg-3-hover` | #d6d6d6 | `text-primary` | Hover brightens secondary text to primary. |
| `--fg-4` | #99999a | `text-muted` | Ewe has three text levels; both tertiary and quaternary become muted. |
| `--fg-disabled` | #5b5c5f | `text-disabled` |  |
| `--fg-inverted` | #232427 | `on-accent` | Ewe has no inverted surface; text on light fills uses `on-accent`. |
| `--fg-on-brand` | #ffffff | `on-accent` |  |
| `--fg` | #ffffff | `text-primary` |  |
| `--fg-secondary` | #d6d6d6 | `text-secondary` |  |
| `--fg-dim` | #adadad | `text-muted` |  |

## Backgrounds

| Current | Value today | Ewe | Note |
| --- | --- | --- | --- |
| `--bg-1` | #131417 | `surface-raised` | Panels, popups, cards. |
| `--bg-1-hover` | #1e1f22 | `surface-hover` |  |
| `--bg-1-pressed` | #0e0f12 | `surface-pressed` |  |
| `--bg-1-selected` | #1b1c1f | `accent-subtle` | Selected rows and items. Inside a sunken well (segmented control, switch), use `surface-selected`. |
| `--bg-2` | #0e0f12 | `surface-base` | The bar, window frames, panes. |
| `--bg-2-hover` | #191a1d | `surface-hover` |  |
| `--bg-2-pressed` | #090a0e | `surface-pressed` |  |
| `--bg-2-selected` | #16171a | `accent-subtle` | Selected rows and items. Inside a sunken well (segmented control, switch), use `surface-selected`. |
| `--bg-3` | #090a0e | `surface-base` | The bar, window frames, panes. |
| `--bg-3-hover` | #131417 | `surface-hover` |  |
| `--bg-3-pressed` | #040509 | `surface-pressed` |  |
| `--bg-3-selected` | #111215 | `accent-subtle` | Selected rows and items. Inside a sunken well (segmented control, switch), use `surface-selected`. |
| `--bg-4` | #040509 | `surface-sunken` | Wells and fields. |
| `--bg-4-hover` | #0e0f12 | `surface-hover` |  |
| `--bg-4-pressed` | #000000 | `surface-pressed` |  |
| `--bg-4-selected` | #0c0d10 | `accent-subtle` | Selected rows and items. Inside a sunken well (segmented control, switch), use `surface-selected`. |
| `--bg-5` | #000000 | `surface-sunken` | Wells and fields. |
| `--bg-5-hover` | #090a0e | `surface-hover` |  |
| `--bg-5-pressed` | #020307 | `surface-pressed` |  |
| `--bg-5-selected` | #07080c | `accent-subtle` | Selected rows and items. Inside a sunken well (segmented control, switch), use `surface-selected`. |
| `--bg-6` | #191a1d | `surface-overlay` | Menus and tooltips. |
| `--bg-disabled` | #090a0e | `surface-raised` | Disabled fills pair with a `border-subtle` outline. |
| `--card` | #191a1d | `surface-raised` | Cards now carry a 1px `border-subtle` outline. |
| `--card-hover` | #232427 | `surface-hover` |  |
| `--card-pressed` | #131417 | `surface-pressed` |  |
| `--card-selected` | #202124 | `accent-subtle` | Selected rows and items. Inside a sunken well (segmented control, switch), use `surface-selected`. |
| `--subtle` | transparent | transparent | No token; ghost controls have no fill at rest. |
| `--subtle-hover` | #1b1c1f | `surface-hover` |  |
| `--subtle-pressed` | #16171a | `surface-pressed` |  |
| `--subtle-selected` | #191a1d | `accent-subtle` | Selected rows and items. Inside a sunken well (segmented control, switch), use `surface-selected`. |
| `--bg-3-bar` | rgba(9, 10, 14, 1) | `glass-base` | Below 100% bar opacity; `surface-base` when solid. |
| `--bg` | #090a0e | `surface-base` |  |

## Strokes

| Current | Value today | Ewe | Note |
| --- | --- | --- | --- |
| `--stroke-1` | rgba(101, 102, 104, 0.5) | `border-strong` | Control outlines, 3:1 on every surface. |
| `--stroke-1-hover` | rgba(117, 117, 119, 0.5) | `text-muted` | Hover border of fields and controls. |
| `--stroke-1-pressed` | rgba(106, 107, 109, 0.5) | `border-strong` | Control outlines, 3:1 on every surface. |
| `--stroke-1-selected` | rgba(112, 112, 114, 0.5) | `accent-text` |  |
| `--stroke-2` | rgba(81, 82, 85, 0.5) | `border-subtle` |  |
| `--stroke-3` | rgba(60, 61, 65, 0.5) | `border-subtle` |  |
| `--stroke-accessible` | rgba(173, 173, 173, 0.5) | `border-strong` | Control outlines, 3:1 on every surface. |
| `--stroke-disabled` | rgba(65, 66, 70, 0.5) | `border-subtle` |  |
| `--stroke-focus-1` | #000000 | removed | Ewe draws a single 1px ring. |
| `--stroke-focus-2` | #ffffff | `focus-ring` |  |
| `--stroke-width` | 1px | `border-width-1` | Ewe draws a 1px outline by default (was 0). |
| `--stroke-width-thick` | 2px | `border-width-2` |  |
| `--stroke` | rgba(81, 82, 85, 0.5) | `border-subtle` |  |

## Brand and accent

| Current | Value today | Ewe | Note |
| --- | --- | --- | --- |
| `--brand-bg` | #1b559c | `accent` |  |
| `--brand-bg-hover` | #2065bb | `accent-hover` |  |
| `--brand-bg-pressed` | #1a4277 | `accent-pressed` |  |
| `--brand-bg-selected` | #1c4d8c | `accent-pressed` |  |
| `--brand-fg-1` | #82aeff | `accent-text` |  |
| `--brand-fg-2` | #93b8ff | `accent-text` |  |
| `--brand-fg-link` | #82aeff | `accent-text` |  |
| `--brand-fg-link-hover` | #93b8ff | `accent-text` | Add an underline on hover instead of a second color. |
| `--brand-stroke-1` | #82aeff | `focus-ring` | Accent outlines, including the open quick-settings tile. |
| `--brand-stroke-2` | #1c467c | `ewellow-900` | Accent border on tinted areas (follows the accent ramp). |
| `--compound-brand-bg` | #82aeff | `accent` |  |
| `--compound-brand-bg-hover` | #93b8ff | `accent-hover` |  |
| `--compound-brand-bg-pressed` | #5c9aff | `accent-pressed` |  |
| `--compound-brand-fg` | #82aeff | `accent-text` |  |
| `--compound-brand-stroke` | #82aeff | `focus-ring` | Accent outlines, including the open quick-settings tile. |
| `--accent-default` | #82aeff | `ewellow` | The default accent. |
| `--link` | #82aeff | `accent-text` |  |
| `--link-solid` | #1b559c | `accent` |  |
| `--accent-fg` | #ffffff | `on-accent` |  |
| `--btn-hover-bg` | #2065bb | `accent-hover` |  |
| `--btn-hover-fg` | #ffffff | `on-accent` |  |
| `--accent` | var(--accent-default) | `accent` | Still the user's pick, injected at runtime. |

## Status

| Current | Value today | Ewe | Note |
| --- | --- | --- | --- |
| `--success` | #54b054 | `success` |  |
| `--success-bg` | #052505 | `success-subtle` |  |
| `--success-border` | #9fd89f | `success` | Status borders use the status color itself. |
| `--warning` | #fdea3d | `warning` |  |
| `--warning-bg` | #332a00 | `warning-subtle` |  |
| `--warning-border` | #fbde3d | `warning` | Status borders use the status color itself. |
| `--danger` | #f1707b | `danger` |  |
| `--danger-bg` | #3b0509 | `danger-subtle` |  |
| `--danger-border` | #f1707b | `danger` | Status borders use the status color itself. |
| `--info` | #9ea2a6 | `info` |  |
| `--info-bg` | #222527 | `info-subtle` |  |
| `--info-border` | #9ea2a6 | `info` | Status borders use the status color itself. |

## Shadows

| Current | Value today | Ewe | Note |
| --- | --- | --- | --- |
| `--shadow-ambient` | rgba(0,0,0,0.24) | `shadow-float` | One short shadow: 0 2px 6px. |
| `--shadow-key` | rgba(0,0,0,0.28) | `shadow-float` | One short shadow: 0 2px 6px. |
| `--elevation-sm` | 0 1px 2px rgba(0,0,0,0.28), 0 0 2px rgba(0,0,0,0.24) | `shadow-sm` |  |
| `--elevation` | 0 8px 16px rgba(0,0,0,0.28), 0 0 2px rgba(0,0,0,0.24) | `shadow-float` | One short shadow: 0 2px 6px. |
| `--shadow-offset` | 0px | removed | Not used in Ewe. |

## Shape and size

| Current | Value today | Ewe | Note |
| --- | --- | --- | --- |
| `--bar-alpha` | 1 | setting | Stays an ewe.conf setting (`bar_opacity`); `opacity-glass` (0.8) is the Glass preset. |
| `--radius-control` | 12px | `primary` (8px) | Was 12px / 20px. |
| `--radius-card` | 20px | `rounded` (10px) | Was 20px / 26px. |
| `--radius-panel` | 26px | `rounded` (10px) | Was 20px / 26px. |
| `--radius-pill` | 999px | `fully-rounded` | Only badges, tags, switches and round media buttons. Buttons are no longer capsules. |
| `--outline-width` | 0px | `border-width-1` | Ewe draws a 1px outline by default (was 0). |
| `--focus-width` | 2px | `focus-width` (1px) | The focus ring is 1px (was 2px); Increase contrast makes it 2px. |
| `--pad` | 12px | `space-s` + `space-xs` (12px) | Or `space-s` (8px) inside compact panels. |
| `--gap` | 8px | `space-s` |  |
| `--control` | 32px | `control-md` (28px) | Was 32px. |
| `--row` | 36px | `control-md` (28px) | List rows; was 36px. |
| `--icon` | 18px | `icon-md` (16px) | The bar uses `icon-lg` (20px); was 18px. |
| `--bar-height` | 30px | `bar-height` (48px) | Was 30px; `bar-height-lg` is 64px. |
| `--radius` | 26px | `rounded` (10px) | Was 20px / 26px. |
| `--radius-inner` | 20px | `primary` (8px) | Was 12px / 20px. |
| `--border` | 0px | `border-width-1` | Ewe draws a 1px outline by default (was 0). |
| `--border-thin` | 0px | `border-width-1` | Ewe draws a 1px outline by default (was 0). |
| `--hover-inset` | 1px | removed | Not used in Ewe. |
| `--focus` | 2px | `focus-width` (1px) | The focus ring is 1px (was 2px); Increase contrast makes it 2px. |
| `--input-border-width` | 0px | `border-width-1` | Ewe draws a 1px outline by default (was 0). |

## Space

| Current | Value today | Ewe | Note |
| --- | --- | --- | --- |
| `--space-none` | 0px | 0 |  |
| `--space-xxs` | 2px | `space-xxs` |  |
| `--space-xs` | 4px | `space-xs` |  |
| `--space-snudge` | 6px | `space-xs` or `space-s` | Ewe has no half steps; pick the nearer rung. |
| `--space-s` | 8px | `space-s` |  |
| `--space-mnudge` | 10px | `space-xs` or `space-s` | Ewe has no half steps; pick the nearer rung. |
| `--space-m` | 12px | `space-s` + `space-xs` (12px) |  |
| `--space-l` | 16px | `space-md` |  |
| `--space-xl` | 20px | `space-md` | 20px rounds down to 16px. |
| `--space-xxl` | 24px | `space-md` + `space-s` (24px) |  |
| `--space-xxxl` | 32px | `space-lg` |  |

## Type

| Current | Value today | Ewe | Note |
| --- | --- | --- | --- |
| `--fs-100` | 10px | `font-size-xs` (11px) | Was 10px. |
| `--lh-100` | 14px | `line-height-xs` |  |
| `--fs-200` | 12px | `font-size-s` (12px) |  |
| `--lh-200` | 16px | `line-height-s` |  |
| `--fs-300` | 14px | `font-size-md` (13px) | Was 14px. |
| `--lh-300` | 20px | `line-height-md` (18px) |  |
| `--fs-400` | 16px | `font-size-lg` (15px) | Was 16px. |
| `--lh-400` | 22px | `line-height-lg` |  |
| `--fs-500` | 20px | `font-size-xl` (18px) | Was 20px. |
| `--lh-500` | 28px | `line-height-xl` |  |
| `--fs-600` | 24px | `font-size-2xl` (22px) | Was 24px. |
| `--lh-600` | 32px | `line-height-2xl` |  |
| `--fs-700` | 28px | `font-size-3xl` (28px) |  |
| `--lh-700` | 36px | `line-height-3xl` |  |
| `--fs-800` | 32px | `font-size-4xl` (36px) | Was 32px. |
| `--lh-800` | 40px | `line-height-4xl` |  |
| `--fs-body` | 14px | `font-size-md` (13px) | Was 14px. |
| `--fs-small` | 12px | `font-size-s` (12px) |  |
| `--fs-large` | 16px | `font-size-lg` (15px) | Was 16px. |
| `--fs-title` | 24px | `font-size-2xl` (22px) | Was 24px. |
| `--label-transform` | none | none | Use the `overline` style for capitalized group headers. |
| `--label-tracking` | normal | `tracking-normal` |  |
| `--label-weight` | 600 | `font-weight-medium` (500) | Was 600. |

## Older aliases

| Current | Value today | Ewe | Note |
| --- | --- | --- | --- |
| `--panel` | #131417 | `surface-raised` |  |
| `--elevated` | #191a1d | `surface-overlay` |  |
| `--hover` | #1b1c1f | `surface-hover` |  |
