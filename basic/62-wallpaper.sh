#!/usr/bin/env bash
# b-wallpaper — cycles the images in wallpapers/ (gitignored but default.jpg) with feh. Links the
# command into ~/.local/bin; ~/.i3rc/09-wallpaper.local binds $mod+Shift+w and cycles every 5 min.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/wallpapers/b-wallpaper"
I3="$HOME/.i3rc"

title "Wallpapers (b-wallpaper)"

if [[ ! -f "$SRC" ]]; then
    skip "No wallpapers/b-wallpaper in this repo — nothing to install."
    exit 0
fi

# The i3 repo's setup.sh installs feh too; this one cannot rely on it having run.
has_cmd feh || apt_ensure feh

# A link, not a copy: the script finds the images beside itself through it.
run chmod +x "$SRC"
link "$SRC" "$HOME/.local/bin/b-wallpaper"

# ── the i3 key ───────────────────────────────────────────────────────────────
# Login and reload go through ~/.i3rc/scripts/set_background.sh, which calls
# `b-wallpaper restore` and falls back to the solid colour when it fails.
if [[ ! -d "$I3" ]]; then
    skip "No ~/.i3rc — no key to bind. Run 'b-wallpaper' by hand."
    exit 0
fi
write_gen "$I3/09-wallpaper.local" <<'EOF'
# Written by best-linux-environment (basic/62-wallpaper.sh). Do NOT edit: every
# run rewrites it. Images from ~/best-linux-environment/wallpapers/.
bindsym $mod+Shift+w exec --no-startup-id ~/.local/bin/b-wallpaper next
# Next image every 5 minutes; a lock keeps it to one loop per session.
exec_always --no-startup-id ~/.local/bin/b-wallpaper auto 300
EOF
# Start the loop in the running session too; reload alone does not run exec_always.
if [[ "$DRY_RUN" != true ]] && has_cmd i3-msg && i3-msg -t get_version >/dev/null 2>&1; then
    if [[ "$GEN_CHANGED" == true ]]; then
        i3-msg reload >/dev/null && ok "i3 reloaded: \$mod+Shift+w is the next wallpaper."
    fi
    i3-msg exec --no-startup-id "$HOME/.local/bin/b-wallpaper auto 300" >/dev/null \
        && ok "Wallpaper changes every 5 minutes."
fi

[[ -n "$("$SRC" list)" ]] \
    || skip "No images in wallpapers/ yet — drop some there, then press \$mod+Shift+w."
exit 0
