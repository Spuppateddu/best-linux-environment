#!/usr/bin/env bash
# Vim: deps, then clone the vimrc repo into ~/.vim, point ~/.vimrc at it, and
# install plugins headlessly. Repo: https://github.com/Spuppateddu/vimrc
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Vim"

apt_ensure vim git nodejs npm ripgrep silversearcher-ag

# yarn (global) — a few plugins build with it.
if has_cmd yarn; then
    skip "yarn already installed."
else
    step "Installing yarn (global, via npm)"
    run sudo npm install -g yarn
    ok "yarn installed."
fi

# vim-plug is bundled in the repo (autoload/plug.vim), so a clone is enough.
clone_or_pull https://github.com/Spuppateddu/vimrc.git "$HOME/.vim"
ensure_source_line "runtime vimrc" "$HOME/.vimrc"

# Install plugins headlessly (skip under dry-run / no TTY concerns — vim -es).
if [[ "$DRY_RUN" == true ]]; then
    printf '%s  would run:%s vim +PlugInstall +qall (headless)\n' "$C_DIM" "$C_OFF"
else
    step "Installing vim plugins (headless — first run takes a minute)"
    vim -es -u "$HOME/.vimrc" +'PlugInstall --sync' +qall >/dev/null 2>&1 \
        || warn "Headless PlugInstall reported issues — open vim and run :PlugInstall."
    ok "vim plugins installed."
fi

# Reload: nothing to live-reload — vim reads the pulled config on next launch
# (plugins were just synced above). Inside a running vim: ':source $MYVIMRC'.
skip "Vim loads the pulled config on next launch."
ok "Vim ready. Copilot: open vim → ':Copilot setup'."
