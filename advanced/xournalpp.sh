#!/usr/bin/env bash
# Xournal++ — handwritten notes / PDF annotation. In the Ubuntu repos.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

is_installed() { apt_installed xournalpp; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }

apt_app_module xournalpp "Xournal++" --desktop
