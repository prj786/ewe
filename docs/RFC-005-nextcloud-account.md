# RFC-005 — the ewe account is a Nextcloud account

*Status: accepted (owner decision, 2026-09-02) · supersedes the Google half of
RFC-002 · implemented on the `nextcloud` branch of ewe, komble-arch,
ewe-settings, ewe-os and the website; merges as one wave*

## The decision

**ewe's account, identity and settings sync move from Google to Nextcloud.**
The user signs in to *their* Nextcloud — self-hosted or a hosted provider
(Murena, Disroot, Infomaniak, …) — through Nextcloud's own browser login
flow. Everything ewe syncs lives in a folder of that account. Google is
**demoted to an optional extra** for two things only, mail notifications
and the Drive folder, and only when the user brings their own OAuth client
file. **ewe ships no Google client at all.**

Why:

- **No gatekeeper.** WebDAV, CalDAV and IMAP need nobody's verification.
  The unverified-app warning, the restricted Gmail scope, the CASA audit,
  the dedicated Google project, the client secret in CI — all gone.
- **The audience.** People who choose an Arch-based desktop are the people
  who do not want Google in their login screen.
- **The owner is out of the loop.** Nothing about the owner's accounts or
  cloud projects lives in the package or the repos.
- **Better sync primitives.** WebDAV gives ETags and `If-Match`: a push
  that races another machine is rejected by the server itself, no clock or
  hostname guesswork (RFC-002's guard becomes the server's job).

## What the user sees

- **Installer** (ISO): unchanged — Network step first, everything else needs it.
- **Welcome** (first login): network → updates → **Sign in to Nextcloud**
  (server URL, then the browser) → restore offer when the account holds a
  backup → tour. The Nextcloud logo is on that card. Google is not on the
  Welcome screen at all.
- **Settings → Account**: the Nextcloud card (who, server, quota, last
  synced, backup saved by which machine), sign out, sync now / back up now,
  restore. Below it, a small **Google (optional)** card: "for Gmail
  notifications and a Drive folder — needs your own OAuth client file",
  with the path to drop it and Connect / Disconnect. ewe-settings is the
  one writer of `ewe.conf` besides the tools.
- **Control Center**: the Mail card and the calendar widget stay; mail is
  IMAP (any account — the Nextcloud provider's, or Google through the
  optional client), calendar is CalDAV from the Nextcloud account.
- **Komble**: no sync, backup, restore or "fetch" buttons. For You reads
  `apps.installed` from `ewe.conf` and offers what is missing; every
  install and removal updates `apps.installed` through `ewe-conf`, with
  `source` ∈ {repo, aur, first-party} and never a path. Restore is a
  Welcome/Settings action; Komble just sees the manifest change.

## Architecture

```
ewe-cloud   (Python, GLib-free stdlib, the house pattern)  — NEW
   login <server>   Login Flow v2: POST /index.php/login/v2 → open the
                    returned login URL in the browser, poll the endpoint
                    until it hands back {server, loginName, appPassword};
                    app password → keyring; server + loginName → auth.json
   status           {signed_in, server, user, display_name, email, quota}
                    via OCS /ocs/v2.php/cloud/user (never prompts)
   token            the app password (for the shell, rclone, ewe-conf)
   logout           delete the app password server-side (OCS) + keyring
   avatar           caches /index.php/avatar/<user>/128 → ~/.cache/ewe
ewe-conf push/pull  provider from [sync].provider ("nextcloud"|"google"):
                    nextcloud = WebDAV at <server>/remote.php/dav/files/
                    <user>/ewe/ewe.conf, sidecar ewe.conf.meta.json
                    {machine, saved_at, schema}; push sends If-Match: <etag
                    recorded at last sync> (If-None-Match: * for the first
                    push) — 412 ⇒ remote-newer; local record stays
                    ~/.local/state/ewe/sync.json {etag, remote_machine,
                    remote_saved_at, local_synced_at}
ewe-auth            unchanged code paths, but: no SHIPPED_CLIENT. Configured
                    only when ~/.config/ewe/oauth-client.json exists. Scopes:
                    gmail.readonly + drive (the user's own client, so the
                    restricted-scope rule is theirs to manage); no calendar,
                    no appdata.
ewe-drive           unchanged (rclone, Google), gated on ewe-auth configured
ewe-files           NEW, rclone webdav mount of the Nextcloud account at
                    ~/Nextcloud (setup · mount · unmount · status) — the
                    Drive-folder feature for everyone
shell               Cloud.qml (singleton: identity, sync, restore — what
                    Google.qml did for sync) · Google.qml shrinks to mail +
                    drive, only when ewe-auth is configured · Calendar reads
                    CalDAV through ewe-cloud (REPORT calendar-query, next 7
                    days, cached) · Mail reads IMAP (imaplib, UNSEEN count +
                    latest subjects) from [accounts.mail] or Google
```

Credentials policy (RFC-001 rule 3 still holds): the app password and IMAP
password live in the keyring only; `ewe.conf` records server, login name,
folder, and the mail account's host/user — never a secret.

## ewe.conf

```toml
[sync]
provider = "nextcloud"          # or "google" (legacy, personal client) or ""
server   = "https://cloud.example.org"
user     = "scubba"
folder   = "ewe"                # <files>/ewe/ewe.conf, ewe.conf.meta.json
enabled  = true                 # THE auto-sync switch (google-sync.json dies)

[accounts.mail]                 # optional; IMAP for the Control Center badge
host = "imap.example.org"; user = "scubba@example.org"; port = 993
# password: keyring. Absent + google configured ⇒ Gmail via ewe-auth.

[accounts.google]               # optional, informational
client = "~/.config/ewe/oauth-client.json"   # present ⇒ the Google card shows
```

`google-sync.json`, `PUSH_STAMP` and the Drive appdata path are removed
after one release of migration: on first start, a machine with a Google
sync record and no Nextcloud is told in the account card that sync now
needs a Nextcloud account; its file is untouched.

## Phases and gates

| # | what | repo | gate |
|---|---|---|---|
| 1 | `ewe-cloud` broker + `ewe-conf` WebDAV backend + `ewe-files` + **mock Nextcloud server** (login v2, OCS user, WebDAV PUT/GET/PROPFIND/If-Match/412) + test suite | ewe | `tests/ewe-cloud-test.sh` + `tests/ewe-conf-sync-test.sh` (both providers) all pass |
| 2 | shell: Cloud.qml, Welcome Nextcloud step, Settings account card, Google.qml reduced, Calendar via CalDAV, Mail via IMAP | ewe | nested-shell screenshots of Welcome + account card; `qs` log clean |
| 3 | ewe-settings Account pane (Nextcloud + optional Google), Mail account form | ewe-settings | builds; CI fmt/clippy |
| 4 | Komble: sync/backup/restore UI removed; manifest writes verified after every install/remove/AppImage; For You reads only | komble-arch | builds; manual: install → `ewe-conf get apps.installed` shows it |
| 5 | ISO: `oauth-client.json` injection removed from ewe-repo publish and the package assertion; ewe-os docs; website account page recommends providers | ewe-repo, ewe-os, site | publish green without the secret; ISO boots to Welcome with the Nextcloud card |
| 6 | **e2e on a real account** (owner's Nextcloud): sign in, push, second machine (QEMU) pulls, conflict, restore, apps reinstall, calendar + mail cards | all | the restore demo, recorded |

Each phase lands on the `nextcloud` branch of its repo; main keeps taking
ISO hotfixes. The wave merges together and ships as DE 0.10.0, Komble and
ewe-settings 0.10.0, ISO 0.9-alpha.

## Owner decisions still open

1. Which hosted providers the website recommends (proposed: Murena,
   Disroot, Infomaniak; self-hosting first).
2. Folder name in the account (proposed `ewe/`).
3. Whether Google Calendar stays reachable through the optional client
   (proposed: no — calendar is CalDAV only; fewer scopes, fewer surprises).
4. ~~Desktop client or rclone mount~~ — **decided 2026-09-02: the official
   Nextcloud desktop client (`nextcloud-client`, Arch extra) ships with ewe
   and is the files path.** After the ewe sign-in the shell hands the same
   account to the client through its `nextcloud://login/server:…&user:…&
   password:…` scheme, so the user signs in once; the sync folder is
   `~/Nextcloud`, bookmarked in Nemo. `ewe-files` (rclone) stays only as
   the fallback when the client is absent. The shell's tray opens the
   themed menu on left-click for menu-on-activate apps (the client's own
   Qt menu is unusable under a layer-shell tray).
5. A test account for phase 6, and whether the owner's own account may be
   used for it.
