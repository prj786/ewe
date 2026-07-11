#!/usr/bin/env bash
# phase 60 — per-user defaults that don't need root: default apps, EDITOR, zram.

phase_userconfig() {
    step "60 · user config"

    # default applications (writes ~/.config/mimeapps.list — no Hyprland involvement)
    if command -v xdg-settings >/dev/null 2>&1; then
        for b in firefox.desktop firefox-esr.desktop org.mozilla.firefox.desktop; do
            [ -r "/usr/share/applications/$b" ] && { run xdg-settings set default-web-browser "$b" && break; }
        done
    fi
    # Install our Fresh launcher (runs `fresh` inside kitty) so it can be the GUI
    # default text/code editor. Shipped in the repo; copied to the user apps dir.
    if [ -r "$DOTREPO/system/applications/fresh.desktop" ]; then
        run mkdir -p "$HOME/.local/share/applications"
        run cp -f "$DOTREPO/system/applications/fresh.desktop" "$HOME/.local/share/applications/fresh.desktop"
        run update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi

    # Default apps. _mime <desktop> <mimes…> — sets each mime's default handler.
    # WARNS (not a silent skip) when the desktop file is missing: a wrong/renamed
    # id would otherwise leave the *previous* default in place (e.g. an uninstalled
    # KDE app from an earlier install), and a dead default = double-click in the
    # file manager opens nothing. The warning surfaces the bad id in the log.
    _mime() {
        local d="$1"; shift
        if [ ! -r "/usr/share/applications/$d" ] && [ ! -r "$HOME/.local/share/applications/$d" ]; then
            warn "default-apps: $d not installed — no handler set for: $*"
            return 0
        fi
        local m; for m in "$@"; do run xdg-mime default "$d" "$m"; done
    }
    if command -v xdg-mime >/dev/null 2>&1; then
        _mime nemo.desktop             inode/directory
        # Fresh IDE is the default text + code editor (terminal IDE; no GUI editor ships).
        _mime fresh.desktop text/plain text/markdown text/html text/css text/javascript \
              application/json application/javascript application/xml text/xml application/x-yaml \
              text/x-python text/x-csrc text/x-chdr text/x-c++src application/x-shellscript \
              text/x-rust text/x-go
        _mime imv.desktop              image/png image/jpeg image/gif image/webp image/bmp image/tiff
        _mime org.pwmt.zathura.desktop application/pdf application/epub+zip
        _mime mpv.desktop              video/mp4 video/x-matroska video/webm video/quicktime audio/mpeg audio/flac
        _mime engrampa.desktop         application/zip application/x-tar application/gzip application/x-xz \
              application/x-bzip2 application/x-7z-compressed application/x-rar application/zstd application/x-compressed-tar
    fi

    # GTK/GIO reads ~/.config/mimeapps.list directly — there is no KDE ksycoca cache
    # to rebuild. Just refresh the desktop-file/mimeinfo cache so "Open With" lists
    # are current (covers Fresh, which we copied into the user apps dir above).
    if command -v update-desktop-database >/dev/null 2>&1; then
        run update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi

    # Verify: print what the common types now resolve to. If any row shows a dead
    # handler (e.g. a leftover org.kde.*.desktop that's no longer installed),
    # double-click won't open it — and this surfaces it instead of failing silently.
    if command -v xdg-mime >/dev/null 2>&1 && [ "${DRY_RUN:-0}" != "1" ]; then
        info "default handlers (double-click targets):"
        for t in inode/directory text/plain image/png image/jpeg application/pdf video/mp4 application/zip; do
            printf '    %-20s → %s\n' "$t" "$(xdg-mime query default "$t" 2>/dev/null || echo '(none)')"
        done
    fi

    # Nemo right-click actions: "Compress…" / "Extract Here" via engrampa. Shipped
    # in the repo, copied to the user's Nemo actions dir (Nemo loads *.nemo_action).
    if [ -d "$DOTREPO/system/nemo-actions" ]; then
        run mkdir -p "$HOME/.local/share/nemo/actions"
        run sh -c "cp -f '$DOTREPO/system/nemo-actions/'*.nemo_action '$HOME/.local/share/nemo/actions/' 2>/dev/null || true"
    fi

    # Nemo: bare window — no sidebar, menubar, toolbar, or status bar; just the
    # folder contents (the window is already titlebar-less under Hyprland).
    # Seeded ONCE (stamp): these are the very keys Nemo rewrites when the user
    # toggles the UI back on (F9 = sidebar, Alt = menubar), so re-applying every
    # run would keep reverting the user's own choice. gsettings needs a session
    # DBus — best-effort here; autostart.sh runs the identical seed at login to
    # cover an install done from a bare TTY.
    local nemo_stamp="${XDG_STATE_HOME:-$HOME/.local/state}/hypr-shell/nemo-chrome.seeded"
    if command -v gsettings >/dev/null 2>&1 && command -v nemo >/dev/null 2>&1 && [ ! -e "$nemo_stamp" ]; then
        if run gsettings set org.nemo.window-state start-with-sidebar false 2>/dev/null; then
            run gsettings set org.nemo.window-state start-with-menu-bar false 2>/dev/null || true
            run gsettings set org.nemo.window-state start-with-toolbar false 2>/dev/null || true
            run gsettings set org.nemo.window-state start-with-status-bar false 2>/dev/null || true
            if [ "${DRY_RUN:-0}" != "1" ]; then mkdir -p "${nemo_stamp%/*}"; touch "$nemo_stamp"; fi
            ok "nemo set to bare-window mode (pure folder view; F9 brings the sidebar back)"
        else
            info "gsettings has no session bus here — nemo bare-window seed will run at first login instead."
        fi
    fi

    # (Reversal icon theme + Mocu cursor are installed system-wide in phase 20.)

    # default app appearance: dark across GTK + Qt + KDE, tinted with the default
    # accent. Writes the toolkit config files now (gsettings is best-effort from a
    # TTY; Quickshell re-applies it live at first login, then honours user-theme.json).
    # Coexist: colorscheme.sh writes GLOBAL GTK/gsettings theming (and the shell
    # re-applies it at every startup), so your OTHER session (e.g. Sway) picks up
    # the DE's dark + accent look too. Snapshot the current theme first so a single
    # `theme-backup.<stamp>/restore.sh` reverts it. (Run install.sh as your normal
    # user — under sudo, gsettings would read root's empty theme, not yours.)
    # The snapshot lives in the XDG state dir — NOT under ~/.config/hypr, which is
    # a symlink into the git checkout (link_tree), where it would dirty the repo.
    # Only the FIRST run snapshots: a re-run would capture the already-recoloured
    # theme — restoring that is exactly what this backup exists to undo.
    if [ "${COEXIST:-0}" = "1" ]; then
        local tbroot="${XDG_STATE_HOME:-$HOME/.local/state}/hypr-shell"
        local tb="$tbroot/theme-backup.$RUN_STAMP"
        if compgen -G "$tbroot/theme-backup.*" >/dev/null 2>&1; then
            info "pre-hypr-shell theme snapshot already exists under $tbroot — keeping it."
        elif [ "${DRY_RUN:-0}" = "1" ]; then
            info "would back up current GTK/gsettings theme to $tb/ (with restore.sh)"
        else
            mkdir -p "$tb"
            [ -r "$HOME/.config/gtk-3.0/settings.ini" ] && cp -f "$HOME/.config/gtk-3.0/settings.ini" "$tb/gtk-3.0-settings.ini"
            [ -r "$HOME/.config/gtk-4.0/settings.ini" ] && cp -f "$HOME/.config/gtk-4.0/settings.ini" "$tb/gtk-4.0-settings.ini"
            {
                printf '#!/usr/bin/env bash\n# Restore the GTK/gsettings theme that was active before hypr-shell (coexist mode).\nset -u\n'
                if command -v gsettings >/dev/null 2>&1; then
                    local k v
                    for k in gtk-theme icon-theme cursor-theme color-scheme font-name; do
                        v="$(gsettings get org.gnome.desktop.interface "$k" 2>/dev/null)"
                        [ -n "$v" ] && printf 'gsettings set org.gnome.desktop.interface %s %s\n' "$k" "$v"
                    done
                fi
                # $(dirname)-relative so the snapshot keeps working if the dir moves
                [ -f "$tb/gtk-3.0-settings.ini" ] && printf 'cp -f "$(dirname "$0")/gtk-3.0-settings.ini" "$HOME/.config/gtk-3.0/settings.ini"\n'
                [ -f "$tb/gtk-4.0-settings.ini" ] && printf 'cp -f "$(dirname "$0")/gtk-4.0-settings.ini" "$HOME/.config/gtk-4.0/settings.ini"\n'
                printf 'echo "Restored the pre-hypr-shell GTK theme."\n'
            } > "$tb/restore.sh"
            chmod +x "$tb/restore.sh"
            ok "backed up current GTK theme -> $tb/restore.sh"
        fi
    fi

    local cs="$HOME/.config/quickshell/scripts/colorscheme.sh"
    if [ -r "$cs" ]; then
        run sh "$cs" dark 0a84ff && ok "default appearance set to dark (GTK + Qt fallback)"
    else
        info "colorscheme.sh not found yet (dotfiles not linked?) — skipping appearance default."
    fi

    # EDITOR/VISUAL for the user shell (idempotent: only append once)
    local rc="$HOME/.profile"
    if [ -w "$rc" ] || [ ! -e "$rc" ]; then
        if ! grep -q 'hypr-shell: default editor' "$rc" 2>/dev/null; then
            run sh -c "printf '\n# hypr-shell: default editor\nexport EDITOR=fresh VISUAL=fresh\n' >> '$rc'"
        fi
    fi

    # ── Node toolchain via mise (no system nodejs) ──
    # mise owns Node here. Provision Node LTS + pnpm + the front-end language
    # servers/formatter declared in dotfiles/mise/config.toml, and wire mise into
    # the shells. The shims dir is also added to PATH by start-hyprland.sh so
    # GUI-launched Fresh finds the servers without an interactive shell.
    if [ "${DEV:-0}" != "1" ]; then
        info "dev toolchain: skipped (opt-in) — re-run with --dev to provision the Node/LSP stack via mise."
    elif command -v mise >/dev/null 2>&1; then
        run mise trust "$HOME/.config/mise/config.toml" 2>/dev/null || true
        if [ "${DRY_RUN:-0}" = "1" ]; then
            info "would run 'mise install' (node LTS, pnpm, TS/CSS/HTML/JSON/Tailwind/Vue/Svelte servers, prettier)"
        else
            info "provisioning Node toolchain via mise (this builds/downloads node + npm tools)…"
            run mise install || warn "mise install reported errors — run 'mise install' again after login."
        fi
        # activate mise in interactive shells (shims also live on PATH via the session wrapper)
        for rcf in "$HOME/.bashrc" "$HOME/.zshrc"; do
            [ -e "$rcf" ] || continue
            local sh_name; sh_name="$(basename "$rcf" | sed 's/^\.//; s/rc$//')"   # bashrc→bash, zshrc→zsh
            grep -q 'mise activate' "$rcf" 2>/dev/null || \
                run sh -c "printf '\n# hypr-shell: mise (node toolchain)\neval \"\$(mise activate %s)\"\n' '$sh_name' >> '$rcf'"
        done
    else
        warn "mise not installed — Node toolchain not provisioned (install mise, then 'mise install')."
    fi

    # zram (laptop benefit). Ship a sane generator config if none exists.
    if [ "$CHASSIS" = "laptop" ] && [ ! -e /etc/systemd/zram-generator.conf ]; then
        info "writing /etc/systemd/zram-generator.conf (zstd, capped at 8G)"
        if [ "${DRY_RUN:-0}" != "1" ]; then
            printf '[zram0]\nzram-size = min(ram, 8192)\ncompression-algorithm = zstd\n' \
                | sudo_run tee /etc/systemd/zram-generator.conf >/dev/null && ok "zram configured"
        fi
    fi

    ok "user config done"
}
