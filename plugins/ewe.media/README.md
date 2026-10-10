# Music — an ewe plugin

`ewe.media` — first-party, ships inside the ewe payload, not installed until
you ask.

The now-playing card: cover art, the source, title and artist, previous ·
play/pause · next, and a seek bar with times whenever the player publishes a
position and a length. Any MPRIS player — Spotify, a browser tab, mpv with
`mpv-mpris`, Stremio — through `Quickshell.Services.Mpris`; the one that is
playing wins, else the first controllable player with a track.

Two ways in, one card:

- **dock item** — with the Dock plugin installed, a music note in the dock;
  the card opens above it.
- **bar widget** — a music note in the top bar's right section; the card
  opens under the bar. Shown only while a player exists (like the dock
  button always was), and per the `button` setting.

    ewe-plugin install ewe.media          # or Komble → Plugins → Music
    ewe-plugin remove ewe.media

## Settings

Komble → Plugins → Music → Options, or `ewe-plugin set ewe.media <key> <value>`.
`button` decides where it shows, so there is no Show in bar switch for it
(the manifest's `barWidget.toggle: false`):

| key | values | default | meaning |
|---|---|---|---|
| `button` | `auto` `bar` `dock` `both` | `auto` | where the button lives — `auto` puts it in the bar only while no dock is present; `dock` never shows it in the bar.; `bar` also hides the dock item; the dock item is shown only while a player exists, unless `always_show`. |
| `always_show` | bool | `false` | keep the bar button in place when nothing is playing |

## IPC

    qs ipc call ewe.media toggle|show|hide
    qs ipc call player toggle|hide            # the shell's pre-0.25 target, kept as an alias

With nothing playing, `toggle` says so in a toast instead of opening an
empty card.

## Needs

`busctl` (systemd) — the play/pause button sends the spec's combined
`PlayPause` verb directly, the one every player answers. Media keys and the
screensaver's MPRIS hold-off stay in the shell core. `mpv-mpris` makes mpv
show up here; `playerctl` is not used.

Layer namespace `quickshell:mediaplayer`, as before (Hyprland layer rules
and the Glass blur list keep matching).
