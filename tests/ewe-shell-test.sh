#!/usr/bin/env bash
# ewe-shell kit tests — sandboxed HOME, no network. Covers: shell-setup.sh
# idempotency + migration (one marked block per rc file, the old phase-60
# oh-my-posh block migrated away, the mise block kept, user lines kept, one
# backup), `bash -n` on every new bash/sh script, and a clean (silent) source
# of ewe.bash with none of the optional tools on PATH. zsh checks SKIP (not
# fail) when zsh is not installed.
set -euo pipefail
cd "$(dirname "$0")/.."
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
export HOME="$SB/home"
mkdir -p "$HOME/.config" "$SB/empty"
ln -s "$(pwd)/dotfiles/shell" "$HOME/.config/ewe-shell"
# bash's own path, resolved before we strip PATH for the silent-source test
BASH_BIN="$(command -v bash)"

pass=0; failn=0
check() { if eval "$2"; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1"; fi; }

# ── syntax: bash -n on every new bash/sh script ─────────────────────────────
for f in dotfiles/shell/shell-setup.sh dotfiles/shell/ewe.bash \
         dotfiles/shell/aliases.sh dotfiles/kitty/ewe-shell.sh; do
    check "bash -n $f" "bash -n '$f'"
done
# ewe.zsh is zsh, not bash — only syntax-check it when zsh is present.
if command -v zsh >/dev/null 2>&1; then
    check "zsh -n dotfiles/shell/ewe.zsh" "zsh -n 'dotfiles/shell/ewe.zsh'"
else
    echo "SKIP: zsh not installed — dotfiles/shell/ewe.zsh not syntax-checked"
fi

# ── shell-setup: migrate + idempotent, run twice ────────────────────────────
cat > "$HOME/.bashrc" <<'EOF'
# my custom user line
export MY_MARKER=keepme

# ewe: mise (node toolchain)
eval "$(mise activate bash)"

# ewe: oh-my-posh prompt (flock theme)
if command -v oh-my-posh >/dev/null 2>&1; then
    eval "$(oh-my-posh init bash --config "$HOME/.config/oh-my-posh/flock.omp.json")"
fi
EOF
cp "$HOME/.bashrc" "$SB/orig.bashrc"

bash dotfiles/shell/shell-setup.sh
bash dotfiles/shell/shell-setup.sh

n_bash="$(grep -c '^# >>> ewe shell >>>$' "$HOME/.bashrc" || true)"
n_zsh="$(grep -c '^# >>> ewe shell >>>$' "$HOME/.zshrc" || true)"
check "one marked block in .bashrc" "[ '$n_bash' = 1 ]"
check "one marked block in .zshrc" "[ '$n_zsh' = 1 ]"
check "old oh-my-posh block migrated away" "! grep -q 'oh-my-posh prompt (flock theme)' '$HOME/.bashrc' && ! grep -q 'oh-my-posh init' '$HOME/.bashrc'"
check "mise block preserved" "grep -q '# ewe: mise (node toolchain)' '$HOME/.bashrc' && grep -q 'mise activate' '$HOME/.bashrc'"
check "user line preserved" "grep -q 'MY_MARKER=keepme' '$HOME/.bashrc'"
check "backup created once with the original content" "[ -e '$HOME/.bashrc.bak.ewe' ] && cmp -s '$HOME/.bashrc.bak.ewe' '$SB/orig.bashrc'"
check "zsh block sources ewe.zsh" "grep -q 'ewe.zsh' '$HOME/.zshrc'"

# ── ewe.bash sources silently with no optional tools on PATH ────────────────
err="$(PATH="$SB/empty" "$BASH_BIN" --norc -c '. "$HOME/.config/ewe-shell/ewe.bash"' 2>&1 1>/dev/null)"
check "sourcing ewe.bash with no optional tools prints nothing to stderr" "[ -z \"\$err\" ]"

# ── the kitty wrapper (dotfiles/kitty/ewe-shell.sh) ──────────────────────────
# A fake zsh on PATH records that it was exec'd; the real one is not needed.
WH="$SB/wrap-home"; mkdir -p "$WH/.config" "$SB/fakebin"
ln -s "$PWD/dotfiles/shell" "$WH/.config/ewe-shell"
printf '#!/bin/sh\necho "FAKE-ZSH"\n' > "$SB/fakebin/zsh"; chmod +x "$SB/fakebin/zsh"
out="$(HOME="$WH" PATH="$SB/fakebin:$PATH" SHELL=/bin/true EWE_SHELL= bash dotfiles/kitty/ewe-shell.sh 2>&1)"
check "wrapper starts zsh when it exists" "[ '$out' = 'FAKE-ZSH' ]"
check "wrapper wired a missing ~/.zshrc first (no new-user wizard)" "grep -q '^# >>> ewe shell >>>\$' '$WH/.zshrc'"
out="$(HOME="$WH" PATH="$SB/fakebin:$PATH" SHELL="$SB/fakebin/zsh" EWE_SHELL=bash bash dotfiles/kitty/ewe-shell.sh 2>&1)"
mkdir -p "$WH/.config/ewe"; echo bash > "$WH/.config/ewe/shell"
printf '#!/bin/sh\necho "LOGIN-SHELL"\n' > "$SB/fakebin/login"; chmod +x "$SB/fakebin/login"
out="$(HOME="$WH" PATH="$SB/fakebin:$PATH" SHELL="$SB/fakebin/login" bash dotfiles/kitty/ewe-shell.sh 2>&1)"
check "opt-out file keeps the login shell" "[ '$out' = 'LOGIN-SHELL' ]"
nozsh="$SB/nozsh-bin"; mkdir -p "$nozsh"; for t in bash cat grep sh; do ln -s "$(command -v $t)" "$nozsh/$t"; done
rm -f "$WH/.config/ewe/shell"
out="$(HOME="$WH" PATH="$nozsh" SHELL="$SB/fakebin/login" bash dotfiles/kitty/ewe-shell.sh 2>&1)"
check "no zsh installed: falls back to the login shell" "[ '$out' = 'LOGIN-SHELL' ]"

echo "ewe-shell: $pass passed, $failn failed"
[ "$failn" = 0 ]
