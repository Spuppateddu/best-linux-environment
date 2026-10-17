#!/usr/bin/env bash
# b-lock — the lock screen: the login screen's wallpapers/default.jpg, a gruvbox well for the ring.
# Links it into ~/.local/bin; ~/.i3rc/scripts/lock.sh runs it for $mod+Shift+x, the power menu, suspend.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/lock-screen/b-lock"

title "Lock screen (b-lock)"

# The i3 repo's setup.sh installs i3lock too; this one cannot rely on it having run.
has_cmd i3lock || apt_ensure i3lock
# Pillow draws the picture; xrandr and xdpyinfo say where the monitors are and how dense.
apt_ensure python3 python3-pil x11-xserver-utils x11-utils

run chmod +x "$SRC"
link "$SRC" "$HOME/.local/bin/b-lock"

# Drawn now, so the first lock after a change does not wait for it.
if [[ "$DRY_RUN" != true && -n "${DISPLAY:-}" ]]; then
    if "$SRC" image >/dev/null 2>&1; then
        ok "Lock screen picture drawn."
    else
        warn "Could not draw the lock screen picture — i3lock shows plain gruvbox until it can."
    fi
fi
[[ -x "$HOME/.i3rc/scripts/lock.sh" ]] \
    || skip "No ~/.i3rc/scripts/lock.sh yet — until the i3 repo has it, i3 locks with plain i3lock."
exit 0
