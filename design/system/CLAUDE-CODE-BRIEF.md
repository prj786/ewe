# Brief: implement the Ewe design system (version 3)

You are updating the Ewe desktop to follow its new design system. Ewe is an Arch-based OS: a Hyprland compositor, a Quickshell (QML) shell, and three Tauri + Svelte apps. Today everything uses a modified Fluent 2 look. The design system replaces that with Ewe's own design language.

Read this whole brief before you change anything.

---

## 1. Setup

The four repositories must be checked out side by side, because `design/check-tokens.sh` compares their files:

```
projects/
  ewe/            github.com/prj786/ewe            (shell, generator, dotfiles)
  ewe-settings/   github.com/prj786/ewe-settings   (Tauri + Svelte 5, shadcn-svelte, bits-ui, Tailwind 4)
  komble-arch/    github.com/prj786/komble-arch    (same stack; the package manager "Komble")
  ewe-sync/       github.com/prj786/ewe-sync       (same stack, no shadcn)
```

1. Unzip `ewe-design-system-v3.zip` into `ewe/design/system/`, so that `ewe/design/system/README-FIRST.md` exists. Commit it on its own first: `design: add Ewe design system v3`.
2. Add a short section to `ewe/CLAUDE.md`:
   - "The design system in `design/system/` is the source of truth for how every surface looks."
   - "Read `design/system/guidelines/40-implementation.md` before UI work."
3. Work on a branch in each repo: `ewe-design-v3`.

## 2. What to read, in this order

1. `design/system/README-FIRST.md`: what is in the folder.
2. `design/system/README.md`: principles, UX values, color, type, layout, look presets, motion, layers, transparency, writing, accessibility.
3. `design/system/guidelines/40-implementation.md`: **your plan**, covering:
   - the ground rules and the six phases;
   - every token with its CSS and QML name;
   - the old `Theme.qml` → new mapping;
   - which shell file follows which component;
   - the settings keys.
4. `design/system/guidelines/10-color-schemes.md`: schemes, YAML files, CLI, role derivation, contrast guarantees.
5. `design/system/guidelines/20-migration.md`: every current Fluent CSS variable → its Ewe token.
6. `design/system/guidelines/30-writing.md`: for every string you touch.
7. `design/system/tokens.json`: every value, with a usage note.
8. Per task: `design/system/components/<Name>/README.md`, the spec. Then look at its preview:
   - Open `design/system/view/<Name>.html?theme=dark` and `?theme=light` in a browser.
   - Or run `python3 design/system/tools/screenshot.py <Name>` and read the PNGs.
9. `design/system/components/bundle.css`: reference CSS. The `ewe-*` rules use only tokens and can be ported as they are. The `ds-*` rules only lay out previews; ignore them.

When you need a value, look it up; never guess it. If a spec is silent, say so in your report and choose the closest documented pattern.

## 3. Rules

1. **Looks come from the design system; behavior comes from the code.** On color, size, spacing, type, radius, outline, shadow or motion, the design system wins. On what something does (features, modules, shortcuts, IPC commands, placement), the current code wins. Change behavior only where a component README's "Where it lives" section marks something as **new**.
2. **Keep every feature.**
   - The bar keeps its modules and their order.
   - The dock keeps its launchers, workspace groups, the Pen and intelligent auto-hide.
   - Overview, Places, Welcome and the other screens keep their flows.
   - If a spec seems to drop something, treat it as an omission: keep the feature and note it in your report.
3. **Tokens only.** No raw colors, pixel sizes or durations in QML or app CSS. Values come from the generated tokens and the motion table. If a needed value has no token, stop and report it instead of inventing one.
4. **Schemes, look presets, Glass and accessibility modes are remaps of roles.**
   - The generator and `Theme` apply them.
   - Components never check which one is active.
5. **Don't delete anything without asking.** That covers features, settings keys and CLI commands.
6. **One commit per logical step, one PR per phase per repo.** Each commit says which component or token group it follows. Run the checks for the phase before moving on.
7. **Ask before:**
   - changing a public ewe.conf key in a way that isn't listed in the implementation guide;
   - removing a dependency;
   - touching the installer or packaging.

## 4. Decisions already made (don't reopen)

**Brand, color and type**
- Brand color and default accent: ewellow `#eeb407`. People can pick any accent.
- Two built-in schemes: **Ewe Dark** (default) and **Ewe Light**.
- Fonts: Geist and Geist Mono, with Noto Sans Georgian as fallback. Icons stay Lucide.

**Schemes**
- Scheme files are **Base24 YAML** with ewe keys: `slug`, `variant`, `accent`, `semantic`, `overrides`, `builtin`.
- The existing `ewe-theme scheme` commands and the Import button in Settings are how people add schemes.
- There is **no scheme editor screen**.

**Look presets**
- Default look: 8px controls, 10px panels, 28px controls, 1px outlines. The presets are `corner` = medium, `density` = comfortable, `stroke` = thin.
- Old `round` maps to `large`.

**Focus**
- Every focus ring is 1px, from `focus-width`. Increase contrast makes it 2px.
- Text fields turn their own border `focus-ring`.

**Bar**
- `bar-height` is 48px, or 64px at the large size.
- Modules are 32px or 40px with 20px or 24px glyphs.
- The bar's status glyphs sit inside the **Quick settings button** (the old "control center" pill).

**Glass**
- The bar opacity setting (default 100) drives Glass on the bar, the dock and the lock card.
- Glass preset: **80%**, changed from 72%.
- Settings warns below 80%.
- Inside glass, roles remap to the `glass-*` tokens.
- Panels, menus and dialogs stay solid.

**Other components**
- Side navigation marks the selected item with an `accent-subtle` fill, not an edge bar.
- Badge labels are centered on cap height.

**Motion**
- `durFast` 150, `durBase` 200, `durSlow` 250, `durDim` 1500 ms. The animation speed setting divides them.
- Easing: OutCubic, and InOutCubic for slow.
- **No OutBack or overshoot anywhere.**

**Also decided**
- Lock screen, power menu and screensaver always use Ewe Dark.
- Accessibility modes live under `[desktop.accessibility]`: `reduce_motion`, `reduce_transparency`, `increase_contrast`, `text_scale`.
- Writing: US English, sentence case, "Quick settings", "Overview", "workspace", "sign in". The full list is in the Writing guide.

## 5. The work

The implementation guide has the full plan. In short:

| Phase | Repo | Do | Check |
| --- | --- | --- | --- |
| 1. Tokens | ewe | `bin/ewe-theme` emits the full Ewe token set for the active scheme. It keeps the Fluent names as aliases, adds `glass-*`, `opacity-*`, `blur-glass` and `focus-width`, and applies look presets and accessibility modes as remaps. It also extends scheme YAML import/export and `scheme set` for `overrides`, `builtin` and `semantic`. `bin/ewe-conf` gets the new keys. | `tests/ewe-theme-test.sh` and `design/check-spec.sh` are updated and pass. Contrast holds for ewe-dark, ewe-light, one Catppuccin import and one wallpaper scheme: text 4.5:1; borders and focus 3:1; glass text at 80% over white and black. |
| 2. Fonts | ewe | Package Geist, Geist Mono and Noto Sans Georgian (fonts and license in `design/system/fonts/`). | Georgian strings render. Clock and battery digits don't shift. |
| 3. Theme | ewe | `Theme.qml` gets one property per token (QML names in the guide), `type.<style>` objects and the motion values. Old properties point at the new values. | The shell starts in both schemes. Nothing is visibly broken. |
| 4. Shell | ewe | Restyle each QML file per the guide's file → component table. Build `Toast.qml` (new). Add the "new" items listed in the component READMEs. Set up Glass (and Hyprland layer blur) as the Glass component describes. | Screenshot every surface in both schemes: at Glass 80%, with Increase contrast, and at text size 130%. Compare with `tools/screenshot.py` output. |
| 5. Apps | all four | Rewrite `ewe/design/components.css` from the `ewe-*` rules in `bundle.css` and regenerate `design/tokens.css`. Copy both into each app's `src/`, and move the Svelte wrappers to the Ewe classes and states. In ewe-settings: Appearance gets Scheme cards (Import sheet, Export, Duplicate, Remove), the Accent picker, Look presets and the bar opacity slider; add an Accessibility page. | `design/check-tokens.sh` passes. Each app looks right in both schemes, and keyboard focus is visible everywhere. |
| 6. Clean-up | all | Remove the Fluent aliases, `Sheen.qml`, OutBack easings and any leftover raw values. | Grepping QML and app CSS for `#` colors and pixel literals only finds them in the generator. |

**Things in the current code to be aware of:**
- `Theme.qml` reads `theme-tokens.json` through `Globals.tokColor` / `tokShape` / `tokSize` / `tokSurface`.
- `Theme.barAlpha` already follows `bar_opacity`.
- `EWE_NO_BLUR=1` is set on VMs and NVIDIA. With it, Glass must still work, just without blur.
- `Globals.qml` has stale comments about `noBlur`.
- `design/tokens.css` and `design/components.css` are authored in `ewe` and copied verbatim into the apps. `check-tokens.sh` catches drift.
- `window_transparency` defaults disagree: `Globals.qml` says `true`, `ewe-conf` says `false`. Follow ewe-conf (`false`) and fix `Globals.qml`.
- `Theme.labelCaps` always resolves to MixedCase. The overline style replaces it. Never uppercase Georgian text.
- Bar icon badges currently use `brand-bg` at 10px. They become the solid accent Badge (16px) per the Bar README.

## 6. Reporting

At the end of each phase, report:
- what changed (files, commits);
- how you checked it (commands, screenshots);
- anything the design system didn't cover and what you chose;
- anything you left for later.

Keep a running list of open questions. When the design system and the code conflict in a way these rules don't settle, stop and ask.
