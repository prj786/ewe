#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  ewe update — the repo is the single source of truth.                    ║
# ║                                                                          ║
# ║      ./update.sh              fetch the latest + converge this machine   ║
# ║      ./update.sh --check      is an update available? change nothing     ║
# ║      ./update.sh --json       same, but machine-readable (for Komble)    ║
# ║                                                                          ║
# ║  What a full run does:                                                   ║
# ║    1. fetch the latest — a git clone pulls origin (--ff-only); a         ║
# ║       tarball install (the get.sh one-liner) downloads the newest        ║
# ║       GitHub release and unpacks it in place, as get.sh does             ║
# ║    2. bash install.sh --yes   (idempotent: packages, /etc files,         ║
# ║       services, symlink farm, seeds)                                     ║
# ║    3. restart the shell so QML/script changes take effect                ║
# ║  A pacman install is pacman's: this script only points at `pacman -Syu`. ║
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
#     1   anything else (offline, a pacman install, a failed download …)

set -uo pipefail
cd "$(dirname "$0")"

REPO=prj786/ewe
MODE=run          # run | check
JSON=0

while [ $# -gt 0 ]; do
    case "$1" in
        --check)      MODE=check ;;
        --json)       JSON=1 ;;
        -h|--help)    sed -n '2,17p' "$0"; exit 0 ;;
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

# ── 0. which kind of install is this? ─────────────────────────────────────────
# A git clone follows origin. A tarball install — what get.sh leaves in
# ~/.local/share/ewe — has no history to compare, so it follows the newest
# GitHub release instead (before 0.35.3 it answered "up to date" for ever: git
# saw nothing to pull). A pacman install (/usr/share/ewe, or the user copy
# ewe-setup makes of it) belongs to pacman — never unpack a tarball over it.
if [ -d .git ]; then
    KIND=git
elif pacman -Qq ewe >/dev/null 2>&1 || [ "$PWD" = /usr/share/ewe ] || [ ! -w . ]; then
    KIND=package
else
    KIND=tarball
fi

# newer A B — is version A newer than B? The core compares numerically; on an
# equal core a plain release beats any pre-release, and pre-releases compare by
# name (alpha < beta < rc). `sort -V` alone gets the first wrong: it puts
# 0.35.2 before 0.35.2-beta.
newer() {
    local a="$1" b="$2" ac="${1%%-*}" bc="${2%%-*}" as bs
    [ "$a" = "$b" ] && return 1
    if [ "$ac" != "$bc" ]; then
        [ "$(printf '%s\n%s\n' "$ac" "$bc" | sort -V | tail -1)" = "$ac" ]
        return
    fi
    as="${a#"$ac"}"; bs="${b#"$bc"}"
    [ -z "$as" ] && return 0
    [ -z "$bs" ] && return 1
    [ "$(printf '%s\n%s\n' "$as" "$bs" | sort -V | tail -1)" = "$as" ]
}

# release_lookup — REL_VER + REL_URL of the newest release. `releases?per_page=1`
# answers the NEWEST release, pre-releases included — while the line is beta
# every release is a pre-release, and `/releases/latest` only answers stable
# ones (get.sh has the same lookup). The version is the artefact's own name:
# release.sh names it ewe-<VERSION>.tar.zst, so it equals the tree's VERSION.
REL_VER=""; REL_URL=""
release_lookup() {
    local json
    json=$(curl -fsSL --max-time 20 "https://api.github.com/repos/$REPO/releases?per_page=1" 2>/dev/null) || return 1
    REL_URL=$(printf '%s' "$json" | grep -o '"browser_download_url": *"[^"]*\.tar\.zst"' | head -1 | cut -d'"' -f4)
    REL_VER=${REL_URL##*/}; REL_VER=${REL_VER#ewe-}; REL_VER=${REL_VER%.tar.zst}
    [ -n "$REL_URL" ] && [ -n "$REL_VER" ]
}

# ── 1. what is there to do? ───────────────────────────────────────────────────
VER="$(cat VERSION 2>/dev/null || echo '?')"
LOCAL="$VER"; REMOTE="unknown"; BEHIND=0; DIRTY=0

case "$KIND" in
git)
    git fetch -q origin 2>/dev/null || true
    LOCAL="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    UPSTREAM="$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo '')"
    if [ -n "$UPSTREAM" ]; then
        REMOTE="$(git rev-parse --short '@{u}' 2>/dev/null || echo unknown)"
        BEHIND="$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"
    fi
    # -uno: only MODIFIED tracked files block a fast-forward. Untracked files
    # don't (git aborts by itself in the rare path-collision case), and counting
    # them made any stray file — a note, a screenshot, a not-yet-ignored state
    # file — refuse the whole desktop update.
    [ -n "$(git status --porcelain -uno 2>/dev/null)" ] && DIRTY=1
    ;;
tarball)
    if ! release_lookup; then
        emit event=error reason=offline \
             message="could not reach GitHub to look up the newest ewe release"
        exit 1
    fi
    REMOTE="$REL_VER"
    newer "$REL_VER" "$VER" && BEHIND=1
    ;;
package)
    # pacman owns it. checkupdates (pacman-contrib, an ewe dependency) reads
    # the [ewe] repository without root — "ewe 0.35.0beta-1 -> 0.35.2beta-1"
    # — so --check still says whether a newer package is waiting. The package
    # is built from ewe's latest release tag by prj786/ewe-repo's publish
    # workflow (release.sh dispatches it), so it lags a release by the ~35
    # minutes that build takes.
    LOCAL="$(pacman -Q ewe 2>/dev/null | awk '{print $2}')"; LOCAL="${LOCAL:-$VER}"
    PKG_NEW="$(checkupdates 2>/dev/null | awk '$1 == "ewe" { print $4 }')"
    if [ -n "$PKG_NEW" ]; then REMOTE="$PKG_NEW"; BEHIND=1; fi
    if [ "$MODE" = "check" ]; then
        if [ "$JSON" = "1" ]; then
            emit event=check updateAvailable="$([ "$BEHIND" -gt 0 ] && echo true || echo false)" \
                 local="$LOCAL" remote="$REMOTE" behind="$BEHIND" dirty=false version="$VER" install=package
        elif [ "$BEHIND" -gt 0 ]; then
            printf 'update available: ewe %s → %s — `sudo pacman -Syu` installs it\n' "$LOCAL" "$REMOTE"
        else
            printf 'up to date (ewe %s, installed by pacman — `sudo pacman -Syu` updates it)\n' "$LOCAL"
        fi
        [ "$BEHIND" -gt 0 ] && exit 10
        exit 0
    fi
    emit event=error reason=packaged \
         message="ewe is installed by pacman — update it with \`sudo pacman -Syu\`${PKG_NEW:+ (ewe $PKG_NEW is in the repository)}; the session refreshes itself at the next login"
    exit 1
    ;;
esac

if [ "$MODE" = "check" ]; then
    if [ "$JSON" = "1" ]; then
        emit event=check updateAvailable="$([ "$BEHIND" -gt 0 ] && echo true || echo false)" \
             local="$LOCAL" remote="$REMOTE" behind="$BEHIND" \
             dirty="$([ "$DIRTY" = 1 ] && echo true || echo false)" version="$VER" install="$KIND"
    elif [ "$BEHIND" -gt 0 ] && [ "$KIND" = git ]; then
        printf 'update available: %s commit(s) behind (%s → %s)\n' "$BEHIND" "$LOCAL" "$REMOTE"
        [ "$DIRTY" = 1 ] && printf 'note: working tree has local changes — the update will refuse\n'
    elif [ "$BEHIND" -gt 0 ]; then
        printf 'update available: %s → %s (release tarball)\n' "$VER" "$REMOTE"
    elif [ "$KIND" = git ]; then
        printf 'up to date (%s, %s)\n' "$LOCAL" "$VER"
        [ "$DIRTY" = 1 ] && printf 'note: working tree has local changes\n'
    else
        printf 'up to date (%s, release tarball)\n' "$VER"
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
if [ "$KIND" = tarball ] && [ "$BEHIND" -gt 0 ] && ! command -v zstd >/dev/null 2>&1; then
    emit event=error reason=no-zstd message="the release artefact is zstd-compressed — install zstd"
    exit 1
fi

# sudo up front, for the same reason: better to stop before touching anything.
if [ "$JSON" = "1" ] && ! sudo -n true 2>/dev/null; then
    die_needs_auth
fi

# ── 3. fetch the latest ───────────────────────────────────────────────────────
emit event=phase name=pull status=start
if [ "$KIND" = git ]; then
    if ! PULL_OUT="$(git pull --ff-only 2>&1)"; then
        emit event=phase name=pull status=error message="$PULL_OUT"
        emit event=error reason=not-fast-forward message="history diverged — resolve manually"
        exit 30
    fi
    emit event=phase name=pull status=ok message="now at $(git rev-parse --short HEAD)"
elif [ "$BEHIND" -gt 0 ]; then
    # Unpacked over the tree exactly as get.sh does: tar overwrites only the
    # files the release ships, so the gitignored runtime state living inside
    # the tree (user-theme.json, pinned-apps.json, generated/…) is untouched.
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    if ! curl -fsSL --max-time 600 "$REL_URL" -o "$tmp/ewe.tar.zst" 2>/dev/null; then
        emit event=phase name=pull status=error message="download failed: $REL_URL"
        emit event=error reason=download-failed message="could not download ewe $REL_VER"
        exit 1
    fi
    if ! TAR_OUT="$(tar --zstd -xf "$tmp/ewe.tar.zst" -C . --strip-components=1 2>&1)"; then
        emit event=phase name=pull status=error message="$TAR_OUT"
        emit event=error reason=unpack-failed message="could not unpack ewe $REL_VER"
        exit 1
    fi
    emit event=phase name=pull status=ok message="now at $(cat VERSION 2>/dev/null || echo "$REL_VER")"
else
    emit event=phase name=pull status=ok message="already at $VER (the newest release)"
fi

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
     commit="$(git rev-parse --short HEAD 2>/dev/null || echo release)"
