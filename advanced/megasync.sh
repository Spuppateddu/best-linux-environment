#!/usr/bin/env bash
# MEGAsync — MEGA desktop sync. Official apt repo, one build per Ubuntu release
# (xUbuntu_<version>). Falls back gracefully if 26.04 isn't published yet.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

is_installed() { apt_installed megasync; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }

title "MEGAsync"
if is_installed; then skip "MEGAsync already installed."; ok "MEGAsync ready."; exit 0; fi

apt_ensure curl gnupg

# Release number drives the repo folder (e.g. 26.04 → xUbuntu_26.04).
release="$(lsb_release -rs 2>/dev/null || echo '')"
if [[ -z "$release" ]]; then
    fail "Could not determine Ubuntu release — install MEGAsync manually from https://mega.io/desktop."
    exit 1
fi
base="https://mega.nz/linux/repo/xUbuntu_${release}"

apt_repo_add mega.nz \
    "${base}/Release.key" \
    "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/mega.nz.gpg] ${base}/ ./"

if apt-get update -qq 2>/dev/null; then
    apt_ensure megasync
    ok "MEGAsync ready."
else
    warn "MEGA repo for xUbuntu_${release} not reachable yet (26.04 may not be published)."
    warn "Remove /etc/apt/sources.list.d/mega.nz.list and grab the .deb from https://mega.io/desktop."
fi
