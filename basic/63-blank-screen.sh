#!/usr/bin/env bash
# b-blank — $mod+x turns the focused workspace off: visiting it shows only the wallpaper and
# the PC's name in red binary; $mod+z hides only the focused window. Links it into ~/.local/bin.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/blank-screen/b-blank"
I3="$HOME/.i3rc"

title "Blank screen (b-blank)"

# The i3 repo's setup.sh installs jq too; this one cannot rely on it having run.
has_cmd jq || apt_ensure jq

run chmod +x "$SRC"
link "$SRC" "$HOME/.local/bin/b-blank"

if [[ ! -d "$I3" ]]; then
    skip "No ~/.i3rc — no key to bind. Run 'b-blank' by hand."
    exit 0
fi
write_gen "$I3/10-blank-screen.local" <<'EOF2'
# Written by best-linux-environment (basic/63-blank-screen.sh). Do NOT edit: every
# run rewrites it. Turn the focused workspace off (just the wallpaper) and back on.
bindsym $mod+x exec --no-startup-id ~/.local/bin/b-blank
# Hide only the focused window: its border stays, the wallpaper shows inside. Again: back.
bindsym $mod+z exec --no-startup-id ~/.local/bin/b-blank window
# A cover opens hidden in the scratchpad, so the swap is the first time it shows. Only while
# titled b-blank-new: an i3 reload re-runs rules, and a cover on screen must stay there.
for_window [class="^b-blank-cover$" title="^b-blank-new$"] move scratchpad
# The PC's name in red binary, bottom-right of a workspace that is off: tiled, so $mod+hjkl
# can leave it (a lone floating window traps focus), no border, not focused when it opens.
for_window [class="^b-blank-label$"] floating disable, border none
no_focus [class="^b-blank-label$"]
EOF2
if [[ "$DRY_RUN" != true && "$GEN_CHANGED" == true ]] && has_cmd i3-msg \
   && i3-msg -t get_version >/dev/null 2>&1; then
    i3-msg reload >/dev/null && ok "i3 reloaded: \$mod+x turns the focused workspace off and on, \$mod+z the focused window."
fi
exit 0
