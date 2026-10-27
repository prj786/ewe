#!/usr/bin/env bash
# Build the release artefact — dist/ewe-<VERSION>.tar.zst from HEAD — and, with
# --publish, create the GitHub release (tag v<VERSION>) carrying it. The
# artefact is what get.sh installs, so users never need git or a clone.
# Reminder: VERSION and Globals.version must be bumped together before this.
set -euo pipefail
cd "$(dirname "$0")"

VER=$(<VERSION)
out="dist/ewe-$VER.tar.zst"
mkdir -p dist
git archive --format=tar --prefix="ewe-$VER/" HEAD | zstd -19 -T0 -q -f -o "$out"
printf 'built %s (%s)\n' "$out" "$(du -h "$out" | cut -f1)"

if [ "${1:-}" = "--publish" ]; then
    pre=""
    case "$VER" in *-alpha*|*-beta*) pre="--prerelease" ;; esac
    gh release create "v$VER" "$out" --title "ewe $VER" $pre --generate-notes

    # The [ewe] pacman repository (prj786/ewe-repo) builds the `ewe` package
    # from ewe's LATEST release tag — but only when its publish workflow runs:
    # by hand, or the Monday cron. Kick it now (repository_dispatch), or every
    # pacman install waits for the cron with `pacman -Syu` saying nothing new,
    # as 0.35.2 did for hours. The build takes ~35 minutes.
    if gh api -X POST repos/prj786/ewe-repo/dispatches -f event_type=publish >/dev/null 2>&1; then
        printf 'dispatched the ewe-repo publish (the ewe pacman package, ~35 min): https://github.com/prj786/ewe-repo/actions\n'
    else
        printf 'warning: could not dispatch the ewe-repo publish — run it by hand: gh workflow run publish -R prj786/ewe-repo\n' >&2
    fi
fi
