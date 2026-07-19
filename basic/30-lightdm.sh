#!/usr/bin/env bash
# LightDM + GTK greeter — the login screen for i3. Ubuntu Desktop ships GDM3,
# whose session picker is a small cog that only appears on the password screen
# and, on some builds, doesn't surface the i3 xsession at all — so a fresh box
# has no obvious way to log into i3. The LightDM GTK greeter puts a session
# dropdown right on the login form, making "pick i3" a one-click choice.
#
# Upstream's `dpkg-reconfigure lightdm` opens an interactive debconf dialog to
# choose the default display manager; we preseed that answer so the switch is
# silent, idempotent, and safe to re-run. The switch takes effect at the next
# reboot — we deliberately never restart the display manager (that would kill
# the running graphical session).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

title "LightDM (login screen)"
require_desktop "LightDM"

apt_ensure lightdm lightdm-gtk-greeter

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
    warn "Set it later from a terminal: ./install.sh basic  (or sudo dpkg-reconfigure lightdm)"
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
