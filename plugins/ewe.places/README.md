# Places — an ewe add-on

`ewe.places` — first-party, ships inside the ewe payload, not installed until
you ask.

A compact file browser in a popup: your home folder at the top, the folders
and files inside it (no dotfiles), a path field with back and home, and a
**Pinned** strip for the folders you keep returning to. Browse into folders
with a click (or Up/Down, Enter, Backspace), open a file with its default
app, **drag any entry out** and drop it as a file into another app — a chat
window, an upload field — or drop a file or folder **onto** the panel to pin
it. Esc closes.

Two ways in, one panel:

- **dock item** — with the Dock add-on installed, a folder in the dock; the
  panel opens above it.
- **bar widget** — a folder in the top bar's right section; the panel opens
  under the bar. Shown per the `button` setting.

    ewe-plugin install ewe.places         # or Komble → Add-ons → Places
    ewe-plugin remove ewe.places

## Settings

Komble → Add-ons → Places, or `ewe-plugin set ewe.places button bar`:

| key | values | default | meaning |
|---|---|---|---|
| `button` | `auto` `bar` `dock` `both` | `auto` | where the button lives — `auto` puts it in the bar only while no dock is present; `dock` never shows it in the bar.; `bar` also hides the dock item. |

Pinned folders are your `[[apps.places]]` in `ewe.conf` — the same list
ewe-settings shows and ewe-sync carries between machines. The panel reads
`~/.config/quickshell/places.json` (ewe-conf's mirror of that list) and
writes through `ewe-conf set apps.places`, never by hand.

## IPC

    qs ipc call ewe.places toggle|show|hide
    qs ipc call places toggle|show|hide       # the shell's pre-0.25 target, kept as an alias

## Needs

`find` (findutils) to list a folder and `xdg-open` (xdg-utils) to open a
file — both ewe dependencies. Layer namespace `quickshell:places`, as before
(Hyprland layer rules and the Glass blur list keep matching). The panel's
window takes input only inside the card, so a drag out of it lands on the
app behind — which is also why a click beside it does not close it.
