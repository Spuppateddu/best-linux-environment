#!/usr/bin/env bash
# b-update — updates everything now: apt update + full-upgrade + autoremove, then
# snap and flatpak when they are here. Links it into ~/.local/bin; installs nothing.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SRC="$BLE_ROOT/updates/b-update"

title "Update everything (b-update)"

# A script on PATH rather than an alias in each shell's file: one copy, both shells.
[[ -x "$SRC" ]] || run chmod +x "$SRC"
link "$SRC" "$HOME/.local/bin/b-update"
exit 0
