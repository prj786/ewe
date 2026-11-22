# RFC-010 — eep: apps from the Nix binary cache

*Status: **accepted** 2026-11-22 — the prototype passed every go/no-go row
(`eep/bench/RESULTS.md`) and the owner said go the same day ("Let's commit
and release"). Repo: `prj786/eep`; the package `eep` is in `[ewe]`
(opt-in: nothing depends on it yet); Komble 0.26 and ewe Files 0.3 speak
eep. Rule 10 now reads "pacman for the system, eep for apps".*

## The problem

Arch's official repositories are small, the AUR is hard to manage and slow
(it builds on your machine), AppImages are often outdated and heavy.
ewe users want "click, it's there; delete, it's gone" — the way a phone
does apps — with current versions and small updates.

## The proposal

1. **One card per app.** `~/Apps/Firefox.eep` (TOML, ~1 KB). The card there
   means the app is in the launcher; delete the card (or move it to Trash)
   and the app is gone, its disk freed at the next `eep gc`. Restore from
   Trash before that and it is back without a download. Double-click a card
   from anywhere to install and start it.
2. **Prebuilt, signed apps from cache.nixos.org** (nixos-unstable: it
   matches Arch's versions). The client **never evaluates Nix**: an eep
   server makes a per-release index (one Nix evaluation per release) that
   lists exactly which store paths an app needs.
3. **Updates are binary patches** made by the eep server (zstd
   `--patch-from` against the piece the machine already has). The client
   rebuilds the piece and hands it to Nix with the upstream narinfo,
   signature untouched; Nix verifies every byte as it would a download, and
   falls back to the full download by itself if a patch is wrong.
4. **Nix is the engine** (`extra/nix`, the daemon): store, signatures,
   garbage collection. eep owns the index, cards, patches and the desktop:
   launcher entries under the app's own desktop-file name, PATH programs,
   and `eep run`, which removes the host variables that would load Arch
   libraries into a Nix app.
5. **One root step**, `sudo eep driver install`: `/run/opengl-driver` from
   the index's Mesa (patched on update), a system timer that keeps it
   current, and one marked `/etc/hosts` line (Nix's glibc can't use Arch's
   myhostname module).

## What the prototype measured (ewe VM, 2026-11-22)

| | eep | pacman / plain Nix |
|---|---|---|
| Weekly update, 5 apps with version bumps | 129 MB | 542 MB (plain Nix) |
| Daily update, whole catalog | 29.6 MB | 400 MB (plain Nix) |
| Warm launch, Firefox / Calculator | 759 / 362 ms | 802 / 355 ms (pacman) |
| `eep run` overhead | 2 ms | — |
| Delete → gone from the launcher | 0.5 s; gc frees 99.7 % of the app's bytes | — |
| First install, 8 apps | 1.9 GB | 0.66 GB (pacman) |
| Disk, 8 apps | 7.2 GB | 2.8 GB (pacman) |

All seven go/no-go claims pass (no client evaluation, small updates, safe,
apps work, fast launch, iOS-style delete, affordable server). The costs
are real and stay: the first install and the disk are 2–3× pacman's (Nix
brings its own userland), small GTK apps use ~40 MB more RAM, unfree apps
(Chrome, Steam, Discord, NVIDIA userspace) are not in the cache, and Nix
apps can't resolve mDNS `.local` names.

## What changes for ewe

- **Rule 10** becomes "pacman for the system, eep for apps; no partial
  upgrades". pacman keeps the base, the desktop, drivers and anything
  unfree.
- Komble gains eep as a source (search, install, the update badge reads
  `eep updates --count`); AppImages stay for what isn't in nixpkgs.
- ewe's session adds `~/.local/share/eep/bin` to PATH; the `eep` package
  ships the units and a pacman hook that restarts the watcher.
- Recommended in ewe regardless: the shell should not leak
  `__EGL_VENDOR_LIBRARY_FILENAMES` / `VK_DRIVER_FILES` (its RAM-diet pin)
  to the apps it starts, and the launcher's file search should skip
  hidden folders such as `~/.local`.

## Open before 1.0

- The real-GPU hour (B11), NVIDIA (its userspace must match the kernel
  module — likely pacman's job), the server (GitHub Actions + a static
  host; a signed index), and which apps the catalog offers.
