#!/usr/bin/env bash
# Alacritty — the terminal. Its config repo (~/.alacritty, cloned by 10-tools
# from tools.conf) ships only alacritty.toml and no install.sh on purpose, so
# this repo owns the two things that toml can't do for itself: install the apt
# package, and link the config where Alacritty actually reads it. Alacritty does
# NOT read ~/.alacritty/alacritty.toml — it looks in ~/.config/alacritty/ — so
# without this link the terminal launches with stock defaults. Runs after the
# Nerd Font (50) that its config renders.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Alacritty"
require_desktop "Alacritty"

apt_ensure alacritty

# Link the config from the cloned tool repo. 10-tools runs first, so on a normal
# `all`/`basic` run the toml is already on disk; if the tool was skipped in the
# menu, install the package but point the user at how to get the config.
src="$HOME/.alacritty/alacritty.toml"
if [[ -f "$src" ]]; then
    link "$src" "$HOME/.config/alacritty/alacritty.toml"
else
    warn "Config repo ~/.alacritty not cloned yet — package installed, config not linked."
    warn "Get the config: ./install.sh basic  (pick alacritty in the tool menu) or ./install.sh all"
fi

ok "Alacritty ready."
