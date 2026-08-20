#!/usr/bin/env bash
# phase 30 — enable services, install the SDDM config + Wayland session entry.

_enable_system() {  # <unit> — enable (+start) if present
    command -v systemctl >/dev/null 2>&1 || return 0
    if systemctl list-unit-files "$1" 2>/dev/null | grep -q "^$1"; then
        sudo_run systemctl enable "$1" && ok "enabled $1" || warn "could not enable $1"
    else
        info "service not present, skipping: $1"
    fi
}

phase_services() {
    step "30 · services + greeter + session entry"
    command -v systemctl >/dev/null 2>&1 || { warn "no systemd — skipping service enablement (enable equivalents in your init)."; return 0; }

    # ── user audio stack (socket-activated) ──
    # Enable for the REAL user: under `sudo ./install.sh` a bare `systemctl --user`
    # targets root's instance and no-ops for the actual account (mirrors phase 10).
    if [ "$(id -u)" = "0" ] && [ -n "${SUDO_USER:-}" ]; then
        run sudo -u "$SUDO_USER" "XDG_RUNTIME_DIR=/run/user/$(id -u "$SUDO_USER")" \
            systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null \
            || info "pipewire user units will come up with the session"
    else
        run systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null \
            || info "pipewire user units will come up with the session"
    fi

    # ── system services ──
    _enable_system NetworkManager.service
    _enable_system bluetooth.service
    _enable_system power-profiles-daemon.service
    # ── Cast to TV: Chromecast / Google TV discovery is mDNS, which is avahi's
    # job (Miracast needs nothing extra — NetworkManager + wpa_supplicant do the
    # Wi-Fi P2P). Start it now too: the Cast tile should work without a reboot.
    _enable_system avahi-daemon.service
    if pkg_present avahi && ! systemctl is-active --quiet avahi-daemon.service 2>/dev/null; then
        sudo_run systemctl start avahi-daemon.service || warn "could not start avahi-daemon — Chromecast discovery works after reboot"
    fi

    # ── time: NTP on + a real timezone ──
    # A minimal Arch install often leaves NTP off and the clock in UTC — the
    # desktop then shows the wrong time. timesyncd ships with systemd, so just
    # turn it on; if the timezone was never set, take a best-effort GeoIP guess
    # (the user can always change it: timedatectl set-timezone <Region/City>).
    _enable_system systemd-timesyncd.service
    sudo_run timedatectl set-ntp true 2>/dev/null || true
    if [ "$(timedatectl show -p Timezone --value 2>/dev/null)" = "UTC" ]; then
        local tz
        tz=$(curl -fsSL --max-time 8 "http://ip-api.com/line/?fields=timezone" 2>/dev/null || true)
        case "$tz" in
            */*) sudo_run timedatectl set-timezone "$tz" && ok "timezone set from GeoIP: $tz" \
                     || warn "could not set timezone '$tz' — set it manually: timedatectl set-timezone <Region/City>" ;;
            *)   info "timezone is UTC and the GeoIP lookup failed — set it with: timedatectl set-timezone <Region/City>" ;;
        esac
    fi

    # ── Wi-Fi regulatory domain ──
    # A fresh Arch never sets one, so the kernel runs the "world" domain (00):
    # 5 GHz is receive-only (NO-IR) — no 5 GHz hotspot and no 5 GHz Wi-Fi
    # Direct, which pins Cast to TV's Miracast link to the crowded 2.4 GHz band
    # (lag, frozen frames). Set it once from GeoIP (the timezone lookup above
    # already trusts the same source); the user can change it any time in
    # /etc/conf.d/wireless-regdom.
    if pkg_present wireless-regdb && ! grep -qE '^[[:space:]]*WIRELESS_REGDOM=' /etc/conf.d/wireless-regdom 2>/dev/null; then
        local cc
        cc=$(curl -fsSL --max-time 8 "http://ip-api.com/line/?fields=countryCode" 2>/dev/null | tr -d '[:space:]' || true)
        if printf '%s' "$cc" | grep -qE '^[A-Z]{2}$'; then
            printf 'WIRELESS_REGDOM="%s"\n' "$cc" | sudo_run tee -a /etc/conf.d/wireless-regdom >/dev/null \
                && ok "Wi-Fi regulatory domain set from GeoIP: $cc (5 GHz allowed for hotspot / Wi-Fi Direct)"
            command -v iw >/dev/null 2>&1 && { sudo_run iw reg set "$cc" 2>/dev/null || true; }
        else
            info "could not determine the country for the Wi-Fi regulatory domain — set WIRELESS_REGDOM in /etc/conf.d/wireless-regdom"
        fi
    fi

    # ── persistent journal ──
    # journald's Storage=auto keeps logs across reboots only if /var/log/journal
    # exists. Without it a hard freeze + forced power-off leaves NOTHING to
    # diagnose (the log of the frozen boot lived in tmpfs). With it:
    #   journalctl -b -1 -p err        ← the previous (frozen) boot's errors
    # See docs/TROUBLESHOOTING.md for the full freeze playbook.
    if [ ! -d /var/log/journal ]; then
        sudo_run install -d /var/log/journal
        # let systemd fix up ownership/ACLs so unprivileged `journalctl -b -1` works
        sudo_run systemd-tmpfiles --create --prefix /var/log/journal 2>/dev/null || true
        ok "persistent journal enabled (/var/log/journal) — post-freeze logs survive reboots"
    fi

    # ── Wayland session entry — installed to BOTH standard dirs so ReGreet finds
    #    it regardless of its scan paths. ──
    local tmpl="$DOTREPO/templates/hyprland-de.desktop.in"
    local wrap="$HOME/.config/hypr/start-hyprland.sh"
    if [ -r "$tmpl" ]; then
        local d
        for d in /usr/share/wayland-sessions /usr/local/share/wayland-sessions; do
            sudo_run install -d "$d"
            if [ "${DRY_RUN:-0}" = "1" ]; then info "would write $d/hyprland-de.desktop (Exec=$wrap)"
            else sed "s|@EXEC@|$wrap|g" "$tmpl" | sudo_run tee "$d/hyprland-de.desktop" >/dev/null && ok "installed session entry $d/hyprland-de.desktop"; fi
        done
    fi

    # ── greetd greeter (Quickshell/QML, themed) via cage; zero Xorg ──
    if [ "${COEXIST:-0}" = "1" ]; then
        info "coexist: leaving your existing login manager in charge — the 'Hyprland (DE)' session entry above is all that's needed to pick this DE at login."
    elif command -v greetd >/dev/null 2>&1 || pkg_present greetd; then
        sudo_run install -d /etc/greetd
        sudo_run install -m 644 "$DOTREPO/system/greetd/config.toml"  /etc/greetd/config.toml  && ok "installed greetd config"

        # The themed greeter is a Quickshell config installed to the system XDG
        # dir so the `greeter` user can read it (qs -c ewe-greeter).
        sudo_run install -d /etc/xdg/quickshell/ewe-greeter
        sudo_run install -m 644 "$DOTREPO/system/greeter/shell.qml" /etc/xdg/quickshell/ewe-greeter/shell.qml \
            && ok "installed Quickshell greeter (/etc/xdg/quickshell/ewe-greeter)"
        # migrate: pre-rename greeter config dir + wrapper
        [ -d /etc/xdg/quickshell/hyprshell-greeter ] && sudo_run rm -rf /etc/xdg/quickshell/hyprshell-greeter
        [ -f /usr/local/bin/hypr-shell-greeter ] && sudo_run rm -f /usr/local/bin/hypr-shell-greeter

        # Greeter wrapper — config.toml's command points here. A real script (not
        # an `env …` prefix, which greetd word-splits and mis-parses, nor a service
        # drop-in, whose env greetd may not pass through) is the place to set env:
        #   WLR_NO_HARDWARE_CURSORS — fixes the inverted virtio-gpu / flaky `xe` cursor.
        #   WLR_RENDERER_ALLOW_SOFTWARE (VM) — cage software-GL fallback.
        #   XDG_CONFIG_DIRS/XDG_CACHE_HOME — so `qs -c` finds the config + has a
        #     writable cache as the greeter user.
        # Runs the QML greeter, falling back to ReGreet if qs exits nonzero (a QML
        # error must never lock you out of login).
        if [ "${DRY_RUN:-0}" = "1" ]; then info "would write /usr/local/bin/ewe-greeter (cage → qs greeter)"
        else
            { printf '#!/bin/sh\n# Generated by ewe phase 30. Greeter session wrapper run by greetd.\n'
              printf 'export WLR_NO_HARDWARE_CURSORS=1\n'
              [ "${IS_VM:-0}" = "1" ] && printf 'export WLR_RENDERER_ALLOW_SOFTWARE=1\n'
              printf 'export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/etc/xdg}"\n'
              printf 'export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/ewe-greeter}"\n'
              # cage offers no server-side decorations, so Qt draws its OWN client-side
              # titlebar (min/max/close) around the greeter — which is why it looked
              # "in a window". Disable Qt CSD so the greeter is borderless/fullscreen.
              printf 'export QT_QPA_PLATFORM=wayland\n'
              printf 'export QT_WAYLAND_DISABLE_WINDOWDECORATION=1\n'
              printf 'exec cage -s -- sh -c "qs -c ewe-greeter || regreet"\n'
            } | sudo_run tee /usr/local/bin/ewe-greeter >/dev/null \
              && sudo_run chmod 755 /usr/local/bin/ewe-greeter \
              && ok "installed greeter wrapper (Quickshell greeter, regreet fallback)"
        fi
        # Remove the earlier drop-in attempt if a previous run left one.
        [ -f /etc/systemd/system/greetd.service.d/hypr-shell.conf ] && sudo_run rm -f /etc/systemd/system/greetd.service.d/hypr-shell.conf
        sudo_run install -m 644 "$DOTREPO/system/greetd/regreet.toml" /etc/greetd/regreet.toml && ok "installed ReGreet config (fallback)"
        # PAM keyring unlock: login keyring opens with your password at the greeter,
        # so the "login keyring did not get unlocked" prompt never appears.
        if [ -f /usr/lib/security/pam_gnome_keyring.so ] || [ -f /lib/security/pam_gnome_keyring.so ] || pkg_present gnome-keyring; then
            sudo_run install -m 644 "$DOTREPO/system/pam.d/greetd" /etc/pam.d/greetd && ok "installed greetd PAM (gnome-keyring auto-unlock)"
        else
            info "gnome-keyring not present — skipped greetd PAM keyring integration."
        fi
        # Only enable greetd if a greeter binary exists (qs is primary, regreet is
        # the fallback). Otherwise cage's "Failed to spawn client" loops a black
        # screen — refuse to enable and say how to finish.
        if command -v qs >/dev/null 2>&1 || command -v quickshell >/dev/null 2>&1 || command -v regreet >/dev/null 2>&1 || pkg_present quickshell; then
            _enable_system greetd.service
            info "greetd → cage → Quickshell greeter (regreet fallback), lists 'Ewe'. Disable any other display-manager.service first."
        else
            warn "no greeter found (quickshell/regreet) — NOT enabling greetd.service to avoid a broken boot."
            warn "Install with:  sudo pacman -S quickshell greetd-regreet  &&  sudo systemctl enable greetd.service"
        fi
    else
        warn "greetd not installed — start the session from a TTY with start-hyprland.sh, or enable a greeter."
    fi

    # ── Screen-share picker: xdg-desktop-portal-hyprland runs OUR chooser
    # (SharePicker.qml — live previews, real monitor names) instead of its
    # white Qt list. xdph exec()s screencopy:custom_picker_binary verbatim
    # (no shell, no ~), so the wrapper needs a fixed absolute path — same
    # reason the greeter wrapper lives in /usr/local/bin. Config: hypr/xdph.conf.
    sudo_run install -m 755 "$DOTREPO/system/bin/ewe-share-picker" /usr/local/bin/ewe-share-picker \
        && ok "installed screen-share picker wrapper (/usr/local/bin/ewe-share-picker)"
    if systemctl --user is-active --quiet xdg-desktop-portal-hyprland.service 2>/dev/null; then
        run systemctl --user restart xdg-desktop-portal-hyprland.service 2>/dev/null \
            || info "restart xdg-desktop-portal-hyprland (or log out) to pick up the new share picker"
    fi

    # ── Cast to TV: keep the Wi-Fi radio awake during a Miracast session ──
    # A P2P group owner on a radio that still power-saves its station link
    # delivers beacons/RTP late; the TV walks away after a few minutes (a clean
    # 3.5-min stream died this way on 2026-08-21, TV-side AP-STA-DISCONNECTED
    # and nothing else logged). This dispatcher turns power_save off on the
    # parent Wi-Fi iface while a p2p-* connection is up, and back on after.
    if [ -d /etc/NetworkManager/dispatcher.d ] || command -v NetworkManager >/dev/null 2>&1 || pkg_present networkmanager; then
        sudo_run install -d /etc/NetworkManager/dispatcher.d
        sudo_run install -m 755 "$DOTREPO/system/networkmanager/50-ewe-cast-powersave" \
            /etc/NetworkManager/dispatcher.d/50-ewe-cast-powersave \
            && ok "installed NetworkManager cast power-save hook (Miracast link stays up)"
    fi

    # ── Lid ownership: Hyprland's lid.sh does clamshell (panel off when docked,
    # lock+suspend when alone) — logind must not ALSO suspend on lid close.
    sudo_run install -d /etc/systemd/logind.conf.d
    sudo_run install -m 644 "$DOTREPO/system/logind/10-ewe-lid.conf" /etc/systemd/logind.conf.d/10-ewe-lid.conf \
        && ok "installed logind lid drop-in (Hyprland owns the lid switch)"
    # migrate: pre-rename drop-in — two files would both feed logind
    [ -f /etc/systemd/logind.conf.d/10-hypr-shell-lid.conf ] && sudo_run rm -f /etc/systemd/logind.conf.d/10-hypr-shell-lid.conf
    # logind only reads its config at start — but restarting it under a LIVE
    # Wayland session can yank the compositor's session/DRM handle and black-
    # screen the desktop (observed when re-running install.sh inside the DE).
    # Only restart from a TTY/headless run; in-session it applies on reboot.
    if [ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
        sudo_run systemctl restart systemd-logind || warn "could not restart systemd-logind — lid/power-key config applies after reboot"
    else
        info "graphical session active — skipping logind restart (lid/power-key config applies on next reboot)"
    fi

    # ── Battery charge ceiling: hand that ONE sysfs attribute to the wheel
    # group so Settings → Power can set it without a root prompt. Skipped on
    # machines whose battery has no such attribute (desktops, most non-ASUS).
    if compgen -G "/sys/class/power_supply/BAT*/charge_control_end_threshold" >/dev/null 2>&1; then
        sudo_run install -d /etc/udev/rules.d
        sudo_run install -m 644 "$DOTREPO/system/udev/99-ewe-charge-threshold.rules" \
            /etc/udev/rules.d/99-ewe-charge-threshold.rules \
            && ok "installed udev rule (battery charge ceiling settable from Settings)"
        [ -f /etc/udev/rules.d/99-hypr-shell-charge-threshold.rules ] && sudo_run rm -f /etc/udev/rules.d/99-hypr-shell-charge-threshold.rules
        sudo_run udevadm control --reload || warn "udevadm reload failed — the charge ceiling applies after reboot"
        sudo_run udevadm trigger --subsystem-match=power_supply || true
    else
        ok "no battery charge-ceiling attribute on this machine — skipping the udev rule"
    fi

    # ── Poweroff reliability ──
    # 1. USB-dock Realtek LAN adapters must not be wake sources — their armed
    #    Wake-on-LAN can power the machine straight back on after poweroff.
    sudo_run install -d /etc/udev/rules.d
    sudo_run install -m 644 "$DOTREPO/system/udev/99-ewe-usb-lan-no-wake.rules" \
        /etc/udev/rules.d/99-ewe-usb-lan-no-wake.rules \
        && ok "installed udev rule (USB LAN adapters can't wake / power on the machine)"
    [ -f /etc/udev/rules.d/99-hypr-shell-usb-lan-no-wake.rules ] && sudo_run rm -f /etc/udev/rules.d/99-hypr-shell-usb-lan-no-wake.rules
    sudo_run udevadm control --reload || true
    # 2. Unload NIC drivers at the very end of poweroff — iwlwifi's shutdown
    #    path can hang the final ACPI power-off on Lunar Lake (BE200); the
    #    driver-remove path quiesces the hardware properly.
    sudo_run install -d /usr/lib/systemd/system-shutdown
    sudo_run install -m 755 "$DOTREPO/system/shutdown/ewe-unload-nics.shutdown" \
        /usr/lib/systemd/system-shutdown/ewe-unload-nics.shutdown \
        && ok "installed poweroff hook (unloads Wi-Fi/dock-LAN drivers before ACPI S5)"
    [ -f /usr/lib/systemd/system-shutdown/hypr-shell-unload-nics.shutdown ] && sudo_run rm -f /usr/lib/systemd/system-shutdown/hypr-shell-unload-nics.shutdown

    # ── plocate index for the launcher's file search (Super+D → files) ──
    if pkg_present plocate; then
        _enable_system plocate-updatedb.timer
        sudo_run updatedb 2>/dev/null || true   # first index now, not at 2 AM
    fi

    # ── KDE Connect through the firewall (the Mobile card in Quick Settings).
    # Discovery is UDP broadcast on 1716; transfers use TCP/UDP 1714-1764. A
    # default-deny ufw silently eats it and phone + PC never see each other.
    if command -v ufw >/dev/null 2>&1 && systemctl is-active ufw >/dev/null 2>&1; then
        sudo_run ufw allow 1714:1764/tcp comment 'KDE Connect' \
            && sudo_run ufw allow 1714:1764/udp comment 'KDE Connect' \
            && ok "opened ufw 1714-1764 (KDE Connect device discovery + transfer)"
    fi

    ok "services done"
}
