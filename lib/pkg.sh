#!/usr/bin/env bash
# lib/pkg.sh — Arch package handling: official repos via pacman, AUR via the
# helper bootstrapped in phase 10 (paru). No name mapping needed — the lists
# carry real Arch package names.

# read_list <file> — echo package names (strip # comments, inline comments, blanks)
read_list() { awk '{sub(/#.*/,"")} NF {print $1}' "$DOTREPO/packages/$1"; }

# install_official <pkg...> — pacman, idempotent (--needed skips installed).
# RESILIENT: pacman is all-or-nothing, so a single unknown/unavailable name
# (typo, AUR-only package, or a multilib/lib32 target when [multilib] is off)
# aborts the WHOLE batch and installs nothing — which once silently wiped out
# hyprland/quickshell/greetd. So: try the batch (fast path, correct dep order);
# if it fails, retry package-by-package so one missing package can't block the
# rest. Missing ones are warned and skipped — never fatal. Always returns 0.
install_official() {
    [ "$#" -gt 0 ] || return 0
    if sudo_run pacman -S --needed --noconfirm "$@"; then return 0; fi
    warn "official batch hit an error — retrying one-by-one so a missing package can't block the rest"
    local p; local -a missed=()
    for p in "$@"; do
        sudo_run pacman -S --needed --noconfirm -- "$p" || missed+=("$p")
    done
    [ "${#missed[@]}" -gt 0 ] && warn "skipped (not in repos / unavailable): ${missed[*]}"
    return 0
}

# install_aur <pkg...> — via $AUR_HELPER (set in phase 10). Runs as the normal
# user (makepkg refuses root); the helper escalates only for the final install.
# Same resilience as install_official: one failed build can't sink the batch.
install_aur() {
    [ "$#" -gt 0 ] || return 0
    [ -n "${AUR_HELPER:-}" ] || { warn "no AUR helper — skipping AUR packages: $*"; return 0; }
    if run "$AUR_HELPER" -S --needed --noconfirm "$@"; then return 0; fi
    warn "AUR batch hit an error — retrying one-by-one so a failed build can't block the rest"
    local p; local -a missed=()
    for p in "$@"; do
        run "$AUR_HELPER" -S --needed --noconfirm -- "$p" || missed+=("$p")
    done
    [ "${#missed[@]}" -gt 0 ] && warn "skipped (build/install failed): ${missed[*]}"
    return 0
}

# install_git_pkgbuild <pkgname> <git-url> — build and install a PKGBUILD that
# lives in a git repo rather than the AUR. Same resilience contract as
# install_aur: it warns and returns 0 no matter what, because a first-party tool
# failing to build must never sink a desktop install.
#
# This exists for our own apps that are not published to the AUR yet. Once one
# is, drop the call here and add the package name to packages/aur.list instead —
# paru does this better than we can.
install_git_pkgbuild() {
    local name="$1" url="$2" tmp=""
    pkg_present "$name" && { ok "$name already installed"; return 0; }
    command -v git >/dev/null 2>&1 || { warn "git missing — skipping $name"; return 0; }
    command -v makepkg >/dev/null 2>&1 || { warn "base-devel missing — skipping $name"; return 0; }
    if [ "${DRY_RUN:-0}" = "1" ]; then
        printf '%s   would run:%s git clone %s && makepkg -si (%s)\n' "$C_DIM" "$C_0" "$url" "$name"
        return 0
    fi
    tmp="$(mktemp -d)" || { warn "no build dir — skipping $name"; return 0; }
    if git clone --depth 1 "$url" "$tmp/$name" >/dev/null 2>&1; then
        # makepkg refuses to run as root and escalates only for the final install
        if ( cd "$tmp/$name" && makepkg -si --noconfirm --needed ); then
            ok "built and installed $name"
        else
            warn "$name failed to build — skipped (retry later: git clone $url && makepkg -si)"
        fi
    else
        warn "could not clone $url — skipping $name"
    fi
    rm -rf "$tmp"
    return 0
}

# pkg_present <pkg> — installed? (official or AUR, pacman tracks both)
pkg_present() { pacman -Qq "$1" >/dev/null 2>&1; }

# multilib_enabled — is the [multilib] repo active in pacman.conf?
multilib_enabled() { pacman-conf --repo-list 2>/dev/null | grep -qx multilib; }
