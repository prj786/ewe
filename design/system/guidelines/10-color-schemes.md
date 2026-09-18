# Color schemes

Ewe is a customizable desktop. Everything on screen takes its color from **roles** (`surface-raised`, `text-secondary`, `accent`…), and a **scheme** decides what each role looks like. Components never know which scheme is active.

## Built-in schemes

| Scheme | Variant | Use |
| --- | --- | --- |
| **Ewe Dark** (`ewe-dark`) | dark | The default. Warm near-black surfaces and the gold accent. |
| **Ewe Light** (`ewe-light`) | light | The same design on warm off-white surfaces. Gold stays the fill color; text and focus rings use a deeper gold so they stay readable. |

Both are the two themes of this design system's tokens, and both are in the Schemes asset group as files. They can't be edited or removed, but they can be duplicated.

## What people can change

From least to most effort:

1. **Pick a built-in scheme.** Settings → Appearance shows both as Scheme cards.
2. **Pick an accent.** Any color. The accent roles (`accent`, `accent-hover`, `accent-pressed`, `accent-subtle`, `accent-text`, `focus-ring`) and the accent ramp are regenerated from it; everything else stays.
3. **Import a scheme.** The Import button in Settings → Appearance, or `ewe-theme scheme import <file or URL>`. It reads Base16 and Base24 YAML, Omarchy `colors.toml`, Catppuccin `palette.json` (pick a flavour) and Gogh YAML. A scheme can also be made from the wallpaper.
4. **Write their own.** A scheme is a YAML file. Export one, change its values in any editor, and import it again. Single values can also be set from the command line.

There is no scheme editor screen: files, the command line and Import are the way in, and the generator makes any file usable (see Guarantees).

## Scheme files

A scheme file is Base24 YAML with a few ewe keys. Only `palette` is required.

```yaml
system: "base24"
name: "Kanagawa"
author: "someone"
slug: "kanagawa"          # defaults to the name, lowercased
variant: "dark"           # dark | light: which way the surfaces run
accent: "#7e9cd8"         # leave out to use base0A or the person's accent
semantic: true            # status colors from the palette (base08, base09, base0B, base0D)
palette:                  # base00–base0F required, base10–base17 optional
  base00: "#1f1f28"
  base01: "#2a2a37"
  # …
  base0F: "#d27e99"
overrides:                # optional: any color role by name, applied last
  border-subtle: "#363646"
  accent-text: "#9cabca"
```

| Key | Meaning |
| --- | --- |
| `name`, `slug`, `author` | How it is shown, stored and credited |
| `variant` | `dark` or `light`; also picks the GTK, Qt and icon variant |
| `accent` | Optional accent; without it, `base0A` or the person's accent setting |
| `semantic` | `true` takes status colors from the palette; `false` keeps Ewe's |
| `palette` | Base24: `base00`…`base0F` required, `base10`…`base17` optional |
| `overrides` | Optional: any color role by name, with a hex value, applied after derivation (the guarantees still apply) |
| `builtin` | Only on the two shipped schemes; they can't be changed or removed |

Imported schemes are stored in ewe.conf as `[[desktop.theme.schemes]]` records, so they sync with the rest of the settings. The Schemes asset group has both built-in schemes as YAML.

## Command line

| Command | What it does |
| --- | --- |
| `ewe-theme scheme list` | Lists schemes; the active one is marked |
| `ewe-theme scheme apply <slug>` | Switches scheme (`ewe-dark`, `ewe-light` or a user slug) |
| `ewe-theme scheme import <path or URL> [--name] [--slug] [--accent] [--flavour] [--apply]` | Imports a file |
| `ewe-theme scheme export [slug]` | Prints the scheme as YAML |
| `ewe-theme scheme set <field> <value> [--slug]` | Changes one field: `accent`, `name`, `variant`, `semantic`, `base00`…`base17`, or `overrides.<role>` |
| `ewe-theme scheme from-wallpaper [--light] [--apply]` | Makes a scheme from the current wallpaper |
| `ewe-theme scheme remove <slug>` | Removes a user scheme |

The commands exist today; `overrides`, `builtin` and `set overrides.<role>` are new.

## In Settings

- Appearance shows every scheme as a Scheme card: the two built-in ones first, then imported and wallpaper schemes.
- **Import scheme** opens a file picker (YAML, TOML or JSON) or takes a URL. After import, a Toast offers to apply it.
- Each user scheme's menu has Apply, Export, Duplicate and Remove. Built-in schemes have Apply, Export and Duplicate.
- When the generator had to adjust a color to keep contrast, the scheme card shows an Inline alert naming the roles it moved.

## How roles are derived

Every role comes from one palette entry, a mix of two, or a step of the accent ramp (`ewellow-50`…`ewellow-950`, regenerated from the accent). Mixes use OKLCH, so hue stays steady.

| Role | Dark scheme | Light scheme |
| --- | --- | --- |
| `surface-base` | `base00` | `base00` |
| `surface-raised` | `base01` | `base01` |
| `surface-overlay` | halfway from `base01` to `base02` | `base07` |
| `surface-sunken` | `base10`, or `base00` darkened | `base10`, or `base00` darkened |
| `surface-hover` | `base02` | `base02` |
| `surface-pressed` | `base02` moved 8 L toward `base05` | `base02` moved 6 L toward `base05` |
| `surface-selected` | `base02` | `base07` |
| `border-subtle` | `base02` | 30% of the way from `base02` to `base03` |
| `border-strong` | halfway from `base03` to `base04` | halfway from `base03` to `base04` |
| `text-primary` | `base05` | `base05` |
| `text-secondary` | `base06` | `base06` |
| `text-muted` | `base04` | `base04` |
| `text-disabled` | `base03` | `base03` |
| `accent`, `accent-hover`, `accent-pressed` | the accent (`ewellow-500`), `ewellow-400`, `ewellow-600` | the accent, `ewellow-600`, `ewellow-700` |
| `accent-subtle` | `ewellow-950` | `ewellow-50` |
| `accent-text`, `focus-ring`, `glass-accent` | `ewellow-400` | `ewellow-800`, `ewellow-700`, `ewellow-900` |
| `on-accent` | `black` or `neutral-0`, whichever contrasts more with `accent` | same |
| `success`, `warning`, `danger`, `info` | palette colors when `semantic = true`, else Ewe's | same |
| `*-subtle` | the status color at 27 L, low chroma | the status color at 95 L, low chroma |
| `on-status` | `black` or `neutral-0`, whichever contrasts more | same |
| `scrim` | `base11` at 64% opacity | `base05` at 32% opacity |

One black, one white: no color is darker than `black` or lighter than `neutral-0`. A derived value beyond them, an imported `#000000` or `#ffffff` included, becomes `black` or `neutral-0`.

Shadows and gradients follow the scheme too. Shadows are `black` (dark) or `base05` (light) at the shadow tokens' alphas. `gradient-ewellow` runs from halfway between `ewellow-400` and the accent to a quarter of the way from the accent to `ewellow-600`; `gradient-night` from `surface-raised` to `surface-base`; `gradient-ember` the same, its first stop tinted with the hue of `accent-subtle`; `gradient-glow` is the accent. Type, spacing, radii and sizes don't change with the scheme.

## Guarantees the generator keeps

A scheme can look like anything, but it can't make the desktop unusable. After deriving the roles, the generator checks them and fixes what fails, moving only lightness and keeping hue:

- `text-primary`, `text-secondary`, `text-muted`, `accent-text` and the status colors reach 4.5:1 on every surface role.
- `border-strong` and `focus-ring` reach 3:1 on every surface role.
- Surfaces stay apart: `surface-raised`, `surface-overlay` and `surface-hover` each differ from the surface below by at least 2 L, so layers never merge into one flat color, as far as the range from `black` to `neutral-0` allows. A surface already at the end of that range stays there (Ewe Light's `surface-overlay` is `neutral-0`, 1.25 L above `surface-raised`).
- If the accent's hue is within 20° of `warning`, `warning` turns toward red so the two never look alike.
- When it fixes something, the scheme card in Settings says which role moved and why, and `ewe-theme scheme show` lists it.

## Where the scheme reaches

The shell, ewe-settings, Komble and ewe-sync; Hyprland's window borders (`accent` for the active window, `border-subtle` for the rest); GTK and Qt apps; the icon theme's hue; kitty's sixteen colors (from `base08`–`base0F` and `base12`–`base17`); Zathura and mpv.
