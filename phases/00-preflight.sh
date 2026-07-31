#!/usr/bin/env bash
# phase 00 — preflight: sanity checks + announce the backup policy.

phase_preflight() {
    step "00 · preflight"

    # tools the installer itself needs
    for t in awk grep sed ln; do
        command -v "$t" >/dev/null 2>&1 || die "missing required tool: $t"
    done

    # Network. This is FATAL, not a warning, and the check deliberately does not
    # use curl.
    #
    # Every package helper here warns and skips on failure so one bad package
    # cannot sink a run. With no network at all that forgiveness compounds: all
    # of them skip, and the installer reports success having installed nothing —
    # no Hyprland, no Quickshell, no greeter. That happened to a real install,
    # and the symptom ("the desktop does not start") points nowhere near the
    # cause. Better to refuse up front.
    #
    # The old check was guarded by `command -v curl`, and a base Arch install has
    # no curl — so it silently skipped on precisely the systems most likely to be
    # freshly installed and unconfigured. getent is part of glibc and always there.
    if [ "${DRY_RUN:-0}" != "1" ] && [ "${HYPR_SHELL_SKIP_NET:-0}" != "1" ]; then
        if ! getent hosts archlinux.org >/dev/null 2>&1 \
           && ! getent hosts github.com >/dev/null 2>&1; then
            # distinguish "no route" from "route fine, DNS broken" — the second
            # is much more common on a fresh install and needs a different fix
            if (exec 3<>/dev/tcp/1.1.1.1/443) 2>/dev/null; then
                die "DNS is not working (routing is fine — 1.1.1.1:443 is reachable).
   Fix name resolution, then re-run. On a fresh Arch install that usually means
   no resolver is configured: put a nameserver in /etc/resolv.conf, or enable
   systemd-resolved. Override with HYPR_SHELL_SKIP_NET=1."
            fi
            die "no network. Every package step would silently install nothing,
   leaving a desktop that cannot start. Bring the link up first — on a fresh
   Arch install nothing enables networking by default; systemd-networkd plus a
   .network file, or NetworkManager, is the usual fix.
   Override with HYPR_SHELL_SKIP_NET=1 if you really mean to continue."
        fi
    fi

    # disk space on / (need a couple GB for the package set)
    local freem; freem="$(df -Pm / 2>/dev/null | awk 'NR==2{print $4}')"
    if [ -n "$freem" ] && [ "$freem" -lt 3000 ]; then
        warn "only ${freem}MB free on / — the full package set may not fit."
    fi

    info "existing ~/.config/{hypr,quickshell} will be backed up to *.bak.$RUN_STAMP before linking."
    ok "preflight done"
}
