#!/usr/bin/env bash
# Steam — from Ubuntu multiverse (steam-installer). Needs i386 + multiverse.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

is_installed() { apt_installed steam-installer || apt_installed steam-launcher || has_cmd steam; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }

title "Steam"
require_desktop "Steam"
if is_installed; then skip "Steam already installed."; ok "Steam ready."; exit 0; fi

# 32-bit libs are required by the Steam runtime.
# grep without -q (reads all input) so dpkg never hits SIGPIPE under pipefail.
if dpkg --print-foreign-architectures 2>/dev/null | grep -x i386 >/dev/null; then
    skip "i386 architecture already enabled."
else
    step "Enabling i386 architecture"
    run sudo dpkg --add-architecture i386
fi

# steam-installer lives in multiverse.
apt_ensure software-properties-common
step "Enabling multiverse component"
run sudo add-apt-repository -y multiverse

apt_ensure steam-installer
ok "Steam ready — launch it once to let it self-update."
