#!/usr/bin/env bash
# Zsh: Oh My Zsh + plugins FIRST, then clone the zshrc repo into ~/.zsh and
# point ~/.zshrc at it. Order matters — plugins must exist before the config
# that loads them, and oh-my-zsh must be installed before the clone.
# Repo: https://github.com/Spuppateddu/zshrc  (kept light; lives in ~/.zsh)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Zsh"

ZSH_DIR="$HOME/.oh-my-zsh"
ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH_DIR/custom}"
ZDOTREPO="$HOME/.zsh"

apt_ensure zsh git curl

# ── 1. Oh My Zsh (unattended) ────────────────────────────────────────────────
if [[ -d "$ZSH_DIR" ]]; then
    skip "Oh My Zsh already installed."
else
    step "Installing Oh My Zsh (unattended)"
    # RUNZSH/CHSH=no: don't switch shell or drop into zsh mid-install.
    run bash -c 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
    ok "Oh My Zsh installed."
fi

# ── 2. Plugins (external ones the config expects) ────────────────────────────
declare -A PLUGINS=(
    [zsh-autosuggestions]=https://github.com/zsh-users/zsh-autosuggestions
    [zsh-syntax-highlighting]=https://github.com/zsh-users/zsh-syntax-highlighting
    [zsh-history-substring-search]=https://github.com/zsh-users/zsh-history-substring-search
)
for name in "${!PLUGINS[@]}"; do
    clone_or_pull "${PLUGINS[$name]}" "$ZSH_CUSTOM/plugins/$name"
done

# ── 3. The config repo itself (kept light in its own repo) ───────────────────
clone_or_pull https://github.com/Spuppateddu/zshrc.git "$ZDOTREPO"
ensure_source_line "source ~/.zsh/zshrc" "$HOME/.zshrc"

# ── 4. Make zsh the login shell ──────────────────────────────────────────────
zsh_path="$(command -v zsh || true)"
if [[ -n "$zsh_path" && "${SHELL:-}" != "$zsh_path" ]]; then
    step "Setting zsh as the default shell"
    run chsh -s "$zsh_path" || warn "chsh failed — run: chsh -s $zsh_path"
else
    skip "zsh already the default shell."
fi

# Reload: the parent shell can't be sourced from this subprocess, so guide it.
warn "Reload zsh to apply the pulled config: run 'exec zsh' or open a new terminal."
ok "Zsh ready."
