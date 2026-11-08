#!/bin/sh
# ewe system tuning — the one place that installs (or removes) the drop-ins
# in this folder, so phase 60, the package's post_install/post_upgrade and
# `uninstall.sh --purge` can never drift apart. Run as root.
#
#   apply.sh            install what differs, apply it to the running system
#   apply.sh --remove   delete the drop-ins this script installed (only when
#                       they are still ours, byte for byte)
#
# What it ships (2026-11-08, measured on the owner's laptop — see each file):
#   70-ewe-memory.sysctl.conf   → /etc/sysctl.d/70-ewe-memory.conf      (zram only)
#   70-ewe-memory.tmpfiles.conf → /etc/tmpfiles.d/70-ewe-memory.conf    (zram only)
#   70-ewe-journald.conf        → /etc/systemd/journald.conf.d/70-ewe.conf
#   plocate-updatedb.timer.conf → /etc/systemd/system/plocate-updatedb.timer.d/70-ewe.conf
# The memory pair is written only when zram is configured
# (/etc/systemd/zram-generator.conf) — the values are zram's, and zswap is
# worth keeping on a machine whose only swap is a disk.
#
# Idempotent: an unchanged file is not touched or re-applied. Prints one
# ":: ewe:" line per change, always exits 0 (a package scriptlet must never
# fail an upgrade). Tests: EWE_TUNING_ROOT=<dir> prefixes every path and
# EWE_TUNING_NO_LIVE=1 skips sysctl/tmpfiles/systemctl.

SRC="$(cd "$(dirname "$0")" && pwd)"
R="${EWE_TUNING_ROOT:-}"
LIVE=1
[ "${EWE_TUNING_NO_LIVE:-0}" = 1 ] && LIVE=0
REMOVE=0
[ "${1:-}" = "--remove" ] && REMOVE=1

SYSCTL="$R/etc/sysctl.d/70-ewe-memory.conf"
TMPF="$R/etc/tmpfiles.d/70-ewe-memory.conf"
JOURNAL="$R/etc/systemd/journald.conf.d/70-ewe.conf"
PLOCATE="$R/etc/systemd/system/plocate-updatedb.timer.d/70-ewe.conf"

say() { echo ":: ewe: $*"; }

# put $1 at $2 unless it is already there; 0 = changed
put() {
    cmp -s "$1" "$2" && return 1
    install -Dm644 "$1" "$2" 2>/dev/null || { say "could not write $2"; return 1; }
    return 0
}

# remove $2 if it is still exactly our $1
drop() {
    [ -e "$2" ] || return 1
    if cmp -s "$1" "$2"; then
        rm -f "$2" && rmdir "$(dirname "$2")" 2>/dev/null
        return 0
    fi
    say "left $2 in place (it was edited)"
    return 1
}

live() { [ "$LIVE" = 1 ] && "$@" >/dev/null 2>&1; }

if [ "$REMOVE" = 1 ]; then
    drop "$SRC/70-ewe-memory.sysctl.conf" "$SYSCTL" && say "removed the zram memory tuning (kernel defaults after the next boot)"
    drop "$SRC/70-ewe-memory.tmpfiles.conf" "$TMPF" && say "removed the zswap/huge-page switches (kernel defaults after the next boot)"
    drop "$SRC/70-ewe-journald.conf" "$JOURNAL" && say "removed the journal size cap"
    drop "$SRC/plocate-updatedb.timer.conf" "$PLOCATE" && { live systemctl daemon-reload; say "removed the file-index boot delay"; }
    exit 0
fi

if [ -e "$R/etc/systemd/zram-generator.conf" ]; then
    if put "$SRC/70-ewe-memory.sysctl.conf" "$SYSCTL"; then
        live sysctl -q -p "$SYSCTL"
        say "memory: swap goes to zram before app files leave the cache (swappiness 180, page-cluster 0)"
    fi
    if put "$SRC/70-ewe-memory.tmpfiles.conf" "$TMPF"; then
        live systemd-tmpfiles --create "$TMPF"
        say "memory: zswap off (zram already compresses), huge pages only on request"
    fi
fi
if put "$SRC/70-ewe-journald.conf" "$JOURNAL"; then
    say "logs: the journal is capped at 1 GB (from the next boot)"
fi
if put "$SRC/plocate-updatedb.timer.conf" "$PLOCATE"; then
    live systemctl daemon-reload
    say "file index: no disk scan while the desktop starts (10 min after boot)"
fi
exit 0
