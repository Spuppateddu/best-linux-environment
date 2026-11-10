#!/usr/bin/env bash
# Per-keyboard key remaps, as udev hwdb files from keyboard/ (every *.hwdb there).
# Today: the Epomaker TH66 Pro's Left Ctrl types ` and ~, and the HHKB Hybrid's
# Power, Sleep and Print Screen keys do nothing. Only those keyboards change.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

HWDB_DIR=/etc/udev/hwdb.d
SRCS=("$BLE_ROOT"/keyboard/*.hwdb)

# Rebuild the hwdb and re-read every keyboard, so the remap is live now:
# no reboot, no re-plug.
reload_hwdb() {
    run sudo systemd-hwdb update
    run sudo udevadm trigger --subsystem-match=input --action=change
}

if [[ "${1:-}" == "--check" ]]; then
    for src in "${SRCS[@]}"; do
        cmp -s "$src" "$HWDB_DIR/$(basename "$src")" || exit 1
    done
    exit 0
fi
if [[ "${1:-}" == --uninstall ]]; then
    title "Keyboard remaps — uninstall"
    dests=()
    for src in "${SRCS[@]}"; do
        dest="$HWDB_DIR/$(basename "$src")"
        [[ -e "$dest" ]] && dests+=("$dest")
    done
    [[ ${#dests[@]} -gt 0 ]] || { skip "No keyboard remap installed."; exit 0; }
    remove_files --sudo "${dests[@]}"
    reload_hwdb
    ok "Keyboard remaps removed: every key does what the keyboard sends again."
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
for src in "${SRCS[@]}"; do
    install_root_file 0644 "$src" "$HWDB_DIR/$(basename "$src")"
done
if [[ "$ROOT_FILE_CHANGED" == true ]]; then
    reload_hwdb
    ok "Epomaker TH66 Pro: Left Ctrl now types \` (Shift+Left Ctrl: ~). Caps Lock is your Ctrl."
    ok "HHKB Hybrid: Power, Sleep and Print Screen keys now do nothing."
fi
