# Mail — an ewe add-on

`ewe.mail` — first-party, ships inside the ewe payload, not installed until
you ask for it.

Unread mail where you look: an **Inbox** page in Quick settings (the latest
ten messages, a click opens one), an envelope with the unread count in the
bar's Quick settings pill while there is unread mail, and a notification for
new mail (once per message, never again after a restart — and never a storm
for mail that was already there).

    Komble → Add-ons → Mail                  # or:
    ewe-plugin install ewe.mail
    qs ipc call quicksettings tab mail       # the page (the key the shell always used)

Two sources, one inbox — IMAP wins when both are set up:

- **any IMAP account** — added in Settings → Account → Mail (the core
  `ewe-mail` tool keeps the account in `ewe.conf` and the password in the
  keyring; this add-on only runs `ewe-mail status` and `ewe-mail unseen`).
- **Gmail** — through your own Google client connected in ewe-sync (ewe ships
  no Google client). The add-on asks the core broker `ewe-auth token` for a
  short-lived access token; the refresh token never leaves the keyring and
  no token is ever written to disk. Read-only scope; the Gmail History API
  tells new arrivals from old unread mail.

Polls every 2 minutes (5 on battery), when Quick settings opens with a stale
inbox, and after a suspend (`Shell.resumed`).

## IPC

`qs ipc call mail <verb>` — the target the shell always had — and the add-on's
own `qs ipc call ewe.mail <verb>`, same verbs:

| verb | what |
|---|---|
| `status` | one JSON object: `probed source available title imapConfigured imapHost imapUser imapKeyring unread state error notify needsReconnect` (what ewe-settings → Account reads) |
| `refresh` | re-read both accounts, then fetch |
| `fetch` | fetch the active source |
| `setNotify <true\|false>` | new-mail notifications on or off |

## Files

| file | what it is |
|---|---|
| `Inbox.qml` | the model (a directory singleton the entry points share): IMAP + Gmail, one shape |
| `Service.qml` | the two IPC targets, the resume hook |
| `Page.qml` | the Inbox page (`quickPage.key` `mail`) |
| `Status.qml` | the pill envelope + count (`bar-status`) |

State (ids, flags, counts, the latest rows — nothing secret, Rule 2):
`~/.config/quickshell/mail-state.json` (IMAP) and
`~/.config/quickshell/google-mail.json` (the Gmail History cursor and
notified-set) — the paths the shell used before this was an add-on, so an
upgrade re-notifies nothing.

`./test.sh` — the manifest's compat contract, both IPC targets with the four
verbs, the `status` field set, no secrets persisted, Rule 8.
