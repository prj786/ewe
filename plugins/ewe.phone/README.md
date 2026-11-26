# Phone — an ewe plugin

`ewe.phone` — first-party, ships inside the ewe payload, not installed until
you ask for it.

Your phone in ewe, through [ewe Mobile](https://github.com/prj786/ewe-mobile)
(and the KDE Connect protocol daemon that carries it): a **dock button** with
the phone's apps and files, a **Mobile** page in Quick settings (pair a phone, see its battery, read and dismiss its
notifications — reply inline where the app allows it — and read and answer
your SMS conversations), and a phone glyph in the bar's Quick settings pill
while the phone is paired and reachable, with its battery and an accent dot
for unread phone notifications.

    Komble → Plugins → Phone                 # or:
    ewe-plugin install ewe.phone
    qs ipc call quicksettings tab mobile     # the page (the key the shell always used)

## The dock button

A phone button in the dock (`dock-item`, action `ewe.phone.toggle`; also
`qs ipc call ewe.phone toggle`). Hidden while no phone is paired, lit while its
card is open. The card, above the button:

- **head**: the phone's name, its battery and whether it is in reach; *Mirror
  screen* (`ewe-mobile --screen`) and *Open ewe Mobile* — only where
  `ewe-mobile` is installed.
- **Apps**: search and a grid of the phone's apps with their real icons.
  Click opens the app (here when ewe Mobile's adb link is up, else on the
  phone — `ewe-mobile --open-app` decides); right-click: *Open here* / *Open on
  the phone*. A phone that runs the stock KDE Connect app shows "Install ewe
  Mobile on your phone to see its apps here"; a phone that is away shows the
  last list from the cache, dimmed, with the reason opening is off.
- **Files**: Camera, Screenshots, Downloads, Documents, Music, Movies and the
  internal storage. One click mounts the phone (`mountAndWait`) and opens the
  folder in ewe Files (`ewe-files-app <folder>`, `xdg-open` without it); a
  folder the phone does not have is greyed; a phone that is asleep or away
  says so in words, with Try again.
- **keys**: type to search · arrows move · Enter opens (Shift: on the phone,
  Ctrl: here) · Tab flips Apps / Files · Esc clears the search, then closes.
  Automation: `qs ipc call ewe.phone tab|search|pick …`.

### Where the apps come from (the cache)

ewe Mobile for Android sends its launchable apps as its `remotecommands` list
(contract C1 in ewe-mobile's `docs/ECOSYSTEM.md`). The bridge reads it for
each paired device that is ewe Mobile (a list with an `ewe` key, `v` >= 1),
follows `commandsChanged`, **validates it** (package `[A-Za-z0-9._]{1,255}`
with no leading, trailing or doubled dots; names cut to 200 characters with no
control characters; an icon must be a square PNG of 16–512 px and 256 KB at
most — a bad icon costs the app its icon, never its place) and writes the C2
cache `$XDG_CACHE_HOME/ewe-mobile/<deviceId>/apps.json` + `icons/<package>.png`
(atomic; an icon is rewritten only when its bytes change; a package that left
the list loses its icon; an unpaired phone loses all of it). `phone_apps.py`
is that code, pure stdlib. The popup reads the same cache when the phone is
away.

### No KDE Connect window anywhere (C6)

Setting **Hide KDE Connect's own windows** (`hide_kdeconnect`, default on).
`hide_kdeconnect.py hide` takes the launcher entries that open a KDE Connect
window (`org.kde.kdeconnect.app`, `.sms`, `.nonplasma`, `.handler`, the daemon
and settings-module entries where they are not already hidden) out of the
launcher the way eep does: a `NoDisplay=true` **copy** in
`~/.local/share/applications` (file types and the `kdeconnect:` scheme still
resolve). Where eep has a card for the entry (`eep list --all`) eep's own verb
does it — `eep remove sys-…`, which also takes the card out of ~/Applications —
and `show` brings it back with `eep install sys-…`. Otherwise the copy is
marked `X-Ewe-Phone-Hides=1`; a user's own entry of the same name is kept
byte for byte under `~/.local/state/ewe-phone/backup/` and put back by `show`.
Setting it off runs `show`: everything returns exactly as it was; a file that
does not carry one of the two marks is never touched. `kdeconnectd` itself stays
— it is the engine.

With [ewe Mobile](https://github.com/prj786/ewe-mobile) installed, the page's
head has a button that opens it — the window with the rest: contacts, the
phone's player, files, a keyboard to type on the phone with. The page stays
the short version; the bar glyph and the page are this plugin's either way
(a window cannot be a layer surface).

Needs `kdeconnect` (the `kdeconnectd` daemon — started by the plugin when it
is installed and not running, since Hyprland processes no XDG autostart) and
`python-dbus` + `python-gobject` for the bridge; all three are ewe
dependencies and are declared in `manifest.json` → `requires`, so Komble can
offer a missing one. Then install **ewe Mobile** on the phone; both devices
need the same network.

## How it is built

| file | what it is |
|---|---|
| `Phone.qml` | the model (a directory singleton the three entry points share): devices, pairing, battery, notifications with a persisted seen-set, SMS threads — owns the bridge process |
| `kdeconnect-bridge.py` | the D-Bus side: `dbus-python` + a GLib loop, newline-delimited JSON over stdio (`{"event": …}` out, `{"cmd": …}` in). Runs from this directory |
| `Service.qml` | starts `kdeconnectd` once if needed, starts the bridge, probes it after a suspend (`Shell.resumed`) |
| `Page.qml` | the Mobile page (`quickPage.key` `mobile`) |
| `Status.qml` | the pill glyph (`bar-status`) |
| `Popup.qml` | the dock button's card (`panel` kind + `dock-item`) |
| `phone_apps.py` | C1 parse/validation and the C2 cache, pure stdlib |
| `hide_kdeconnect.py` | C6: hide / show KDE Connect's launcher entries |

State: `~/.config/quickshell/kdeconnect-state.json` (seen notification ids,
the chosen device) — the path the shell used before this was a plugin, so
an upgrade keeps it. No secrets: pairing keys live in kdeconnectd's own
config.

`EWE_PHONE_NO_DAEMON=1` in the shell's environment stops the plugin and the
bridge from starting `kdeconnectd` — for the nested test harness on a private
session bus, where an activated daemon would be a new device on your network.

`EWE_PHONE_FIXTURE=<file.json>` makes the bridge run without a phone or a bus,
from a fixture (devices, the C1 object each phone sends, a directory standing
in for the mounted storage; the file is re-read when it changes) — the popup
can be looked at in the nested shell. See `FixtureBridge` in the bridge.

`./test.sh` — the bridge's pure functions, the NDJSON framing and the fatal
path, with stub `dbus`/`GLib` modules; C1 with hostile fixtures; C2 (atomic
rename, stale icons); the bridge in fixture mode end to end; the hide/show
files (with and without a stub eep); no bus, no phone.
