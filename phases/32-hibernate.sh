#!/usr/bin/env bash
# phase 32 — hibernate backing, so suspend-then-hibernate has somewhere to land.
#
# Why: every sleep entry point in the DE funnels through zzz.sh, which asks for
# suspend-then-hibernate and falls back to plain suspend. On a laptop, s2idle
# for 15–20 h is a dead battery (observed on the Zenbook S14); hibernate is
# zero drain. This phase provides the three things logind needs to say yes:
#   1. a swapfile big enough to hold the hibernation image (RAM-sized + 1 GiB)
#   2. resume=UUID=… resume_offset=… on the kernel cmdline + the mkinitcpio
#      `resume` hook, so the next boot can find and read the image back
#   3. the sleep.conf.d drop-in (HibernateDelaySec) that turns a long s2idle
#      into a hibernate
#
# Laptop-only (a desktop on AC gains nothing and loses disk); every action goes
# through run/sudo_run so --dry-run stays honest; each config file is backed up
# to *.bak.$RUN_STAMP. Safe to re-run: an already-configured machine no-ops.
# If any step can't proceed (btrfs, no space, no mkinitcpio) it warns and skips
# — zzz.sh's suspend fallback keeps the DE fully functional without it.

phase_hibernate() {
    step "32 · hibernate (suspend-then-hibernate backing)"

    # ── the sleep policy drop-in goes in unconditionally: with no swap it is
    #    inert (zzz.sh falls back to suspend), with swap it is the 2 h timer ──
    sudo_run install -d /etc/systemd/sleep.conf.d
    sudo_run install -m 644 "$DOTREPO/system/sleep/10-hypr-shell-sleep.conf" \
        /etc/systemd/sleep.conf.d/10-hypr-shell-sleep.conf \
        && ok "installed sleep drop-in (s2idle 2 h → hibernate)"

    if ! ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
        info "no battery — desktop; skipping the swapfile/resume setup."
        return 0
    fi

    # ── logind must be able to SEE a swapfile under /home. It runs with
    #    ProtectHome=yes, so /home/.swapfile stats as ENOENT inside its mount
    #    namespace and every CanHibernate / suspend-then-hibernate request is
    #    refused — zzz.sh then silently falls back to plain suspend and the
    #    machine s2idles the whole night (observed 2026-08-15). This must run
    #    BEFORE the resume=-already-set early return: that return is exactly
    #    the machine that hit this. read-only is all logind needs. ──
    if mountpoint -q /home; then
        sudo_run install -d /etc/systemd/system/systemd-logind.service.d
        sudo_run install -m 644 "$DOTREPO/system/logind/10-hypr-shell-hibernate.conf" \
            /etc/systemd/system/systemd-logind.service.d/10-hypr-shell-hibernate.conf \
            && ok "installed logind drop-in (swapfile under /home stays visible to CanHibernate)"
        sudo_run systemctl daemon-reload
        if [ -z "${XDG_CURRENT_DESKTOP:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
            sudo_run systemctl restart systemd-logind || warn "could not restart systemd-logind — hibernate visibility applies after reboot"
        else
            info "graphical session active — skipping logind restart (hibernate visibility applies on next reboot)"
        fi
    fi

    # Already resumable? (a prior run, or the user set it up themselves)
    if grep -q 'resume=' /proc/cmdline 2>/dev/null; then
        info "resume= already on the kernel cmdline — hibernate is set up; nothing to do."
        return 0
    fi

    # ── pick where the swapfile lives: /home when it is its own filesystem
    #    (it has the space), else / ──
    local swapdir=/ swapfile fstype uuid
    mountpoint -q /home && swapdir=/home
    swapfile="${swapdir%/}/.swapfile"
    fstype="$(findmnt -no FSTYPE "$swapdir" 2>/dev/null)"
    case "$fstype" in
        ext4|xfs) : ;;
        btrfs)
            warn "$swapdir is btrfs — swapfile hibernation needs a +C subvolume and btrfs-specific offsets. Set it up manually (Arch wiki: Power management/Suspend and hibernate) and re-run."
            return 0 ;;
        *)
            warn "unsupported filesystem '$fstype' on $swapdir — skipping hibernate setup."
            return 0 ;;
    esac

    # RAM-sized + 1 GiB: the image is compressed and usually far smaller, but a
    # full-RAM worst case must never fail mid-hibernate on a dying battery.
    local mem_kb size_g free_g
    mem_kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo)"
    size_g=$(( (mem_kb + 1048575) / 1048576 + 1 ))
    free_g="$(df -BG --output=avail "$swapdir" 2>/dev/null | tail -1 | tr -dc 0-9)"
    if [ -z "$free_g" ] || [ "$free_g" -lt $((size_g + 10)) ]; then
        warn "not enough free space on $swapdir for a ${size_g}G swapfile (need ${size_g}G + 10G headroom, have ${free_g:-?}G) — skipping."
        return 0
    fi

    if [ "${DRY_RUN:-0}" = "1" ]; then
        info "would create $swapfile (${size_g}G), add it to fstab (pri=0 — zram stays first),"
        info "add the mkinitcpio 'resume' hook, and put resume=UUID=(uuid of $swapdir) resume_offset=(first extent) on the kernel cmdline."
        return 0
    fi

    # ── 1. the swapfile ──
    if [ ! -f "$swapfile" ]; then
        sudo_run fallocate -l "${size_g}G" "$swapfile" || { warn "fallocate failed — skipping hibernate setup."; return 0; }
        sudo_run chmod 600 "$swapfile"
        sudo_run mkswap "$swapfile" >/dev/null || { warn "mkswap failed — skipping."; return 0; }
        ok "created $swapfile (${size_g}G)"
    else
        info "swapfile already present: $swapfile"
    fi
    # pri=0 keeps zram (pri 100) first for day-to-day swapping; the disk file
    # exists for the hibernation image, not for paging.
    sudo_run swapon -p 0 "$swapfile" 2>/dev/null || true
    if ! grep -q "^$swapfile " /etc/fstab 2>/dev/null; then
        sudo_run cp /etc/fstab "/etc/fstab.bak.$RUN_STAMP"
        sudo_run sh -c "printf '%s none swap defaults,pri=0 0 0\n' '$swapfile' >> /etc/fstab" \
            && ok "added $swapfile to fstab"
    fi

    # ── 2. resume plumbing: UUID + physical offset of the file's first extent ──
    uuid="$(findmnt -no UUID "$swapdir" 2>/dev/null)"
    local offset
    offset="$(sudo_run filefrag -v "$swapfile" 2>/dev/null | awk '$1=="0:"{print $4}' | tr -d '.,')"
    if [ -z "$uuid" ] || [ -z "$offset" ]; then
        warn "couldn't determine resume UUID/offset (uuid='$uuid' offset='$offset') — hibernate stays off; zzz.sh keeps falling back to suspend."
        return 0
    fi

    # mkinitcpio: the resume hook must come after block (it reads the image
    # straight off the device). Busybox and systemd inits spell it differently.
    if [ -f /etc/mkinitcpio.conf ] && ! grep -qE '^HOOKS=.*\b(resume|systemd)\b' /etc/mkinitcpio.conf; then
        sudo_run cp /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.bak.$RUN_STAMP"
        sudo_run sed -i -E 's/^(HOOKS=\(.*\bblock)\b/\1 resume/' /etc/mkinitcpio.conf \
            && ok "added 'resume' to mkinitcpio HOOKS (after block)"
        sudo_run mkinitcpio -P >/dev/null 2>&1 && ok "regenerated initramfs" \
            || warn "mkinitcpio -P failed — run it manually before relying on hibernate."
    elif grep -qE '^HOOKS=.*\bsystemd\b' /etc/mkinitcpio.conf 2>/dev/null; then
        info "systemd-based initramfs — it resumes from the cmdline params on its own, no hook needed."
    fi

    _apply_resume_cmdline "resume=UUID=$uuid resume_offset=$offset"
    info "hibernate ready after the next reboot (the cmdline change needs one). Until then zzz.sh falls back to plain suspend."
}

# Append the resume params (only if a resume= token isn't already there) to every
# kernel cmdline source that exists — same sources phase 35 handles for `quiet`.
_apply_resume_cmdline() {
    local params="$1" did=""
    local script='
        params="'"$1"'"; stamp="'"$RUN_STAMP"'"
        changed=""
        if ls /boot/loader/entries/*.conf >/dev/null 2>&1; then
            for f in /boot/loader/entries/*.conf; do
                [ -f "$f" ] || continue
                grep -q "^options .*resume=" "$f" && continue
                cp "$f" "$f.bak.$stamp"
                if grep -q "^options " "$f"; then sed -i "/^options /s|\$| $params|" "$f"
                else printf "options %s\n" "$params" >> "$f"; fi
                changed="systemd-boot-entries"
            done
        fi
        if [ -f /etc/kernel/cmdline ] && ! grep -q "resume=" /etc/kernel/cmdline; then
            cp /etc/kernel/cmdline "/etc/kernel/cmdline.bak.$stamp"
            printf "%s %s\n" "$(tr -d "\n" < /etc/kernel/cmdline)" "$params" > /etc/kernel/cmdline
            changed="$changed etc-kernel-cmdline"
        fi
        if [ -f /etc/default/grub ] && ! grep -q "resume=" /etc/default/grub; then
            cp /etc/default/grub "/etc/default/grub.bak.$stamp"
            sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"|&$params |" /etc/default/grub
            if command -v grub-mkconfig >/dev/null 2>&1 && [ -f /boot/grub/grub.cfg ]; then
                grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 && changed="$changed grub"
            else changed="$changed grub-default-only"; fi
        fi
        printf "%s" "$changed"
    '
    did="$(sudo_run bash -c "$script" 2>/dev/null)"
    if [ -n "$did" ]; then
        ok "resume params applied ($did): $params"
        case "$did" in *grub-default-only*) warn "GRUB default updated but grub.cfg not regenerated — run grub-mkconfig yourself." ;; esac
    else
        warn "no bootloader cmdline found (or resume= already set elsewhere) — add manually: $params"
    fi
}
