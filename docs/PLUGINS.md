# Plugins — extending the shell

ewe's desktop is one long-lived Quickshell process. A **plugin** is a
directory of QML that this process loads at startup, exactly as it loads its
own bar, dock and panels. Plugins add bar widgets, panels, overlays, menus
and headless services; they use the same `Theme` roles and the same
`Globals` the first-party components use.

Plugins are not apps. **Komble installs programs; `ewe-plugin` extends the
desktop.**

```sh
ewe-plugin add https://github.com/prj786/ewe-plugin-example.git --enable
ewe-plugin list
ewe-plugin disable example.hello
```

## Writing one

```sh
ewe-plugin create acme.clock --name "Desk Clock" --kinds desktop-widget,bar-widget
cd acme.clock && ewe-plugin dev .        # linked, enabled, shell restarted, log follows
```

That is a git repository with a working plugin in it. You own the QML —
what it draws and does. ewe owns where it lives and what the user may
change: a bar widget's section and visibility, a desktop widget's place
on the screen, whether it is **sticky** (above windows) or on the desktop
(below them), whether it is shown, and the values of the `settings` you
declared. None of that is in your code: the user moves widgets in
**arrange mode** (`Super+Shift+W`: drag, Sticky, Hide, Esc), Komble shows
your settings as a form, and every entry point that declares
`property var settings` receives the current values — live, on every
change.

A `desktop-widget` is a sized `Item` (set `implicitWidth`/`implicitHeight`);
a `bar-widget` the same but bar-height; `panel`/`overlay`/`menu` own a
`PanelWindow` and an `IpcHandler { target: "<your id>" }`. `import qs`
gives you `Theme`, the public `Globals` subset and `Log`.

Ship it by pushing the repo; anyone installs with `ewe-plugin add <url>
--enable` or from Komble → Plugins. `ewe-plugin remove` on a linked
working copy only unlinks it.

## Trust

Installing **never runs plugin code** — there are no install hooks and
nothing asks for privileges. `add` clones the repository, validates its
manifest, and records where it came from. The code runs the moment the
plugin is enabled, unsandboxed, inside your shell process, with everything
the desktop itself can do. Read it first. There is no way to sandbox QML
inside one engine, and the tool says so instead of pretending.

## The tool

| verb | what it does |
|---|---|
| `add <git-url \| dir> [--enable] [--yes]` | clone (or copy a plain directory), validate, remember the source |
| `list [--json]` | every plugin: on/off, version, kinds; flags one that is enabled but not installed |
| `info <id> [--json]` | one plugin's manifest and state |
| `enable <id>` / `disable <id>` | flip `[plugins].enabled` in `ewe.conf`, restart the shell (`--no-restart` to defer) |
| `update [id] [--yes]` | fast-forward git-managed plugins; the diff is shown first, a manifest that stops validating is rolled back |
| `remove <id> [--yes]` | delete a git clone; a hand-made directory is moved to `<id>.bak.<stamp>`; forgets the plugin in `ewe.conf` |
| `restore [--yes]` | clone every plugin `ewe.conf` knows that is not installed here — the plugin half of Komble's "For you" |
| `validate <dir>` | check a manifest and its entry points; exit 1 lists every problem |
| `path` | the plugins directory |
| `create <ns.name> [--name T] [--kinds a,b] [--section right] [--dir P]` | **a new plugin repo**: manifest, one working QML per kind, README, MIT licence, `git init` + first commit — push it and it is installable |
| `dev [dir]` | link a working copy into the plugins dir (edits are live after a restart), enable it, restart the shell, follow its log lines |
| `place <id> [--x N --y N] [--layer desktop\|top] [--visible on\|off] [--output NAME] [--reset]` | where a **desktop widget** sits — live, no restart |
| `set <id> <key> <value>` / `get <id> [key]` | a plugin's declared **settings** (typed by its manifest) — live |

Enabling and disabling restart `ewe.service` — there is no QML hot reload,
and a one-second restart is honest about that. The shell's own apps are not
touched by the restart (`KillMode=process`).

## Where things live

```
~/.config/ewe/plugins/<id>/        the plugins — code, outside the ewe payload,
                                   never synced, never touched by upgrades
~/.config/ewe/ewe.conf             [plugins] enabled = [...]   (what is on)
                                   [plugins.sources] id = url (where each came from)
~/.local/state/ewe/plugin-boots.json   the crash guard's counter
```

`[plugins.sources]` **is the installed set**: `add` records a plugin there
whether or not it is enabled, `remove` forgets it, and the file syncs with
the rest of the machine. So on a fresh machine `ewe-plugin list` shows every
plugin your other machine had — on, off or not installed — and
`ewe-plugin restore` clones the missing ones from their git URLs (never
automatic: it asks, or takes `--yes`). A plugin added from a plain directory
is recorded as `"local"`: there is nothing another machine could fetch, and
`restore` says so. Komble's Plugins section and the Welcome flow's restore
step offer the same thing with a button.

## Manifest

A plugin is a git repository with `manifest.json` at its root:

```json
{
  "schemaVersion": 1,
  "id": "acme.weather",
  "name": "Weather",
  "version": "0.1.0",
  "apiVersion": 1,
  "description": "Current conditions in the bar, forecast in a panel.",
  "homepage": "https://github.com/acme/ewe-weather",
  "author": "acme",
  "kinds": ["bar-widget", "panel"],
  "entryPoints": { "bar-widget": "Widget.qml", "panel": "Panel.qml" },
  "barWidget": { "defaultSection": "right" }
}
```

| field | rule |
|---|---|
| `schemaVersion` | `1` |
| `id` | `<namespace>.<name>`, lowercase `[a-z0-9_-]`, at least one dot. `ewe.` is reserved. The install directory is named after it. |
| `name`, `version` | non-empty strings; `version` is what `list` shows |
| `apiVersion` | the shell's plugin API this plugin was written against (`1`); a mismatch is refused at install, not at login |
| `kinds` | one or more of `service`, `panel`, `overlay`, `menu`, `bar-widget`, `desktop-widget` |
| `desktopWidget` | optional, for `desktop-widget`: `{ "x": 48, "y": 64, "layer": "desktop" }` — the default place; the user's own placement in ewe.conf wins |
| `settings` | optional: `[{ "key", "type", "default", "label", "choices"?, "min"?, "max"? }]` with `type` one of `bool`, `int`, `string`, `choice`, `color`. The values reach every entry point as `settings` and render as a form in Komble |
| `entryPoints` | one `.qml` file per kind, relative, inside the plugin (symlinks that resolve outside it are rejected) |
| `barWidget.defaultSection` | `left`, `center` or `right` (default `right`) — where the widget is packed |
| `description`, `homepage`, `author` | optional, shown by `info` |

## Kinds

| kind | what the shell does with it |
|---|---|
| `service` | instantiated headless — a `QtObject`/`Scope` with timers, processes, D-Bus, an `IpcHandler` |
| `panel`, `overlay`, `menu` | instantiated identically to `service`; the plugin owns its `PanelWindow`s and its `IpcHandler`s. The names describe intent (a floating panel, a fullscreen overlay, a summoned menu) so a future UI can group them |
| `bar-widget` | an `Item` the bar packs into its section, between the built-in indicators — see below |

Every entry point except `bar-widget` is created once, under a `Scope`
owned by `PluginHost`. A bar widget is created once **per monitor**, like
every other bar item.

### The bar-widget contract

The entry point's root is an `Item` with an implicit size. The bar's `Row`
packs it; give it the bar's conventions and it will not look foreign:

```qml
import QtQuick
import qs

Item {
    implicitWidth: row.implicitWidth + 2 * Theme.barItemPad
    implicitHeight: Theme.barItemHeight
    Rectangle { anchors.fill: parent; radius: Theme.barItemRadius
                color: ma.containsMouse ? Theme.barHover : "transparent" }
    Row {
        id: row; anchors.centerIn: parent; spacing: 5
        Text { text: Theme.icStar; font.family: Theme.fontIcons; font.pixelSize: Theme.barIconPx; color: Theme.fg2 }
        Text { text: "hello"; font.family: Theme.fontText; font.pixelSize: 12; color: Theme.fg1 }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: Globals.openSettings() }
}
```

Widgets append to their section in id order after the built-ins; the
centre section yields on an output too narrow to hold it. Settings → Layout →
Top bar's show/hide map covers plugins under the key `plugin:<id>` (absent =
shown), so a widget can be hidden without disabling its plugin.

## What a plugin may use

A plugin's QML says `import qs` and sees the shell's modules like any
first-party file. Of those, this is **public** — it will not change without
`apiVersion` moving:

- **`Theme`** — every role: the background ladder `bg1…bg6`, `fg1…fg4`, the
  `brand*`/`accent*` colours, `success`/`warning`/`danger`, `stroke*`,
  `radius*`, the bar metrics (`barHeight`, `barItemHeight`, `barItemRadius`,
  `barItemPad`, `barIconPx`, `barItemSpacing`), the type ramp (`fontText`,
  `fontMono`, `fontIcons`, `fs*`), the durations (`durFast`, `durBase`,
  `durSlow`, `ease`), and the `ic*` Lucide glyphs. Ask for a role, never a
  value — the accent is the user's and changes at runtime.
- **`Globals`** — read: `version`, `accentColor`, `dnd`, `onBattery`,
  `lowPower`, `locked`, `barShows(key)`; call: `openSettings()`,
  `openStore()`, `launchEntry(desktopId)`, `focusWindowByClass(cls)`,
  `playSound(name)`.
- **`Log`** — `Log.info("my.plugin", …)` / `warn` / `debug`. Set
  `HS_LOG_MODULES=my.plugin` to see your debug lines.

Everything else in `Globals` (the `*Open` flags, the notification `server`,
the updater, the `_private` plumbing) is internal and may be renamed without
notice. Use `IpcHandler` for anything a keybind or script should reach:

```qml
IpcHandler { target: "acme.weather"; function toggle(): void { root.shown = !root.shown } }
```

```sh
qs ipc call acme.weather toggle       # bind it in Settings → Keybinds
```

Name IPC targets after your id so they cannot collide with the shell's own
(`bar`, `settings`, `store`, `plugins`, …).

## Safe mode

`ewe.service` relaunches the shell one second after any crash, so a plugin
that compiles and then crashes is not a broken widget — it is a login loop
with no desktop. The guard: every shell start is counted; the **third start
inside a minute** boots with no plugins loaded and a notification names the
plugins that were enabled. Disable the culprit and restart:

```sh
ewe-plugin list            # shows the safe-mode notice and the suspects
ewe-plugin disable acme.weather
```

A start that stays up for a minute clears the counter; the tool's own
restarts (enable/disable/remove) never count. A plugin that fails to
*compile* is not a crash — it is logged (`journalctl --user -u ewe.service`)
and skipped.

## Writing one

1. `git clone https://github.com/prj786/ewe-plugin-example.git my-plugin` —
   a service, a panel with its own IPC, and a bar widget, MIT.
2. Rename `id` (your namespace, your name), edit, then check it:
   `ewe-plugin validate ./my-plugin`.
3. Try it without a repository: `ewe-plugin add ./my-plugin --enable` copies
   it in as a hand-made plugin. Iterate in place under
   `$(ewe-plugin path)/<id>/` and `systemctl --user restart ewe.service`.
4. Push it, `ewe-plugin remove <id>`, and `add` the URL — that is how your
   users will get it, and `update` now works.

The shell's own components are the reference: `Bar.qml`, `Caffeine.qml`
(a small service), `Cast.qml` (a panel with a process behind it) in
`~/.config/quickshell/`.

## `plugins` IPC target

`qs ipc call plugins list` — what the host actually instantiated, as JSON
(fewer than enabled when an entry point failed to compile).
`qs ipc call plugins apiVersion` / `safeMode` — the host's API version and
whether this session booted in safe mode.
