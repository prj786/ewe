#!/usr/bin/env bash
# uninstall.sh — unlink the dotfiles and restore the most recent backup.
# Does NOT remove packages (leaving them is safer than guessing). Pass --purge
# to also disable the services this installer enabled.
set -u
DOTREPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; export DOTREPO
. "$DOTREPO/lib/log.sh"

DRY_RUN=0; PURGE=0
for a in "$@"; do case "$a" in --dry-run) DRY_RUN=1;; --purge) PURGE=1;; esac; done
export DRY_RUN

# restore <dest> — if it's our symlink, remove it and restore the newest .bak.
restore() {
    local dest="$1"
    if [ -L "$dest" ] && readlink -f "$dest" | grep -q "$DOTREPO/dotfiles"; then
        run rm -f "$dest"; ok "unlinked $dest"
        local bak; bak="$(ls -dt "$dest".bak.* 2>/dev/null | head -1)"
        if [ -n "$bak" ]; then run mv "$bak" "$dest"; ok "restored $dest from $(basename "$bak")"; fi
    else
        info "not a hyprdots symlink, leaving as-is: $dest"
    fi
}

step "uninstall"
restore "$HOME/.config/hypr"
restore "$HOME/.config/quickshell"
restore "$HOME/.config/fresh"
restore "$HOME/.config/kitty"
restore "$HOME/.config/oh-my-posh"
restore "$HOME/.config/mise"

# the Fresh launcher we copied into the user apps dir
if [ -e "$HOME/.local/share/applications/fresh.desktop" ]; then
    run rm -f "$HOME/.local/share/applications/fresh.desktop"; ok "removed fresh.desktop"
fi

if [ -e "$HOME/.config/systemd/user/hyprland-session.target" ]; then
    run rm -f "$HOME/.config/systemd/user/hyprland-session.target"
    run systemctl --user daemon-reload 2>/dev/null || true
    ok "removed hyprland-session.target"
fi

if [ -e /usr/local/share/wayland-sessions/hyprland-de.desktop ]; then
    sudo_run rm -f /usr/local/share/wayland-sessions/hyprland-de.desktop && ok "removed session entry"
fi

if [ "$PURGE" = "1" ]; then
    for u in greetd.service sddm.service; do
        systemctl is-enabled "$u" >/dev/null 2>&1 && sudo_run systemctl disable "$u"
    done
    warn "purge: display manager disabled — re-enable one before next boot or you'll land on a TTY."
fi

ok "uninstall done (packages left installed; use your package manager to remove them)"
