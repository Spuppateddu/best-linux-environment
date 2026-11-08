#!/usr/bin/env bash
# Per-keyboard key remaps, as udev hwdb files from keyboard/. Today: the Epomaker
# TH66 Pro's Left Ctrl types ` and ~. Only that keyboard changes; any other is untouched.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SRC="$BLE_ROOT/keyboard/90-ble-epomaker-th66.hwdb"
HWDB=/etc/udev/hwdb.d/90-ble-epomaker-th66.hwdb

# Rebuild the hwdb and re-read every keyboard, so the remap is live now:
# no reboot, no re-plug.
reload_hwdb() {
    run sudo systemd-hwdb update
    run sudo udevadm trigger --subsystem-match=input --action=change
}

[[ "${1:-}" == "--check" ]] && { cmp -s "$SRC" "$HWDB" && exit 0 || exit 1; }
if [[ "${1:-}" == --uninstall ]]; then
    title "Keyboard remaps — uninstall"
    [[ -e "$HWDB" ]] || { skip "No keyboard remap installed."; exit 0; }
    remove_files --sudo "$HWDB"
    reload_hwdb
    ok "Keyboard remaps removed: Left Ctrl is Ctrl again."
    exit 0
fi

title "Keyboard remaps"
if ! has_cmd systemd-hwdb || ! has_cmd udevadm; then
    skip "No udev here (systemd-hwdb, udevadm) — no remap to install."
    exit 0
fi
if ! can_sudo; then
    skip "No terminal to authenticate sudo — the remap is left as it is."
    exit 0
fi
ROOT_FILE_CHANGED=false
install_root_file 0644 "$SRC" "$HWDB"
if [[ "$ROOT_FILE_CHANGED" == true ]]; then
    reload_hwdb
    ok "Epomaker TH66 Pro: Left Ctrl now types \` (Shift+Left Ctrl: ~). Caps Lock is your Ctrl."
fi
