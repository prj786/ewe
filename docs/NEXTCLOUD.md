# Your Nextcloud account in ewe

ewe signs in to **your** Nextcloud — a server you run, or a hosted account
from a provider such as Murena, Disroot or Infomaniak — and uses it for
three things. Nothing about the account is baked into ewe; there is no
project client, no vendor console, nobody to ask for permission. See
[RFC-005](RFC-005-nextcloud-account.md) for the reasoning.

| what | where in the account | tool |
|---|---|---|
| the one file (`ewe.conf`) and its backup stamp | `<files>/ewe/ewe.conf`, `ewe.conf.meta.json` | `ewe-conf push` / `pull` |
| your files as a folder | the whole account, mounted at `~/Nextcloud` | `ewe-files` |
| your calendar | CalDAV (the shell's calendar widget) | the shell |

Mail is separate: any IMAP account works for the Control Center badge —
the mail your provider gives you with the Nextcloud account, or Gmail
through the optional Google client (`docs/GOOGLE-CLIENT.md`).

## Signing in

Welcome (first login) and ewe-sync, the account app, both ask for the server
address and open the browser. That is Nextcloud's own **Login Flow v2**:
you sign in on your server's page (with your password, 2FA, SSO — whatever
your server uses), the page asks whether to grant access to *"ewe
(<your computer's name>)"*, and hands ewe an **app password**. ewe never
sees your real password.

From a terminal:

```sh
ewe-cloud login cloud.example.org      # opens the browser; prints JSON when done
ewe-cloud status                       # {signed_in, server, user, display_name, email, quota, keyring…}
ewe-conf push                          # first backup (or: ewe-sync → Back up this machine)
ewe-files setup                        # mount the account at ~/Nextcloud
```

## What is stored where

- **The app password** — only in the keyring (Secret Service, entry
  `service=ewe-cloud`). It is the single credential; `ewe-cloud token`
  reads it for rclone and the shell.
- **Non-secret account facts** — `~/.config/ewe/cloud.json`: server, login
  name, display name, email, when you signed in.
- **In `ewe.conf`** — `[sync] provider = "nextcloud"`, `server`, `user`,
  `folder`, `enabled`. Identity, never a secret, so a restored machine
  knows where its backup lives.
- **Sync record** — `~/.local/state/ewe/sync.json`: the ETag this machine
  last saw, who saved the remote copy and when, when this machine last
  synced. That record is the whole conflict rule (below).
- **rclone remote** — `~/.config/ewe/rclone-nextcloud.conf` (mode 0600),
  regenerated from the keyring by `ewe-files setup`.

## Sync, conflicts, other machines

`ewe-conf push` uploads `ewe.conf` with `If-Match: <the ETag recorded at
the last sync>`. If another machine saved in between, the **server** answers
412 and ewe reports `remote-newer`: pull theirs, or push with `--force`. A
machine that has never synced and finds a backup gets `remote-exists`:
restore first (Welcome offers exactly that), or force. No clocks, no
hostnames, no race window — the guard is the server's.

`ewe.conf.meta.json` next to the file records which machine saved it and
when, purely so the account card can say *"backup saved by laptop, 5 min
ago"*.

## Your server's side

- Nextcloud → **Settings → Security → Devices & sessions** lists *ewe
  (<computer>)*. Revoking it there signs that machine out; ewe notices
  (`status` reports `reason: revoked`) and asks you to sign in again.
- `ewe-cloud logout` revokes the app password itself and clears everything
  local.
- Only `https://` servers are accepted.

## Troubleshooting

- *"did not answer like a Nextcloud"* — the address is not a Nextcloud
  root. Use the address you open in the browser, without `/index.php/…`.
- *No browser tab opened* — the login link is printed on stderr
  (`login-url: …`) and written to `$XDG_RUNTIME_DIR/ewe-cloud-login-url`;
  Welcome and Settings offer **Open the sign-in page / Copy the link**.
- *keyring-* errors* — the same keyring playbook as for any sign-in:
  `docs/TROUBLESHOOTING.md` → Google sign-in / keyring.
- *`unauthorized` on push/pull* — the app password was revoked on the
  server; sign in again.
