#!/usr/bin/env bash
# Update counts for the bar's Komble indicator — one JSON line on stdout:
#   {"repo":N,"aur":M,"busy":true|false}            (a good check)
#   {"error":true,"busy":true|false}                (checkupdates failed twice)
#
# repo: pending official updates via checkupdates (pacman-contrib), which syncs
#       into ITS OWN temp DB — never `pacman -Sy`, that arms a partial upgrade.
# aur:  pending AUR rebuilds via paru's query (network; cheap, read-only).
# busy: a pacman transaction holds the DB lock RIGHT NOW (something is
#       installing/upgrading — the bar shows a spinner instead of a count).
#
# Every good result is also written to $XDG_STATE_HOME/ewe/updates.json;
# `updates-check.sh --cached` prints that snapshot and exits. Globals reads
# the cache at shell start so the bar shows the last known count immediately
# instead of nothing until the first live check lands (which, sixty seconds
# after login, regularly lost the race against Wi-Fi).

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ewe"
STATE="$STATE_DIR/updates.json"

if [ "${1:-}" = "--cached" ]; then
    [ -r "$STATE" ] && cat "$STATE"
    exit 0
fi

repo=0; aur=0; busy=false
[ -e /var/lib/pacman/db.lck ] && busy=true

if command -v checkupdates >/dev/null 2>&1; then
    # Private sync DB (checkupdates mkdirs it): the stock /tmp/checkup-db-$UID
    # is shared with every other checkupdates on the system — Komble's check, a
    # terminal run — and concurrent runs collide on its lock: exit 1, empty
    # output, and the count silently read as "0 updates".
    export CHECKUPDATES_DB="${XDG_CACHE_HOME:-$HOME/.cache}/ewe/checkup-db"
    # Exit codes: 0 = updates, 2 = none, 1 = error. Retry an error once; if it
    # persists say so OUT LOUD — an explicit error lets Globals keep the last
    # known counts AND schedule a short-interval retry, where empty output
    # used to mean an hour of a silently wrong bar.
    out=$(checkupdates 2>/dev/null); rc=$?
    if [ "$rc" -eq 1 ]; then sleep 3; out=$(checkupdates 2>/dev/null); rc=$?; fi
    if [ "$rc" -eq 1 ]; then
        printf '{"error":true,"busy":%s}\n' "$busy"
        exit 0
    fi
    repo=$(printf '%s\n' "$out" | grep -c ' -> ')
fi
if command -v paru >/dev/null 2>&1; then
    aur=$(paru -Qua 2>/dev/null | grep -c ' -> ')
fi

# The snapshot keeps only the counts — "busy" is a right-now fact and a
# stale true would spin the bar at every login.
mkdir -p "$STATE_DIR" \
    && printf '{"repo":%d,"aur":%d}\n' "${repo:-0}" "${aur:-0}" > "$STATE.tmp" \
    && mv "$STATE.tmp" "$STATE"
printf '{"repo":%d,"aur":%d,"busy":%s}\n' "${repo:-0}" "${aur:-0}" "$busy"
