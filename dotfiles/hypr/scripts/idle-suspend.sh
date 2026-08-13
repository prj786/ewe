#!/bin/sh
# idle-suspend.sh — suspend on long idle, but ONLY on a laptop running on battery.
# Called by hypridle's long-idle timeout. Deliberately conservative so it never
# surprises a desktop or a plugged-in laptop (e.g. mid-download):
#   • plugged in (any AC adapter online) → do nothing
#   • no battery present (desktop)       → do nothing
#   • on battery                         → sleep via zzz.sh (suspend-then-
#                                          hibernate; hypridle locks first via
#                                          before_sleep_cmd)
set -u

# AC adapter reports online=1 when plugged in.
for ac in /sys/class/power_supply/A*/online /sys/class/power_supply/AC*/online; do
    [ -r "$ac" ] || continue
    [ "$(cat "$ac" 2>/dev/null)" = "1" ] && exit 0   # on AC → don't suspend
done

# A battery must exist (i.e. this is a laptop) before we ever auto-suspend.
[ -e /sys/class/power_supply/BAT0/status ] || [ -e /sys/class/power_supply/BAT1/status ] || exit 0

exec "$(dirname "$0")/zzz.sh"
