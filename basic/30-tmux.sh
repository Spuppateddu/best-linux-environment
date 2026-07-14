#!/usr/bin/env bash
# Tmux: deps + TPM, clone the tmuxrc repo into ~/.tmuxrc, point ~/.tmux.conf at
# it. Repo: https://github.com/Spuppateddu/tmuxrc
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Tmux"

apt_ensure tmux git xclip

clone_or_pull https://github.com/Spuppateddu/tmuxrc.git "$HOME/.tmuxrc"
ensure_source_line "source-file ~/.tmuxrc/config" "$HOME/.tmux.conf"

# TPM — the plugin manager the config drives.
clone_or_pull https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"

# Install plugins non-interactively if TPM ships its installer.
tpm_install="$HOME/.tmux/plugins/tpm/bin/install_plugins"
if [[ -x "$tpm_install" ]]; then
    step "Installing tmux plugins via TPM"
    run "$tpm_install" >/dev/null 2>&1 || warn "TPM install failed — inside tmux press: prefix + I"
    ok "tmux plugins installed."
else
    warn "TPM installer not found — inside tmux press: prefix + I (backtick + I)."
fi

# Reload: apply the pulled config to any running tmux server right now.
if tmux info >/dev/null 2>&1; then
    step "Reloading running tmux"
    run tmux source-file "$HOME/.tmux.conf" || warn "tmux reload failed."
    ok "tmux reloaded."
else
    skip "No running tmux server — config loads on next start."
fi

ok "Tmux ready."
