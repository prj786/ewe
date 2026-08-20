#!/usr/bin/env bash
# phase 20 — install the official-repo set (pacman), the AUR set (helper), then
# the two upstream themes that aren't reliably packaged (built from source,
# system-wide, so the accent icons + cursor always land — no silent AUR skips).

# Reversal icon theme (all accent variants) + Mocu cursor → /usr/share/icons.
# System-wide so every user AND the greeter see them. Loud on failure; idempotent.
_install_themes() {
    command -v git >/dev/null 2>&1 || { warn "git missing — cannot install icon/cursor themes"; return 0; }
    local d

    # ── Reversal icon theme: sudo ./install.sh -d /usr/share/icons -t all ──
    if [ -d /usr/share/icons/Reversal-blue-dark ]; then
        ok "Reversal icon theme already installed"
    else
        info "installing Reversal icon theme (all accent variants → /usr/share/icons)…"
        d="$(mktemp -d)"
        if git clone --depth 1 https://github.com/yeyushengfan258/Reversal-icon-theme.git "$d/rev"; then
            ( cd "$d/rev" && sudo_run bash ./install.sh -d /usr/share/icons -t all ) \
                && ok "Reversal icon theme installed" \
                || warn "Reversal install.sh FAILED — icons will fall back to Papirus."
        else
            warn "Reversal clone failed (network?) — icons will fall back to Papirus."
        fi
        rm -rf "$d"
    fi

    # ── Mocu cursor: build (rsvg-convert/xcursorgen/xmlstarlet) then copy dist/* ──
    if [ -d /usr/share/icons/Mocu-White-Right ]; then
        ok "Mocu cursor already installed"
    else
        info "building Mocu cursor (→ /usr/share/icons)…"
        d="$(mktemp -d)"
        if git clone --depth 1 https://github.com/sevmeyer/mocu-xcursor.git "$d/mocu"; then
            if ( cd "$d/mocu" && bash ./make.sh ); then
                sudo_run cp -r "$d/mocu/dist/." /usr/share/icons/ \
                    && ok "Mocu cursor installed" \
                    || warn "Mocu copy FAILED — cursor falls back to default."
            else
                warn "Mocu make.sh FAILED (need librsvg/xorg-xcursorgen/xmlstarlet) — cursor falls back."
            fi
        else
            warn "Mocu clone failed (network?) — cursor falls back to default."
        fi
        rm -rf "$d"
    fi
}

phase_packages() {
    step "20 · packages"
    [ "${NO_PACKAGES:-0}" = "1" ] && { info "--no-packages: skipping install"; return 0; }

    local off aur game dev
    mapfile -t off < <(read_list common.list)
    mapfile -t aur < <(read_list aur.list)
    mapfile -t game < <(read_list gaming.list)
    mapfile -t dev < <(read_list dev.list)

    # Coexist: don't install the login-manager stack (greetd/regreet/cage) — that
    # would let phase 30 enable greetd.service and replace the user's existing
    # display manager. And drop pipewire-jack, which conflicts with a jack2 the
    # host may already depend on (we also skip the jack2 removal below).
    if [ "${COEXIST:-0}" = "1" ]; then
        local -a keep=(); local p
        for p in "${off[@]}"; do
            case "$p" in
                greetd|greetd-regreet|cage|pipewire-jack) info "coexist: skipping '$p' (would alter your login/audio stack)"; continue ;;
                *) keep+=("$p") ;;
            esac
        done
        off=("${keep[@]}")
    fi

    info "${#off[@]} official packages + ${#aur[@]} AUR packages + 2 first-party apps (Komble, ewe-settings) + 2 source themes (Reversal, Mocu)"
    [ "${DEV:-0}" = "1" ] && info "+ ${#dev[@]} optional dev packages (--dev)"
    [ "${GAMING:-0}" = "1" ] && info "+ ${#game[@]} optional gaming packages (--gaming)"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        printf '%s   pacman:%s %s\n' "$C_DIM" "$C_0" "${off[*]}"
        printf '%s   aur:%s    %s\n' "$C_DIM" "$C_0" "${aur[*]}"
        [ "${DEV:-0}" = "1" ] && printf '%s   dev:%s    %s\n' "$C_DIM" "$C_0" "${dev[*]}"
        [ "${GAMING:-0}" = "1" ] && printf '%s   gaming:%s %s\n' "$C_DIM" "$C_0" "${game[*]}"
        printf '%s   source:%s Reversal-icon-theme (all variants), mocu-xcursor → /usr/share/icons\n' "$C_DIM" "$C_0"
        printf '%s   releases:%s komble-arch (the software manager), ewe-settings (the Settings app) — prebuilt GitHub release, source-build fallback\n' "$C_DIM" "$C_0"
        printf '%s   patched:%s %s — official packages rebuilt with not-yet-released upstream fixes (packages/patched/*, self-retiring)\n' "$C_DIM" "$C_0" "$(ls "$DOTREPO/packages/patched" 2>/dev/null | tr '\n' ' ')"
        return 0
    fi

    # Known provider conflict: pipewire-jack and jack2 both provide `jack` and
    # can't coexist. We ship the PipeWire stack, so PipeWire owns JACK. If the
    # standalone jack2 is installed it dead-ends the non-interactive install on
    # the "Remove jack2? [y/N]" prompt (--noconfirm answers N → whole batch
    # fails). Force-remove jack2 (keeping its dependents — `jack` is immediately
    # re-satisfied by pipewire-jack in the batch below).
    if [ "${COEXIST:-0}" = "1" ]; then
        info "coexist: leaving jack2 in place (host packages like ffmpeg/vlc/waybar may depend on it; we skip pipewire-jack instead)"
    elif pkg_present jack2; then
        info "removing jack2 (conflicts with pipewire-jack; PipeWire provides JACK)"
        sudo_run pacman -Rdd --noconfirm jack2 || warn "could not remove jack2 — pipewire-jack may be skipped"
    fi

    ask_yes "Install ${#off[@]} official packages now?" && install_official "${off[@]}" || warn "skipped official packages"
    if [ "${DEV:-0}" = "1" ] && [ "${#dev[@]}" -gt 0 ]; then
        info "installing the optional dev toolchain (${#dev[@]} packages)"
        install_official "${dev[@]}"
    fi
    if [ "${GAMING:-0}" = "1" ] && [ "${#game[@]}" -gt 0 ]; then
        info "installing the optional gaming stack (${#game[@]} packages)"
        install_official "${game[@]}"
    fi
    if [ "${#aur[@]}" -gt 0 ]; then
        ask_yes "Build & install ${#aur[@]} AUR packages now? (compiles from source)" \
            && install_aur "${aur[@]}" || warn "skipped AUR packages"
    fi
    # Official packages with upstream fixes the repos don't ship yet
    # (packages/patched/*). Today: xdg-desktop-portal-hyprland — without the
    # three post-1.4.1 screencopy fixes any screen share whose consumer returns
    # a buffer late (Cast to TV encoding 1080p, OBS under load) freezes for good.
    install_patched_pkgs
    # Komble — THE software manager of the DE (repos + AUR + AppImages +
    # updates). The dock's store button and `qs ipc call store` launch it; the
    # shell's built-in quick installer is only a fallback while the binary is
    # absent. Not on the AUR yet: installed from the prebuilt GitHub release
    # (its release.yml builds the .pkg.tar.zst), source build as fallback —
    # resilient either way. Move to packages/aur.list once published.
    install_release_pkg komble-arch prj786/komble-arch https://github.com/prj786/komble-arch.git
    # ewe-settings — THE Settings app (formerly hypr-shell-settings). Every
    # settings entry point (Super+comma, the Quick Settings gear,
    # `qs ipc call settings`) launches it; the in-shell panel remains only as a
    # fallback when the binary is absent, so a failed build can never leave the
    # desktop unconfigurable.
    # Migration: the new package conflicts/replaces the old name, but
    # `pacman -U --noconfirm` answers NO to the conflict-removal question, so
    # the old package must go first or the install errors out.
    if pkg_present hypr-shell-settings; then
        info "migrating hypr-shell-settings → ewe-settings"
        sudo_run pacman -R --noconfirm hypr-shell-settings
    fi
    install_release_pkg ewe-settings prj786/ewe-settings https://github.com/prj786/ewe-settings.git
    _install_themes
    ok "package phase done"
}
