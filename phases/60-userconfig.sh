#!/usr/bin/env bash
# phase 60 — per-user defaults that don't need root: default apps, EDITOR, zram.

phase_userconfig() {
    step "60 · user config"

    # default applications (writes ~/.config/mimeapps.list — no Hyprland involvement)
    #
    # SEED, never clobber: these run on every re-run of the installer, and the
    # user's own choices (browser set to Zen, a different image viewer…) must
    # survive. A default is only written when the current handler is unset or
    # points at a desktop file that no longer exists (a dead default = the link/
    # double-click opens nothing, which is worse than re-seeding).
    _desktop_ok() { [ -n "$1" ] && { [ -r "/usr/share/applications/$1" ] || [ -r "$HOME/.local/share/applications/$1" ]; }; }
    if command -v xdg-settings >/dev/null 2>&1; then
        local cur_browser
        cur_browser="$(xdg-settings get default-web-browser 2>/dev/null)"
        if _desktop_ok "$cur_browser"; then
            info "default browser: keeping your choice ($cur_browser)"
        else
            for b in helium.desktop firefox.desktop firefox-esr.desktop org.mozilla.firefox.desktop; do
                [ -r "/usr/share/applications/$b" ] && { run xdg-settings set default-web-browser "$b" && break; }
            done
        fi
    fi
    # Shipped desktop-entry overrides. Same id as the package's own entry, and
    # the user apps dir wins over /usr/share/applications, so each file here
    # replaces upstream's outright. Two live today: Zed (upstream declares only
    # text/plain; ours carries the full text/code MimeType list) and the
    # Nextcloud client (hidden — ewe-sync is the sync app; see the file).
    if [ -d "$DOTREPO/system/applications" ]; then
        run mkdir -p "$HOME/.local/share/applications"
        for _d in "$DOTREPO/system/applications/"*.desktop; do
            [ -r "$_d" ] || continue
            run cp -f "$_d" "$HOME/.local/share/applications/$(basename "$_d")"
        done
        unset _d
        run update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi

    # Default apps. _mime <desktop> <mimes…> — sets each mime's default handler.
    # WARNS (not a silent skip) when the desktop file is missing: a wrong/renamed
    # id would otherwise leave the *previous* default in place (e.g. an uninstalled
    # KDE app from an earlier install), and a dead default = double-click in the
    # file manager opens nothing. The warning surfaces the bad id in the log.
    # Seed-only, same rule as the browser above: a mime the user has explicitly
    # set (in ~/.config/mimeapps.list) to a WORKING desktop file is their choice
    # — leave it. NOT `xdg-mime query default`, which falls back to the
    # mimeinfo cache's first claimant when nothing was chosen — that fallback
    # must not count as a choice, or fresh installs would never get seeded.
    _user_default() {
        awk -F= -v m="$1" '/^\[/{s=($0=="[Default Applications]")} s && $1==m {sub(/;.*/,"",$2); print $2; exit}' \
            "$HOME/.config/mimeapps.list" 2>/dev/null
    }
    _mime() {
        local d="$1"; shift
        if [ ! -r "/usr/share/applications/$d" ] && [ ! -r "$HOME/.local/share/applications/$d" ]; then
            warn "default-apps: $d not installed — no handler set for: $*"
            return 0
        fi
        local m cur; for m in "$@"; do
            cur="$(_user_default "$m")"
            if _desktop_ok "$cur"; then continue; fi
            run xdg-mime default "$d" "$m"
        done
    }
    if command -v xdg-mime >/dev/null 2>&1; then
        _mime nemo.desktop             inode/directory
        # Zed is the default text + code editor (micro covers \$EDITOR in a TTY).
        _mime dev.zed.Zed.desktop text/plain text/markdown text/html text/css text/javascript \
              application/json application/javascript application/xml text/xml application/x-yaml \
              text/x-python text/x-csrc text/x-chdr text/x-c++src application/x-shellscript \
              text/x-rust text/x-go
        _mime imv.desktop              image/png image/jpeg image/gif image/webp image/bmp image/tiff
        _mime org.pwmt.zathura.desktop application/pdf application/epub+zip
        _mime mpv.desktop              video/mp4 video/x-matroska video/webm video/quicktime audio/mpeg audio/flac
        _mime engrampa.desktop         application/zip application/x-tar application/gzip application/x-xz \
              application/x-bzip2 application/x-7z-compressed application/x-rar application/zstd application/x-compressed-tar
        # Double-clicking a downloaded .AppImage opens Komble's install flow
        # (shared-mime-info tags type-2 AppImages as vnd.appimage, type-1 as
        # x-iso9660-appimage; x-appimage covers older tag variants).
        _mime komble.desktop           application/vnd.appimage application/x-iso9660-appimage application/x-appimage
    fi

    # GTK/GIO reads ~/.config/mimeapps.list directly — there is no KDE ksycoca cache
    # to rebuild. Just refresh the desktop-file/mimeinfo cache so "Open With" lists
    # are current (covers the Zed override we copied into the user apps dir above).
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
    local nemo_stamp="${XDG_STATE_HOME:-$HOME/.local/state}/ewe/nemo-chrome.seeded"
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

    # Nemo "Open in Terminal": Nemo spawns whatever
    # org.cinnamon.desktop.default-applications.terminal says, and Cinnamon's
    # shipped default is gnome-terminal — which ewe does not install. The menu
    # item was therefore present and silently did nothing. Point it at kitty,
    # the terminal ewe actually ships (phase 20 / postcheck both assert it).
    # exec-arg is what Nemo puts before a command when it runs one there.
    # NOT stamped: this is ours to keep correct, and re-asserting a key the
    # user has no UI to change costs nothing.
    if command -v gsettings >/dev/null 2>&1 && command -v nemo >/dev/null 2>&1; then
        if run gsettings set org.cinnamon.desktop.default-applications.terminal exec kitty 2>/dev/null; then
            run gsettings set org.cinnamon.desktop.default-applications.terminal exec-arg "-e" 2>/dev/null || true
            ok "nemo: Open in Terminal now opens kitty (was gnome-terminal, which is not installed)"
        fi
    fi

    # RFC-006: the Nextcloud DESKTOP CLIENT is not part of ewe. We depend on
    # the package only for `nextcloudcmd`, the headless engine ewe-sync drives,
    # so the package cannot simply be dropped — nextcloudcmd goes with it.
    #
    # Hiding the launcher entry (system/applications/) was not enough: the
    # package also ships a D-Bus activation file, so ANY caller that pokes
    # com.nextcloudgmbh.Nextcloud makes systemd start `/usr/bin/nextcloud
    # --background` — a second tray icon, account wizard and sync engine,
    # competing with ewe-sync over the same folders. A user-level activation
    # file wins over /usr/share, so point it at true; and mask the user unit
    # so nothing can enable it later either.
    if [ -e /usr/share/dbus-1/services/com.nextcloudgmbh.Nextcloud.service ]; then
        run mkdir -p "$HOME/.local/share/dbus-1/services"
        run sh -c "printf '%s\n' \
'[D-BUS Service]' \
'# ewe: neutralises nextcloud-client D-Bus activation. The package stays for' \
'# nextcloudcmd (the engine ewe-sync drives); its GUI is not part of ewe.' \
'Name=com.nextcloudgmbh.Nextcloud' \
'Exec=/bin/true' \
> '$HOME/.local/share/dbus-1/services/com.nextcloudgmbh.Nextcloud.service'"
        run systemctl --user mask com.nextcloud.desktopclient.nextcloud.service 2>/dev/null || true
        ok "nextcloud desktop client neutralised (nextcloudcmd kept for ewe-sync)"
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
        local tbroot="${XDG_STATE_HOME:-$HOME/.local/state}/ewe"
        local tb="$tbroot/theme-backup.$RUN_STAMP"
        if compgen -G "$tbroot/theme-backup.*" >/dev/null 2>&1; then
            info "pre-ewe theme snapshot already exists under $tbroot — keeping it."
        elif [ "${DRY_RUN:-0}" = "1" ]; then
            info "would back up current GTK/gsettings theme to $tb/ (with restore.sh)"
        else
            mkdir -p "$tb"
            [ -r "$HOME/.config/gtk-3.0/settings.ini" ] && cp -f "$HOME/.config/gtk-3.0/settings.ini" "$tb/gtk-3.0-settings.ini"
            [ -r "$HOME/.config/gtk-4.0/settings.ini" ] && cp -f "$HOME/.config/gtk-4.0/settings.ini" "$tb/gtk-4.0-settings.ini"
            {
                printf '#!/usr/bin/env bash\n# Restore the GTK/gsettings theme that was active before ewe (coexist mode).\nset -u\n'
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
                printf 'echo "Restored the pre-ewe GTK theme."\n'
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
        if ! grep -q 'hypr-shell: default editor\|ewe: default editor' "$rc" 2>/dev/null; then
            run sh -c "printf '\n# ewe: default editor (terminal — a GUI editor cannot serve a TTY)\nexport EDITOR=micro VISUAL=micro\n' >> '$rc'"
        fi
    fi

    # ── Node toolchain via mise (no system nodejs) ──
    # mise owns Node here. Provision Node LTS + pnpm + the front-end language
    # servers/formatter declared in dotfiles/mise/config.toml, and wire mise into
    # the shells. The shims dir is also added to PATH by start-hyprland.sh so
    # GUI-launched apps (Zed, kitty tools) find them without an interactive shell.
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
                run sh -c "printf '\n# ewe: mise (node toolchain)\neval \"\$(mise activate %s)\"\n' '$sh_name' >> '$rcf'"
        done
    else
        warn "mise not installed — Node toolchain not provisioned (install mise, then 'mise install')."
    fi

    # ── prompt: oh-my-posh, themed to match the shell ────────────────────────
    # One look (flock), one theme file. Written once and guarded by a grep so
    # re-running the installer never duplicates it. (graphite.omp.json remains
    # on disk only so snippets written by older installs keep resolving.)
    if command -v oh-my-posh >/dev/null 2>&1; then
        local rcf sh_name
        for rcf in "$HOME/.bashrc" "$HOME/.zshrc"; do
            [ -e "$rcf" ] || continue
            grep -q 'oh-my-posh init' "$rcf" 2>/dev/null && continue
            sh_name="$(basename "$rcf" | sed 's/^\.//; s/rc$//')"
            info "adding the oh-my-posh prompt to $(basename "$rcf")"
            if [ "${DRY_RUN:-0}" != "1" ]; then
                cat >> "$rcf" <<RC

# ewe: oh-my-posh prompt (flock theme)
if command -v oh-my-posh >/dev/null 2>&1; then
    eval "\$(oh-my-posh init $sh_name --config "\$HOME/.config/oh-my-posh/flock.omp.json")"
fi
RC
            fi
        done
    else
        warn "oh-my-posh not installed — prompt left as-is (install it, then re-run)."
    fi

    # RFC-001 [system]: record what this run made the machine into. Only ever
    # raises flags — the file is the memory, not the off switch.
    if [ -x "${EWE_CONF_BIN:-}" ] && [ "${DRY_RUN:-0}" != "1" ]; then
        [ "${GAMING:-0}" = "1" ] && run "$EWE_CONF_BIN" set --no-hooks system.gaming true
        [ "${DEV:-0}" = "1" ]    && run "$EWE_CONF_BIN" set --no-hooks system.development true
        ok "profiles recorded in $("$EWE_CONF_BIN" path)"
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
