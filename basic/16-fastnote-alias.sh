#!/usr/bin/env bash
# One alias, `fn`, added to aliases.local (gitignored, so machine-local): creates
# /opens ~/fastnote.txt in vim. Never over an alias you have. basic/95-settings.sh
# then copies it into both shells.
# --check exits 0 when an alias opens fastnote.txt; --uninstall removes only ours.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
source "$BLE_ROOT/lib/settings.sh"

ALIAS_NAME="fn"
ALIAS_CMD='touch ~/fastnote.txt && vim ~/fastnote.txt'

# The exact lines the install appends: --uninstall deletes these and nothing else.
OUR_LINES=(
    '# Quick scratch note: create/open ~/fastnote.txt in vim. Added by'
    '# best-linux-environment.'
    "alias $ALIAS_NAME='$ALIAS_CMD'"
)

# drop_old  — older runs wrote these lines into ~/.<shell>/<shell>-alias.local.
# Aliases live only in aliases.local now, so they are taken back out of there.
drop_old() {
    local shell_name f
    for shell_name in zsh bash; do
        f="$HOME/.$shell_name/$shell_name-alias.local"
        if aliases_drop "$f" "${OUR_LINES[@]}"; then
            ok "$shell_name: removed alias $ALIAS_NAME from ${f/#$HOME/\~}."
        fi
    done
    return 0
}

case "${1:-}" in
    --check)
        aliases_has '^[[:space:]]*alias[[:space:]]+[^=]+=.*fastnote\.txt' && exit 0
        exit 1
        ;;
    --uninstall)
        title "fastnote alias — uninstall"
        if aliases_drop "$BLE_ALIASES_LOCAL" "${OUR_LINES[@]}"; then
            ok "Removed alias $ALIAS_NAME from ${BLE_ALIASES_LOCAL/#$HOME/\~}."
        fi
        drop_old
        exit 0
        ;;
esac

title "fastnote alias for your shell ($ALIAS_NAME)"

# ── 1. is vim here? ──────────────────────────────────────────────────────────
if ! has_cmd vim; then
    skip "vim is not installed — nothing to alias."
    exit 0
fi

# ── 2. the old copies ────────────────────────────────────────────────────────
drop_old

# ── 3. is one already there? ─────────────────────────────────────────────────
# Loose on purpose: this decides whether to LEAVE THINGS ALONE, so it errs wide.
if aliases_has '^[[:space:]]*alias[[:space:]]+[^=]+=.*fastnote\.txt'; then
    skip "An alias already opens fastnote.txt — left exactly as it is."
    exit 0
fi
# Separately: is the NAME taken? A second `alias fn=` would silently win.
if aliases_has "^[[:space:]]*alias[[:space:]]+$ALIAS_NAME="; then
    warn "'$ALIAS_NAME' is already an alias for something else — not touching it."
    warn "Add your own with: alias NAME='$ALIAS_CMD'  in ${BLE_ALIASES_LOCAL/#$HOME/\~}"
    exit 0
fi

# ── 4. append it ─────────────────────────────────────────────────────────────
aliases_add "${OUR_LINES[@]}"
[[ "$DRY_RUN" == true ]] || \
    ok "Added alias $ALIAS_NAME='$ALIAS_CMD' to ${BLE_ALIASES_LOCAL/#$HOME/\~} (open a new shell to use it)."
exit 0
