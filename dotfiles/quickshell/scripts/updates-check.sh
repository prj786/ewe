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
    repo=$(checkupdates 2>/dev/null | grep -c ' -> ')
fi
if command -v paru >/dev/null 2>&1; then
    aur=$(paru -Qua 2>/dev/null | grep -c ' -> ')
fi
[ -e /var/lib/pacman/db.lck ] && busy=true

printf '{"repo":%d,"aur":%d,"busy":%s}\n' "${repo:-0}" "${aur:-0}" "$busy"
