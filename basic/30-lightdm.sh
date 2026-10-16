#!/usr/bin/env bash
# LightDM + GTK greeter — the login screen for i3, whose session dropdown GDM3
# hides. The debconf answer is preseeded; the switch applies at the next reboot.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "LightDM (login screen)"
require_desktop "LightDM"

apt_ensure lightdm lightdm-gtk-greeter

# ── the look: wallpapers/default.jpg behind a gruvbox, Windows 95 style box ──
# The greeter runs as the lightdm user, who cannot read $HOME: copies, not links.
STYLE="$BLE_ROOT/login-screen"
GREETER_DROPIN=/etc/xdg/lightdm/lightdm-gtk-greeter.conf.d/50-ble.conf
if [[ "$DRY_RUN" != true ]] && ! can_sudo; then
    skip "No terminal to authenticate sudo — login screen style left as it is."
else
    install_root_file 0644 "$BLE_ROOT/wallpapers/default.jpg" /usr/share/backgrounds/ble-login.jpg || true
    install_root_file 0644 "$STYLE/gtk.css" /usr/share/themes/BLE-Retro/gtk-3.0/gtk.css || true
    install_root_file 0644 "$STYLE/greeter.conf" "$GREETER_DROPIN" || true
    ok "Login screen style in place — it shows at the next logout."
fi

# The real switch is systemd's display-manager.service alias; whichever DM it
# points at is the one that starts at boot.
current_dm="$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" .service 2>/dev/null || true)"
if [[ "$current_dm" == lightdm ]]; then
    skip "LightDM is already the default display manager."
    ok "LightDM ready."
    exit 0
fi

if ! can_sudo; then
    warn "sudo unavailable — LightDM installed but not set as default."
    warn "Set it later from a terminal: ./setup.sh  (or sudo dpkg-reconfigure lightdm)"
    exit 0
fi

step "Making LightDM the default display manager (replacing ${current_dm:-none})"
# Preseed the shared debconf question so dpkg-reconfigure runs non-interactively
# now and package upgrades don't flip the default back to GDM later.
run sudo debconf-set-selections <<< "lightdm shared/default-x-display-manager select lightdm"
# Reconfigure updates /etc/X11/default-display-manager and the systemd alias.
run sudo env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure lightdm

# Verify the alias actually moved; belt-and-suspenders if reconfigure was a no-op.
new_dm="$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" .service 2>/dev/null || true)"
if [[ "$new_dm" != lightdm && "$DRY_RUN" != true ]]; then
    warn "display-manager alias still points at ${new_dm:-none} — forcing it to LightDM."
    run sudo ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service
fi

ok "LightDM set as default — the session picker appears on the login form after a reboot."
