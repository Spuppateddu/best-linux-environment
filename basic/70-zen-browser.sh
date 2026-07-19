#!/usr/bin/env bash
# Zen browser — installed via its official user-local script: no root, no apt.
# It drops a launcher at ~/.local/bin/zen and a .desktop entry. Light by design.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Zen browser"
require_desktop "Zen browser"

apt_ensure curl

if [[ -x "$HOME/.local/bin/zen" ]] || has_cmd zen; then
    skip "Zen already installed (re-run its own updater to upgrade)."
else
    step "Installing Zen (official user-local script)"
    url="https://github.com/zen-browser/updates-server/raw/refs/heads/main/install.sh"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would run:%s curl -fsSL %s | bash\n' "$C_DIM" "$C_OFF" "$url"
    else
        curl -fsSL "$url" | bash
    fi
    ok "Zen installed to ~/.local/bin/zen (ensure ~/.local/bin is on PATH)."
fi
