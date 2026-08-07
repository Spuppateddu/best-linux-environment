#!/usr/bin/env bash
# lazygit — terminal UI for git, on servers too. apt first, because it then moves
# with the system; the GitHub prebuilt → ~/.local/bin is the fallback.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "lazygit"

# A git front-end and nothing else, so git is what justifies it. Only reachable
# where 00-base could not run — otherwise you get a git TUI and no git.
if ! has_cmd git; then
    skip "git is not installed — skipping lazygit. Re-run once basic/00-base has installed git."
    exit 0
fi

# Asked by path: the boot cron's PATH lacks ~/.local/bin. `|| true` because a
# binary too broken to print its version would abort under `set -e`.
lazygit_local_version() {
    "$HOME/.local/bin/lazygit" --version 2>/dev/null \
        | sed -n 's/.*version=\([^,]*\).*/\1/p' | head -1 || true
}

# Upgrading only ever touches a copy WE downloaded: shadowing an apt lazygit
# would silently take it off the system's update path. ./boot.sh's job.
if have_local_bin lazygit; then
    have="$(lazygit_local_version)"
    if ! want_upgrade; then
        skip "lazygit ${have:-present} in ~/.local/bin — ./boot.sh upgrades it."
    elif newer="$(gh_newer_tag jesseduffield/lazygit "$have")"; then
        lgarch="$(arch_pick x86_64 arm64)" || lgarch=""
        if [[ -z "$lgarch" ]]; then
            warn "Unsupported arch $(uname -m) — cannot upgrade lazygit."
        else
            step "Upgrading lazygit ${have:-?} → ${newer}"
            url="https://github.com/jesseduffield/lazygit/releases/download/${newer}/lazygit_${newer#v}_Linux_${lgarch}.tar.gz"
            install_tarball_bin "$url" lazygit && ok "lazygit upgraded to ${newer}." \
                || warn "Could not upgrade lazygit — keeping ${have:-the current build}."
        fi
    else
        skip "lazygit ${have:-present} — nothing newer to install."
    fi
    ok "lazygit ready."
    exit 0
fi

if has_cmd lazygit; then
    skip "lazygit already installed via apt ($(lazygit --version 2>/dev/null | head -1))."
    ok "lazygit ready."
    exit 0
fi

# ── Path 1: apt (preferred) ──────────────────────────────────────────────────
# Refresh once if the candidate looks absent — a first-boot index can be stale.
if apt_has_candidate lazygit \
   || { [[ "$DRY_RUN" != true ]] && can_sudo && apt_refresh && apt_has_candidate lazygit; }; then
    apt_ensure lazygit
    ok "lazygit ready."
    exit 0
fi

# ── Path 2: GitHub prebuilt binary → ~/.local/bin ────────────────────────────
lgarch="$(arch_pick x86_64 arm64)" || {
    fail "Unsupported arch $(uname -m) for the lazygit prebuilt binary."
    exit 1
}

apt_ensure curl
tag="$(gh_latest_tag jesseduffield/lazygit)" || {
    fail "lazygit not in apt and couldn't resolve a GitHub release — install it manually."
    exit 1
}

ver="${tag#v}"
url="https://github.com/jesseduffield/lazygit/releases/download/${tag}/lazygit_${ver}_Linux_${lgarch}.tar.gz"
step "lazygit not in apt — installing ${tag} ($lgarch) from GitHub"
if install_tarball_bin "$url" lazygit; then
    ok "lazygit ${tag} installed → ~/.local/bin (ensure ~/.local/bin is on PATH)."
else
    fail "Could not download lazygit ${tag} from GitHub — install it manually."
    exit 1
fi
