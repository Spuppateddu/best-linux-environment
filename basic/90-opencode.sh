#!/usr/bin/env bash
# opencode — terminal AI coding agent. Not in apt: its official script installs a
# prebuilt binary to ~/.local/bin. Theme lives in ~/.config/opencode/tui.json
# ("theme" moved out of opencode.json into tui.json) — set to the built-in gruvbox.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "opencode"

apt_ensure curl

# ── 1. Binary — official installer → ~/.local/bin/opencode ────────────────────
if [[ -x "$HOME/.local/bin/opencode" ]] || has_cmd opencode; then
    skip "opencode already installed."
else
    step "Installing opencode via opencode.ai/install"
    run bash -c 'curl -fsSL https://opencode.ai/install | bash'
    ok "opencode installed → ~/.local/bin (open with: opencode)."
fi

# ── 2. Gruvbox theme — only if the user has no tui.json yet ───────────────────
tui="$HOME/.config/opencode/tui.json"
if [[ -f "$tui" ]]; then
    skip "opencode tui.json exists — leaving theme untouched."
else
    step "Setting opencode theme to gruvbox"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s theme=gruvbox → %s\n' "$C_DIM" "$C_OFF" "$tui"
    else
        mkdir -p "$(dirname "$tui")"
        printf '{\n  "$schema": "https://opencode.ai/tui.json",\n  "theme": "gruvbox"\n}\n' > "$tui"
    fi
    ok "opencode theme → gruvbox."
fi

ok "opencode ready."
