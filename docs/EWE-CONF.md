# `ewe.conf` — the manual

*The machine as one file. This is the human guide to `~/.config/ewe/ewe.conf`;
the architecture and its history live in [RFC-001](RFC-001-one-config.md).*

## The idea

Everything you can express about your desktop — theme, dock, animations,
displays, wallpapers, window rules, pinned apps, what Komble installed —
lives in **one declarative TOML document**. The Settings surfaces edit it,
one tool (`ewe-conf`) applies it, and every runtime file Hyprland and the
shell actually read is *generated from it*. Save this file, restore the
machine.

```
~/.config/ewe/ewe.conf          ← the document (this manual)
ewe-conf apply                  ← turns it into the runtime files
~/.config/hypr/generated/*      ← build artifacts (never edit)
~/.config/quickshell/*.json     ← build artifacts (never edit)
```

Three rules worth internalising:

1. **One writer.** Only `ewe-conf` writes the file. The shell, ewe-settings,
   Komble, and the installer all persist *through* it. You may edit it by
   hand — it round-trips — but every Settings change rewrites the file
   wholesale, and your hand-written comments do not survive. The `#` comments
   you see in the file are regenerated on every write, so it always explains
   itself.
2. **Everything else is generated.** Editing a `generated/` file works
   exactly until the next `apply`, then your change is gone. Change the
   source of truth instead.
3. **Secrets never enter this file.** `ewe.conf` is the thing that syncs to
   your Drive. It may name an account (an email address); it never carries a
   token, password, or private key — those live in the system keyring behind
   the `ewe-auth` broker. If a future feature would need a secret in here,
   the feature is designed differently instead (see *SSH & VPN* below).

## The tool

```
ewe-conf get <dotted.key>          value (JSON on stdout for structures)
ewe-conf set <dotted.key> <value>  value parsed as JSON, else string; then apply
ewe-conf dump                      whole file as JSON (one read for QML/Rust)
ewe-conf import                    build ewe.conf FROM the live runtime files
ewe-conf apply [--only <domain>]   regenerate artifacts + poke the shell + reload Hyprland
ewe-conf path                      print the canonical file path
ewe-conf push [--force]            upload the file to your account (see Sync)
ewe-conf pull [--out <path>]       download it — run `apply` afterwards
ewe-conf sync-status               the remote copy, and this machine's sync record
```

Writes are atomic (tmp + rename) with `flock` around read-modify-write, and
key order is stable, so diffs of the file are honest. `import` exists for
migration and repair: it rebuilds the document from whatever the machine is
actually doing right now — and seeds what a fresh machine lacks: a
`[desktop.layout]` with the defaults, and an `[apps.installed]` baseline
from every explicitly installed pacman package.

`apply` regenerates every artifact — `user.lua` (gaps, rounding, the
accent-tinted border) is rewritten on every apply, so it can never lag
the theme — then, unless `--no-hooks`, re-themes the toolkits, pokes the
shell, and runs `hyprctl reload` when a Hyprland session is up. The shell
passes `--no-hooks` because it applies live itself; from a terminal the
full restore is simply:

```
ewe-conf pull && ewe-conf apply
```

## Sync

`push` uploads the file to the account named in `[sync]`; `pull` downloads
it, keeping the previous local file as `ewe.conf.<timestamp>.bak`. Two
providers speak the same contract ([RFC-005](RFC-005-nextcloud-account.md)):

| `[sync].provider` | where the file lives | the guard |
|---|---|---|
| `nextcloud` | WebDAV: `<server>/remote.php/dav/files/<user>/<folder>/ewe.conf` + `ewe.conf.meta.json` `{machine, saved_at, schema}` | the server's own `If-Match` on the ETag recorded at the last sync (412 ⇒ refused) — no race window |
| `google` | Drive app data (RFC-002; only with a personal OAuth client) | the file id + `modifiedTime` recorded at the last sync |

Both record what they saw — in `~/.local/state/ewe/sync.json` — and that
record is the whole conflict rule:

- a push is refused (`remote-newer`) when the remote is not the copy
  recorded here: another machine saved since this one last synced. `pull`
  to adopt theirs, or `push --force` to overwrite;
- a machine that has **never** synced may push only into an empty remote.
  If a backup already exists it gets `remote-exists`: restore first (the
  Welcome flow offers exactly that), or `--force`. This is what keeps a
  fresh install from erasing the backup it was about to restore.

No clocks and no hostnames take part — two machines both called `ewe`, or
a fresh install with a wrong clock, sync fine. The machine name is still
stamped next to the file, purely so the UI can say *"backup saved by
<name>"*; `sync-status` reports that (`remote_machine`, `remote_modified`)
separately from *when this machine last synced* (`local_synced_at`), plus
`provider`, `server`, `folder`, `enabled` and `in_sync`. Credentials come
from the brokers — `ewe-cloud token` / `ewe-auth token` — never from this
file. `[sync].enabled` is THE auto-sync switch: every `set` schedules a
debounced push when it is on.

## Reference

### `schema = 1`

Version of this document's shape. Bumped only when a key changes meaning.

### `[desktop.theme]` — colours and look

| key | type | default | meaning |
|---|---|---|---|
| `color_scheme` | `"dark"` | `"dark"` | always `"dark"` — ewe is dark-only by decision (2026-09-01); the key stays because Komble reads it to follow the DE |
| `accent` | hex string | `"#0a84ff"` | recolours the whole shell live |
| `theme_name` | `"flock"` \| `"blacksheep"` | `"flock"` | soft greys vs absolute black |
| `tint_borders` | bool | `true` | accent-tinted window borders |
| `window_transparency` | bool | `false` | translucent unfocused windows |
| `avatar_shape` | `"circle"` \| `"rounded"` | `"circle"` | greeter/bar avatar mask |

Applying this section re-runs `colorscheme.sh`, which writes every toolkit's
config (GTK, Qt, cursor, icon hue) in one pass.

### `[desktop.dock]`

`enabled` (bool) · `autohide` (bool — "intelligent hide") ·
`icon_size` (`"small"`/`"medium"`/`"large"`).

### `[desktop.animations]`

`speed` — one multiplier over every animation: `0` (off), `0.6` (brisk),
`1` (default), `2` (showy). `detail` holds per-leaf overrides (enable,
duration, curve per animation) exactly as the Animations pane writes them.

### `[desktop.tiling]`

`enabled` (bool) — the DE's tiling behaviour as one switch.

### `[desktop.power]`

`low_power` (bool — battery-aware timers) · `lid_docked_suspend` (bool —
`false` keeps working on external monitors when the lid closes) · `saver`
(the screensaver stage: `enabled`, `lock`, `lockAfterMin`, `min`, `style`).

### `[desktop.displays]`

Per-monitor-set profiles, verbatim from Settings → Displays. Keyed by the
identity of every connected monitor, so docking at a desk restores that
desk's layout. Owned entirely by the Displays UI — hand-editing this section
is possible but the UI is the better editor.

### `[[desktop.window_rules]]`

One block per app: `name`, `class` (matched case-insensitively), `workspace`
(0 = any), `mode` (`"float"` or `""`).

### `[desktop.wallpapers]`

`mode` (`fill`/…) · `mute` (video sound) · `default` (path for every output)
· `[desktop.wallpapers.outputs]` per-output overrides. Images, GIFs, and
videos are all valid paths.

### `[desktop.input]`

Keyboard and pointer, whole: `kb_layout`/`kb_variant` (comma-joined parallel
lists), `kb_options`, repeat rate/delay, numlock, sensitivity, acceleration
profile, natural scroll, scroll factors, the eight touchpad switches, and
`[desktop.input.devices]` — per-device overrides keyed by device name.
`apply` generates both `hypr/generated/input.lua` and
`quickshell/input-devices.json` from this.

### `[desktop.layout]`

Four numbers — `gaps_in`, `gaps_out`, `border_size`, `rounding`. Everything
else in `generated/user.lua` (border tint + accent, window transparency,
animation speed fallback, the tiling float rule) is derived from the other
domains, so changing any of them regenerates the file.

### `[[desktop.keybinds]]`

Your own launch bindings: one `{combo, exec}` record each, e.g.
`{combo = "SUPER + T", exec = "kitty"}` → `generated/keybinds.lua`. Exec
binds only — a bind that launches something is data and syncs; rebinding
the DE's own dispatchers stays in Lua territory.

### `[apps]`

`pinned` — the dock's pinned launcher list, in order.
`[[apps.startup]]` — login autostart entries (`name`, `exec`, `icon`,
`enabled`).
`[[apps.places]]` — the Places panel's folder shortcuts.
`[apps.installed]` — **Komble's manifest**: every repo package, AUR package,
and AppImage Komble manages on this machine. This is the restore loop: a
fresh install that pulls your synced `ewe.conf` can offer to reinstall all
of it. Komble maintains this section; nothing else touches it.

### `[system]` — what this machine is

Read by the installer and ewe-os tooling only; the desktop never reads it.
`gaming` (Steam + multilib + lib32 drivers) and `development` (dev CLI
stack) record which install profiles this machine carries. Flags only ever
raise on import — a box with Steam installed is a gaming box, whatever the
file said.

### `[sync]`

`provider` (`"nextcloud"` | `"google"`) · `server` · `user` · `folder`
(default `ewe`) · `enabled` (bool, the auto-sync switch). Identity only,
so a restored machine knows where its backup lives. The app password (or
the Google refresh token) lives in the keyring behind `ewe-cloud` /
`ewe-auth`, never in this file.

## SSH & VPN — the `[network]` domain

"My SSH hosts and VPN setup are part of my machine — why don't they restore
too?" They do, with a firm line through the middle:

**Config syncs. Credentials never do.**

- `[[network.ssh.hosts]]` carries your `~/.ssh/config` *host definitions* —
  aliases, hostnames, users, ports, per-host options (an `IdentityFile` line
  is a path, not a key). `import` adopts every single-name host; every push
  re-adopts, so hand edits ride along. On restore, `apply` writes them into
  a marker-bounded **managed block** at the end of `~/.ssh/config` — your
  own lines are never touched, and hosts you already define yourself are
  skipped (first match wins in ssh config). Keys are yours to bring; the
  aliases just work again.
- `[[network.vpn]]` carries NetworkManager VPN *profile definitions* — name,
  type, service, and the non-secret `vpn.data` property string (OpenVPN's
  remote/port, L2TP/IPsec's gateway/user/ipsec-enabled; the `*-flags`
  entries that say where THIS machine stores a secret are dropped). On
  restore, missing profiles are recreated as skeletons; the first connect
  from the Control Center or Settings → Network opens an inline credentials
  form (username, password, and the IPsec pre-shared key for L2TP) and
  stores them in the profile — the toggle just works from then on.
  WireGuard is recorded by name only — its peer config holds key material,
  so re-importing your `.conf` is the honest path there.
- Deletions go through `ewe-conf unset` (adoption is a union — removing a
  host locally doesn't remove it from the file, because it may belong to
  another machine).

Why not sync the secrets too, encrypted? Because the synced file then
becomes a vault, and a vault needs key management, passphrase UX, rotation,
and a threat model — a different product. Dedicated secret managers do this
well; `ewe.conf` stays a document you can `cat`, diff, and email to yourself
without a second thought. That is rule 3, and it is load-bearing.

## Editing by hand

Entirely supported, with the caveats above:

```sh
$EDITOR "$(ewe-conf path)"    # edit
ewe-conf apply                # make it real
```

A syntax error fails `apply` loudly and changes nothing — the generated
files are only replaced by a successful run. If the file and reality ever
disagree (a fresh machine, a repair), `ewe-conf import` rebuilds the
document from the live system.

## desktop.browser — Helium

| key | default | meaning |
|---|---|---|
| `desktop.browser.layout` | `"vertical"` | Helium tab layout: `"vertical"` (ewe's default) or `"horizontal"`. Applied by `helium-theme.sh` (run by every theme change) the next time the browser starts while closed; the browser chrome itself always follows `desktop.theme` (flock/blacksheep surface + accent). |

