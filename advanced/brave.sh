#!/usr/bin/env bash
# Brave browser — official apt repo. The keyring is already dearmored and the
# repo ships a deb822 .sources file, so both are downloaded as-is (no dearmor).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

is_installed() { apt_installed brave-browser; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }

title "Brave browser"
if is_installed; then skip "Brave already installed."; ok "Brave ready."; exit 0; fi

apt_ensure curl

keyring="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
sources="/etc/apt/sources.list.d/brave-browser-release.sources"
if [[ -f "$keyring" && -f "$sources" ]]; then
    skip "Brave apt repo already configured."
else
    step "Adding Brave apt repo"
    run sudo curl -fsSLo "$keyring" \
        https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    run sudo curl -fsSLo "$sources" \
        https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
    ok "Brave apt repo added."
fi

apt_ensure brave-browser
ok "Brave ready."
