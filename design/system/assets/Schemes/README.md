# Schemes

The two color schemes ewe ships with. A scheme is a **Base24 YAML file** (the Tinted Theming format) with a few ewe keys on top; `ewe-theme scheme export` prints exactly this, and `ewe-theme scheme import` or the Import button in Settings → Appearance reads it back. The `.json` files here hold the same data for tools.

- `ewe-dark.json`: **Ewe Dark**, the default. Warm near-black surfaces, gold accent.
- `ewe-light.json`: **Ewe Light**. Warm off-white surfaces, the same gold accent with darker gold for text.

Both are `builtin: true`: they can be applied, exported and duplicated, not changed or removed. The `overrides` table sets the roles a Base24 palette can't express on its own (overlay and pressed surfaces, both border strengths, accent text and focus ring). User schemes may carry the same table. The Color schemes section of this design system has every key and how each role is derived.

## Ewe Dark as YAML

```yaml
system: "base24"
name: "Ewe Dark"
author: "ewe"
slug: "ewe-dark"
variant: "dark"
builtin: true
accent: "#eeb407"
semantic: true
palette:
  base00: "#0b0a08"
  base01: "#151411"
  base02: "#2c2a26"
  base03: "#5d5a55"
  base04: "#a8a49d"
  base05: "#faf9f6"
  base06: "#d5d2cb"
  base07: "#fefdfc"
  base08: "#ffa196"
  base09: "#f9a870"
  base0A: "#eeb407"
  base0B: "#69d6aa"
  base0C: "#64d1d7"
  base0D: "#76c7ff"
  base0E: "#e0a4ee"
  base0F: "#805708"
  base10: "#020202"
  base11: "#000000"
  base12: "#febfb7"
  base13: "#ffc29a"
  base14: "#7deabd"
  base15: "#79e5eb"
  base16: "#a3d8ff"
  base17: "#f1bafe"
overrides:
  on-accent: "#020202"
  accent-text: "#f8c23a"
  focus-ring: "#f8c23a"
  surface-overlay: "#201e1a"
  surface-pressed: "#423f3a"
  surface-selected: "#2c2a26"
  border-subtle: "#2c2a26"
  border-strong: "#7f7b75"
  accent-subtle: "#352206"
```

## Ewe Light as YAML

```yaml
system: "base24"
name: "Ewe Light"
author: "ewe"
slug: "ewe-light"
variant: "light"
builtin: true
accent: "#eeb407"
semantic: true
palette:
  base00: "#f4f2ee"
  base01: "#faf9f6"
  base02: "#e9e6e0"
  base03: "#a8a49d"
  base04: "#5d5a55"
  base05: "#0b0a08"
  base06: "#423f3a"
  base07: "#fefdfc"
  base08: "#a04038"
  base09: "#964d09"
  base0A: "#eeb407"
  base0B: "#047554"
  base0C: "#057176"
  base0D: "#026a9d"
  base0E: "#814a8d"
  base0F: "#805708"
  base10: "#e9e6e0"
  base11: "#d5d2cb"
  base12: "#8c2e28"
  base13: "#7f3f02"
  base14: "#016245"
  base15: "#035e62"
  base16: "#025884"
  base17: "#6f397b"
overrides:
  on-accent: "#020202"
  accent-text: "#805708"
  focus-ring: "#a77607"
  surface-overlay: "#fefdfc"
  surface-pressed: "#d5d2cb"
  surface-selected: "#fefdfc"
  border-subtle: "#d5d2cb"
  border-strong: "#7f7b75"
  accent-subtle: "#fff6e4"
```
