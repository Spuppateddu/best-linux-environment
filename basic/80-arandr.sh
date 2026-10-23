#!/usr/bin/env bash
# ARandR — GUI for xrandr (monitor layout/arrangement). In the Ubuntu repos.
# Plus b-max-hz: ARandR cannot pick a refresh rate, so i3 sets every monitor to its
# highest one at each login (~/.i3rc/11-max-hz.local).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/max-hz/b-max-hz"
I3="$HOME/.i3rc"

apt_app_module arandr "ARandR" --desktop

# ── b-max-hz ─────────────────────────────────────────────────────────────────
run chmod +x "$SRC"
link "$SRC" "$HOME/.local/bin/b-max-hz"

if [[ ! -d "$I3" ]]; then
    skip "No ~/.i3rc — nothing runs b-max-hz at login. Run 'b-max-hz' by hand."
    exit 0
fi
write_gen "$I3/11-max-hz.local" <<'EOF'
# Written by best-linux-environment (basic/80-arandr.sh). Do NOT edit: every
# run rewrites it. Every monitor that is on runs at its highest refresh rate.
exec_always --no-startup-id ~/.local/bin/b-max-hz
EOF
# The running session too: reload alone does not run exec_always.
if [[ "$DRY_RUN" != true ]] && has_cmd i3-msg && i3-msg -t get_version >/dev/null 2>&1; then
    [[ "$GEN_CHANGED" != true ]] || i3-msg reload >/dev/null
    # One string: i3-msg would take a bare --no-startup-id as its own option.
    i3-msg "exec --no-startup-id $HOME/.local/bin/b-max-hz" >/dev/null \
        && ok "Every monitor now runs at its highest refresh rate."
fi
exit 0
