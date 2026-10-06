#!/usr/bin/env bash
# playwright-remote — the host half: Claude Code drives a Firefox window on the
# screen of whoever ssh'd in with b-pw-display. No browser is installed here.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

NAME=playwright-remote
ENDPOINT="ws://127.0.0.1:${PW_DISPLAY_PORT:-9323}/firefox"
PW_ARGS=(-y @playwright/mcp@latest --endpoint "$ENDPOINT" --output-dir "$HOME/.cache/playwright-mcp")
NOTE_SRC="$BLE_ROOT/playwright-remote/claude-note.md"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
NOTE_START='<!-- playwright-remote (best-linux-environment) -->'
NOTE_END='<!-- /playwright-remote -->'

claude_bin=""
if   have_local_bin claude; then claude_bin="$HOME/.local/bin/claude"
elif has_cmd claude;        then claude_bin="$(command -v claude)"
fi

# The note out of CLAUDE.md, start marker to end marker included.
strip_note() { awk -v s="$NOTE_START" -v e="$NOTE_END" '$0==s{on=1} !on; $0==e{on=0}' "$CLAUDE_MD"; }

is_installed() { jq -e --arg n "$NAME" '.mcpServers[$n]' "$HOME/.claude.json" >/dev/null 2>&1; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }
if [[ "${1:-}" == --uninstall ]]; then
    title "playwright-remote — uninstall"
    if [[ -n "$claude_bin" ]] && is_installed; then
        run "$claude_bin" mcp remove -s user "$NAME" >/dev/null && ok "Claude Code: $NAME unregistered."
    fi
    if grep -qsxF "$NOTE_START" "$CLAUDE_MD"; then
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would drop:%s the %s note from %s\n' "$C_DIM" "$C_OFF" "$NAME" "${CLAUDE_MD/#$HOME/\~}"
        else
            rest="$(strip_note)"
            printf '%s\n' "$rest" > "$CLAUDE_MD"
            ok "Note removed from ${CLAUDE_MD/#$HOME/\~}."
        fi
    fi
    exit 0
fi

title "playwright-remote (Claude drives the Firefox of the PC that ssh'd in)"
apt_ensure nodejs npm

if [[ -z "$claude_bin" ]]; then
    warn "Claude Code not installed — nothing to register. Tick this again after installing it."
    exit 0
fi

# ── 1. the MCP server, user scope ────────────────────────────────────────────
want="$(jq -cn --args '$ARGS.positional' -- "${PW_ARGS[@]}")"
have="$(jq -c --arg n "$NAME" '.mcpServers[$n].args // empty' "$HOME/.claude.json" 2>/dev/null || true)"
if [[ "$have" == "$want" ]]; then
    skip "Claude Code: $NAME already registered."
elif [[ -n "$have" && "$BLE_FORCE" != true ]]; then
    skip "Claude Code: your $NAME entry differs — left as it is (./setup.sh resets it)."
elif [[ "$DRY_RUN" == true ]]; then
    printf '%s  would run:%s claude mcp add -s user %s -- npx %s\n' "$C_DIM" "$C_OFF" "$NAME" "${PW_ARGS[*]}"
else
    [[ -n "$have" ]] && "$claude_bin" mcp remove -s user "$NAME" >/dev/null 2>&1 || true
    "$claude_bin" mcp add -s user "$NAME" -- npx "${PW_ARGS[@]}" >/dev/null \
        && ok "Claude Code: $NAME registered → $ENDPOINT." \
        || warn "Claude Code: could not register $NAME."
fi

# ── 2. the note in ~/.claude/CLAUDE.md ───────────────────────────────────────
# Tells every session here how the browser is reached, and what to say when the tunnel is down.
note="$(cat "$NOTE_SRC")"
if [[ -f "$CLAUDE_MD" ]] && grep -qxF "$NOTE_START" "$CLAUDE_MD"; then
    current="$(awk -v s="$NOTE_START" -v e="$NOTE_END" '$0==s{on=1} on; $0==e{on=0}' "$CLAUDE_MD")"
    if [[ "$current" == "$note" ]]; then
        skip "${CLAUDE_MD/#$HOME/\~} already has the $NAME note."
    elif [[ "$DRY_RUN" == true ]]; then
        printf '%s  would refresh:%s the %s note in %s\n' "$C_DIM" "$C_OFF" "$NAME" "${CLAUDE_MD/#$HOME/\~}"
    else
        rest="$(strip_note)"
        { printf '%s\n\n' "$rest"; printf '%s\n' "$note"; } > "$CLAUDE_MD"
        ok "Refreshed the $NAME note in ${CLAUDE_MD/#$HOME/\~}."
    fi
elif [[ "$DRY_RUN" == true ]]; then
    printf '%s  would append:%s the %s note → %s\n' "$C_DIM" "$C_OFF" "$NAME" "${CLAUDE_MD/#$HOME/\~}"
else
    mkdir -p "$(dirname "$CLAUDE_MD")"
    { [[ -s "$CLAUDE_MD" ]] && printf '\n'; printf '%s\n' "$note"; } >> "$CLAUDE_MD"
    ok "Added the $NAME note to ${CLAUDE_MD/#$HOME/\~}."
fi

ok "Ready. From a desktop: b-pw-display <user>@$(hostname), then start claude there."
