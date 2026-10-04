# Phone — an ewe add-on

`ewe.phone` — first-party, ships inside the ewe payload, not installed until
you ask for it.

Your phone through [KDE Connect](https://kdeconnect.kde.org/): a **Mobile**
page in Quick settings (pair a phone, see its battery, read and dismiss its
notifications — reply inline where the app allows it — and read and answer
your SMS conversations), and a phone glyph in the bar's Quick settings pill
while the phone is paired and reachable, with its battery and an accent dot
for unread phone notifications.

    Komble → Add-ons → Phone                 # or:
    ewe-plugin install ewe.phone
    qs ipc call quicksettings tab mobile     # the page (the key the shell always used)

Needs `kdeconnect` (the `kdeconnectd` daemon — started by the add-on when it
is installed and not running, since Hyprland processes no XDG autostart) and
`python-dbus` + `python-gobject` for the bridge; all three are ewe
dependencies and are declared in `manifest.json` → `requires`, so Komble can
offer a missing one. Then install **KDE Connect** on the phone; both devices
need the same network.

## How it is built

| file | what it is |
|---|---|
| `Phone.qml` | the model (a directory singleton the three entry points share): devices, pairing, battery, notifications with a persisted seen-set, SMS threads — owns the bridge process |
| `kdeconnect-bridge.py` | the D-Bus side: `dbus-python` + a GLib loop, newline-delimited JSON over stdio (`{"event": …}` out, `{"cmd": …}` in). Runs from this directory |
| `Service.qml` | starts `kdeconnectd` once if needed, starts the bridge, probes it after a suspend (`Shell.resumed`) |
| `Page.qml` | the Mobile page (`quickPage.key` `mobile`) |
| `Status.qml` | the pill glyph (`bar-status`) |

State: `~/.config/quickshell/kdeconnect-state.json` (seen notification ids,
the chosen device) — the path the shell used before this was an add-on, so
an upgrade keeps it. No secrets: pairing keys live in kdeconnectd's own
config.

`EWE_PHONE_NO_DAEMON=1` in the shell's environment stops the add-on and the
bridge from starting `kdeconnectd` — for the nested test harness on a private
session bus, where an activated daemon would be a new device on your network.

`./test.sh` — the bridge's pure functions, the NDJSON framing and the fatal
path, with stub `dbus`/`GLib` modules; no bus, no phone.
