#!/usr/bin/env bash
# MEGAsync — MEGA desktop sync. Official apt repo, one build per Ubuntu release
# (xUbuntu_<version>). Falls back gracefully if 26.04 isn't published yet.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SRC="$BLE_ROOT/megasync"
WRAPPER="$HOME/.local/bin/megasync-wait-tray"
AUTOSTART="$HOME/.config/autostart/megasync.desktop"

is_installed() { apt_installed megasync; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }

title "MEGAsync"
require_desktop "MEGAsync"

# ── 1. the package ───────────────────────────────────────────────────────────
if is_installed; then
    skip "MEGAsync already installed."
else
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

    # apt_ensure refreshes once when a package has no candidate, so an unpublished
    # release reads as "no candidate". Not a bare `apt-get update`: that needs root.
    apt_ensure megasync

    if ! apt_installed megasync; then
        warn "No megasync package for xUbuntu_${release} (it may not be published yet)."
        warn "Remove /etc/apt/sources.list.d/mega.nz.list and grab the .deb from https://mega.io/desktop."
        exit 0
    fi
fi

# ── 2. the autostart race ────────────────────────────────────────────────────
# `dex --autostart` and the bar that hosts the tray start together, and MEGAsync
# usually wins. With no tray it opens a frameless window i3 can never focus, so
# the window sits there drawn and dead. The wrapper waits for the tray first.
if [[ ! -r "$SRC/megasync-wait-tray" ]]; then
    warn "Missing $SRC/megasync-wait-tray — autostart left as MEGAsync wrote it."
elif cmp -s "$SRC/megasync-wait-tray" "$WRAPPER"; then
    skip "megasync-wait-tray already current."
else
    run mkdir -p "$HOME/.local/bin"
    run install -m 0755 "$SRC/megasync-wait-tray" "$WRAPPER"
    ok "megasync-wait-tray installed to ~/.local/bin."
fi

# Absolute path on purpose: the session that runs autostart has no ~/.local/bin
# on PATH. X-GNOME-Autostart-Delay is dropped — dex ignores it anyway.
if [[ -x "$WRAPPER" || "$DRY_RUN" == true ]]; then
    config_write "$AUTOSTART" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.0
GenericName=File Synchronizer
Name=MEGAsync
Comment=Easy automated syncing between your computers and your MEGA cloud drive.
TryExec=$WRAPPER
Exec=$WRAPPER
Icon=mega
Terminal=false
Categories=Network;System;
StartupNotify=false
DESKTOP
fi

ok "MEGAsync ready."
