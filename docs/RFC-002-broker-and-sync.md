# RFC-002 — ewe-auth and the sync of the one file

*Status: steps 1–3 SHIPPED and verified against real Google (broker token
from a live session; ewe.conf → Drive appData → back, byte-identical).
Remaining: komble's restore surface (4), legacy-pipeline retirement (5),
and the owner minting the fresh "ewe" client (docs/GOOGLE-CLIENT.md — a
drop-in file swap). Target: ewe OS 0.5-alpha "connected".*

The promise: **log in, get your machine back.** `ewe.conf` already describes
the machine; this RFC moves it to the user's Google Drive and gives every ewe
app one shared Google identity to do it with.

## Why a broker, and why now

Today Google OAuth lives inside the shell (Google.qml): it owns the client
config, the refresh token (keyring), the access-token refresh loop, and the
sync of its own caches. Komble runs a *separate* restore pipeline off files
the shell wrote. Known state: **the existing google sync has unresolved bugs
the owner deferred** — so this RFC deliberately REPLACES that pipeline's
foundation instead of patching around it.

`ewe-auth` is a small broker (python, stdlib + keyring via libsecret CLI or
D-Bus) owning exactly three things:

1. **the refresh token** — in gnome-keyring, nowhere else, ever;
2. **access tokens** — `ewe-auth token [scope-set]` prints a short-lived
   access token, refreshing under an flock when expired. Shell, komble and
   future apps call this instead of doing OAuth;
3. **sign-in/out** — `ewe-auth login` runs the loopback-redirect flow once
   for all apps; `ewe-auth logout` revokes + wipes.

The shell's Google.qml shrinks to a *consumer* (profile/mail/calendar reads
through the broker). One client id, one consent screen, one sign-out.

## Sync of the file

- Target: Drive **appDataFolder** (hidden app storage, not user-visible file
  clutter; scoped so the app sees only its own data).
- Unit: `ewe.conf` verbatim + a small manifest (schema version, machine name,
  updated-at). No credentials by construction (RFC-001 rule 4).
- Direction rules, deliberately boring:
  - upload after every `ewe-conf` write, debounced (30 s), only when
    `[sync].enabled`;
  - download on demand only — `ewe-conf pull` (and the greeter/first-login
    "restore this machine?" flow) — never silent overwrite in the background;
  - conflicts: newest-wins with the loser saved as `ewe.conf.<timestamp>.bak`
    beside the file. One file makes conflict recovery a diff, not a hunt.
- Restore: `ewe-conf pull && ewe-conf apply` rebuilds the desktop; komble
  reads `[apps.installed]` and offers the reinstall list (explicit confirm —
  a restored file must never silently install software).

## What moves where

| piece | today | after |
|---|---|---|
| OAuth client + refresh token | shell (Google.qml + keyring) | `ewe-auth` (keyring) |
| access-token refresh | shell | `ewe-auth token` |
| komble Google access | none (separate restore files) | `ewe-auth token` |
| settings backup | google-sync.json pipeline (buggy, deferred) | `ewe.conf` ⇄ Drive appData |
| app restore list | google-restore-* files | `[apps.installed]` in the file |

## Order of work (0.5)

1. `ewe-auth` CLI + keyring storage + login flow; shell keeps working
   untouched (parallel install).
2. Shell's Google.qml consumes the broker (delete its own token plumbing).
3. `ewe-conf push/pull` + debounced upload hook + `[sync]` wiring.
4. komble: restore surface reading `[apps.installed]`.
5. Retire the legacy google-sync/restore pipeline once 1–4 hold on the
   owner's machine — its deferred bugs die with it rather than being fixed.

Open question for the owner: keep the current Google OAuth client id (shell's)
as the shared one, or mint a fresh "ewe" client so consent screens say the
right name? Fresh client means one re-login for existing setups.
