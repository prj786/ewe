#!/usr/bin/env bash
# ewe bootstrap — install or update without cloning the repo.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/prj786/ewe/main/get.sh)
#
# Any arguments are passed straight to install.sh (--yes, --gaming, --dev, …).
# Downloads the latest release artefact (ewe-<version>.tar.zst; falls back to a
# snapshot of main), unpacks it to ~/.local/share/ewe and runs the installer
# from there. Re-running refreshes the tree in place — the gitignored runtime
# state that lives inside it (user-theme.json, pinned-apps.json, generated/…)
# is untouched because tar only overwrites the files it ships.
#
# Use `bash <(curl …)`, not `curl … | bash` — the installer prompts, so it
# needs stdin to still be your terminal.
set -euo pipefail

REPO=prj786/ewe
DEST="${EWE_HOME:-$HOME/.local/share/ewe}"

say() { printf '\033[1;36m::\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

command -v pacman >/dev/null 2>&1 || die "ewe is Arch-only (pacman not found)."
[ "$(id -u)" = 0 ] && die "run as your normal user, not root (the installer uses sudo only where it must)."
for t in curl tar; do command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"; done

# A git clone at $DEST already knows how to update itself.
if [ -d "$DEST/.git" ]; then
    say "$DEST is a git clone — handing over to its update.sh"
    cd "$DEST" && exec ./update.sh
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# Latest release artefact, if one exists (pre-release included via /latest is
# fine once stable; before that the API may 404 — then use the main snapshot).
url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
      | grep -o '"browser_download_url": *"[^"]*\.tar\.zst"' | head -1 | cut -d'"' -f4 || true)

mkdir -p "$DEST"
if [ -n "$url" ] && command -v zstd >/dev/null 2>&1; then
    say "downloading $(basename "$url")"
    curl -fL --progress-bar "$url" -o "$tmp/ewe.tar.zst"
    tar --zstd -xf "$tmp/ewe.tar.zst" -C "$DEST" --strip-components=1
else
    say "downloading main branch snapshot"
    curl -fL --progress-bar "https://codeload.github.com/$REPO/tar.gz/refs/heads/main" -o "$tmp/ewe.tar.gz"
    tar -xzf "$tmp/ewe.tar.gz" -C "$DEST" --strip-components=1
fi

say "installing ewe $(cat "$DEST/VERSION" 2>/dev/null || echo '?') from $DEST"
cd "$DEST"
exec bash install.sh "$@"
