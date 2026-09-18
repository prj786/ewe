# Changelog

The system's version is the `version` field in `tokens.json`. The repositories say which version they follow (in `design/tokens.css` and each app's `src/tokens.css` header), so it's always clear what still has to be done.

## Versioning

- **Raise the version** when a token is added, renamed, removed or changes value, or when a component's anatomy, states or behavior change.
- Wording, examples and preview-only changes don't raise it.
- Every version gets an entry here: what changed, and what an implementation has to do about it.
- Renamed or removed tokens stay listed in Migration until no repository uses them.

## Version 3

**Components (15 new):**
- Glass.
- Toast.
- Overview.
- Launcher panel.
- Places.
- Authentication prompt.
- Bluetooth pairing.
- Share picker.
- Wi-Fi picker.
- Agenda.
- Welcome.
- Desktop widgets.
- Screensaver.
- Accessibility modes.
- Look presets.

**Tokens:**
- Added `focus-width` (1px). Every focus ring now uses it; Increase contrast raises it to 2px.
- Added the `glass-*` roles, `blur-glass` and the `opacity-*` tokens.

**Bar and dock:**
- They follow the shipped shell layout.
- The bar's Quick settings button holds the status indicators, in a fixed order.
- The dock has launchers and workspace groups.

**Glass:**
- Translucency is specified for the bar, the dock and the lock card.
- The Glass preset is 80% (it was 72%).

**Side navigation:** the selected item is an `accent-subtle` fill, with no edge bar.

**Badge:** labels are centered on cap height, so they sit right in every browser and at fractional scales.

**Look presets:**
- `corner` is none, small, medium or large; medium is the default (the old `round` becomes large).
- `stroke` defaults to thin.

**Schemes:**
- Scheme files are Base24 YAML with ewe keys (`slug`, `variant`, `accent`, `semantic`, `overrides`, `builtin`).
- They come in through `ewe-theme scheme import` or the Import button in Settings. There is no scheme editor screen.
- The Sheet example is now the Import scheme sheet.

**Accessibility modes:** reduce motion, reduce transparency, increase contrast and text size, stored under `[desktop.accessibility]`.

**Motion:** a fixed table (fast 150, base 200, slow 250, dim 1500 ms). No overshoot.

**Guides:**
- Writing (voice, word list, formats, Georgian).
- Implementation (work plan, token-to-QML map, file-to-card map, settings keys).
- This changelog.

**To do in the repos:** everything in the Implementation guide. Nothing has been implemented yet.

## Version 2 and earlier

**Foundations:**
- Palette built on ewellow (#eeb407) and near-black.
- Geist and Geist Mono with a Georgian fallback.
- The type scale and weights.
- Spacing, radius, border, size, shadow and gradient tokens.
- The Ewe look (8px / 10px radii, 28px controls, 1px outlines).
- A 1px focus ring.
- The UX values, based on Nielsen's heuristics.

**Color:**
- Ewe Dark and Ewe Light as built-in schemes.
- The user scheme model.
- Role derivation and its contrast guarantees.

**Components:** the first 70, from Button to Wallpaper picker.

**Migration:** the map from today's Fluent 2 token names.
