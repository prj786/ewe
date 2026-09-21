# aliases.sh — shared aliases for ewe's bash and zsh.
# POSIX-compatible on purpose: it is sourced by BOTH shells, so it sticks to
# plain `[ ]` / `command -v` and never uses `[[ ]]`, arrays, or other bashisms.
# Every alias is guarded by `command -v` so a missing tool (a bare install, a
# machine that trimmed its package set) never leaves a broken alias behind.

# ls -> eza (colourful, icons, git-aware) only when eza is installed; a plain
# `ls` stays plain otherwise (we do NOT shadow ls with --color=auto).
if command -v eza >/dev/null 2>&1; then
    alias ls='eza --group-directories-first --icons=auto'
    alias ll='eza -l --group-directories-first --icons=auto --git'
    alias la='eza -la --group-directories-first --icons=auto --git'
    alias lt='eza -l --sort=modified --icons=auto'
    alias tree='eza --tree --icons=auto'
else
    alias ll='ls -l'
    alias la='ls -la'
    alias lt='ls -lt'
fi

# navigation
alias ..='cd ..'
alias ...='cd ../..'

# fastfetch (system info) — see the configs in dotfiles/fastfetch/. Use the
# kitty-image logo inside kitty, the ASCII fallback anywhere else (kitty-direct
# and any other image protocol degrade badly without a graphics-capable terminal).
if command -v fastfetch >/dev/null 2>&1; then
    if [ "${TERM:-}" != "xterm-kitty" ] || [ -z "${KITTY_WINDOW_ID:-}" ]; then
        alias fastfetch='fastfetch --config "$HOME/.config/fastfetch/config-ascii.jsonc"'
    fi
fi
# neofetch is gone from the Arch repos — point the muscle-memory name at fastfetch.
if command -v fastfetch >/dev/null 2>&1 && ! command -v neofetch >/dev/null 2>&1; then
    alias neofetch='fastfetch'
fi
