#!/usr/bin/env bash
# Playwright MCP — lets a coding agent drive a real, visible Firefox window.
# Desktop: Playwright's Firefox here + b-pw-display. Server: the Firefox of the PC
# that ssh'd in with b-pw-display. Either way, registered in every agent here.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

PW_CACHE="$HOME/.cache/ms-playwright"
# Snapshots and screenshots land here, not as .playwright-mcp/ inside the repo you test.
PW_OUT="$HOME/.cache/playwright-mcp"
# One profile for every folder, so a login in one repo holds in all of them.
# Firefox locks it: one agent at a time can have the browser open.
PW_PROFILE="$PW_OUT/firefox-profile"
PW_PKG="@playwright/mcp@latest"
PW_PORT="${PW_DISPLAY_PORT:-9323}"

DISPLAY_SRC="$BLE_ROOT/playwright-remote/b-pw-display"
DISPLAY_DST="$HOME/.local/bin/b-pw-display"
NOTE_SRC="$BLE_ROOT/playwright-remote/claude-note.md"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
NOTE_START='<!-- playwright-remote (best-linux-environment) -->'
NOTE_END='<!-- /playwright-remote -->'

# Desktop: the Firefox on this screen. Server: the one at the end of b-pw-display's
# ssh -R tunnel — no browser is installed here.
if is_desktop; then
    MCP_NAME=playwright
    PW_ARGS=(-y "$PW_PKG" --browser firefox --output-dir "$PW_OUT" --user-data-dir "$PW_PROFILE")
else
    MCP_NAME=playwright-remote
    PW_ARGS=(-y "$PW_PKG" --endpoint "ws://127.0.0.1:$PW_PORT/firefox" --output-dir "$PW_OUT")
fi

claude_bin=""
if   have_local_bin claude; then claude_bin="$HOME/.local/bin/claude"
elif has_cmd claude;        then claude_bin="$(command -v claude)"
fi
codex_cfg="$HOME/.codex/config.toml"
# Header of the [mcp_servers.<name>] table, and of its own sub-tables.
# Passed to awk through ENVIRON: -v would eat the backslashes under gawk.
codex_re() { printf '^\\[mcp_servers\\.%s(\\.|\\])' "$1"; }

# The note out of CLAUDE.md, start marker to end marker included.
strip_note() { awk -v s="$NOTE_START" -v e="$NOTE_END" '$0==s{on=1} !on; $0==e{on=0}' "$CLAUDE_MD"; }

# Registered in any agent here: on a server that is all there is to have.
is_registered() {
    local n="$1" oc_cfg
    jq -e --arg n "$n" '.mcpServers[$n]' "$HOME/.claude.json" >/dev/null 2>&1 && return 0
    for oc_cfg in "$HOME/.config/opencode/opencode.jsonc" "$HOME/.config/opencode/opencode.json"; do
        jq -e --arg n "$n" '.mcp[$n]' "$oc_cfg" >/dev/null 2>&1 && return 0
    done
    grep -qE "$(codex_re "$n")" "$codex_cfg" 2>/dev/null
}
is_installed() {
    if is_desktop; then compgen -G "$PW_CACHE/firefox-*/firefox/firefox" >/dev/null
    else is_registered "$MCP_NAME"
    fi
}

# Drop the NAME entry from every agent: one left pointing at a missing browser
# or tunnel fails at every start.
unregister() {
    local n="$1" oc_cfg new rest
    if [[ -z "$claude_bin" ]] || ! jq -e --arg n "$n" '.mcpServers[$n]' "$HOME/.claude.json" >/dev/null 2>&1; then
        :
    elif [[ "$DRY_RUN" == true ]]; then
        printf '%s  would run:%s claude mcp remove -s user %s\n' "$C_DIM" "$C_OFF" "$n"
    else
        "$claude_bin" mcp remove -s user "$n" >/dev/null \
            && ok "Claude Code: $n unregistered." \
            || warn "Claude Code: could not unregister $n — run: claude mcp remove -s user $n"
    fi
    for oc_cfg in "$HOME/.config/opencode/opencode.jsonc" "$HOME/.config/opencode/opencode.json"; do
        jq -e --arg n "$n" '.mcp[$n]' "$oc_cfg" >/dev/null 2>&1 || continue
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would drop:%s mcp.%s from %s\n' "$C_DIM" "$C_OFF" "$n" "${oc_cfg/#$HOME/\~}"
            continue
        fi
        new="$(jq --arg n "$n" 'del(.mcp[$n])' "$oc_cfg")"
        cp -a "$oc_cfg" "$oc_cfg.backup.$$"
        printf '%s\n' "$new" > "$oc_cfg"
        ok "opencode: $n unregistered from ${oc_cfg/#$HOME/\~}."
    done
    if grep -qE "$(codex_re "$n")" "$codex_cfg" 2>/dev/null; then
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would drop:%s [mcp_servers.%s] from %s\n' "$C_DIM" "$C_OFF" "$n" "${codex_cfg/#$HOME/\~}"
        else
            rest="$(re="$(codex_re "$n")" awk '/^\[/{on = ($0 ~ ENVIRON["re"])} !on' "$codex_cfg")"
            cp -a "$codex_cfg" "$codex_cfg.backup.$$"
            printf '%s\n' "$rest" > "$codex_cfg"
            ok "Codex: $n unregistered from ${codex_cfg/#$HOME/\~}."
        fi
    fi
}

[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }
if [[ "${1:-}" == --uninstall ]]; then
    title "Playwright MCP — uninstall"
    # Both names, whatever the profile: a machine may have been the other one once.
    unregister playwright
    unregister playwright-remote
    if grep -qsxF "$NOTE_START" "$CLAUDE_MD"; then
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would drop:%s the playwright-remote note from %s\n' "$C_DIM" "$C_OFF" "${CLAUDE_MD/#$HOME/\~}"
        else
            rest="$(strip_note)"
            printf '%s\n' "$rest" > "$CLAUDE_MD"
            ok "Note removed from ${CLAUDE_MD/#$HOME/\~}."
        fi
    fi
    # Only the Firefox build: other Playwright browsers in that cache belong to your projects.
    # $PW_OUT holds the shared profile; ms-playwright-mcp the per-folder ones of older setups.
    for d in "$PW_CACHE"/firefox-* "$PW_OUT" "$HOME/.cache/ms-playwright-mcp"/mcp-firefox-* "$DISPLAY_DST"; do
        [[ -e "$d" ]] || continue
        run rm -rf "$d"
        [[ "$DRY_RUN" == true ]] || ok "removed ${d/#$HOME/\~}"
    done
    ok "Playwright MCP removed. nodejs and npm stay — other tools may use them."
    exit 0
fi

if is_desktop; then
    title "Playwright MCP (Firefox, for coding agents here and on hosts you ssh into)"
else
    title "Playwright MCP (Firefox of the PC that ssh'd in with b-pw-display)"
fi

# npx comes with npm on Ubuntu; node is its dependency. A server needs it too:
# its MCP server is the Playwright client that reaches the tunnel.
apt_ensure nodejs npm

# ── 1. the browser (desktop only) ────────────────────────────────────────────
# Playwright cannot drive the system Firefox: it needs its own patched build, and
# the exact revision the current @latest expects. So this runs at every boot too —
# without it, a newer server looks for a build that isn't there and fails.
# b-pw-display serves this same build to the hosts you ssh into.
if is_server; then
    skip "Server profile — no browser here; b-pw-display on your PC brings one."
elif [[ "$DRY_RUN" == true ]]; then
    printf '%s  would run:%s npx %s install-browser firefox\n' "$C_DIM" "$C_OFF" "$PW_PKG"
else
    step "Making sure Playwright's Firefox build matches $PW_PKG"
    # Output only on failure: on success it is a "no package.json here" warning box.
    if pw_log="$(npx -y "$PW_PKG" install-browser firefox 2>&1)"; then
        ok "Playwright Firefox ready in ${PW_CACHE/#$HOME/\~}."
    else
        printf '%s\n' "$pw_log" | tail -5
        warn "Could not fetch Playwright's Firefox (offline?) — continuing."
    fi
fi
is_desktop && run mkdir -p "$PW_PROFILE"

# Global git ignore: catches a .playwright-mcp/ written by a server started without
# --output-dir (a project's own .mcp.json, an older entry) in every repo at once.
git_ignore="$(git config --global core.excludesFile 2>/dev/null || true)"
git_ignore="${git_ignore/#\~/$HOME}"
if [[ -z "$git_ignore" ]]; then
    git_ignore="$HOME/.config/git/ignore"   # git's default when excludesFile is unset
fi
ensure_line "$git_ignore" '^/?\.playwright-mcp/?$' '.playwright-mcp/'

# ── 2. register it in each agent that is installed ───────────────────────────
# Missing entry → added. Entry that differs → ./setup.sh resets it, ./boot.sh
# leaves it. An agent that isn't here is skipped, never installed.

# Claude Code — user scope in ~/.claude.json, so every project sees it.
if [[ -z "$claude_bin" ]]; then
    skip "Claude Code not installed — nothing to register."
else
    want="$(jq -cn --args '$ARGS.positional' -- "${PW_ARGS[@]}")"
    have="$(jq -c --arg n "$MCP_NAME" '.mcpServers[$n].args // empty' "$HOME/.claude.json" 2>/dev/null || true)"
    if [[ "$have" == "$want" ]]; then
        skip "Claude Code: $MCP_NAME already registered."
    elif [[ -n "$have" && "$BLE_FORCE" != true ]]; then
        skip "Claude Code: your $MCP_NAME entry differs — left as it is (./setup.sh resets it)."
    elif [[ "$DRY_RUN" == true ]]; then
        printf '%s  would run:%s claude mcp add -s user %s -- npx %s\n' "$C_DIM" "$C_OFF" "$MCP_NAME" "${PW_ARGS[*]}"
    else
        [[ -n "$have" ]] && "$claude_bin" mcp remove -s user "$MCP_NAME" >/dev/null 2>&1 || true
        "$claude_bin" mcp add -s user "$MCP_NAME" -- npx "${PW_ARGS[@]}" >/dev/null \
            && ok "Claude Code: $MCP_NAME registered (user scope)." \
            || warn "Claude Code: could not register $MCP_NAME."
    fi
fi

# opencode — the "mcp" key of its global config. jq can't read JSONC comments,
# so a commented file is left alone with the block to paste.
oc_dir="$HOME/.config/opencode"
if ! { have_local_bin opencode || have_opencode_bin || has_cmd opencode; }; then
    skip "opencode not installed — nothing to register."
else
    oc_cfg="$oc_dir/opencode.jsonc"
    [[ -f "$oc_cfg" ]] || oc_cfg="$oc_dir/opencode.json"
    entry="$(jq -cn --args '{type: "local", command: (["npx"] + $ARGS.positional), enabled: true}' -- "${PW_ARGS[@]}")"
    [[ -f "$oc_cfg" ]] || { [[ "$DRY_RUN" == true ]] || printf '{\n  "$schema": "https://opencode.ai/config.json"\n}\n' > "$oc_cfg"; }
    if [[ -f "$oc_cfg" ]] && ! jq empty "$oc_cfg" 2>/dev/null; then
        warn "opencode: ${oc_cfg/#$HOME/\~} has comments jq can't read — add this under \"mcp\" by hand:"
        warn "  \"$MCP_NAME\": $entry"
    else
        have="$(jq -c --arg n "$MCP_NAME" '.mcp[$n] // empty' "$oc_cfg" 2>/dev/null || true)"
        if [[ "$have" == "$entry" ]]; then
            skip "opencode: $MCP_NAME already registered."
        elif [[ -n "$have" && "$BLE_FORCE" != true ]]; then
            skip "opencode: your $MCP_NAME entry differs — left as it is (./setup.sh resets it)."
        elif [[ "$DRY_RUN" == true ]]; then
            printf '%s  would add:%s mcp.%s → %s\n' "$C_DIM" "$C_OFF" "$MCP_NAME" "${oc_cfg/#$HOME/\~}"
        else
            new="$(jq --arg n "$MCP_NAME" --argjson e "$entry" '.mcp[$n] = $e' "$oc_cfg")"
            cp -a "$oc_cfg" "$oc_cfg.backup.$$"
            # `cat >` and not `mv`, to keep the inode.
            printf '%s\n' "$new" > "$oc_cfg"
            ok "opencode: $MCP_NAME registered in ${oc_cfg/#$HOME/\~} (old copy: $(basename "$oc_cfg").backup.$$)."
        fi
    fi
fi

# Codex — a [mcp_servers.<name>] table in ~/.codex/config.toml.
if ! { has_cmd codex || [[ -d "$HOME/.codex" ]]; }; then
    skip "Codex not installed — nothing to register."
else
    toml_args="$(printf '"%s", ' "${PW_ARGS[@]}")"
    block="[mcp_servers.$MCP_NAME]
command = \"npx\"
args = [${toml_args%, }]"
    # The table as it stands: its header up to the next header that isn't one of its own.
    have="$(re="$(codex_re "$MCP_NAME")" awk '/^\[/{on = ($0 ~ ENVIRON["re"])} on' "$codex_cfg" 2>/dev/null \
        | sed -e '/^[[:space:]]*$/d' || true)"
    if [[ "$have" == "$block" ]]; then
        skip "Codex: $MCP_NAME already registered."
    elif [[ -n "$have" && "$BLE_FORCE" != true ]]; then
        skip "Codex: your $MCP_NAME entry differs — left as it is (./setup.sh resets it)."
    elif [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s [mcp_servers.%s] → %s\n' "$C_DIM" "$C_OFF" "$MCP_NAME" "${codex_cfg/#$HOME/\~}"
    else
        mkdir -p "$(dirname "$codex_cfg")"
        touch "$codex_cfg"
        rest="$(re="$(codex_re "$MCP_NAME")" awk '/^\[/{on = ($0 ~ ENVIRON["re"])} !on' "$codex_cfg")"
        [[ -n "$have" ]] && cp -a "$codex_cfg" "$codex_cfg.backup.$$"
        { [[ -n "$rest" ]] && printf '%s\n\n' "$rest"; printf '%s\n' "$block"; } > "$codex_cfg"
        ok "Codex: $MCP_NAME registered in ${codex_cfg/#$HOME/\~}."
    fi
fi

# ── 3a. desktop: b-pw-display, to lend this screen to a host ─────────────────
if is_desktop; then
    if cmp -s "$DISPLAY_SRC" "$DISPLAY_DST"; then
        skip "b-pw-display already current."
    else
        run mkdir -p "$HOME/.local/bin"
        run install -m 0755 "$DISPLAY_SRC" "$DISPLAY_DST"
        ok "b-pw-display installed to ~/.local/bin."
    fi
    ok "Playwright MCP ready — restart the agent, then ask it to open a page."
    ok "For an agent on another host: b-pw-display <user>@<host> instead of ssh."
    exit 0
fi

# ── 3b. server: the note in ~/.claude/CLAUDE.md ──────────────────────────────
# Tells every session here how the browser is reached, and what to say when the tunnel is down.
note="$(cat "$NOTE_SRC")"
if [[ -f "$CLAUDE_MD" ]] && grep -qxF "$NOTE_START" "$CLAUDE_MD"; then
    current="$(awk -v s="$NOTE_START" -v e="$NOTE_END" '$0==s{on=1} on; $0==e{on=0}' "$CLAUDE_MD")"
    if [[ "$current" == "$note" ]]; then
        skip "${CLAUDE_MD/#$HOME/\~} already has the playwright-remote note."
    elif [[ "$DRY_RUN" == true ]]; then
        printf '%s  would refresh:%s the playwright-remote note in %s\n' "$C_DIM" "$C_OFF" "${CLAUDE_MD/#$HOME/\~}"
    else
        rest="$(strip_note)"
        { printf '%s\n\n' "$rest"; printf '%s\n' "$note"; } > "$CLAUDE_MD"
        ok "Refreshed the playwright-remote note in ${CLAUDE_MD/#$HOME/\~}."
    fi
elif [[ "$DRY_RUN" == true ]]; then
    printf '%s  would append:%s the playwright-remote note → %s\n' "$C_DIM" "$C_OFF" "${CLAUDE_MD/#$HOME/\~}"
else
    mkdir -p "$(dirname "$CLAUDE_MD")"
    { [[ -s "$CLAUDE_MD" ]] && printf '\n'; printf '%s\n' "$note"; } >> "$CLAUDE_MD"
    ok "Added the playwright-remote note to ${CLAUDE_MD/#$HOME/\~}."
fi

ok "Ready. From your desktop: b-pw-display <user>@$(hostname), then start the agent there."
