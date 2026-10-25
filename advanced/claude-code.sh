#!/usr/bin/env bash
# Claude Code — Anthropic's terminal coding agent, installed by its own script
# into ~/.local/bin/claude (the binary) and ~/.local/share/claude (its versions).
# It updates itself, so a re-run that finds it leaves it alone.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

is_installed() { have_local_bin claude || has_cmd claude; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }
if [[ "${1:-}" == --uninstall ]]; then
    title "Claude Code — uninstall"
    remove_files "$HOME/.local/bin/claude"
    if [[ -d "$HOME/.local/share/claude" ]]; then
        run rm -rf "$HOME/.local/share/claude"
        [[ "$DRY_RUN" == true ]] || ok "removed ~/.local/share/claude"
    fi
    [[ "$DRY_RUN" != true ]] && has_cmd claude && warn "Another claude is still on PATH: $(command -v claude)"
    ok "Claude Code removed. Your login and settings in ~/.claude and ~/.claude.json are kept."
    exit 0
fi

title "Claude Code"

apt_ensure curl

# The one other module that pipes a remote script into bash — hence `secondary`.
if is_installed; then
    skip "Claude Code already installed (it updates itself)."
else
    step "Installing Claude Code via claude.ai/install.sh"
    run bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
    [[ "$DRY_RUN" == true ]] || is_installed \
        || warn "claude is not in ~/.local/bin — check the installer's output above."
fi

ok "Claude Code ready (open with: claude; log in on first start)."
