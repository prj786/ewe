#!/bin/sh
# zzz.sh — THE sleep verb for the whole DE. Lid close, long idle, Quick Settings
# → Suspend and the critical-battery guard all funnel through here, so how the
# machine sleeps is decided in exactly one place:
#
#   zzz.sh            suspend-then-hibernate: s2idle now; if nobody wakes it
#                     before HibernateDelaySec (sleep.conf.d drop-in, 2 h) the
#                     machine surfaces once and hibernates to disk. A laptop
#                     forgotten shut for a day wakes with a full battery instead
#                     of a dead one — 20 h of s2idle is real drain, hibernate
#                     is zero.
#   zzz.sh hibernate  straight to disk, no s2idle first (critical battery —
#                     there is no spare charge to idle away).
#
# Both fall back to plain suspend when hibernation isn't possible (no swapfile /
# no resume= — phase 32 of the installer sets those up), so calling this is
# always safe: worst case it behaves exactly like `systemctl suspend` did.
set -u

case "${1:-}" in
    hibernate)
        systemctl hibernate 2>/dev/null && exit 0
        ;;
    *)
        systemctl suspend-then-hibernate 2>/dev/null && exit 0
        ;;
esac
exec systemctl suspend
