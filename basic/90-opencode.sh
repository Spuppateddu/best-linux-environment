#!/usr/bin/env bash
# opencode — terminal AI coding agent, installed by its own script into its own
# prefix (~/.opencode/bin, or ~/.local/bin on older machines). --check tests both.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# By path, never through PATH (see have_opencode_bin). modules.conf's `script`
# check points here, so "is opencode installed" is defined once.
is_installed() { have_local_bin opencode || have_opencode_bin || has_cmd opencode; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }

# opencode_bin  — the copy to run. ~/.local/bin first so a machine that predates
# upstream's move keeps upgrading the binary it actually has on PATH.
opencode_bin() {
    if   have_local_bin opencode; then printf '%s' "$HOME/.local/bin/opencode"
    elif have_opencode_bin;       then printf '%s' "$HOME/.opencode/bin/opencode"
    else printf 'opencode'
    fi
}

title "opencode"

apt_ensure curl

# ── 1. Binary — official installer → ~/.opencode/bin/opencode ─────────────────
# The one module that pipes a remote script into bash — hence `secondary`: you ticked it.
if is_installed; then
    skip "opencode already installed."
    # Its own updater is the supported way, and avoids fetching a remote script
    # at every boot. An update, not a reset, so ./boot.sh only.
    oc="$(opencode_bin)"
    if want_upgrade; then
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would run:%s %s upgrade\n' "$C_DIM" "$C_OFF" "$oc"
        else
            step "Checking for a newer opencode ($oc upgrade)"
            "$oc" upgrade && ok "opencode up to date." \
                || warn "Could not upgrade opencode (offline?) — continuing."
        fi
    fi
else
    step "Installing opencode via opencode.ai/install"
    run bash -c 'curl -fsSL https://opencode.ai/install | bash'
    ok "opencode installed → ~/.opencode/bin (open with: opencode)."
    # The installer appends its prefix to the shell rc itself, so this only
    # matters for the shell you are standing in right now.
    [[ "$DRY_RUN" == true ]] || is_installed \
        || warn "opencode is not where either prefix expects it — check the installer's output above."
fi

# ── 2. Gruvbox theme ──────────────────────────────────────────────────────────
# --seed: opencode writes here itself, so only ./setup.sh sets it back to gruvbox.
tui="$HOME/.config/opencode/tui.json"
config_write "$tui" --seed <<'JSON'
{
  "$schema": "https://opencode.ai/tui.json",
  "theme": "gruvbox"
}
JSON

ok "opencode ready."
