#!/usr/bin/env bash
# Update counts for the bar's Komble indicator — one JSON line on stdout:
#   {"repo":N,"aur":M,"busy":true|false}
#
# repo: pending official updates via checkupdates (pacman-contrib), which syncs
#       into ITS OWN temp DB — never `pacman -Sy`, that arms a partial upgrade.
# aur:  pending AUR rebuilds via paru's query (network; cheap, read-only).
# busy: a pacman transaction holds the DB lock RIGHT NOW (something is
#       installing/upgrading — the bar shows a spinner instead of a count).

repo=0; aur=0; busy=false

if command -v checkupdates >/dev/null 2>&1; then
    # Private sync DB (checkupdates mkdirs it): the stock /tmp/checkup-db-$UID
    # is shared with every other checkupdates on the system — Komble's check, a
    # terminal run — and concurrent runs collide on its lock: exit 1, empty
    # output, and the count silently read as "0 updates".
    export CHECKUPDATES_DB="${XDG_CACHE_HOME:-$HOME/.cache}/ewe/checkup-db"
    # Exit codes: 0 = updates, 2 = none, 1 = error. Retry an error once, and if
    # it persists print nothing at all — Globals keeps the last known counts
    # instead of flashing "up to date" on a mirror hiccup.
    out=$(checkupdates 2>/dev/null); rc=$?
    if [ "$rc" -eq 1 ]; then sleep 3; out=$(checkupdates 2>/dev/null); rc=$?; fi
    [ "$rc" -eq 1 ] && exit 0
    repo=$(printf '%s\n' "$out" | grep -c ' -> ')
fi
if command -v paru >/dev/null 2>&1; then
    aur=$(paru -Qua 2>/dev/null | grep -c ' -> ')
fi
[ -e /var/lib/pacman/db.lck ] && busy=true

printf '{"repo":%d,"aur":%d,"busy":%s}\n' "${repo:-0}" "${aur:-0}" "$busy"
