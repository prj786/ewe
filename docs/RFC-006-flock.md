# RFC-006 — Flock, the account app

*Status: proposed (owner idea, 2026-09-02) · builds on RFC-005 · a fourth
first-party Tauri app in its own repo `prj786/flock`, shipped preinstalled
by the `ewe` package from ISO 0.9-alpha on*

## The idea

One app owns everything "cloud": the Nextcloud account, the sync of
`ewe.conf`, the list of your machines, and which folders sync where. It has
a tray icon like Komble's, our UI, our theme. Komble installs apps and
writes the manifest; ewe-settings edits `ewe.conf`; **Flock** moves the one
file and your folders between machines. Nothing else has a sync button.

Name: **Flock** — your machines are the flock, and the one file is what
makes them one animal (Dolly). Binary `ewe-flock` (`flock` is taken by
util-linux), desktop id `io.github.prj786.flock`.

## What the research says (2026-09-02)

**Login.** Nextcloud's Login Flow v2 is the only sanctioned way for a
desktop app to obtain credentials; it yields an app password that appears
under the user's Security page as a device. `ewe-cloud` (RFC-005 phase 1)
already implements it; Flock drives that, it does not reimplement it.

**Registration.** There is no public way to create an account on someone
else's Nextcloud. The OCS Provisioning API creates users but needs
*admin* credentials; the Registration app is a server-side web form that a
provider may or may not enable. So Flock cannot register users on Murena,
tab.digital, Disroot or a self-hosted server it does not administer. What
it can do honestly: a **"Create an account"** screen that lists providers
with their signup pages (opened in the browser), then runs the login flow.
Running an ewe-hosted Nextcloud so that registration works in-app would put
the owner back in the loop as an operator (cost, abuse, backups, liability)
— the exact thing RFC-005 removes. Not proposed.

**Folder sync engine.** Writing a two-way file sync (renames, conflicts,
partial uploads, chunking) is a multi-year project — the Nextcloud desktop
client *is* that project. Its package also ships **`nextcloudcmd`**, a
headless one-shot sync of one local folder against one remote folder with
the same engine (conflict files, exclude lists, `--unsyncedfolders`,
`--path`, `--exclude`). Flock's folder sync = *our* UI and scheduler
(inotify + interval + on-login) around `nextcloudcmd` runs, one per folder
pair. The desktop client's own GUI and tray are never started; we ship
`nextcloud-client` for the binary only. If `nextcloudcmd` ever proves too
slow for big trees, the fallback is `rclone bisync` (also headless); the UI
does not change.

**Sync of settings and apps.** Unchanged from RFC-005: `ewe-conf push/pull`
over WebDAV with `If-Match`, the manifest read by Komble. Flock adds a
machine registry — `ewe/machines/<hostname>.json` next to `ewe.conf`
({name, last_seen, ewe_version, apps_count}) — so the UI can show "your
machines" and which one saved the backup.

## The app

```
Flock (Tauri v2 + Svelte 5, tray via SNI like Komble)
├─ Account      sign in (server URL → browser), who/quota/server, sign out,
│               "Create an account" (provider links), keyring trouble → reset
├─ This machine ewe.conf: last synced, backup saved by, Sync now / Back up
│               now / Restore…; auto-sync toggle (= [sync].enabled)
├─ Machines     the registry: name, last seen, ewe version, apps; "Restore
│               from <machine>"; forget a machine
├─ Folders      pairs: local ↔ remote, mode (two-way · upload · download),
│               trigger (on change · every N min · on login), excludes;
│               status per pair, last run, conflicts list with "keep mine /
│               keep theirs"; Add folder (picker) — default pair
│               ~/Nextcloud ↔ / on first sign-in, opt-in
└─ tray         icon = state (idle / syncing / conflict / offline / signed
                out), themed menu: Sync now · Pause · Open Flock · Quit
Backends: ewe-cloud (identity), ewe-conf (the one file), nextcloudcmd
(folders), secret-tool (keyring). Rust side spawns argv-only, never a shell.
Privileges: none — everything is the user's own files.
```

`ewe.conf` gains the folder definitions (synced like everything else; the
local path is per-machine and lives in `~/.local/state/ewe/flock.json`):

```toml
[[sync.folders]]
remote = "/"            # in the account
local  = "~/Nextcloud"  # default; per-machine override in state
mode   = "two-way"      # two-way | upload | download
trigger = "change"      # change | interval | login
interval = 10           # minutes, when trigger = interval
exclude = [".git", "node_modules"]
```

## What moves, what goes

| today | after Flock |
|---|---|
| Welcome → Sign in to Nextcloud (shell) | stays in the shell (it is one field + the browser); on success the shell writes `[sync]` and Flock picks it up |
| Settings → Account card (shell + ewe-settings) | a launcher: who is signed in + **Manage in Flock**; Google (optional) card stays in Settings (mail/Drive client file) |
| Komble For You / sync buttons | gone (RFC-005 phase 4); For You reads the manifest |
| Google.qml sync/restore | gone (RFC-005 phase 2) |
| ewe-files (rclone mount) | retired once Flock's folder sync ships |
| Nextcloud desktop client GUI/tray | never started; package kept for `nextcloudcmd` |

## Phases

| # | what | gate |
|---|---|---|
| F1 | repo `prj786/flock`: Tauri scaffold in the family design system, tray, Account + This machine + Machines panes on top of ewe-cloud/ewe-conf; PKGBUILD; CI (fmt, clippy, build, release on tag) | builds; signs in against the mock; `ewe.conf` round-trips through the UI |
| F2 | Folders: pair model, `nextcloudcmd` runner (inotify + interval + login), conflicts UI, excludes | mock-WebDAV test: two-way pair syncs a tree both ways, a conflict shows and resolves |
| F3 | integration: ewe package depends on flock; Welcome/Settings launchers; ewe-repo publish builds it from its release; website page | ISO 0.9-alpha boots to Welcome → sign in → Flock tray appears signed in |
| F4 | QEMU e2e on the owner's account, then bare metal | the restore demo, recorded |

Order with RFC-005: phases 1–4 of RFC-005 are the plumbing Flock sits on and
are in progress on the `nextcloud` branches; F1 starts as soon as RFC-005
phase 2 has Cloud.qml's contract, F3 merges with RFC-005 phase 5 into ISO
0.9-alpha.

## Owner decisions

1. Name **Flock** / binary `ewe-flock` — yes/no?
2. Default folder pair on first sign-in: opt-in (proposed) or automatic?
3. Providers on the "Create an account" screen: Murena, Disroot, tab.digital,
   Infomaniak, "I run my own"?
4. Does Flock also own the Google optional card (mail/Drive), or does that
   stay in Settings (proposed: stays in Settings — it is a client-file
   configuration, not a cloud account)?
