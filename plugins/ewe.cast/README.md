# Cast to TV — an ewe add-on

`ewe.cast` — first-party, ships inside the ewe payload, not installed until
you ask for it.

Mirror the screen to a TV from Quick settings: Miracast (Samsung "Screen
Mirroring", Android TV — over Wi-Fi Direct) and Chromecast / Google TV. The
protocols live in ewe's headless casting engine
[`ewe-castd`](https://github.com/prj786/ewe-cast) (RFC-004); this add-on is
the shell's end of it — the sink list, the tile, the bar glyph, the
Super+Shift+C bind, and the narrated handshake.

## Install

Komble → Add-ons → **Cast to TV**, or:

    ewe-plugin install ewe.cast
    ewe-plugin remove ewe.cast            # gone until you install it again

## What you get

| kind | file | shows |
|---|---|---|
| `quick-page` | `Page.qml` | the **Cast** page (rail entry, key `cast`): the displays in range, pick one → the shell's SharePicker → streaming; a switch that hangs up |
| `quick-tile` | `Tile.qml` | a **Cast** tile on the Quick settings home: idle it opens the page, while casting it is lit (busy until the picture is on the TV) and a click hangs up |
| `bar-status` | `Status.qml` | the screencast glyph in the bar's Quick settings pill while a session exists — accent once streaming |
| `service` | `Service.qml` | the headless client: starts and talks to `ewe-castd`, narrates Wi-Fi Direct from the system journal, owns the legacy path |

**Super+Shift+C** (a manifest keybind, active while the add-on is enabled):
hang up when a cast is live, otherwise open the sink list.

## IPC

Target `ewe.cast`; the pre-0.25 target `cast` is kept as an alias with the
same verbs, so old keybinds and scripts keep working.

    qs ipc call ewe.cast toggle           # Super+Shift+C
    qs ipc call ewe.cast scan             # refresh the displays in range
    qs ipc call ewe.cast start <sink-id>  # cast to one (ids come from the daemon)
    qs ipc call ewe.cast stop
    qs ipc call ewe.cast legacy           # the gnome-network-displays escape hatch
    qs ipc call quicksettings tab cast    # open the page

`legacy` runs `gnome-network-displays` (its own window picks the TV; closing
it ends the session) with the preflight `cast-check.sh`, the app log captured
to `~/.local/state/ewe/cast.log`, and `cast-audio.sh` moving your audio onto
the TV sink and back. It stays until `ewe-castd`'s Miracast path has
survived a real Samsung.

## Settings

None. The daemon's socket is `$XDG_RUNTIME_DIR/ewe-cast.sock`; in
development `EWE_CASTD=/path/to/ewe-castd` runs a checkout instead of the
installed user unit.

## Requires

Declared in the manifest (`requires`), installed by ewe itself (and reported
by Komble when missing): `ewe-cast` (the engine), `gnome-network-displays`
(the legacy path), `avahi` (Chromecast discovery), `iw`, `wireless-regdb`,
`gst-plugin-va` (hardware H.264), `gst-plugins-bad`. The system side —
avahi-daemon, the regulatory domain, the Wi-Fi power-save dispatcher, the
patched `xdg-desktop-portal-hyprland` — is ewe's installer (phase 30), not
this add-on.

## Troubleshooting

Before anything else run the preflight; it checks every known failure class
and prints the fix for each:

    sh ~/.config/ewe/plugins/ewe.cast/cast-check.sh

- **App log** (legacy path, full GLib debug trace): `~/.local/state/ewe/cast.log`
- **Wi-Fi Direct handshake**, live: `journalctl -f -u NetworkManager -u wpa_supplicant`
  — the service turns these lines into notifications while an attempt runs
  (`supplicant-timeout` with no GO negotiation = the TV wasn't listening:
  open Source → Screen Mirroring on it first)
- **Picture freezes / TV drops ~10 s after connecting**: the portal's
  screencopy bug — `pacman -Q xdg-desktop-portal-hyprland` must be
  ≥ 1.4.1-1.1 (ewe ships the patched build)
- **Lag**: software H.264 (install `gst-plugin-va`), a 2.4 GHz link, or
  `iw reg get` → `country 00`
- **No sound on the TV**: `pactl get-default-sink` should name the
  `gnome_network_displays_*` sink while casting
- **"cast engine not installed"** on the page: the `ewe-cast` package is
  missing, or `systemctl --user status ewe-cast.service` says why it won't start

`ewe-diag` (the workspace skill) gathers all of the above in one go.

## Tests

    ./test.sh

Syntax-checks the scripts and the manifest, and runs `cast-check.sh` and
`cast-audio.sh` against fake `systemctl` / `iw` / `pacman` / `pactl` — no
compositor, nothing touches the machine.

MIT.
