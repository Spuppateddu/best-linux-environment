#!/usr/bin/env bash
# b-pw-display — the desktop half of playwright-remote: ssh into a host and let
# its agent drive a Firefox window on this screen.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SRC="$BLE_ROOT/playwright-remote/b-pw-display"
DST="$HOME/.local/bin/b-pw-display"

is_installed() { have_local_bin b-pw-display; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }
if [[ "${1:-}" == --uninstall ]]; then
    title "b-pw-display — uninstall"
    remove_files "$DST"
    ok "b-pw-display removed. Playwright's Firefox build stays (playwright-mcp owns it)."
    exit 0
fi

title "b-pw-display (Firefox here, agent on another host)"
apt_ensure nodejs npm

# The server runs Playwright's own Firefox build, the revision @latest expects.
if [[ "$DRY_RUN" == true ]]; then
    printf '%s  would run:%s npx @playwright/mcp@latest install-browser firefox\n' "$C_DIM" "$C_OFF"
else
    step "Making sure Playwright's Firefox build matches @playwright/mcp@latest"
    if pw_log="$(npx -y @playwright/mcp@latest install-browser firefox 2>&1)"; then
        ok "Playwright Firefox ready."
    else
        printf '%s\n' "$pw_log" | tail -5
        warn "Could not fetch Playwright's Firefox (offline?) — continuing."
    fi
fi

if cmp -s "$SRC" "$DST"; then
    skip "b-pw-display already current."
else
    run mkdir -p "$HOME/.local/bin"
    run install -m 0755 "$SRC" "$DST"
    ok "b-pw-display installed to ~/.local/bin."
fi
ok "Use: b-pw-display <user>@<host> — the host needs the 'playwright-remote' module."
