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
exec qs "$@"
