#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  hypr-shell update — the repo is the single source of truth.              ║
# ║                                                                            ║
# ║      ./update.sh          pull latest + converge this machine onto it     ║
# ║                                                                            ║
# ║  What it does:                                                             ║
# ║    1. git pull --ff-only                                                   ║
# ║    2. bash install.sh --yes   (idempotent: packages, /etc files,           ║
# ║       services, symlink farm, seeds — anything the repo gained since       ║
# ║       the last run lands here; needs sudo once)                            ║
# ║    3. restart the shell so QML/script changes take effect                  ║
# ╚══════════════════════════════════════════════════════════════════════════╝
set -euo pipefail
cd "$(dirname "$0")"

git pull --ff-only
bash install.sh --yes
systemctl --user restart hypr-shell.service 2>/dev/null \
    || echo "note: hypr-shell.service not running — shell restart skipped"
echo
echo "hypr-shell updated → $(cat VERSION) ($(git rev-parse --short HEAD))"
