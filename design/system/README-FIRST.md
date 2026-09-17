# Ewe design system · offline copy (version 3)

This folder is the complete Ewe design system, for implementing it in the ewe repositories.

| Path | What it is |
| --- | --- |
| `README.md` | The brand book: principles, UX values, color, type, layout, look presets, motion, layers, transparency, writing, accessibility. Start here. |
| `tokens.json` | Every token with its value per scheme and a usage note. The source for generators. |
| `tokens.css` | The same tokens compiled to CSS custom properties (`[data-theme="dark"]` / `[data-theme="light"]`) and type-style classes, with the fonts. |
| `guidelines/` | Color schemes, Migration (Fluent names → Ewe), Writing, Implementation guide, Changelog. |
| `components/<Name>/README.md` | The spec for each component: anatomy, sizes, states, behavior, accessibility, where it lives in the shell. |
| `components/<Name>/preview.html` | The visual spec (every state). Open it through `view/`. |
| `components/bundle.css` | Reference CSS for every component. `ewe-*` rules use only tokens; `ds-*` rules only lay out the previews. |
| `view/index.html` | Every preview, openable in a browser in either scheme (`?theme=dark` or `?theme=light`). |
| `tools/screenshot.py` | Screenshots every preview in both schemes, to compare with the real UI. |
| `fonts/` | Geist and Geist Mono (variable, with italics) and their OFL license. |
| `assets/` | Lucide icons, the ewe logos and sheep mark, wallpapers, and the two built-in schemes as YAML and JSON. |

86 components. Read `guidelines/40-implementation.md` before changing any code.
