#!/usr/bin/env bash
# phase 35 — Plymouth boot splash: the ewe sheep mark + spinner from early boot
# to the greeter, hiding the kernel/systemd [OK] text. Three parts, all idempotent
# and best-effort (a missing piece warns, never aborts):
#   1. install our theme (stock spinner frames + the ewe watermark + colours)
#   2. add the `plymouth` mkinitcpio hook + regenerate the initramfs
#   3. add `quiet splash …` to the kernel cmdline (systemd-boot AND/OR GRUB)
# The after-LOGIN "Welcome <user>" splash is the Quickshell Splash.qml component,
# not here — this phase is purely the pre-greeter boot experience.

# Kernel params that actually silence the boot. Order doesn't matter; appended
# (never reordered) to whatever cmdline already exists. `splash` is a no-op flag
# if plymouth is ever absent, so adding these is safe.
#   systemd.show_status=auto (+rd. for the initramfs) — no "[ OK ] Started …"
#     lines on the console (they still appear if boot actually degrades/errors)
#   udev.log_level=3 — udev after the initramfs handoff (rd.* only covers early boot)
_QUIET_PARAMS="quiet splash loglevel=3 rd.udev.log_level=3 udev.log_level=3 systemd.show_status=auto rd.systemd.show_status=auto vt.global_cursor_default=0"

phase_bootsplash() {
    step "35 · boot splash (plymouth)"

    if ! command -v plymouth-set-default-theme >/dev/null 2>&1 && ! pkg_present plymouth; then
        info "plymouth not installed (skipped in packages?) — no boot splash. Install 'plymouth' and re-run."
        return 0
    fi
    command -v systemctl >/dev/null 2>&1 || { warn "no systemd — skipping plymouth boot splash."; return 0; }

    # ── 1. install the theme ────────────────────────────────────────────────
    local src="$DOTREPO/system/plymouth/ewe" dst=/usr/share/plymouth/themes/ewe
    sudo_run install -d "$dst"
    # Reuse the stock "spinner" theme's throbber/animation frames so we don't ship
    # ~60 PNGs; we only override the watermark (the ewe sheep) and the .plymouth.
    if [ -d /usr/share/plymouth/themes/spinner ]; then
        sudo_run sh -c "cp -f /usr/share/plymouth/themes/spinner/*.png '$dst'/"
    else
        warn "stock 'spinner' theme missing — splash will show the logo without a spinner."
    fi
    sudo_run install -m 644 "$src/watermark.png" "$dst/watermark.png"
    sudo_run install -m 644 "$src/ewe.plymouth"  "$dst/ewe.plymouth"
    # migrate: drop the pre-rename theme so it doesn't linger in the picker
    [ -d /usr/share/plymouth/themes/hypr-shell ] && sudo_run rm -rf /usr/share/plymouth/themes/hypr-shell
    ok "installed plymouth theme: ewe"

    # ── 1b. quit with --retain-splash ───────────────────────────────────────
    # Stock plymouth-quit drops the framebuffer back to the text console, so
    # every boot line flashes up between the splash and the greeter (and again
    # on the VT juggle after login). Retaining the last frame means the sheep
    # stays up until cage draws — no console text is ever exposed.
    sudo_run install -d /etc/systemd/system/plymouth-quit.service.d
    sudo_run install -m 644 "$DOTREPO/system/plymouth/10-ewe-retain-splash.conf" \
        /etc/systemd/system/plymouth-quit.service.d/10-ewe-retain-splash.conf \
        && ok "plymouth-quit retains the splash frame (no console flash before the greeter)"

    # ── 2. mkinitcpio hook ──────────────────────────────────────────────────
    # plymouth must sit right after the `udev` (or `systemd`) hook so it starts
    # before the root device / encryption prompt.
    if [ -f /etc/mkinitcpio.conf ]; then
        if grep -qE '^HOOKS=.*\bplymouth\b' /etc/mkinitcpio.conf; then
            info "mkinitcpio: plymouth hook already present"
        else
            sudo_run cp /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.bak.$RUN_STAMP"
            if grep -qE '^HOOKS=.*\budev\b' /etc/mkinitcpio.conf; then
                sudo_run sed -i -E 's/^(HOOKS=\(.*\budev)\b/\1 plymouth/' /etc/mkinitcpio.conf && ok "added plymouth to mkinitcpio HOOKS (after udev)"
            elif grep -qE '^HOOKS=.*\bsystemd\b' /etc/mkinitcpio.conf; then
                sudo_run sed -i -E 's/^(HOOKS=\(.*\bsystemd)\b/\1 plymouth/' /etc/mkinitcpio.conf && ok "added plymouth to mkinitcpio HOOKS (after systemd)"
            else
                warn "couldn't find a udev/systemd hook in /etc/mkinitcpio.conf — add 'plymouth' to HOOKS manually."
            fi
        fi
    else
        info "no /etc/mkinitcpio.conf (dracut/UKI?) — relying on plymouth-set-default-theme -R to wire the initramfs."
    fi

    # ── set theme + regenerate initramfs (this runs mkinitcpio -P / dracut) ──
    sudo_run plymouth-set-default-theme -R ewe && ok "set default plymouth theme + regenerated initramfs" \
        || warn "plymouth-set-default-theme -R failed — check the initramfs generator output."

    # ── 3. quiet kernel cmdline (systemd-boot entries, /etc/kernel/cmdline, GRUB) ──
    _apply_quiet_cmdline

    # ── greeter handoff: start greetd only after plymouth has cleanly quit, so the
    # splash → greeter transition doesn't flash a TTY or fight over the DRM master ─
    if systemctl list-unit-files greetd.service >/dev/null 2>&1; then
        sudo_run install -d /etc/systemd/system/greetd.service.d
        sudo_run sh -c 'printf "[Unit]\n# ewe: hand off cleanly from the plymouth splash.\nAfter=plymouth-quit-wait.service\n" > /etc/systemd/system/greetd.service.d/plymouth.conf' \
            && ok "ordered greetd after the plymouth splash"
        run systemctl daemon-reload 2>/dev/null || true
    fi

    info "boot splash ready — visible on the next reboot (initramfs was regenerated)."
}

# Append _QUIET_PARAMS (only the tokens not already present) to every kernel
# cmdline source that exists. Idempotent; backs up each file to *.bak.$RUN_STAMP.
_apply_quiet_cmdline() {
    local did=""
    # All the editing happens in one root shell so we touch /boot + /etc atomically.
    # The helper `add_missing <file> <append-style>` works on options/cmdline lines.
    local script='
        params="'"$_QUIET_PARAMS"'"; stamp="'"$RUN_STAMP"'"
        # missing <current-cmdline> -> echoes the tokens not already present (leading space)
        missing() { local cur=" $1 " add="" p k; for p in $params; do k=${p%%=*}; case "$cur" in *" $k="*|*" $k "*) ;; *) add="$add $p";; esac; done; printf "%s" "$add"; }
        changed=0
        # systemd-boot loader entries: each has an "options …" line
        if ls /boot/loader/entries/*.conf >/dev/null 2>&1; then
            for f in /boot/loader/entries/*.conf; do
                [ -f "$f" ] || continue
                if grep -q "^options " "$f"; then
                    add=$(missing "$(sed -n "s/^options //p" "$f" | head -1)")
                    [ -n "$add" ] && { cp "$f" "$f.bak.$stamp"; sed -i "/^options /s|\$|$add|" "$f"; changed=1; }
                else
                    cp "$f" "$f.bak.$stamp"; printf "options %s\n" "$params" >> "$f"; changed=1
                fi
            done
            [ "$changed" = 1 ] && echo "systemd-boot-entries"
        fi
        # mkinitcpio UKI / sdboot-manage cmdline source
        if [ -f /etc/kernel/cmdline ]; then
            add=$(missing "$(cat /etc/kernel/cmdline)")
            [ -n "$add" ] && { cp /etc/kernel/cmdline "/etc/kernel/cmdline.bak.$stamp"; printf "%s%s\n" "$(cat /etc/kernel/cmdline)" "$add" > /etc/kernel/cmdline; echo "etc-kernel-cmdline"; }
        fi
        # GRUB
        if [ -f /etc/default/grub ]; then
            cur=$(sed -n "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/\1/p" /etc/default/grub | head -1)
            add=$(missing "$cur")
            if [ -n "$add" ]; then
                cp /etc/default/grub "/etc/default/grub.bak.$stamp"
                new="$cur$add"; new="${new# }"
                sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new\"|" /etc/default/grub
                if command -v grub-mkconfig >/dev/null 2>&1 && [ -f /boot/grub/grub.cfg ]; then
                    grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 && echo "grub"
                else
                    echo "grub-default-only"
                fi
            fi
        fi
    '
    if [ "${DRY_RUN:-0}" = "1" ]; then
        info "would add to kernel cmdline (systemd-boot/GRUB, missing tokens only): $_QUIET_PARAMS"
        return 0
    fi
    did="$(sudo_run bash -c "$script" 2>/dev/null)"
    if [ -n "$did" ]; then
        ok "quiet kernel cmdline applied ($did): $_QUIET_PARAMS"
        case "$did" in *grub-default-only*) warn "GRUB default updated but /boot/grub/grub.cfg not found — run grub-mkconfig yourself." ;; esac
    else
        warn "no known bootloader cmdline found (systemd-boot/GRUB) or already set — splash still works, but some boot text may flash. Add manually: $_QUIET_PARAMS"
    fi
}
