#!/usr/bin/env bash
# One alias, `fn`, added to <shell>-alias.local (gitignored, so machine-local) for
# both shells: creates/opens ~/fastnote.txt in vim. Never over an alias you have.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

ALIAS_NAME="fn"
ALIAS_CMD='touch ~/fastnote.txt && vim ~/fastnote.txt'

# Both config repos name things the same way: ~/.<shell>/<shell>-alias(.local).
SHELLS=(zsh bash)

title "fastnote alias for your shell ($ALIAS_NAME)"

# ── 1. is vim here? ──────────────────────────────────────────────────────────
if ! has_cmd vim; then
    skip "vim is not installed — nothing to alias."
    exit 0
fi

# grep without -q (a SIGPIPE'd grep reads as "no match" under pipefail), across
# both files: the alias may have been committed as easily as written by us.
grep_aliases() {
    local pattern="$1"; shift
    local files=() f
    for f in "$@"; do [[ -f "$f" ]] && files+=("$f"); done
    [[ ${#files[@]} -gt 0 ]] || return 1
    grep -hE "$pattern" "${files[@]}" >/dev/null 2>&1
}

# ── 2. one shell at a time ───────────────────────────────────────────────────
# `did_one` tells "no shell config here" from "the alias is in place" at the end.
did_one=false
for shell_name in "${SHELLS[@]}"; do
    config_dir="$HOME/.$shell_name"
    alias_file="$config_dir/$shell_name-alias"
    local_file="$alias_file.local"
    label="${local_file/#$HOME/\~}"

    # The tracked file sources the .local one, and a config needs a shell to read it.
    if ! has_cmd "$shell_name"; then
        skip "$shell_name is not installed — skipping its alias file."
        continue
    fi
    if [[ ! -f "$alias_file" ]]; then
        skip "No $shell_name config wired in (${alias_file/#$HOME/\~}) — nowhere to put the alias."
        continue
    fi
    did_one=true

    # Loose on purpose: this decides whether to LEAVE THINGS ALONE, so it errs wide.
    if grep_aliases '^[[:space:]]*alias[[:space:]]+[^=]+=.*fastnote\.txt' "$alias_file" "$local_file"; then
        skip "$shell_name: an alias already opens fastnote.txt — left exactly as it is."
        continue
    fi
    # Separately: is the NAME taken? A second `alias fn=` would silently win.
    if grep_aliases "^[[:space:]]*alias[[:space:]]+$ALIAS_NAME=" "$alias_file" "$local_file"; then
        warn "$shell_name: '$ALIAS_NAME' is already an alias for something else — not touching it."
        warn "Add your own with: alias NAME='$ALIAS_CMD'  in $label"
        continue
    fi

    # ── append it ────────────────────────────────────────────────────────────
    # Appended, never config_write: that owns a whole file, and this one is yours.
    if [[ "$DRY_RUN" == true ]]; then
        printf "%s  would append:%s alias %s='%s' → %s\n" \
            "$C_DIM" "$C_OFF" "$ALIAS_NAME" "$ALIAS_CMD" "$label"
        continue
    fi

    # A hand-edited file with no trailing newline would otherwise get the alias
    # glued onto its last line.
    if [[ -s "$local_file" ]] && [[ -n "$(tail -c 1 "$local_file")" ]]; then
        printf '\n' >> "$local_file"
    fi

    {
        printf '\n'
        printf '# Quick scratch note: create/open ~/fastnote.txt in vim. Added by\n'
        printf '# best-linux-environment.\n'
        printf "alias %s='%s'\n" "$ALIAS_NAME" "$ALIAS_CMD"
    } >> "$local_file"

    ok "$shell_name: added alias $ALIAS_NAME='$ALIAS_CMD' to $label (open a new shell to use it)."
done

[[ "$did_one" == false ]] && \
    skip "No shell config repo is wired in — run ./setup.sh and pick zsh or bash."
exit 0
