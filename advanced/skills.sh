#!/usr/bin/env bash
# Your skills repo for Claude Code: cloned into ~/code/skills (pulled when it
# is already there), ~/.claude/skills linked to it so every skill loads, and
# ~/.claude/CLAUDE.md importing its global-rules.md. An import, not a copy: the
# rules Claude reads are always the ones in the clone, so a git pull updates them.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SKILLS_URL="https://github.com/Spuppateddu/skills.git"
SKILLS_DIR="$HOME/code/skills"
SKILLS_LINK="$HOME/.claude/skills"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
IMPORT_LINE='@~/code/skills/global-rules.md'
# Also matches the same import written with the full path.
IMPORT_RE='^@(~|'"$HOME"')/code/skills/global-rules\.md[[:space:]]*$'

is_linked() { [[ -L "$SKILLS_LINK" && "$(readlink "$SKILLS_LINK")" == "$SKILLS_DIR" ]]; }
is_imported() { grep -Eqs -- "$IMPORT_RE" "$CLAUDE_MD"; }
is_installed() { [[ -d "$SKILLS_DIR/.git" ]] && is_linked && is_imported; }

[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }
if [[ "${1:-}" == --uninstall ]]; then
    title "skills — uninstall"
    if is_linked; then
        run rm "$SKILLS_LINK"
        [[ "$DRY_RUN" == true ]] || ok "removed the ~/.claude/skills link"
    fi
    if is_imported; then
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would drop:%s %s from %s\n' "$C_DIM" "$C_OFF" "$IMPORT_LINE" "${CLAUDE_MD/#$HOME/\~}"
        else
            rest="$(grep -Ev -- "$IMPORT_RE" "$CLAUDE_MD" || true)"
            printf '%s\n' "$rest" > "$CLAUDE_MD"
            ok "Global rules import removed from ${CLAUDE_MD/#$HOME/\~}."
        fi
    fi
    # Your own repo: it may hold local skills or work you have not pushed.
    ok "skills unhooked from Claude Code. The clone in ~/code/skills is kept."
    exit 0
fi

title "skills (~/code/skills → Claude Code)"

# ── 1. the clone ─────────────────────────────────────────────────────────────
# Pulled like the config repos: fast-forward only, your uncommitted edits kept.
if [[ -e "$SKILLS_DIR" && ! -d "$SKILLS_DIR/.git" ]]; then
    warn "~/code/skills exists but is not a git checkout — not touching it."
    warn "Move it away and re-run ./setup.sh to clone $SKILLS_URL there."
    exit 1
fi
apt_ensure git
run mkdir -p "$HOME/code"
clone_or_pull "$SKILLS_URL" "$SKILLS_DIR"

# ── 2. every skill → ~/.claude/skills ────────────────────────────────────────
# A real folder there is backed up first (link does that), never deleted.
link "$SKILLS_DIR" "$SKILLS_LINK"

# ── 3. the global rules → ~/.claude/CLAUDE.md ────────────────────────────────
# Appended, so whatever else is in that file (the playwright-mcp note) stays.
ensure_line "$CLAUDE_MD" "$IMPORT_RE" "$IMPORT_LINE"

ok "skills ready — Claude Code loads them and the global rules at its next start."
