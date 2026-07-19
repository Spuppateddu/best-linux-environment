#!/usr/bin/env bash
# lazygit — terminal UI for git. A CLI tool, so it installs on servers too (no
# desktop guard). Prefer apt: Ubuntu 26.04 ships a recent build that updates with
# the system. If a release has no apt candidate, fall back to the latest prebuilt
# binary from GitHub → ~/.local/bin (which precedes /usr/bin on PATH).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "lazygit"

if has_cmd lazygit; then
    skip "lazygit already installed ($(lazygit --version 2>/dev/null | head -1))."
    ok "lazygit ready."
    exit 0
fi

# True when apt can install lazygit on this release.
lazygit_apt_candidate() {
    local c
    c="$(apt-cache policy lazygit 2>/dev/null | awk '/Candidate:/ {print $2}')"
    [[ -n "$c" && "$c" != "(none)" ]]
}

# ── Path 1: apt (preferred) ──────────────────────────────────────────────────
# Refresh once if the candidate looks absent — a first-boot index can be stale.
if lazygit_apt_candidate \
   || { [[ "$DRY_RUN" != true ]] && can_sudo && apt_refresh && lazygit_apt_candidate; }; then
    apt_ensure lazygit
    ok "lazygit ready."
    exit 0
fi

# ── Path 2: GitHub prebuilt binary → ~/.local/bin ────────────────────────────
case "$(uname -m)" in
    x86_64)        lgarch="x86_64" ;;
    aarch64|arm64) lgarch="arm64" ;;
    *) fail "Unsupported arch $(uname -m) for the lazygit prebuilt binary."; exit 1 ;;
esac

apt_ensure curl
tag="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest 2>/dev/null \
    | awk -F'"' '/"tag_name"/ {print $4; exit}')"
if [[ -z "$tag" ]]; then
    fail "lazygit not in apt and couldn't resolve a GitHub release — install it manually."
    exit 1
fi

ver="${tag#v}"
url="https://github.com/jesseduffield/lazygit/releases/download/${tag}/lazygit_${ver}_Linux_${lgarch}.tar.gz"
tmp="/tmp/lazygit.$$.tgz"
step "lazygit not in apt — installing ${tag} ($lgarch) from GitHub"
run mkdir -p "$HOME/.local/bin"
run curl -fL --progress-bar -o "$tmp" "$url"
run tar -xzf "$tmp" -C "$HOME/.local/bin" lazygit
run chmod +x "$HOME/.local/bin/lazygit"
run rm -f "$tmp"
ok "lazygit ${tag} installed → ~/.local/bin (ensure ~/.local/bin is on PATH)."
