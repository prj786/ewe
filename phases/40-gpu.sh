#!/usr/bin/env bash
# phase 40 — install per-vendor Vulkan + VAAPI drivers and do vendor config.
# mesa + vulkan-icd-loader come from common.list; this adds the vendor-specific
# ICD + video-decode driver for the detected GPU. The 32-bit (lib32-*) drivers
# are added only with --gaming — they exist for 32-bit games, and [multilib] is
# gated on --gaming too (phase 10).

phase_gpu() {
    step "40 · GPU ($GPU_VENDOR)"
    [ "${NO_PACKAGES:-0}" = "1" ] || {
        case " $GPU_VENDOR " in
            *" intel "*)
                # vpl-gpu-rt is the oneVPL GPU runtime: without it libvpl has no
                # implementation to dispatch to and every QuickSync consumer (OBS
                # QSV, ffmpeg -qsv) dies with MFX_ERR_NOT_FOUND while plain VAAPI
                # looks perfectly healthy (bitten live on the Zenbook, 2026-08-20).
                install_official vulkan-intel intel-media-driver vpl-gpu-rt intel-gpu-tools
                [ "${GAMING:-0}" = "1" ] && install_official lib32-vulkan-intel
                ok "Intel: ANV + iHD VAAPI + QSV (oneVPL) + intel_gpu_top installed." ;;
        esac
        case " $GPU_VENDOR " in
            *" amd "*)
                # AMD VAAPI now ships inside mesa (libva-mesa-driver was merged
                # upstream and dropped from the repos), so RADV is all we add here.
                install_official vulkan-radeon
                [ "${GAMING:-0}" = "1" ] && install_official lib32-vulkan-radeon
                ok "AMD: RADV + VAAPI (via mesa) installed." ;;
        esac
        case " $GPU_VENDOR " in
            *" nvidia "*)
                warn "NVIDIA: installing the OPEN modules (Turing+). For older GPUs use nvidia-dkms instead."
                install_official nvidia-open-dkms nvidia-utils egl-wayland
                [ "${GAMING:-0}" = "1" ] && install_official lib32-nvidia-utils ;;
        esac
    }

    # ── Intel Lunar Lake / Xe2 note: the `xe` driver has a DPMS-resume bug, so the
    #    shipped hypridle.conf locks but never powers the panel off. ──
    case " $GPU_VENDOR " in
        *" intel "*) lspci -k 2>/dev/null | grep -qi 'in use: xe' \
            && ok "xe driver detected — hypridle ships without dpms-off (resume-bug guard)." ;;
    esac

    # ── NVIDIA: enable modeset + the suspend-fix services (resume corruption) ──
    case " $GPU_VENDOR " in
        *" nvidia "*)
            info "NVIDIA: set kernel params nvidia_drm.modeset=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1"
            for u in nvidia-suspend nvidia-resume nvidia-hibernate; do
                command -v systemctl >/dev/null 2>&1 && sudo_run systemctl enable "${u}.service" 2>/dev/null || true
            done
            info "NVIDIA: add env in hypr/conf.d — LIBVA_DRIVER_NAME=nvidia, __GL_GSYNC_ALLOWED=1, AQ_DRM_DEVICES if multi-GPU." ;;
    esac

    [ "$GPU_VENDOR" = "virtual" ] && ok "virtual GPU (VM) — mesa-only is correct; no vendor (intel/amd/nvidia) drivers installed."
    [ "$GPU_VENDOR" = "unknown" ] && warn "no GPU detected (no lspci?) — installed mesa only."
    ok "GPU phase done"
}
