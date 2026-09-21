#!/usr/bin/env bash
# ewe-shell — the shell kitty launches (see `shell` in kitty.conf).
#
# The terminal's interactive shell is zsh (with ewe's zsh config); the LOGIN
# shell stays bash — nothing here runs `chsh`, and scripts that assume bash keep
# working. A missing zsh must never leave kitty unable to open, so we fall back
# to "$SHELL", and an explicit opt-out is honoured: either ~/.config/ewe/shell
# containing `bash`, or EWE_SHELL=bash in the environment.
set -u

_optout="$(cat "$HOME/.config/ewe/shell" 2>/dev/null || true)"
if [ "${EWE_SHELL:-}" = "bash" ] || [ "$_optout" = "bash" ]; then
    exec "${SHELL:-/bin/bash}"
fi

if command -v zsh >/dev/null 2>&1; then
    # zsh with no ~/.zshrc opens its "new user" questionnaire instead of a
    # prompt. The rc wiring normally exists already (install.sh phase 60, or
    # ewe-setup at login); if this terminal got here first — or the file was
    # deleted — wire it now. Idempotent, a few milliseconds, never fatal.
    if ! grep -q '^# >>> ewe shell >>>$' "$HOME/.zshrc" 2>/dev/null \
            && [ -x "$HOME/.config/ewe-shell/shell-setup.sh" ]; then
        "$HOME/.config/ewe-shell/shell-setup.sh" >/dev/null 2>&1 || true
    fi
    # still nothing to read? stay on the login shell rather than show a wizard
    [ -s "$HOME/.zshrc" ] && exec zsh
fi

exec "${SHELL:-/bin/bash}"
