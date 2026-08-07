#!/usr/bin/env bash
# Alacritty — the apt package only. Fonts, symlinks and fontconfig all belong to
# ~/.alacritty/install.sh, so one owner wires them: two owners is how they break.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Alacritty"
require_desktop "Alacritty"

apt_ensure alacritty

# Report the wiring rather than doing it, so a run that installed the package
# but never reached the config repo doesn't look complete.
repo="$HOME/.alacritty"
if [[ -x "$repo/install.sh" ]]; then
    skip "Config wiring belongs to ~/.alacritty/install.sh (run by 10-tools.sh)."
elif [[ -d "$repo" ]]; then
    # An older clone, from before the repo shipped an installer. Pulling it is
    # 10-tools.sh's job, so say so rather than link it here.
    warn "~/.alacritty has no install.sh — it is an old clone; nothing linked."
    warn "Update it:  bash basic/10-tools.sh alacritty"
else
    warn "Config repo ~/.alacritty not cloned yet — package installed, config not linked."
    warn "Get the config: ./setup.sh  (tick alacritty in the core list)"
fi

ok "Alacritty ready."
