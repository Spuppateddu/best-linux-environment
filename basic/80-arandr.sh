#!/usr/bin/env bash
# ARandR — GUI for xrandr (monitor layout/arrangement). In the Ubuntu repos.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "ARandR"
require_desktop "ARandR"
apt_ensure arandr
ok "ARandR ready."
