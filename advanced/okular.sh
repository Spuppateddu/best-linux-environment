#!/usr/bin/env bash
# Okular — KDE document/PDF viewer. In the Ubuntu repos.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

is_installed() { apt_installed okular; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }

apt_app_module okular "Okular" --desktop

# The binary is here now, so hand the PDF defaults back to 75-pdf-viewer.sh: its
# own tier ran long ago, and without this call the flip waits for the next setup.

# A condition, not a bare call — a failure there must not fail this module.
bash "$BLE_ROOT/basic/75-pdf-viewer.sh" \
    || warn "Could not re-apply the PDF defaults — ./setup.sh picks them up next run."
