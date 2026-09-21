# ewe.bash — ewe's bash setup, sourced by ~/.bashrc (via the marked block).
# Everything is guarded: a missing optional tool must never error or print, and
# sourcing this twice is safe.

# ── history: larger, deduped, appended across sessions ──────────────────────
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth
shopt -s histappend 2>/dev/null
shopt -s cmdhist 2>/dev/null

# ── bash-completion ─────────────────────────────────────────────────────────
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
fi

# ── fzf: Ctrl-R history, Ctrl-T files, Alt-C cd ─────────────────────────────
if command -v fzf >/dev/null 2>&1 && [ -f /usr/share/fzf/key-bindings.bash ]; then
    . /usr/share/fzf/key-bindings.bash
    if [ -f /usr/share/fzf/completion.bash ]; then
        . /usr/share/fzf/completion.bash
    fi
fi

# ── zoxide: smarter cd ──────────────────────────────────────────────────────
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init bash)"
fi

# ── shared aliases (POSIX; sourced by zsh too) ──────────────────────────────
if [ -f "$HOME/.config/ewe-shell/aliases.sh" ]; then
    . "$HOME/.config/ewe-shell/aliases.sh"
fi

# ── prompt: oh-my-posh (flock theme) ────────────────────────────────────────
if command -v oh-my-posh >/dev/null 2>&1; then
    eval "$(oh-my-posh init bash --config "$HOME/.config/oh-my-posh/flock.omp.json")"
fi
