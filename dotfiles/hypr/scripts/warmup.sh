#!/usr/bin/env bash
# warmup.sh — kill the first-launch lag. Started once per session by
# autostart.sh, ~20s after login, at idle priority.
#
# Why the FIRST open of Firefox/Nemo/Settings is slow and every later one is
# instant: the first launch faults the binary + its libraries in from disk;
# after that they sit in the page cache. This script simply takes that hit
# EARLY, while the session is idle — so the user's first click feels like
# their second. Two extra tricks: the daemons Nemo lazily D-Bus-spawns on
# first contact (gvfs, volume monitor) and the portal stack start now instead
# of inside the user's first file dialog.
#
# Cost model, honestly: page cache is EVICTABLE memory — it shows under
# "buff/cache", not "used", and the kernel drops it under pressure. This
# trades idle I/O for perceived speed; it does not raise steady-state RSS.
# On battery we skip the read-storm entirely (I/O = power).

sleep 20

# session daemons first — cheap, and they start eventually anyway
command -v /usr/lib/gvfsd >/dev/null 2>&1 || true
pgrep -x gvfsd >/dev/null || /usr/lib/gvfsd >/dev/null 2>&1 &
pgrep -f gvfs-udisks2-volume-monitor >/dev/null || /usr/lib/gvfs/gvfs-udisks2-volume-monitor >/dev/null 2>&1 &
systemctl --user start xdg-desktop-portal.service 2>/dev/null &

# battery? then no read-storm — the daemons above were the free part
on_ac=0
for ps in /sys/class/power_supply/*/online; do
    [ -r "$ps" ] && [ "$(cat "$ps")" = "1" ] && on_ac=1
done
[ "$on_ac" = "1" ] || exit 0

# the first-launch working set, biggest wins first
warm() { [ -r "$1" ] && cat "$1" > /dev/null 2>&1; }
renice -n 19 $$ >/dev/null 2>&1
ionice -c3 -p $$ >/dev/null 2>&1

for f in \
    /usr/lib/firefox/libxul.so /usr/lib/firefox/firefox \
    /usr/lib/libwebkitgtk-6.0.so* /usr/lib/libwebkit2gtk-4.1.so* \
    /usr/bin/nemo /usr/lib/libnemo-private.so* \
    /usr/bin/komble /usr/bin/ewe-settings /usr/bin/ewe-sync \
    /usr/lib/libgtk-3.so* /usr/lib/libgtk-4.so* /usr/lib/libglib-2.0.so* \
    /usr/lib/libQt6Core.so* /usr/lib/libQt6Gui.so* /usr/lib/libQt6Qml.so* \
    /usr/bin/kitty /usr/bin/zathura /usr/bin/imv /usr/bin/galculator \
    /usr/bin/zeditor \
    /usr/bin/engrampa /usr/bin/guvcview ; do
    warm "$f"
done
