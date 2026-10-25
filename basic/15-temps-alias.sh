#!/usr/bin/env bash
# One alias, `b-temp`, added to aliases.local (gitignored, so machine-local) —
# only if temps is here, and never over an alias you already have.
# basic/95-settings.sh then copies it into both shells.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
source "$BLE_ROOT/lib/settings.sh"

ALIAS_NAME="b-temp"
ALIAS_CMD="temps"

# The exact lines the install appends. Older runs wrote them into
# ~/.<shell>/<shell>-alias.local; they are taken back out of there below.
OUR_LINES=(
    '# CPU/GPU temperature logger (temperature-logger). Added by'
    '# best-linux-environment because this machine has temps installed.'
    "alias $ALIAS_NAME=\"$ALIAS_CMD\""
)

title "temps alias for your shell ($ALIAS_NAME)"

# ── 1. is the temperature logger here? ───────────────────────────────────────
# PATH *or* ~/.local/bin *or* the repo: the boot cron's PATH has only the first.
temps_here() {
    has_cmd "$ALIAS_CMD" || have_local_bin "$ALIAS_CMD" || [[ -x "$HOME/.temps/$ALIAS_CMD" ]]
}

if ! temps_here; then
    skip "temps is not installed — nothing to alias."
    exit 0
fi

# ── 2. the old copies ────────────────────────────────────────────────────────
# Aliases live only in aliases.local now: drop the ones older runs put per shell.
for shell_name in zsh bash; do
    f="$HOME/.$shell_name/$shell_name-alias.local"
    if aliases_drop "$f" "${OUR_LINES[@]}"; then
        ok "$shell_name: moved $ALIAS_NAME out of ${f/#$HOME/\~}."
    fi
done

# ── 3. is one already there? ─────────────────────────────────────────────────
# Loose on purpose: this decides whether to LEAVE THINGS ALONE, so it errs wide.
if aliases_has '^[[:space:]]*alias[[:space:]]+[^=]+=.*\btemps\b'; then
    skip "An alias already runs temps — left exactly as it is."
    exit 0
fi
# Separately: is the NAME taken by something else? A second `alias b-temp=`
# would silently win over somebody's working alias.
if aliases_has "^[[:space:]]*alias[[:space:]]+$ALIAS_NAME="; then
    warn "'$ALIAS_NAME' is already an alias for something else — not touching it."
    warn "Add your own with: alias NAME=\"$ALIAS_CMD\"  in ${BLE_ALIASES_LOCAL/#$HOME/\~}"
    exit 0
fi

# ── 4. append it ─────────────────────────────────────────────────────────────
aliases_add "${OUR_LINES[@]}"
[[ "$DRY_RUN" == true ]] || \
    ok "Added alias $ALIAS_NAME=\"$ALIAS_CMD\" to ${BLE_ALIASES_LOCAL/#$HOME/\~} (open a new shell to use it)."
exit 0
