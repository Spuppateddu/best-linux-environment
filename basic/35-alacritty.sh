#!/usr/bin/env bash
# Alacritty: the terminal i3 launches ($mod+Return). apt package + clone the
# config repo into ~/.alacritty and link its toml into the default location.
# Repo: https://github.com/Spuppateddu/alacritty-config
# Note: i3rc's setup.sh does NOT install alacritty, so this repo owns it.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Alacritty"

apt_ensure alacritty git

# Config uses the Cascadia Code Nerd Font installed by 50-fonts-cursor.
clone_or_pull https://github.com/Spuppateddu/alacritty-config.git "$HOME/.alacritty"
link "$HOME/.alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"

# Reload: alacritty watches its config and live-reloads by default.
skip "Alacritty live-reloads its config — no restart needed."
ok "Alacritty ready."
