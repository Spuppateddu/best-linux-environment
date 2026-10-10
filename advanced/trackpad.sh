#!/usr/bin/env bash
# Gestures for any trackpad/touchpad: two-finger back/forward in Firefox, three-finger swipes for tabs,
# four-finger ones for fullscreen and workspaces. Classic scrolling on a Magic Trackpad only. Files in trackpad/.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SRC="$BLE_ROOT/trackpad"
XORG_CONF=/etc/X11/xorg.conf.d/50-magic-trackpad.conf
GESTURES="$HOME/.local/bin/ble-trackpad-gestures"
AUTOSTART="$HOME/.config/autostart/ble-trackpad-gestures.desktop"

is_installed() {
    [[ -e "$XORG_CONF" && -x "$GESTURES" && -e "$AUTOSTART" ]] && command -v xdotool xprop >/dev/null \
        && grep -qx 'export MOZ_USE_XINPUT2=1' "$HOME/.xsessionrc" 2>/dev/null
}
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }
if [[ "${1:-}" == --uninstall ]]; then
    title "Trackpad / touchpad gestures — uninstall"
    run pkill -u "$(id -u)" -f ble-trackpad-gestures || true
    remove_files "$GESTURES" "$AUTOSTART"
    if grep -qx 'export MOZ_USE_XINPUT2=1' "$HOME/.xsessionrc" 2>/dev/null; then
        run sed -i '/^export MOZ_USE_XINPUT2=1$/d' "$HOME/.xsessionrc"
        [[ "$DRY_RUN" == true ]] || ok "MOZ_USE_XINPUT2 dropped from ~/.xsessionrc."
    fi
    remove_files --sudo "$XORG_CONF"
    # The 'input' group lets every program read every keyboard — only kept while needed.
    if id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
        if [[ "$DRY_RUN" == true ]] || can_sudo; then
            run sudo gpasswd -d "$USER" input >/dev/null
            [[ "$DRY_RUN" == true ]] || ok "Removed $USER from the 'input' group."
        else
            warn "sudo unavailable — $USER is still in the 'input' group."
        fi
    fi
    # The packages (libinput-tools, xdotool, x11-utils) stay: they are small and generic.
    ok "Trackpad gestures removed. Log out and back in for all of it to apply."
    exit 0
fi

title "Trackpad / touchpad gestures"
require_desktop "Trackpad / touchpad gestures"

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

# Firefox on X only swipes back/forward with two fingers when it reads the
# trackpad through XInput2, which is still opt-in. Chrome does it on its own.
xsessionrc_export MOZ_USE_XINPUT2 1

# ── the root half ────────────────────────────────────────────────────────────
if ! can_sudo; then
    skip "No terminal to authenticate sudo — the root half is left as it is."
    skip "Run ./setup.sh from a terminal to install or refresh it."
    exit 0
fi

# `libinput debug-events`, which the gesture script reads; xdotool and xprop for the tab keys.
apt_ensure libinput-tools xdotool x11-utils

if cmp -s "$SRC/50-magic-trackpad.conf" "$XORG_CONF"; then
    skip "$XORG_CONF already current."
else
    step "installing $XORG_CONF"
    run sudo install -D -m 0644 -o root -g root "$SRC/50-magic-trackpad.conf" "$XORG_CONF"
    ok "Classic scrolling set for the Apple Magic Trackpad — it applies from the next login."
fi

# Reading /dev/input needs the 'input' group. Note that any program you run can
# then read every keyboard and mouse too — the usual price for gesture tools.
if id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
    skip "$USER is already in the 'input' group."
else
    run sudo usermod -aG input "$USER"
    ok "Added $USER to the 'input' group — it applies from the next login."
fi

ok "Trackpad / touchpad gestures ready. Log out and back in (or reboot) for all of it to apply."
