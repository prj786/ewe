#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  ewe update — the repo is the single source of truth.                    ║
# ║                                                                          ║
# ║      ./update.sh              pull latest + converge this machine        ║
# ║      ./update.sh --check      is an update available? change nothing     ║
# ║      ./update.sh --json       same, but machine-readable (for Komble)    ║
# ║                                                                          ║
# ║  What a full run does:                                                   ║
# ║    1. git pull --ff-only                                                 ║
# ║    2. bash install.sh --yes   (idempotent: packages, /etc files,         ║
# ║       services, symlink farm, seeds)                                     ║
# ║    3. restart the shell so QML/script changes take effect                ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# --json exists so Komble can drive an update in-app and show real progress.
# The hard part is not the output format, it is sudo: install.sh needs root for
# /etc files and packages, and a GUI has no terminal for a password prompt. So
# the JSON path REFUSES to start unless sudo is already usable non-interactively
# and exits 20 — the caller is expected to fall back to running this in a
# terminal. Better to say "I need a password" up front than to hang forever on a
# prompt nobody can see.
#
# Exit codes (the contract Komble depends on):
#     0   success, or --check found nothing to do
#    10   --check: an update IS available
#    20   needs interaction (sudo password) — re-run in a terminal
#    30   working tree dirty, or history diverged: cannot fast-forward
#     1   anything else

set -uo pipefail
cd "$(dirname "$0")"

MODE=run          # run | check
JSON=0

while [ $# -gt 0 ]; do
    case "$1" in
        --check)      MODE=check ;;
        --json)       JSON=1 ;;
        -h|--help)    sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

# ── output ────────────────────────────────────────────────────────────────────
# In JSON mode every line on stdout is one event, so human text must not leak
# there. python3 does the escaping: hand-rolling JSON string quoting in bash is
# how you end up emitting invalid output the first time a path contains a quote.
if [ "$JSON" = "1" ] && ! command -v python3 >/dev/null 2>&1; then
    echo '{"event":"error","reason":"no-python","message":"--json needs python3"}'
    exit 1
fi

emit() {   # emit <key=value>...  → one JSON object, or a readable human line
    if [ "$JSON" = "1" ]; then
        python3 -c '
import sys, json
def coerce(v):
    # emit real types: a consumer should not have to compare against "false"
    if v == "true":  return True
    if v == "false": return False
    if v.lstrip("-").isdigit(): return int(v)
    return v
print(json.dumps({k: coerce(v) for k, v in
                  (a.split("=", 1) for a in sys.argv[1:])}), flush=True)
' "$@"
        return
    fi
    local ev="" name="" status="" msg=""
    local kv
    for kv in "$@"; do
        case "$kv" in
            event=*)   ev="${kv#event=}" ;;
            name=*)    name="${kv#name=}" ;;
            status=*)  status="${kv#status=}" ;;
            message=*) msg="${kv#message=}" ;;
        esac
    done
    case "$ev" in
        phase) printf '  %-8s %s%s\n' "$name" "$status" "${msg:+ — $msg}" ;;
        error) printf 'error: %s\n' "${msg:-unknown}" >&2 ;;
        done)  printf '\newe updated\n' ;;
        *)     [ -n "$msg" ] && printf '%s\n' "$msg" ;;
    esac
}

die_needs_auth() {
    emit event=error reason=needs-auth \
         message="sudo needs a password; re-run ./update.sh in a terminal"
    exit 20
}

# ── 1. what is there to do? ───────────────────────────────────────────────────
git fetch -q origin 2>/dev/null || true

LOCAL="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
UPSTREAM="$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo '')"
REMOTE="unknown"; BEHIND=0
if [ -n "$UPSTREAM" ]; then
    REMOTE="$(git rev-parse --short '@{u}' 2>/dev/null || echo unknown)"
    BEHIND="$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"
fi
DIRTY=0
[ -n "$(git status --porcelain 2>/dev/null)" ] && DIRTY=1

if [ "$MODE" = "check" ]; then
    VER="$(cat VERSION 2>/dev/null || echo '?')"
    if [ "$JSON" = "1" ]; then
        emit event=check updateAvailable="$([ "$BEHIND" -gt 0 ] && echo true || echo false)" \
             local="$LOCAL" remote="$REMOTE" behind="$BEHIND" \
             dirty="$([ "$DIRTY" = 1 ] && echo true || echo false)" version="$VER"
    elif [ "$BEHIND" -gt 0 ]; then
        printf 'update available: %s commit(s) behind (%s → %s)\n' "$BEHIND" "$LOCAL" "$REMOTE"
        [ "$DIRTY" = 1 ] && printf 'note: working tree has local changes — the update will refuse\n'
    else
        printf 'up to date (%s, %s)\n' "$LOCAL" "$VER"
        [ "$DIRTY" = 1 ] && printf 'note: working tree has local changes\n'
    fi
    [ "$BEHIND" -gt 0 ] && exit 10
    exit 0
fi

# ── 2. refuse early rather than failing halfway ───────────────────────────────
# A dirty tree cannot be fast-forwarded, and finding that out after a package
# phase has already run leaves the machine half-converged.
if [ "$DIRTY" = "1" ]; then
    emit event=error reason=dirty \
         message="working tree has local changes — commit, stash or discard them first"
    exit 30
fi

# sudo up front, for the same reason: better to stop before touching anything.
if [ "$JSON" = "1" ] && ! sudo -n true 2>/dev/null; then
    die_needs_auth
fi

# ── 3. pull ───────────────────────────────────────────────────────────────────
emit event=phase name=pull status=start
if ! PULL_OUT="$(git pull --ff-only 2>&1)"; then
    emit event=phase name=pull status=error message="$PULL_OUT"
    emit event=error reason=not-fast-forward message="history diverged — resolve manually"
    exit 30
fi
emit event=phase name=pull status=ok message="now at $(git rev-parse --short HEAD)"

# ── 4. converge ───────────────────────────────────────────────────────────────
emit event=phase name=install status=start
if [ "$JSON" = "1" ]; then
    # Stream install.sh's output as one event per line so a GUI can show live
    # progress. PIPESTATUS, not $?, because $? here is python's.
    bash install.sh --yes 2>&1 | python3 -c '
import sys, json
for line in sys.stdin:
    print(json.dumps({"event": "log", "line": line.rstrip("\n")}), flush=True)
'
    RC="${PIPESTATUS[0]}"
else
    bash install.sh --yes
    RC=$?
fi
if [ "$RC" != "0" ]; then
    emit event=phase name=install status=error message="install.sh exited $RC"
    emit event=error reason=install-failed message="see the log above"
    exit 1
fi
emit event=phase name=install status=ok

# ── 5. restart the shell ──────────────────────────────────────────────────────
emit event=phase name=restart status=start
# migrate: a pre-rename session may still be running the shell under the old
# unit name — stop it or two shells fight over the same sockets
systemctl --user stop hypr-shell.service 2>/dev/null || true
if systemctl --user restart ewe.service 2>/dev/null; then
    emit event=phase name=restart status=ok
else
    emit event=phase name=restart status=skipped message="ewe.service not running"
fi

emit event=done status=ok version="$(cat VERSION 2>/dev/null || echo '?')" \
     commit="$(git rev-parse --short HEAD)"
