#!/usr/bin/env bash
# i3: clone the i3rc repo into ~/.i3rc and delegate to its own setup.sh, which
# is already idempotent (apt packages, eww build, config symlinks, mpd services).
# Repo: https://github.com/Spuppateddu/i3rc
#
# We deliberately do NOT reimplement i3rc's install here — its setup.sh owns the
# i3-specific logic. Cross-cutting bits (font, cursor) are owned by
# 50-fonts-cursor.sh in this repo instead; i3rc's copies are idempotent no-ops.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "i3 window manager"

I3REPO="$HOME/.i3rc"
clone_or_pull https://github.com/Spuppateddu/i3rc.git "$I3REPO"

setup="$I3REPO/setup.sh"
if [[ ! -f "$setup" ]]; then
    fail "i3rc/setup.sh not found at $setup — clone may have failed."
    exit 1
fi
run chmod +x "$setup"

step "Running i3rc/setup.sh"
if [[ "$DRY_RUN" == true ]]; then
    run bash "$setup" --dry-run
else
    bash "$setup"
fi

# Reload: apply the pulled config to a running i3 session right now.
if has_cmd i3-msg && i3-msg -t get_version >/dev/null 2>&1; then
    step "Reloading running i3"
    run i3-msg reload >/dev/null || warn "i3 reload failed — try \$mod+Shift+r."
    ok "i3 reloaded."
fi

ok "i3 ready — log out and pick 'i3', or \$mod+Shift+r if already in i3."
