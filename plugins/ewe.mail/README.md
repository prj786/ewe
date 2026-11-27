# Mail — an ewe plugin

`ewe.mail` — first-party, ships inside the ewe payload, not installed until
you ask for it.

Unread mail where you look: an **Inbox** page in Quick settings (the latest
ten messages, a click opens one), an envelope with the unread count in the
bar's Quick settings pill while there is unread mail, and a notification for
new mail (once per message, never again after a restart — and never a storm
for mail that was already there).

    Komble → Plugins → Mail                  # or:
    ewe-plugin install ewe.mail
    qs ipc call quicksettings tab mail       # the page (the key the shell always used)

Since 2.0 the one source is **ewe Mail** (`ewe-mail`, preinstalled with ewe):
the plugin runs `ewe-mail-app --inbox` and shows what it answers — every
account, Gmail and any other mailbox, in one inbox. A click on a row or on a
new-mail notification opens that message in ewe Mail; the page's button is
**Open ewe Mail**. The plugin no longer polls Gmail or IMAP itself: one
engine and one cache (ewe Mail's), one Gmail poller, and no token or
password anywhere near the shell.

Accounts are added in ewe Sync: **Google** for Gmail (your own Google client
file; ewe ships none) and **Mail** for any other mailbox. "Reconnect Google"
opens ewe Sync's Google page when Gmail can only read.

Looks every 2 minutes (5 on battery), when Quick settings opens with a
stale inbox, when ewe.conf or the Google sign-in changes, and after a
suspend (`Shell.resumed`).

## Settings

`notify` (on by default) — a notification for each new message. Komble →
Plugins → Mail → Options, the bell on the Inbox page, `qs ipc call mail
setNotify false` or `ewe-plugin set ewe.mail notify false` all change the
same setting (ewe.conf `[plugins.settings]."ewe.mail"`). 1.0 kept it in
`mail-state.json`; an "off" there is carried over once. ewe Settings →
User no longer has a Mail section.

## IPC

`qs ipc call mail <verb>` — the target the shell always had — and the plugin's
own `qs ipc call ewe.mail <verb>`, same verbs:

| verb | what |
|---|---|
| `status` | one JSON object: `probed source available title imapConfigured imapHost imapUser imapKeyring unread state error notify needsReconnect` |
| `refresh` | re-read both accounts, then fetch |
| `fetch` | fetch the active source |
| `setNotify <true\|false>` | new-mail notifications on or off (writes the `notify` setting) |

## Files

| file | what it is |
|---|---|
| `Inbox.qml` | the model (a directory singleton the entry points share): what `ewe-mail-app --inbox` says |
| `Service.qml` | the two IPC targets, the resume hook |
| `Page.qml` | the Inbox page (`quickPage.key` `mail`) |
| `Status.qml` | the pill envelope + count (`bar-status`) |

State (ids, flags, counts, the latest rows — nothing secret, Rule 2):
`~/.config/quickshell/mail-state.json`, the path the shell used before this
was a plugin. 2.0's first look marks what is already there as seen, so an
upgrade notifies nothing.

`./test.sh` — the manifest's compat contract, both IPC targets with the four
verbs, the `status` field set, ewe Mail as the one source, no secrets, Rule 8.
