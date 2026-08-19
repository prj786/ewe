#!/usr/bin/env bash
# phase 90 — verification checklist. Read-only; prints a green/red summary.
# Most session checks only pass once logged into Hyprland; re-run after login:
#   bash install.sh --check-only

# _check "<label>" <cmd...> — green tick on success, red cross on fail
_check() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then printf '  %s✓%s %s\n' "$C_G" "$C_0" "$label"; else printf '  %s✗%s %s\n' "$C_R" "$C_0" "$label"; fi; }
# _note "<label>" — neutral, non-failing line (for things that are expected to be N/A)
_note()  { printf '  %s•%s %s\n' "$C_DIM" "$C_0" "$1"; }
# running under a VM/container? hardware GPU accel is expected to be absent there.
_in_vm() { systemd-detect-virt -q 2>/dev/null; }

phase_postcheck() {
    step "90 · verification"
    echo "  (✗ on session items is expected until you log into the Hyprland session)"

    _check "binaries: Hyprland + qs present"      sh -c 'command -v Hyprland && command -v qs'
    _check "AUR helper present (paru or yay)"     sh -c 'command -v paru || command -v yay'
    # greetd is skipped on purpose by --coexist (your own login manager stays in
    # charge), so only verify the greeter stack when greetd was actually installed.
    if pkg_present greetd; then
        _check "greeter: greetd + regreet + cage"     sh -c 'pacman -Qq greetd && pacman -Qq greetd-regreet && pacman -Qq cage'
        _check "greeter: Quickshell config installed"  test -r /etc/xdg/quickshell/ewe-greeter/shell.qml
    else
        _note "greeter: not installed (coexist — your login manager lists 'Ewe')"
    fi
    _check "fully Wayland: no xorg-server"         sh -c '! pacman -Qq xorg-server 2>/dev/null'
    _check "apps: file manager (nemo)"             sh -c 'command -v nemo'
    _check "apps: viewers (imv + zathura)"         sh -c 'command -v imv && command -v zathura'
    _check "apps: archive (engrampa) + video (mpv)" sh -c 'command -v engrampa && command -v mpv'
    _check "theming: qt6ct fallback present"       sh -c 'pacman -Qq qt6ct'
    _check "theming: Reversal icons installed"     test -d /usr/share/icons/Reversal-blue-dark
    _check "theming: Mocu cursor installed"        test -d /usr/share/icons/Mocu-White-Right
    _check "session target active"                systemctl --user is-active hyprland-session.target
    _check "portal: xdg-desktop-portal active"    systemctl --user is-active xdg-desktop-portal.service
    _check "portal: hyprland backend active"      systemctl --user is-active xdg-desktop-portal-hyprland.service
    _check "portal: gtk backend active"           systemctl --user is-active xdg-desktop-portal-gtk.service
    _check "audio: a default sink exists"         sh -c 'wpctl status 2>/dev/null | grep -qi sink'
    _check "audio: SOF + UCM firmware present"     sh -c 'pacman -Qq sof-firmware && pacman -Qq alsa-ucm-conf'
    _check "network: NetworkManager active"       systemctl is-active NetworkManager.service
    _check "power: power-profiles-daemon active"   systemctl is-active power-profiles-daemon.service
    _check "bluetooth: service active"            systemctl is-active bluetooth.service
    # Wi-Fi/GPU firmware lives in linux-firmware; usually pulled by the kernel, but a
    # truly stripped base can lack it — note (don't fail) so a dead radio is explained.
    if pkg_present linux-firmware; then _note "firmware: linux-firmware present"
    else _note "firmware: linux-firmware NOT found — Wi-Fi/GPU may fail (sudo pacman -S linux-firmware)"; fi
    # CPU microcode: the vendor ucode package should be installed on real hardware.
    # In a VM the host applies microcode, so it's a neutral note, not a red ✗.
    if _in_vm; then
        _note "CPU microcode: skipped (VM — host applies it)"
    elif [ "${CPU_VENDOR:-unknown}" = intel ] || [ "${CPU_VENDOR:-unknown}" = amd ]; then
        _check "CPU microcode: ${CPU_VENDOR}-ucode installed" sh -c "pacman -Qq ${CPU_VENDOR}-ucode"
    else
        _note "CPU microcode: CPU vendor unknown — no intel/amd-ucode"
    fi
    # GPU hardware accel is expected to be unavailable in a VM (software rendering),
    # so don't flag it red there — just note it.
    if _in_vm; then
        _note "GPU: hardware accel skipped (VM — software rendering)"
    else
        _check "GPU: VAAPI entrypoint available"      sh -c 'vainfo 2>/dev/null | grep -q VAEntrypoint'
        _check "GPU: a Vulkan device is visible"      sh -c 'vulkaninfo --summary 2>/dev/null | grep -qi deviceName'
    fi
    # grim uses wlr-screencopy, which is unreliable on a VM's software-rendered
    # virtio-gpu (the capture can come back empty). Real check on hardware; in a
    # VM it's a neutral note, not a red ✗ — screenshots work fine on real GPUs.
    if _in_vm; then
        _note "screenshot: grim (screencopy unreliable under VM software rendering)"
    else
        _check "screenshot: grim can capture"         sh -c 'grim - 2>/dev/null | head -c1 | grep -q .'
    fi
    _check "keyring agent running"                pgrep -f gnome-keyring-daemon
    _check "kb layout: english (us)"              sh -c 'hyprctl getoption input:kb_layout 2>/dev/null | grep -qw us'
    # gaming is opt-in (--gaming); only verify it when it was actually installed,
    # so a normal install never shows a red ✗ for packages it deliberately skipped.
    if pkg_present steam; then
        _check "gaming: gamemode + steam installed"   sh -c 'pacman -Qq gamemode && pacman -Qq steam'
        _check "gaming: multilib repo enabled"        sh -c 'pacman-conf --repo-list | grep -qx multilib'
    else
        _note "gaming: not installed (opt-in — re-run with --gaming)"
    fi
    _check "editor: Fresh (fresh) on PATH"        sh -c 'command -v fresh'
    _check "terminal: kitty installed"            sh -c 'command -v kitty'
    # dev toolchain is opt-in (--dev); only verify it when mise was actually installed.
    if pkg_present mise; then
        _check "dev: node via mise shims"             sh -c 'command -v mise && [ -x "$HOME/.local/share/mise/shims/node" ]'
        _check "dev: TypeScript language server"      sh -c '[ -x "$HOME/.local/share/mise/shims/typescript-language-server" ] || command -v typescript-language-server'
    else
        _note "dev: toolchain not installed (opt-in — re-run with --dev)"
    fi

    # ── Laptop hardening (0.4.x). Only meaningful on a laptop, and every item is
    # something a user would otherwise discover missing days later — a lid that
    # suspends when docked, a charge ceiling that silently refuses to write, a
    # keyboard backlight key that does nothing.
    if [ "$CHASSIS" = "laptop" ]; then
        echo
        _check "laptop: logind lid drop-in installed"  test -r /etc/systemd/logind.conf.d/10-ewe-lid.conf
        _check "laptop: panel backlight present"       sh -c 'ls /sys/class/backlight/*/brightness >/dev/null 2>&1'
        # The bridge is what locks BEFORE suspend and makes loginctl lock-session
        # work; without it those silently do nothing.
        _check "laptop: logind bridge script"          test -r "$HOME/.config/quickshell/scripts/logind-bridge.py"
        _check "laptop: python D-Bus deps for it"      sh -c 'python3 -c "import dbus, gi" 2>/dev/null'

        if ls /sys/class/power_supply/BAT*/charge_control_end_threshold >/dev/null 2>&1; then
            # Present-but-root-only is the normal state WITHOUT the udev rule, and
            # is exactly the case worth reporting: Settings hides the control and
            # the user is left wondering where it went.
            _check "laptop: charge ceiling writable"   sh -c 'test -w /sys/class/power_supply/BAT*/charge_control_end_threshold'
        else
            _note "laptop: no battery charge-ceiling control on this hardware"
        fi

        if ls /sys/class/leds/*kbd_backlight >/dev/null 2>&1; then
            _check "laptop: keyboard backlight"        sh -c 'ls /sys/class/leds/*kbd_backlight/max_brightness >/dev/null 2>&1'
        else
            _note "laptop: no keyboard backlight on this hardware"
        fi

        _check "laptop: hypridle (idle timing)"        sh -c 'command -v hypridle'
        _check "laptop: checkupdates (safe updates)"   sh -c 'command -v checkupdates'

        # Sleep that can actually survive a day in a bag: zzz.sh asks for
        # suspend-then-hibernate; without a resumable swapfile it silently (and
        # safely) degrades to s2idle-only, which drains for real. Surface that.
        if grep -q 'resume=' /proc/cmdline 2>/dev/null; then
            _check "laptop: hibernate backing (resume=)" true
        else
            _note "laptop: hibernate not active yet (phase 32 sets it up; needs one reboot) — long sleeps stay on s2idle"
        fi

        # A 2024/2025 thin laptop on launch-day BIOS is where poweroff hangs and
        # sleep drain live. fwupd can often fix that from Linux; say so.
        if command -v fwupdmgr >/dev/null 2>&1; then
            _note "laptop: BIOS $(cat /sys/class/dmi/id/bios_version 2>/dev/null) ($(cat /sys/class/dmi/id/bios_date 2>/dev/null)) — check for updates: fwupdmgr refresh && fwupdmgr get-updates"
        fi
    fi

    echo
    info "manual: Firefox → about:support → Compositing = 'WebRender'; play a video and watch \`intel_gpu_top\` Video engine."
    ok "verification done"
}
