#!/usr/bin/env bash
# TablePlus — database GUI. Third-party apt repo (release channel is fixed at
# /debian/22, independent of the Ubuntu codename).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

is_installed() { apt_installed tableplus; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }

title "TablePlus"
if is_installed; then skip "TablePlus already installed."; ok "TablePlus ready."; exit 0; fi

apt_ensure curl gnupg
apt_repo_add tableplus-archive \
    "https://deb.tableplus.com/apt.tableplus.com.gpg.key" \
    "deb [signed-by=/usr/share/keyrings/tableplus-archive.gpg] https://deb.tableplus.com/debian/22 tableplus main"

apt_ensure tableplus
ok "TablePlus ready."
