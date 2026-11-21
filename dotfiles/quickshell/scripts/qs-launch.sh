#!/usr/bin/env bash
# qs-launch.sh — start the shell with its GL stack pinned (RSS diet, ewe#18).
#
# GLVND probes EVERY EGL vendor and Vulkan ICD at startup; on a machine with
# nvidia-utils installed but no NVIDIA kernel module (Intel-only boxes, or
# hybrids booted on the iGPU) that keeps ~67 MB of dead NVIDIA userspace
# resident in the shell — measured 440→354 MB by pinning to Mesa/Intel.
#
# Scope discipline: pinned for THE SHELL PROCESS ONLY, and only when the
# nvidia module is absent — a real dGPU session and `prime-run` see nothing.
if [ ! -d /sys/module/nvidia ]; then
    [ -r /usr/share/glvnd/egl_vendor.d/50_mesa.json ] \
        && export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
    # first Intel ICD wins; other vendors' machines simply keep the default
    for icd in /usr/share/vulkan/icd.d/intel_icd.*.json /usr/share/vulkan/icd.d/intel_icd.json \
               /usr/share/vulkan/icd.d/radeon_icd.*.json; do
        [ -r "$icd" ] && { export VK_DRIVER_FILES="$icd"; break; }
    done
fi

# ── Apps with Windows line ends (2026-11-21) ──
# Quickshell drops a .desktop file written with CRLF (LinOffice's Word, Excel,
# Outlook, OneNote, PowerPoint): "[Desktop Entry]\r" is no group header, so
# those apps were missing from the launcher, dock and Overview. desktop-entries.py
# writes LF copies (never touching the user's files) under the cache; that
# folder goes into the SHELL's data dirs — after XDG_DATA_HOME, which always
# comes first, and a broken file there does not shadow the copy. The shell
# re-runs the script whenever its app list changes (Globals.qml).
_de="$(dirname "$(readlink -f "$0")")/desktop-entries.py"
if [ -r "$_de" ] && command -v python3 >/dev/null 2>&1; then
    _dedir="$(timeout 10 python3 "$_de" --dir 2>/dev/null)"
    case ":${XDG_DATA_DIRS:-}:" in
        *":$_dedir:"*) ;;
        *) [ -n "$_dedir" ] && export XDG_DATA_DIRS="$_dedir:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" ;;
    esac
fi

# ── Come back after a compositor kick ──
# qs exits 255 for three different things: no display, a config that fails to
# load, and a Wayland connection the compositor severed. ewe.service refuses to
# restart 255 (RestartPreventExitStatus) because the first two loop forever —
# but the third left the desktop with no bar, dock or lock until someone ran qs
# by hand (2026-09-21…25, six times in four days on the dev box):
#     wl_display#1: error 0: invalid object 115
#     WARN: The Wayland connection experienced a fatal error: Invalid argument
# Hyprland posts that protocol error when a toplevel closes mid-capture and qs
# names the dead object; Hyprland itself is fine. So: a qs that ran for a
# while, exits 255, and leaves a compositor that still answers was kicked, not
# broken — exit 1 instead and let Restart=on-failure bring it back. A quick
# 255 (bad config) or a dead compositor (logout) keeps 255 and stays down.
started=$(date +%s)
qs "$@" &
pid=$!
# KillMode=process signals only this wrapper — pass stop/restart through to qs
trap 'kill -TERM "$pid" 2>/dev/null' TERM INT HUP
while :; do
    wait "$pid"; rc=$?
    kill -0 "$pid" 2>/dev/null || break      # a trapped signal interrupts wait
done
if [ "$rc" = 255 ] && [ $(( $(date +%s) - started )) -ge 15 ] \
   && [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/${WAYLAND_DISPLAY:-none}" ] \
   && timeout 3 hyprctl -j version >/dev/null 2>&1; then
    echo "qs-launch: the compositor dropped the shell's Wayland connection but is still running — restarting" >&2
    exit 1
fi
exit "$rc"
