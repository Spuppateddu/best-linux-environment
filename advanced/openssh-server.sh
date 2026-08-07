#!/usr/bin/env bash
# openssh-server — sshd on port 22, so it opens a port and stays in `secondary`,
# ticked by hand. The client half is basic/20-ssh.sh. --check exits 0 when installed.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

is_installed() { apt_installed openssh-server; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }

title "OpenSSH server"

if is_installed; then
    skip "openssh-server already installed."
else
    apt_ensure openssh-server
fi

# Say what is reachable and from where. `hostname -I` prints every address, so
# take the first: a host with docker, bridges and VPNs has a dozen.
if is_installed; then
    addr="$(hostname -I 2>/dev/null | awk '{print $1}')"
    ok "sshd listening on port 22 — reach this host at ${addr:-<this host IP>}."
    ok "Copy a key in from another machine: ssh-copy-id $(id -un)@${addr:-<ip>}"
fi
