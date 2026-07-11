#!/usr/bin/env bash
# phase 10 — enable [multilib] (for 32-bit gaming libs + Steam) and bootstrap an
# AUR helper. Both are idempotent.

_enable_multilib() {
    if multilib_enabled; then ok "[multilib] already enabled"; return; fi
    info "enabling [multilib] in /etc/pacman.conf (needed for steam + lib32-*)"
    if [ "${DRY_RUN:-0}" = "1" ]; then info "would uncomment the [multilib] block in /etc/pacman.conf"; return; fi
    # uncomment the standard two-line [multilib] block
    sudo_run sed -i '/^#\[multilib\]/{N;s/^#\[multilib\]\n#Include = \(.*\)/[multilib]\nInclude = \1/}' /etc/pacman.conf
    if multilib_enabled; then ok "[multilib] enabled"; else
        warn "could not auto-enable [multilib] — uncomment the [multilib] block in /etc/pacman.conf by hand, then re-run."
    fi
    sudo_run pacman -Sy
}

_sync_system() {
    # Full upgrade BEFORE building/installing anything. A fresh archinstall box
    # carries an older pacman/libalpm than the live repos; installing prebuilt
    # AUR helpers (paru-bin links libalpm.so.N) or new packages onto it triggers
    # "libalpm.so.NN: cannot open shared object file" and other partial-upgrade
    # breakage. -Syu brings the whole system to a consistent state first.
    # Coexist: this is someone's live daily driver (a rolling Arch/CachyOS box),
    # not a fresh archinstall — don't upgrade their whole system behind their
    # back. They keep it current themselves; if a `pacman -S` later fails on a
    # soname mismatch, the advice is to run `sudo pacman -Syu` and re-run.
    if [ "${COEXIST:-0}" = "1" ]; then
        info "coexist: skipping the full 'pacman -Syu' (your system stays as-is). Run it yourself if a package fails to install."
        return
    fi
    if [ "${DRY_RUN:-0}" = "1" ]; then info "would run pacman -Syu (full system upgrade)"; return; fi
    info "full system upgrade (pacman -Syu) — avoids partial-upgrade / soname mismatches"
    sudo_run pacman -Syu --noconfirm || warn "pacman -Syu reported errors — review before continuing."
}

# Does a helper actually RUN? A stale prebuilt paru-bin can be installed but
# broken ("libalpm.so.NN: cannot open shared object file" after a soname bump),
# so test execution — not just `command -v`.
_helper_works() { command -v "$1" >/dev/null 2>&1 && "$1" --version >/dev/null 2>&1; }

_bootstrap_aur() {
    if _helper_works paru; then AUR_HELPER=paru; export AUR_HELPER; ok "AUR helper present (paru)"; return; fi
    # Reuse an existing helper rather than duplicating it — many Arch derivatives
    # (CachyOS ships yay) already have one. Avoids building paru beside it.
    if _helper_works yay; then AUR_HELPER=yay; export AUR_HELPER; ok "AUR helper present (yay)"; return; fi

    info "bootstrapping paru (AUR helper, built from source)…"
    install_official base-devel git rust
    if [ "${DRY_RUN:-0}" = "1" ]; then info "would build paru from source (as the invoking user) and pacman -U it"; AUR_HELPER=paru; export AUR_HELPER; return; fi

    # makepkg refuses to run as root, but install.sh is commonly run with sudo.
    # Build the package as the *invoking* user (SUDO_USER) and install the
    # resulting .pkg with pacman -U as root — so `sudo ./install.sh` yields a
    # working paru too (no more "no AUR helper" at the end).
    local builder=""
    if [ "$(id -u)" = "0" ]; then
        builder="${SUDO_USER:-}"
        if [ -z "$builder" ] || [ "$builder" = "root" ]; then
            warn "running as root with no SUDO_USER — can't build paru (makepkg refuses root)."
            warn "Re-run as your normal user (the script elevates with sudo itself), or as 'sudo -u <you> ./install.sh'."
            return
        fi
        info "building paru as user '$builder' (makepkg can't run as root)"
    fi
    local as_builder=""; [ -n "$builder" ] && as_builder="sudo -u $builder"

    # A broken prebuilt paru-bin blocks installing source paru (file conflict on
    # /usr/bin/paru) — remove it so we can replace it.
    if command -v paru >/dev/null 2>&1 && ! _helper_works paru; then
        warn "existing paru is broken (shared-library mismatch) — removing it to rebuild from source."
        pkg_present paru-bin && sudo_run pacman -Rdd --noconfirm paru-bin
        pkg_present paru     && sudo_run pacman -Rdd --noconfirm paru
    fi

    # Build `paru` (source — links the CURRENTLY-installed libalpm, so it survives
    # the soname bumps that break prebuilt paru-bin) in a dir the builder owns,
    # then install the artifact as root. `-s` resolves makedepends from the
    # base-devel/git/rust we just installed, so it shouldn't need to fetch more.
    local t; t="$(mktemp -d)"
    [ -n "$builder" ] && chown "$builder" "$t"
    if $as_builder git clone --depth 1 https://aur.archlinux.org/paru.git "$t/paru" \
       && ( cd "$t/paru" && $as_builder makepkg -sf --noconfirm --noprogressbar ); then
        local pkg; pkg="$(ls "$t"/paru/paru-*.pkg.tar.* 2>/dev/null | grep -v -- '-debug-' | head -1)"
        if [ -n "$pkg" ] && sudo_run pacman -U --noconfirm "$pkg" && _helper_works paru; then
            AUR_HELPER=paru; export AUR_HELPER; ok "paru installed (built from source)"
        else
            warn "paru built but could not be installed/run — AUR packages will be skipped."
        fi
    else
        warn "paru bootstrap failed — AUR extras (gpu-screen-recorder) skipped. Non-critical: themes install from source regardless."
    fi
    rm -rf "$t"
}

phase_repos() {
    step "10 · repositories"
    # [multilib] is only needed for 32-bit libs (Steam + the lib32 GPU drivers),
    # which are now opt-in — so only enable it when the gaming stack was requested.
    if [ "${GAMING:-0}" = "1" ]; then
        _enable_multilib
    else
        info "[multilib] left disabled — 32-bit libs / Steam are opt-in (re-run with --gaming to enable)"
    fi
    _sync_system
    _bootstrap_aur
    ok "repositories ready"
}
