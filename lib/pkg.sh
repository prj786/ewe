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

# install_release_pkg <pkgname> <owner/repo> <git-url> — install a first-party
# app from its latest GitHub release's prebuilt .pkg.tar.zst (built by the
# repo's release.yml in an Arch container), so the user's machine never spends
# ~10 minutes compiling a Rust/Tauri app. Version-aware: upgrades when the
# release is newer than the installed package (vercmp), no-ops when current.
# Falls back to install_git_pkgbuild (source build) whenever the release, the
# download, or the pacman -U fails. Same contract as everything else here:
# warn-and-continue, ALWAYS returns 0.
install_release_pkg() {
    local name="$1" repo="$2" giturl="$3"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        printf '%s   would run:%s install %s from latest GitHub release of %s (fallback: makepkg from source)\n' "$C_DIM" "$C_0" "$name" "$repo"
        return 0
    fi
    command -v curl >/dev/null 2>&1 || { install_git_pkgbuild "$name" "$giturl"; return 0; }

    local json tag ver url cur
    json="$(curl -fsSL --max-time 15 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)" || json=""
    tag="$(printf '%s' "$json" | grep -m1 '"tag_name"' | sed 's/.*: *"//; s/".*//')"
    ver="${tag#v}"
    # first non-debug package asset for this machine's architecture
    url="$(printf '%s' "$json" \
        | grep -o '"browser_download_url": *"[^"]*\.pkg\.tar\.zst"' \
        | sed 's/.*"\(https[^"]*\)"/\1/' \
        | grep -v -- '-debug-' | grep -m1 -e "$(uname -m)" -e '-any\.pkg')"
    if [ -z "$ver" ] || [ -z "$url" ]; then
        info "$name: no prebuilt release found — building from source"
        install_git_pkgbuild "$name" "$giturl"
        return 0
    fi

    if pkg_present "$name"; then
        cur="$(pacman -Q "$name" 2>/dev/null | awk '{print $2}')"; cur="${cur%-*}"
        if [ "$(vercmp "$cur" "$ver" 2>/dev/null || echo 1)" -ge 0 ]; then
            ok "$name $cur is current (latest release: $ver)"
            return 0
        fi
        info "updating $name $cur → $ver (prebuilt release)"
    else
        info "installing $name $ver (prebuilt release)"
    fi

    local tmp
    tmp="$(mktemp -d)" || { install_git_pkgbuild "$name" "$giturl"; return 0; }
    if curl -fL --max-time 300 -o "$tmp/$name.pkg.tar.zst" "$url" \
        && sudo_run pacman -U --noconfirm "$tmp/$name.pkg.tar.zst"; then
        ok "installed $name $ver from the GitHub release"
    else
        warn "$name: release download/install failed — falling back to a source build"
        install_git_pkgbuild "$name" "$giturl"
    fi
    rm -rf "$tmp"
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
    # Build on REAL DISK, never /tmp. Arch mounts /tmp as tmpfs at roughly half
    # of RAM, and a Rust/Tauri release build with LTO needs several GB — it
    # exhausts the tmpfs partway through linking and dies with "Disk quota
    # exceeded (os error 122)", which reads like a disk-full bug rather than a
    # RAM one. /var/tmp is on persistent storage by design (FHS: large or
    # long-lived temporary files), which is exactly this case.
    local build_root=/var/tmp
    [ -d "$build_root" ] && [ -w "$build_root" ] || build_root="${TMPDIR:-/tmp}"
    local avail_mb
    avail_mb="$(df -Pm "$build_root" 2>/dev/null | awk 'NR==2{print $4}')"
    if [ -n "$avail_mb" ] && [ "$avail_mb" -lt 6144 ]; then
        warn "$name needs ~6 GB to build; $build_root has ${avail_mb} MB — skipping"
        return 0
    fi
    tmp="$(mktemp -d -p "$build_root" "ewe-$name.XXXXXX")" \
        || { warn "no build dir — skipping $name"; return 0; }
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

# install_patched_pkgs — build + install every packages/patched/<name>/PKGBUILD:
# an OFFICIAL package carrying upstream fixes the repos haven't shipped yet
# (Arch's own PKGBUILD, pkgrel bumped to N.1, plus the upstream patches; the
# PKGBUILD header says which fixes and why). Self-retiring: a patched build is
# only made while the repos still offer exactly that pkgver — once they ship a
# newer version (the fix landed upstream) the directory is skipped, and the
# normal -Syu already replaced our N.1 with the repo's next release. Same
# contract as everything here: warn-and-continue, ALWAYS returns 0.
install_patched_pkgs() {
    local dir name ver rel repo cur tmp pkgfile
    for dir in "$DOTREPO"/packages/patched/*/; do
        [ -f "$dir/PKGBUILD" ] || continue
        name="$(basename "$dir")"
        ver="$(sed -n 's/^pkgver=//p' "$dir/PKGBUILD" | head -1)"
        rel="$(sed -n 's/^pkgrel=//p' "$dir/PKGBUILD" | head -1)"
        repo="$(pacman -Si "$name" 2>/dev/null | awk '/^Version/{print $3; exit}')"
        if [ -n "$repo" ] && [ "$(vercmp "${repo%-*}" "$ver" 2>/dev/null || echo 0)" -gt 0 ]; then
            ok "$name: repos now ship ${repo%-*} (> patched $ver) — upstream has the fix, our patched build is retired"
            continue
        fi
        cur="$(pacman -Q "$name" 2>/dev/null | awk '{print $2}')"
        if [ -n "$cur" ] && [ "$(vercmp "$cur" "$ver-$rel" 2>/dev/null || echo -1)" -ge 0 ]; then
            ok "$name $cur already carries the patches"
            continue
        fi
        if [ "${DRY_RUN:-0}" = "1" ]; then
            printf '%s   would run:%s makepkg -s in packages/patched/%s && pacman -U %s-%s-%s (patched official package)\n' "$C_DIM" "$C_0" "$name" "$name" "$ver" "$rel"
            continue
        fi
        command -v makepkg >/dev/null 2>&1 || { warn "base-devel missing — skipping patched $name"; continue; }
        tmp="$(mktemp -d -p /var/tmp "ewe-patched-$name.XXXXXX" 2>/dev/null || mktemp -d)" || { warn "no build dir — skipping patched $name"; continue; }
        cp -r "$dir"/. "$tmp/"
        info "building patched $name $ver-$rel (upstream fixes not yet in the repos — see its PKGBUILD header)"
        # makepkg refuses root and escalates itself for makedepends (-s)
        if ( cd "$tmp" && PACKAGER="ewe <ewe@localhost>" makepkg -s --noconfirm --needed ) \
            && pkgfile="$(find "$tmp" -maxdepth 1 -name "$name-$ver-$rel-*.pkg.tar.*" ! -name '*-debug-*' | head -1)" \
            && [ -n "$pkgfile" ] && sudo_run pacman -U --noconfirm "$pkgfile"; then
            ok "installed patched $name $ver-$rel"
        else
            warn "patched $name failed to build/install — the stock package stays (retry: cd packages/patched/$name && makepkg -si)"
        fi
        rm -rf "$tmp"
    done
    return 0
}

# pkg_present <pkg> — installed? (official or AUR, pacman tracks both)
pkg_present() { pacman -Qq "$1" >/dev/null 2>&1; }

# multilib_enabled — is the [multilib] repo active in pacman.conf?
multilib_enabled() { pacman-conf --repo-list 2>/dev/null | grep -qx multilib; }
