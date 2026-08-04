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
fi
