# ewe.zsh — ewe's zsh setup, sourced by ~/.zshrc (via the marked block).
# Everything is guarded: a missing optional tool must never error or print, and
# sourcing this twice is safe.

# ── history: large, shared across sessions, deduped ─────────────────────────
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
mkdir -p "${HISTFILE:h}" 2>/dev/null
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY
setopt EXTENDED_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY              # !! expands into the line first, never runs blind

# ── behaviour ───────────────────────────────────────────────────────────────
setopt AUTO_CD                  # a directory name alone changes into it
setopt INTERACTIVE_COMMENTS     # pasted commands with # comments just work
setopt NO_BEEP
setopt NO_FLOW_CONTROL          # Ctrl-S / Ctrl-Q are free (fzf, editors)
# a "word" stops at / . - _ so Ctrl-W and Ctrl-arrows move through paths
WORDCHARS='*?[]~=&;!#$%^(){}<>'

# ── editor: emacs keymap + the usual Home/End/Delete/Ctrl-arrow bindings ────
bindkey -e
bindkey '^[[H'    beginning-of-line
bindkey '^[[F'    end-of-line
bindkey '^[[3~'   delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[3;5~' kill-word          # Ctrl-Delete
bindkey '^H'      backward-kill-word # Ctrl-Backspace
bindkey '^[[Z'    reverse-menu-complete  # Shift-Tab walks the menu backwards
# what THIS terminal says its keys send (application mode differs from the
# literal sequences above), when terminfo knows them
[[ -n "${terminfo[khome]:-}" ]] && bindkey "${terminfo[khome]}" beginning-of-line
[[ -n "${terminfo[kend]:-}"  ]] && bindkey "${terminfo[kend]}"  end-of-line
[[ -n "${terminfo[kdch1]:-}" ]] && bindkey "${terminfo[kdch1]}" delete-char

# ── completion: cached compdump, menu select, case-insensitive ──────────────
# zsh-completions (Arch) installs its functions into site-functions. Adding a
# directory that is already in $fpath is harmless, so no dedupe dance.
if [[ -d /usr/share/zsh/site-functions ]]; then
    fpath=(/usr/share/zsh/site-functions "${fpath[@]}")
fi
setopt EXTENDED_GLOB            # the (#q…) age test below needs it
autoload -Uz compinit
_zcompdir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
mkdir -p "$_zcompdir" 2>/dev/null
# the dump is rebuilt at most once a day; -C skips the security scan on the
# other starts, which is most of compinit's cost (a new terminal opens fast)
if [[ -n "$_zcompdir/zcompdump"(#qN.mh-24) ]]; then
    compinit -C -d "$_zcompdir/zcompdump"
else
    # -i: a directory compaudit calls insecure is skipped, silently. Without it
    # compinit stops every new terminal on a yes/no question.
    compinit -i -d "$_zcompdir/zcompdump"
fi
zstyle ':completion:*' menu select
# case-insensitive, then partial words (doc/rea -> Documents/README)
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:descriptions' format '%F{yellow}%d%f'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$_zcompdir/compcache"
zstyle ':completion:*:*:kill:*' menu yes select

# ── plugins (Arch official-repo paths; sourced only when present) ───────────
if [[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    # suggest from history first, then from what completion would offer;
    # fetched asynchronously so typing never waits on it
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
    ZSH_AUTOSUGGEST_USE_ASYNC=1
    ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=40
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
fi
if [[ -f /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]]; then
    source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
    bindkey '^[[A' history-substring-search-up
    bindkey '^[[B' history-substring-search-down
    [[ -n "${terminfo[kcuu1]:-}" ]] && bindkey "${terminfo[kcuu1]}" history-substring-search-up
    [[ -n "${terminfo[kcud1]:-}" ]] && bindkey "${terminfo[kcud1]}" history-substring-search-down
fi

# ── fzf: Ctrl-R history, Ctrl-T files, Alt-C cd ─────────────────────────────
if command -v fzf >/dev/null 2>&1; then
    if fzf --zsh >/dev/null 2>&1; then
        source <(fzf --zsh)
    elif [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
        source /usr/share/fzf/key-bindings.zsh
        source /usr/share/fzf/completion.zsh
    fi
fi

# ── zoxide: smarter cd ──────────────────────────────────────────────────────
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
fi

# ── shared aliases (POSIX; sourced by bash too) ─────────────────────────────
if [[ -f "$HOME/.config/ewe-shell/aliases.sh" ]]; then
    source "$HOME/.config/ewe-shell/aliases.sh"
fi

# ── prompt: oh-my-posh (flock theme), else a minimal readable fallback ──────
if command -v oh-my-posh >/dev/null 2>&1; then
    eval "$(oh-my-posh init zsh --config "$HOME/.config/oh-my-posh/flock.omp.json")"
else
    PROMPT='%F{green}%n@%m%f %F{yellow}%~%f %# '
fi

# ── syntax highlighting LAST (its docs require it) ──────────────────────────
if [[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
