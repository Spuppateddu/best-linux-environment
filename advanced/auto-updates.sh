#!/usr/bin/env bash
# Auto-updates — the daily unattended-upgrades run installs Ubuntu's bug-fix
# updates too, not only the security fixes it ships with. One file in apt.conf.d.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SRC="$BLE_ROOT/updates/52best-linux-environment"
# The override exists for the unit tests only.
CONF="${BLE_APT_CONF_D:-/etc/apt/apt.conf.d}/52best-linux-environment"

is_installed() { [[ -e "$CONF" ]] && apt_installed unattended-upgrades; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }
if [[ "${1:-}" == --uninstall ]]; then
    title "Auto-updates — uninstall"
    # unattended-upgrades stays: Ubuntu ships it, for the security fixes.
    remove_files --sudo "$CONF"
    [[ "$DRY_RUN" == true ]] || ok "Back to Ubuntu's default: security fixes only."
    exit 0
fi

title "Auto-updates (bug fixes too, not only security)"

if ! can_sudo; then
    skip "No terminal to authenticate sudo — $CONF is left as it is."
    skip "Run ./setup.sh from a terminal to install or refresh it."
    exit 0
fi

apt_ensure unattended-upgrades
install_root_file 0644 "$SRC" "$CONF" || exit 1

# Ask apt itself, so a file it cannot parse or does not read is caught here.
if [[ "$DRY_RUN" != true ]] && has_cmd apt-config; then
    if apt-config dump 2>/dev/null | grep -F 'codename}-updates' >/dev/null; then
        ok "Auto-updates on: the daily run now installs bug fixes as well as security fixes."
    else
        warn "apt does not list the -updates pocket — check $CONF."
    fi
fi
exit 0
