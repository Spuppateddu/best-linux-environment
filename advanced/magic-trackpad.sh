#!/usr/bin/env bash
# Apple Magic Trackpad: classic (non-natural) scrolling, and a three-finger swipe left/right
# to change i3 workspace. The files it installs live in magic-trackpad/.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SRC="$BLE_ROOT/magic-trackpad"
XORG_CONF=/etc/X11/xorg.conf.d/50-magic-trackpad.conf
GESTURES="$HOME/.local/bin/ble-trackpad-gestures"
AUTOSTART="$HOME/.config/autostart/ble-trackpad-gestures.desktop"

is_installed() { [[ -e "$XORG_CONF" && -x "$GESTURES" && -e "$AUTOSTART" ]]; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }

title "Magic Trackpad"
require_desktop "Magic Trackpad"

# ── the user half: works without root ───────────────────────────────────────
run mkdir -p "$HOME/.local/bin"
if cmp -s "$SRC/ble-trackpad-gestures" "$GESTURES"; then
    skip "ble-trackpad-gestures already current."
else
    run install -m 0755 "$SRC/ble-trackpad-gestures" "$GESTURES"
    ok "ble-trackpad-gestures installed to ~/.local/bin."
fi
# i3 runs `dex --autostart` at login, and dex starts everything in this folder.
config_write "$AUTOSTART" < "$SRC/ble-trackpad-gestures.desktop"

# ── the root half ────────────────────────────────────────────────────────────
if ! can_sudo; then
    skip "No terminal to authenticate sudo — the root half is left as it is."
    skip "Run ./setup.sh from a terminal to install or refresh it."
    exit 0
fi

# `libinput debug-events`, which the gesture script reads.
apt_ensure libinput-tools

if cmp -s "$SRC/50-magic-trackpad.conf" "$XORG_CONF"; then
    skip "$XORG_CONF already current."
else
    step "installing $XORG_CONF"
    run sudo install -D -m 0644 -o root -g root "$SRC/50-magic-trackpad.conf" "$XORG_CONF"
    ok "Classic scrolling set — it applies from the next login."
fi

# Reading /dev/input needs the 'input' group. Note that any program you run can
# then read every keyboard and mouse too — the usual price for gesture tools.
if id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
    skip "$USER is already in the 'input' group."
else
    run sudo usermod -aG input "$USER"
    ok "Added $USER to the 'input' group — it applies from the next login."
fi

ok "Magic Trackpad ready. Log out and back in (or reboot) for all of it to apply."
