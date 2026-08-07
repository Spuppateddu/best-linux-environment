#!/usr/bin/env bash
# lazydocker — terminal UI for Docker, from the prebuilt release into ~/.local/bin.
# --check exits 0 when installed; --upgrade pulls the newest release (never automatic).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# has_cmd as well as have_local_bin: if Ubuntu ever packages lazydocker, an apt
# copy counts as installed and must not be shadowed by a download of ours.
is_installed() { have_local_bin lazydocker || has_cmd lazydocker; }

UPGRADE=false
case "${1:-}" in
    --check)   is_installed && exit 0 || exit 1 ;;
    --upgrade) UPGRADE=true ;;
esac

title "lazydocker"

# Asked by path, since a non-interactive PATH may not have ~/.local/bin. `|| true`
# because a binary too broken to print its version would abort under `set -e`.
lazydocker_local_version() {
    "$HOME/.local/bin/lazydocker" --version 2>/dev/null \
        | sed -n 's/^Version:[[:space:]]*//p' | head -1 || true
}

ld_asset_url() {   # ld_asset_url TAG ARCH
    printf 'https://github.com/jesseduffield/lazydocker/releases/download/%s/lazydocker_%s_Linux_%s.tar.gz' \
        "$1" "${1#v}" "$2"
}

# ── already ours: leave it, or upgrade it if asked ───────────────────────────
if have_local_bin lazydocker; then
    have="$(lazydocker_local_version)"
    if [[ "$UPGRADE" != true ]] && ! want_upgrade; then
        skip "lazydocker ${have:-present} in ~/.local/bin — bump it with: bash advanced/lazydocker.sh --upgrade"
    elif newer="$(gh_newer_tag jesseduffield/lazydocker "$have")"; then
        ldarch="$(arch_pick x86_64 arm64)" || ldarch=""
        if [[ -z "$ldarch" ]]; then
            warn "Unsupported arch $(uname -m) — cannot upgrade lazydocker."
        else
            step "Upgrading lazydocker ${have:-?} → ${newer}"
            install_tarball_bin "$(ld_asset_url "$newer" "$ldarch")" lazydocker \
                && ok "lazydocker upgraded to ${newer}." \
                || warn "Could not upgrade lazydocker — keeping ${have:-the current build}."
        fi
    else
        skip "lazydocker ${have:-present} — nothing newer to install."
    fi
    ok "lazydocker ready."
    exit 0
fi

if has_cmd lazydocker; then
    skip "lazydocker already installed outside ~/.local/bin ($(command -v lazydocker)) — leaving it to its package manager."
    ok "lazydocker ready."
    exit 0
fi

# ── fresh install ────────────────────────────────────────────────────────────
larch="$(arch_pick x86_64 arm64)" || {
    fail "Unsupported arch $(uname -m) for the lazydocker prebuilt binary."
    exit 1
}

apt_ensure curl
tag="$(gh_latest_tag jesseduffield/lazydocker)" || {
    fail "Couldn't resolve a lazydocker GitHub release (offline or rate-limited) — try again later."
    exit 1
}

step "Installing lazydocker ${tag} (${larch}) from GitHub"
if install_tarball_bin "$(ld_asset_url "$tag" "$larch")" lazydocker; then
    ok "lazydocker ${tag} installed → ~/.local/bin (ensure ~/.local/bin is on PATH)."
else
    fail "Could not download lazydocker ${tag} from GitHub — install it manually."
    exit 1
fi

# Only a hint, never a chain into docker.sh: the dependency runs one way, or a
# TUI install would quietly set up a system daemon.
has_cmd docker || warn "No docker on this host yet — install it with: ./setup.sh only docker"
