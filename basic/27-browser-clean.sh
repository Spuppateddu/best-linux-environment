#!/usr/bin/env bash
# b-browser-clean — empties the browsers you tick in ./setup.sh every
# BLE_BROWSER_CLEAN_DAYS days, at boot. Links it into ~/.local/bin; cleans nothing.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SRC="$BLE_ROOT/browser-clean/b-browser-clean"

title "Browser clean (b-browser-clean)"

# A script on PATH rather than an alias in each shell's file: one copy, both shells.
[[ -x "$SRC" ]] || run chmod +x "$SRC"
link "$SRC" "$HOME/.local/bin/b-browser-clean"
exit 0
