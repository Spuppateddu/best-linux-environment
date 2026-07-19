#!/usr/bin/env bash
# Okular — KDE document/PDF viewer. In the Ubuntu repos.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

is_installed() { apt_installed okular; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }

title "Okular"
require_desktop "Okular"
if is_installed; then skip "Okular already installed."; else apt_ensure okular; fi
ok "Okular ready."
