#!/usr/bin/env bash
# Flameshot — screenshot tool i3 binds to $mod+Shift+s. In the Ubuntu repos.
# i3rc references it but doesn't install it, so this repo owns it.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Flameshot"
apt_ensure flameshot
ok "Flameshot ready."
