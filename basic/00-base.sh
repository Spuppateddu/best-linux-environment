#!/usr/bin/env bash
# Core tooling every other module builds on. Kept minimal on purpose.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "Base tooling"
require_apt

# zsh here so the shell is present before 10-tools runs the zshrc installer.
apt_ensure \
    git curl wget unzip xz-utils ca-certificates gnupg \
    build-essential pkg-config \
    zsh
