# Plugins — extending the shell (API 3)

ewe's desktop is one long-lived Quickshell process. A **plugin** is a
directory of QML that this process loads at startup, exactly as it loads its
own bar, dock and panels. Plugins add Quick settings tiles and pages, glyphs
to the bar's Quick settings pill, dock items, bar widgets, desktop widgets,
their own panels and headless services; they use the same `Theme` roles and
the same public components the first-party surfaces use.

Plugins are not apps. **Komble installs programs; `ewe-plugin` extends the
desktop.** Since 0.25 ewe's own extras are plugins too — the **add-ons**.

```sh
ewe-plugin list                     # installed, and (--json) the add-ons available
ewe-plugin install ewe.clipboard    # an add-on out of the ewe payload, on
ewe-plugin add https://github.com/acme/ewe-weather.git --enable
ewe-plugin disable acme.weather
```

## Add-ons — what ewe ships, and why it is not pre-installed

Preinstalled is the shell core (bar, launcher, Overview, the Quick settings
basics, notifications, lock, OSD, polkit, Welcome), ewe-settings, Komble and
ewe-sync. Everything else — the clipboard history, screenshots, the password
picker, and from 0.25 the features that left the shell (Insomnia, the system
monitor, SSH, VPN, music, Places, phone, mail, cast, the dock — none of them
is in the core any more; their legacy IPC targets `cast launcher places
player mail` and Quick settings keys `ssh vpn mobile mail cast` are the
add-ons' `ipcAliases` / `quickPage.key`) — is an **add-on**: a first-party
plugin that

- **ships inside the ewe payload** (`plugins/<id>/`, vendored from its own
  repository `prj786/ewe-plugin-<name>` by `scripts/vendor-plugins.sh`,
  which records repo, commit and version in `plugins/bundle.json`) — so it
  works offline and moves in lockstep with the shell's `apiVersion`;
- is **not installed on a fresh machine**; Komble → Add-ons, the Welcome
  screen and `ewe-plugin install <id>` put one in with one click;
- is **kept for upgraders**: `ewe-plugin migrate` (run by `ewe-setup` and by
  `install.sh` phase 60 when a previous ewe lived on the account) installs
  and enables, once, the add-ons that replace features the user had built
  in — the dock only unless `[desktop.dock] enabled = false`, and never one
  the user had removed. A fresh install records them as considered and
  installs none (`migrate --fresh`). The marker is
  `~/.local/state/ewe/addons-migrated` — local, never synced — a JSON list
  of the ids already considered, so an add-on that moves out of the shell in
  a later release is still migrated once for the people who had it.

`plugins/bundle.json`:

```json
{ "plugins": {
    "ewe.clipboard": { "repo": "https://github.com/prj786/ewe-plugin-clipboard",
                       "commit": "861d2b3…", "version": "1.1.1",
                       "default": false, "migrate": true } } }
```

`default: true` ids are seeded on every machine (none today); `migrate: true`
ids are what `migrate` installs for upgraders; every id in the payload is
offered by `list --json` under `available`. A package dependency an add-on
needs is declared in its manifest (`requires`) and only **reported**
(`missing`): Komble offers to install it; the shell never does.

Once installed an add-on is an ordinary plugin with source `bundled`:
`list` shows it, `set` changes its settings, `disable` hides it, `remove`
deletes it and remembers that in `[plugins].removed` so a later upgrade
leaves it out — `install <id>` (or `seed --restore <id>`) brings it back. A
newer ewe refreshes an installed bundled copy when its version changes (never
one you linked with `dev`).

## Writing one

```sh
ewe-plugin create acme.weather --name "Weather" --kinds quick-tile,quick-page,bar-status
cd acme.weather && ewe-plugin dev .        # linked, enabled, shell restarted, log follows
```

That is a git repository with a working plugin in it. You own the QML — what
it draws and does. ewe owns where it lives and what the user may change: a
tile's place in the home grid, a page's rail entry, a bar widget's section
and visibility, a desktop widget's place on the screen, whether it is
**sticky** (above windows) or on the desktop (below them), whether it is
shown, and the values of the `settings` you declared. None of that is in your
code: the user moves widgets in **arrange mode** (`Super+Shift+W`), Komble
shows your settings as a form, and every entry point that declares
`property var settings` receives the current values — live, on every change.

Ship it by pushing the repo; anyone installs with `ewe-plugin add <url>
--enable` or from Komble → Plugins. `ewe-plugin remove` on a linked working
copy only unlinks it. The three repos `prj786/ewe-plugin-{clipboard,
screenshot,passwords}` and `tests/fixtures/plugins/acme.v3demo` (every API 3
kind in four small files) are the worked examples.

## Trust

Installing **never runs plugin code** — there are no install hooks and
nothing asks for privileges. `add` clones the repository, validates its
manifest, and records where it came from; `install` copies out of the
payload. The code runs the moment the plugin is enabled, unsandboxed, inside
your shell process, with everything the desktop itself can do. Read it first.
There is no way to sandbox QML inside one engine, and the tool says so
instead of pretending.

## The tool

| verb | what it does |
|---|---|
| `add <git-url \| dir \| id> [--enable] [--yes] [--no-restart]` | clone (or copy a plain directory), validate, remember the source. A first-party URL (`…/ewe-plugin-<name>`) or a reserved id that exists in the payload installs the payload's copy instead |
| `list [--json]` | every plugin: on/off, version, kinds; flags one that is enabled but not installed. `--json` adds `available` (every payload add-on: id, name, description, icon, category, version, kinds, installed, enabled, default, migrate, repo, requires, missing) and `removed` |
| `info <id> [--json]` | one plugin's manifest and state |
| `install <id> [--no-restart]` | an **add-on** out of the payload: copied in with source `bundled`, any removal forgotten, enabled, keybinds regenerated. One JSON object (`ok`, `version`, `missing`, `restarted`); an unknown id is `ok: false`, exit 1 |
| `migrate [--no-restart] [--fresh]` | the one-time add-on migration above. JSON: `migrated`, `skipped` (with `why`), `fresh` |
| `enable <id>` / `disable <id>` | flip `[plugins].enabled` in `ewe.conf`, restart the shell (`--no-restart` to defer) |
| `update [id] [--yes]` | fast-forward git-managed plugins; the diff is shown first, a manifest that stops validating is rolled back |
| `remove <id> [--yes]` | delete a git clone or a bundled copy (remembered in `[plugins].removed`); a hand-made directory is moved to `<id>.bak.<stamp>`; forgets the plugin in `ewe.conf` |
| `restore [--yes] [--no-restart]` | clone every plugin `ewe.conf` knows that is not installed here; bundled add-ons it lists come from the payload — the plugin half of Komble's "For you" and the Welcome flow |
| `validate <dir> [--first-party] [--json]` | check a manifest and its entry points; exit 1 lists every problem (`--first-party` allows a reserved `ewe.` id) |
| `seed [dir] [--restore <id>] [--no-restart]` | the payload's `default` plugins in, installed bundled copies refreshed (run by `ewe-setup`); `--restore <id>` forgets a removal and installs that id |
| `path` | the plugins directory |
| `create <ns.name> [--name T] [--kinds a,b] [--section right] [--dir P]` | **a new plugin repo**: manifest, one working QML per kind, README, MIT licence, `git init` + first commit |
| `dev [dir] [--no-restart] [--no-follow]` | link a working copy into the plugins dir (edits are live after a restart), enable it, restart the shell, follow its log lines |
| `place <id> [--x N --y N] [--layer desktop\|top] [--visible on\|off] [--output NAME] [--reset]` | where a **desktop widget** sits — live, no restart |
| `set <id> <key> <value>` / `get <id> [key]` | a plugin's declared **settings** (typed by its manifest) — live |

Enabling and disabling restart `ewe.service` — there is no QML hot reload,
and a one-second restart is honest about that. The shell's own apps are not
touched by the restart (`KillMode=process`). Every verb that takes
`--no-restart` leaves the host's `ewe.service` alone — use it from scripts,
tests and the nested harness.

## Where things live

```
~/.config/ewe/plugins/<id>/            the plugins — code, outside the ewe payload,
                                       never synced, never touched by upgrades
~/.config/ewe/ewe.conf                 [plugins] enabled = [...]   removed = [...]
                                       [plugins.sources] id = url | "bundled" | "local"
                                       [plugins.settings] / [plugins.widgets] (quoted ids)
~/.local/state/ewe/plugins/<id>/       a plugin's own state (`stateDir`, created on demand)
~/.local/state/ewe/plugin-boots.json   the crash guard's counter
~/.local/state/ewe/addons-migrated     the add-on migration marker (local)
<payload>/plugins/<id>/ + bundle.json  the add-ons ewe ships (/usr/share/ewe, ~/.local/share/ewe)
```

`[plugins.sources]` **is the installed set**: `add`/`install` record a plugin
there whether or not it is enabled, `remove` forgets it, and the file syncs
with the rest of the machine. So on a fresh machine `ewe-plugin list` shows
every plugin your other machine had — on, off or not installed — and
`ewe-plugin restore` fetches the missing ones (git URLs cloned, bundled
add-ons copied from the payload; never automatic). A plugin added from a
plain directory is recorded as `"local"`: there is nothing another machine
could fetch, and `restore` says so.

## Manifest

A plugin is a git repository with `manifest.json` at its root:

```json
{
  "schemaVersion": 1,
  "id": "acme.weather",
  "name": "Weather",
  "version": "0.1.0",
  "apiVersion": 3,
  "description": "Conditions as a tile, the forecast on its page.",
  "homepage": "https://github.com/acme/ewe-weather",
  "author": "acme",
  "icon": "icSun",
  "category": "Utilities",
  "kinds": ["quick-tile", "quick-page", "bar-status", "service"],
  "entryPoints": { "quick-tile": "Tile.qml", "quick-page": "Page.qml",
                   "bar-status": "Status.qml", "service": "Service.qml" },
  "quickTile": { "span": 1, "order": 10 },
  "quickPage": { "key": "weather", "label": "Weather", "icon": "icSun", "order": 10 },
  "barStatus": { "order": 10 },
  "requires": { "packages": ["curl"], "commands": ["curl"] },
  "settings": [{ "key": "city", "type": "string", "default": "", "label": "City" }]
}
```

| field | rule |
|---|---|
| `schemaVersion` | `1` |
| `id` | `<namespace>.<name>`, lowercase `[a-z0-9_-]`, at least one dot. `ewe.` is reserved for the plugins ewe ships. The install directory is named after it. |
| `name`, `version` | non-empty strings; `version` is what `list` shows and what a refresh compares |
| `apiVersion` | `2` or `3` — the shell loads both; a manifest with any other value is refused at install, not at login. The `quick-tile`, `quick-page`, `bar-status` and `dock-item` kinds, `ipcAliases` and the keybind target rule need `3` |
| `kinds` | one or more of `service`, `panel`, `overlay`, `menu`, `bar-widget`, `desktop-widget`, `quick-tile`, `quick-page`, `bar-status`, `dock-item` |
| `entryPoints` | one `.qml` file per kind (none for `dock-item`), relative, inside the plugin (symlinks that resolve outside it are rejected) |
| `quickTile` | optional: `{ "span": 1 \| 2, "order": int }` — half a row or the whole row of the home grid; whole-row cards (span 2) always come after every half-row tile, then by `order` |
| `quickPage` | required with `quick-page`: `{ "key", "label", "icon", "order" }`. `key` is lowercase `[a-z0-9_-]`, unique, and not one the shell keeps (`home wifi bt audio cal notifs`); it is what `quicksettings tab <key>` and `Shell.openQuickSettings(key)` route to |
| `barStatus` | optional: `{ "order": int }` |
| `dockItem` | required with `dock-item`: `{ "icon", "label", "action", "order" }` — static; the dock draws the button and runs `action` (see `Shell.registerAction`), or `qs ipc call <id> toggle` when no action is registered. Hide it at runtime with `Shell.setDockItemShown(id, false)` |
| `requires` | optional: `{ "packages": [...], "commands": [...] }` — reported by `list --json` (`missing`) and `install`; never installed by the shell |
| `ipcAliases` | optional, **`ewe.` plugins only**: legacy IPC targets this plugin's QML registers (`["player"]`), so old keybinds and scripts keep working after a feature moved out of the shell |
| `icon`, `category` | the catalogue card (Komble → Add-ons, Welcome). Icons are Theme glyph **names** (`"icMusic"`), resolved by the host as `Theme[icon]` |
| `desktopWidget` | optional, for `desktop-widget`: `{ "x": 48, "y": 64, "layer": "desktop" }` — the default place; the user's placement in ewe.conf wins |
| `barWidget.defaultSection` | `left`, `center` or `right` (default `right`) — where a bar widget is packed |
| `settings` | optional: `[{ "key", "type", "default", "label", "choices"?, "min"?, "max"? }]`, `type` one of `bool`, `int`, `string`, `choice`, `color`. The values reach every entry point as `settings` and render as a form in Komble |
| `keybinds` | optional: `[{ "combo": "SUPER + P", "ipc": "acme.weather toggle" }]` — Hyprland binds generated while the plugin is enabled (`generated/plugin-keybinds.lua`). With `apiVersion` 3 the target must be the plugin's own id or one of its `ipcAliases` |
| `order` (in the four slot objects) | plugins sort by it, then by id; the shell's own come first |
| `description`, `homepage`, `author` | optional, shown by `info` |

## Kinds

| kind | what the shell does with it | injected |
|---|---|---|
| `service` | instantiated headless, once — a `QtObject`/`Scope` with timers, processes, D-Bus, an `IpcHandler` | the common set |
| `panel`, `overlay`, `menu` | instantiated identically, once; the plugin owns its `PanelWindow`s (or an `AnchoredPopup`) and its `IpcHandler`s. The names describe intent | the common set |
| `bar-widget` | an `Item` with an implicit size, packed into its bar section, once per monitor | + `screen`, `barWindow` |
| `bar-status` | a glyph **inside the Quick settings pill**, after the shell's own, once per monitor. Root it on `BarStatusGlyph`; set `shown` (not `visible`) to whether it has something to say | + `screen`, `barWindow`, `ink` |
| `quick-tile` | a `Tile` in the Quick settings home grid after the built-ins; the host sizes it (`span`) | + `panelOpen` |
| `quick-page` | a `Column` the width of the panel, one rail entry (`quickPage.icon`), shown while its `key` is the tab; start it with a `QsPageHead` | + `panelOpen` |
| `desktop-widget` | a sized `Item` on the desktop or the sticky layer, on one output, moved in arrange mode | the common set |
| `dock-item` | **no QML**: a dock button from `dockItem` (icon, label); a click runs `Shell.runAction(action, anchor)` with the button's anchor, lit while `Shell.isActive(action)`, hidden while `Shell.dockItemShown(id)` is false. Without a dock installed the item simply has no host | — |

**Injected properties** — set on the entry point's root, only when the root
declares them:

| property | type | meaning |
|---|---|---|
| `pluginId` | string | the manifest id |
| `pluginDir` | url | `file://` the plugin's directory (`Qt.resolvedUrl` works too) |
| `stateDir` | string | `~/.local/state/ewe/plugins/<id>` — created when first asked for; never synced |
| `settings` | var | `{key: value}` of the declared settings, pushed again live on every change |
| `screen`, `barWindow` | var | the output and the bar `PanelWindow` this bar slot sits in (`bar-widget`, `bar-status`) — hand `barWindow` to `Shell.anchorFor()` |
| `ink` | color | the pill's current glyph colour (`bar-status`): textSecondary, textPrimary while hovered or open |
| `panelOpen` | bool | **this** tile or page is on screen (Quick settings open and on its tab) — poll only while true |

### The bar-widget contract

The entry point's root is an `Item` with an implicit size. The bar's `Row`
packs it; give it the bar's conventions (the design system's Bar card) and it
will not look foreign — simplest, root it on `BarModule`. A bar **module** is
`Theme.barModule` tall, with `Theme.radiusPrimary` corners, no fill until you
point at it (`Theme.barHoverFill`, `Theme.barPressedFill` while pressed or
open), glyphs `Theme.barIcon` in `Theme.textSecondary` (`textPrimary` on
hover), and `Theme.spaceXs` between modules. A single-glyph widget is a
`barModule` square with no side padding — what the bundled scissors and
camera do.

```qml
import QtQuick
import qs

BarModule {
    property var settings: ({})
    property var barWindow: null
    glyph: Theme.icStar
    a11yName: "Weather"
    onActivated: pop.toggleAt(Shell.anchorFor(this, barWindow))
}
```

The `bar*` roles (`barGround`, `barOutline`, `barHoverFill`,
`barPressedFill`, `barAccentText`, `barTextMuted`) already follow Glass, so
a widget reads them instead of the plain surface roles and never asks
whether Glass is on. Widgets append to their section in id order after the
built-ins; the centre section yields on an output too narrow to hold it. The
Top bar show/hide map hides a plugin's bar widget **and** its pill glyph
under the key `plugin:<id>` (absent = shown); nothing in Settings writes
that key yet — `ewe-conf` and user-theme.json do.

## What a plugin may use

A plugin's QML says `import qs` and sees the shell's modules like any
first-party file. Of those, this is **public** — it will not change without
`apiVersion` moving. Everything else (`Globals`' `*Open` flags, the
notification `server`, the updater, the singletons behind the built-in
features, the `_private` plumbing) is internal and may move without notice.

### The `Shell` singleton

| | member | meaning |
|---|---|---|
| read | `apiVersion` | `3` |
| read | `overviewOpen`, `quickSettingsOpen`, `lowPower`, `onBattery`, `locked`, `dnd` | shell state, bindable |
| read | `bottomInset` | px a dock takes from the bottom of the screen (its strip + `windowGap`); `0` without a dock. Panels that open above the dock keep this clear — so nothing leaves a gap when no dock is installed |
| read | `bottomReserved` | the dock reserves that strip as an exclusive zone (always-visible dock) — a bottom-anchored surface is already pushed up and adds only its own gap |
| read | `dockPresent` | `bottomInset > 0` |
| read | `dockPrefs` | `{ enabled, autohide, iconSize }` — the user's `[desktop.dock]` prefs (`iconSize` is `"small"`, `"normal"` or `"large"`); what a dock plugin obeys. Read-only: Settings and ewe-settings write them |
| read | `pinnedApps` | the pinned desktop ids (`ewe-conf` `apps.pinned`), bindable |
| read | `activeCount` | how many actions report themselves open (an autohide dock stays out while > 0) |
| read | `primaryScreenName` | the primary output's name — a shell concept (the display profile's primary, else the first output); what a dock pins itself to |
| read | `dockItems` | the dock-item registry: `[{ id, name, icon, label, action, order }]` of every enabled plugin with a `dockItem`, in order — read-only, bindable; a dock plugin renders it, filtered by `dockItemShown(id)` |
| call | `toast(text, kind)` | a bottom-centre Toast; `kind` is `""`/`"info"`, `"warning"` or `"danger"`, or a Toast options object (`{ actionLabel, action, icon, timeout }`) |
| call | `openQuickSettings(tab)`, `closeQuickSettings()` | a built-in key or a plugin page's `quickPage.key`; same route as `qs ipc call quicksettings tab <key>` |
| call | `openSettings(page)`, `openStore(page)` | ewe-settings / Komble, focused if already open; `page` is forwarded (`komble --<page>`, e.g. `"addons"`; `ewe-settings --page <name>`) |
| call | `toggleOverview()` | open or close the Overview in-shell (what a dock's Overview button does — no `qs ipc` spawn) |
| call | `launch(desktopId)` | run a `.desktop` id (focuses an existing window first); `false` when unknown |
| call | `focusApp([classes])` | bring the window of one of these app classes forward; `false` when none |
| call | `registerAction(name, fn)`, `runAction(name, anchor)` | a named function (`dockItem.action` names one) and how the dock — or another plugin — runs it; `runAction` returns `false` when none is registered |
| call | `setActive(name, on)`, `isActive(name)` | an action's open state (its dock item lights); `AnchoredPopup` reports it through `action` |
| call | `setDockItemShown(pluginId, on)`, `dockItemShown(pluginId)` | hide or show your own dock item at runtime (default shown) — a player with nothing playing, a "bar only" setting; the dock filters on it live |
| call | `closePopups(exceptId)` | **one add-on popup at a time**: asks every popup but `exceptId`'s to close — emits `popupsClosing(exceptId)`. Every `AnchoredPopup` honours it (and calls it when it opens, with its `owner`); a plugin with its own `PanelWindow` listens to the signal and calls `closePopups(<its id>)` when it opens |
| call | `setBottomInset(pluginId, px, reserved)` | what a dock plugin publishes; `0` withdraws it |
| call | `setPinned(desktopId, on)` | pin or unpin an app; the shell persists it through `ewe-conf` and `pinnedApps` follows |
| call | `anchorFor(item, window)` | `{ screen, x, y, edge, item }` for a popup: the item's centre in its window (screen-local for a full-width bar or dock), `edge` `"top"` or `"bottom"`. Pass the window when you have it (`barWindow`, your own `PanelWindow`); without it the focused monitor is assumed and the edge is bottom |
| signal | `aboutToSleep()`, `resumed()` | the system is about to suspend; the wake sequence reached its network step (about three seconds after wake — refresh what you cache then) |
| signal | `popupsClosing(exceptId)` | another popup is opening (or a plugin asked for the field): close yours unless `exceptId` is your plugin id |

### Public components

| component | what it is |
|---|---|
| `Tile` | the Quick settings tile (`ic`, `label`, `sub`, `active`, `opened`, `hasMenu`, `busy`, `disabled`; `clicked`, `menu`) — root your `quick-tile` on it |
| `QsPageHead` | a page's head: back, `title`, `note`, `busy`, optional Switch (`hasSwitch`, `on`, `toggled`), actions as children |
| `QsSwitchRow` | glyph + `label` + `desc` + Switch; `toggled` |
| `QsButton` | Button: `label`, `ic`, `variant` primary/secondary/ghost/danger, `size` sm/md, `busy`, `disabled`; `go` |
| `QsIconButton` | Icon button: `ic`, `selected`, `danger`, `square`, `size`; `go` |
| `QsField` + `QsFieldInput` | the text field box (`focused`, `error`) and the input inside it (`placeholder`) |
| `QsSegmented` | segmented control: `options` `[{label, value, disabled}]`, `value`; `picked(value)` |
| `QsEmpty` | empty state: `ic`, `title`, `desc`, actions as children |
| `QsNote` | a wrapping caption under a list; `tone` danger/warning |
| `QsMsgRow` | a two-line message row: `title`, `line`, `time`, `unread`; `clicked` |
| `TextBody`, `TextStrong`, `TextCaption`, `TextMono` | text in the system's styles |
| `Glyph` | one icon-font glyph (`text: Theme.icStar`) |
| `BarModule`, `BarSep`, `BarStatusGlyph` | the bar's module, divider and pill glyph (`ink`, `shown`) |
| `AnchoredPopup` | a popup card for a plugin: `openAt(anchor)`, `toggleAt(anchor)`, `close()`, `open`, `name` (layer-shell namespace suffix), `owner` (your plugin id — what `Shell.closePopups(id)` spares), `action` (reports open state), `implicitWidth/Height`, content as children. One `PanelWindow` on the anchor's screen; click outside or Esc closes; keyboard OnDemand; above the dock (`Shell.bottomInset`) for a bottom anchor, under the bar for a top one; opening closes every other add-on popup (`Shell.closePopups`) and it closes when another opens |
| `Toggle`, `Slider`, `Meter`, `ListWell`, `ListRow`, `SectionTitle`, `Badge`, `Spinner`, `Avatar`, `Elevation` | the rest of the kit the first-party panels are built from |

### `Theme`, `Globals`, `Log`

- **`Theme`** — the Ewe design system v3 tokens, under their QML names
  (`design/system/guidelines/40-implementation.md`): colour roles
  (`surface*`, `text*`, `border*`, `accent*`, `onAccent`, `focusRing`,
  `success`/`warning`/`danger`/`info` and their `*Subtle` grounds, `glass*`,
  `scrim`), the bar roles plus `barModule`, `barIcon`, `barHeight`, spacing
  (`spaceXxs…spaceXl`), radii (`radiusSlight`, `radiusSecondary`,
  `radiusPrimary`, `radiusRounded`, `radiusFull`), widths, sizes
  (`control*`, `icon*`, `panel*`, `windowGap`), type (`fontSans`, `fontMono`,
  `fontIcons`, and the styles as `Theme.type.<style>`), motion (`durFast`,
  `durBase`, `durSlow`, `ease`, `easeFast`, `easeSlow`), the accessibility
  modes (`reduceMotion`, `textScale` …) and the `ic*` glyphs. Ask for a
  role, never a value — the accent, the scheme and the look presets are the
  user's and change at runtime. No raw colour, size or duration in a plugin
  either (Rule 8).
- **`Globals`** (the API 2 subset, unchanged) — read: `version`,
  `accentColor`, `dnd`, `onBattery`, `lowPower`, `locked`, `barShows(key)`;
  call: `openSettings()`, `openStore()`, `launchEntry(entry)` (takes a
  Quickshell `DesktopEntry`; use `Shell.launch(desktopId)` for an id),
  `focusWindowByClass(cls)`, `playSound(name)`. New code should prefer
  `Shell`.
- **`Log`** — `Log.info("acme.weather", …)` / `warn` / `debug`. Set
  `HS_LOG_MODULES=acme.weather` to see your debug lines.

Use `IpcHandler` for anything a keybind or script should reach:

```qml
IpcHandler { target: "acme.weather"; function toggle(): void { pop.toggleAt(null) } }
```

```sh
qs ipc call acme.weather toggle       # bind it: a manifest keybind, or Settings → Keybinds
```

Name IPC targets after your id so they cannot collide with the shell's own
(`bar`, `quicksettings`, `settings`, `store`, `plugins`, …). Only a
first-party add-on may keep a legacy target (`ipcAliases`).

API history: **3** (0.25) adds the four Quick settings / bar / dock kinds,
the injected properties, the `Shell` singleton, the public components,
`requires`, `ipcAliases`, the add-ons model — a superset; every API 2 plugin
still loads. **2** is the Ewe design system v3 (the Fluent-era `Theme` names
are gone; the website's plugin API page has the rename table). **1** was the
Fluent-era surface and is refused at install.

## Safe mode

`ewe.service` relaunches the shell one second after any crash, so a plugin
that compiles and then crashes is not a broken widget — it is a login loop
with no desktop. The guard: every shell start is counted, and only a start
that follows crash evidence counts; the **third such start inside a minute**
boots with no plugins loaded and a notification names the plugins that were
enabled. Disable the culprit and restart:

```sh
ewe-plugin list            # shows the safe-mode notice and the suspects
ewe-plugin disable acme.weather
```

A start that stays up for a minute clears the counter; the tool's own
restarts (enable/disable/remove/install) never count. A plugin that fails to
*compile* is not a crash — it is logged (`journalctl --user -u ewe.service`)
and skipped.

## Trying it without installing

`ewe-plugin add ./my-plugin --enable` copies a plain directory in as a
hand-made plugin; `ewe-plugin dev ./my-plugin` links it. The nested harness
loads it beside the add-ons without touching your session:

```sh
HS_WORK=/tmp/hs-me HS_PLUGINS=1 HS_PLUGIN_DIRS=$PWD/my-plugin .claude/skills/run-ewe/driver.sh up
.claude/skills/run-ewe/driver.sh open quicksettings      # the tile, the rail entry
.claude/skills/run-ewe/driver.sh ipc quicksettings tab weather
.claude/skills/run-ewe/driver.sh down
```

## `plugins` IPC target

`qs ipc call plugins list` — what the host actually instantiated, as JSON
(fewer than enabled when an entry point failed to compile), every kind
included. `qs ipc call plugins apiVersion` / `safeMode` — the host's API
version and whether this session booted in safe mode. `plugins reload`
re-reads placement and settings without a restart.
