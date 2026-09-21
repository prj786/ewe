#!/usr/bin/env bash
# dotfiles/shell/shell-setup.sh — wire ewe's shell config into ~/.bashrc and
# ~/.zshrc, and migrate the old inline blocks that phase 60 used to write.
#
# Runs from BOTH install paths:
#   - phases/60-userconfig.sh (the install.sh path) calls it through run();
#   - packaging/ewe-setup (the pacman package path) calls it on every sync.
#
# Idempotent and conservative. For each of ~/.bashrc and ~/.zshrc it:
#   1. creates the file only if it is missing;
#   2. backs it up ONCE to <file>.bak.ewe before the first edit (a file we just
#      created has nothing of the user's to preserve, so no backup);
#   3. removes the old phase-60 oh-my-posh block (the shared config now owns the
#      prompt — never initialise it twice) while KEEPING the `# ewe: mise` block;
#   4. appends ONE marked block that sources the shared file, and a `# ewe: mise`
#      block when mise is installed (both guarded against duplication).
#
# It never touches anything else in the user's rc files; user overrides go AFTER
# the closing marker.
set -u

# The shared config dir is linked to ~/.config/ewe-shell by lib/deploy.sh, so
# the path below is the same on every install path.
setup_rc() {
    local rc="$1" shell="$2"
    local pre_existing=0
    [ -e "$rc" ] && pre_existing=1

    # 1. create if missing
    if [ ! -e "$rc" ]; then
        printf '# %s: user shell configuration (ewe adds a marked block below).\n' "$shell" > "$rc"
    fi

    # 2. back up ONCE, before the first edit (captures the user's original file)
    if [ "$pre_existing" = 1 ] && [ ! -e "$rc.bak.ewe" ]; then
        cp -f "$rc" "$rc.bak.ewe"
    fi

    # 3. migrate: drop the old phase-60 oh-my-posh block (marker .. its fi).
    #    The mise block is left alone (it is guarded and still correct).
    if grep -q '^# ewe: oh-my-posh prompt (flock theme)$' "$rc"; then
        local tmp
        tmp="$(mktemp "${TMPDIR:-/tmp}/ewe-shell.XXXXXX")"
        awk '
            /^# ewe: oh-my-posh prompt \(flock theme\)$/ { in_omp=1; next }
            in_omp { if ($0 ~ /^fi$/) in_omp=0; next }
            { print }
        ' "$rc" > "$tmp"
        cp -f "$tmp" "$rc"
        rm -f "$tmp"
    fi

    # 4. append the marked block (once)
    if ! grep -q '^# >>> ewe shell >>>$' "$rc"; then
        {
            printf '\n# >>> ewe shell >>>\n'
            printf '# Managed by ewe — put your own overrides AFTER the closing marker.\n'
            printf 'if [ -f "$HOME/.config/ewe-shell/ewe.%s" ]; then\n' "$shell"
            printf '    . "$HOME/.config/ewe-shell/ewe.%s"\n' "$shell"
            printf 'fi\n'
            printf '# <<< ewe shell <<<\n'
        } >> "$rc"
    fi

    # 5. mise block when mise is installed (once). Uses the old marker text so
    #    the migration above and any older install stay compatible; the broader
    #    `mise activate` check avoids double-activation from a non-ewe source.
    if command -v mise >/dev/null 2>&1 && ! grep -q 'mise activate' "$rc"; then
        {
            printf '\n# ewe: mise (node toolchain)\n'
            printf 'eval "$(mise activate %s)"\n' "$shell"
        } >> "$rc"
    fi
}

setup_rc "$HOME/.bashrc" bash
setup_rc "$HOME/.zshrc" zsh
