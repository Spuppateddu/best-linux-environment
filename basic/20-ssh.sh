#!/usr/bin/env bash
# The SSH client half (connecting OUT) plus a default ed25519 key, minted without
# a passphrase because this runs unattended. The server half is in advanced/.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "SSH client"

# The `ssh` metapackage pulls the server in too, so ask for the client by name.
# A host with the metapackage is already satisfied and loses nothing.
apt_ensure openssh-client

if has_cmd ssh; then
    ok "ssh ready — $(ssh -V 2>&1)."
else
    warn "ssh not on PATH — check the apt output above."
fi

# ── default key ──────────────────────────────────────────────────────────────
key="$HOME/.ssh/id_ed25519"
if [[ -f "$key" ]]; then
    skip "SSH key already present ($key) — left untouched."
elif ! has_cmd ssh-keygen; then
    warn "ssh-keygen missing — skipping key generation."
else
    step "Generating a default ed25519 key ($key)"
    run mkdir -p "$HOME/.ssh"
    run chmod 700 "$HOME/.ssh"
    run ssh-keygen -q -t ed25519 -f "$key" -N '' -C "$(id -un)@$(uname -n)"
    ok "Key generated — public half:"
    [[ "$DRY_RUN" == true ]] || printf '  %s\n' "$(cat "$key.pub")"
fi

# ── sshd: password logins stay on ────────────────────────────────────────────
# Only the undo is left: turning them off locks out any host with no key copied yet.
SSHD_DROPIN="/etc/ssh/sshd_config.d/60-best-linux-environment.conf"
if [[ ! -f "$SSHD_DROPIN" ]]; then
    :   # nothing of ours in sshd's config — password logins are Ubuntu's default
elif [[ "$DRY_RUN" == true ]]; then
    printf '%s  would remove:%s %s (restores password logins)\n' "$C_DIM" "$C_OFF" "$SSHD_DROPIN"
elif ! can_sudo; then
    warn "sudo unavailable (non-interactive) — $SSHD_DROPIN still blocks password logins."
    warn "Run ./setup.sh from a terminal to remove it."
else
    step "Removing the old key-only drop-in (restoring password logins)"
    sudo rm -f "$SSHD_DROPIN"
    sudo systemctl reload ssh 2>/dev/null \
        || sudo systemctl reload sshd 2>/dev/null \
        || warn "Removed $SSHD_DROPIN but could not reload sshd — applies at the next restart."
    ok "sshd → password logins allowed again."
fi
