#!/usr/bin/env bash
# Playwright MCP — lets a coding agent drive a real, visible Firefox window:
# Playwright's own Firefox build, then the server registered in every agent here.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

PW_CACHE="$HOME/.cache/ms-playwright"
# Snapshots and screenshots land here, not as .playwright-mcp/ inside the repo you test.
PW_OUT="$HOME/.cache/playwright-mcp"
# One profile for every folder, so a login in one repo holds in all of them.
# Firefox locks it: one agent at a time can have the browser open.
PW_PROFILE="$PW_OUT/firefox-profile"
PW_PKG="@playwright/mcp@latest"
PW_ARGS=(-y "$PW_PKG" --browser firefox --output-dir "$PW_OUT" --user-data-dir "$PW_PROFILE")

is_installed() { compgen -G "$PW_CACHE/firefox-*/firefox/firefox" >/dev/null; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }
if [[ "${1:-}" == --uninstall ]]; then
    title "Playwright MCP — uninstall"
    # The agent entries first: one left pointing at a deleted browser fails at every start.
    claude_bin=""
    if   have_local_bin claude; then claude_bin="$HOME/.local/bin/claude"
    elif has_cmd claude;        then claude_bin="$(command -v claude)"
    fi
    if [[ -z "$claude_bin" ]] || ! jq -e '.mcpServers.playwright' "$HOME/.claude.json" >/dev/null 2>&1; then
        :
    elif [[ "$DRY_RUN" == true ]]; then
        printf '%s  would run:%s claude mcp remove -s user playwright\n' "$C_DIM" "$C_OFF"
    else
        "$claude_bin" mcp remove -s user playwright >/dev/null \
            && ok "Claude Code: playwright unregistered." \
            || warn "Claude Code: could not unregister playwright — run: claude mcp remove -s user playwright"
    fi
    for oc_cfg in "$HOME/.config/opencode/opencode.jsonc" "$HOME/.config/opencode/opencode.json"; do
        jq -e '.mcp.playwright' "$oc_cfg" >/dev/null 2>&1 || continue
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would drop:%s mcp.playwright from %s\n' "$C_DIM" "$C_OFF" "${oc_cfg/#$HOME/\~}"
            continue
        fi
        new="$(jq 'del(.mcp.playwright)' "$oc_cfg")"
        cp -a "$oc_cfg" "$oc_cfg.backup.$$"
        printf '%s\n' "$new" > "$oc_cfg"
        ok "opencode: playwright unregistered from ${oc_cfg/#$HOME/\~}."
    done
    codex_cfg="$HOME/.codex/config.toml"
    if grep -qE '^\[mcp_servers\.playwright(\.|\])' "$codex_cfg" 2>/dev/null; then
        if [[ "$DRY_RUN" == true ]]; then
            printf '%s  would drop:%s [mcp_servers.playwright] from %s\n' "$C_DIM" "$C_OFF" "${codex_cfg/#$HOME/\~}"
        else
            rest="$(awk '/^\[/{on = ($0 ~ /^\[mcp_servers\.playwright(\.|\])/)} !on' "$codex_cfg")"
            cp -a "$codex_cfg" "$codex_cfg.backup.$$"
            printf '%s\n' "$rest" > "$codex_cfg"
            ok "Codex: playwright unregistered from ${codex_cfg/#$HOME/\~}."
        fi
    fi
    # Only the Firefox build: other Playwright browsers in that cache belong to your projects.
    # $PW_OUT holds the shared profile; ms-playwright-mcp the per-folder ones of older setups.
    for d in "$PW_CACHE"/firefox-* "$PW_OUT" "$HOME/.cache/ms-playwright-mcp"/mcp-firefox-*; do
        [[ -e "$d" ]] || continue
        run rm -rf "$d"
        [[ "$DRY_RUN" == true ]] || ok "removed ${d/#$HOME/\~}"
    done
    ok "Playwright MCP removed. nodejs and npm stay — other tools may use them."
    exit 0
fi

title "Playwright MCP (Firefox, for coding agents)"

# npx comes with npm on Ubuntu; node is its dependency.
apt_ensure nodejs npm

# ── 1. the browser ───────────────────────────────────────────────────────────
# Playwright cannot drive the system Firefox: it needs its own patched build, and
# the exact revision the current @latest expects. So this runs at every boot too —
# without it, a newer server looks for a build that isn't there and fails.
if [[ "$DRY_RUN" == true ]]; then
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
run mkdir -p "$PW_PROFILE"

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
claude_bin=""
if   have_local_bin claude; then claude_bin="$HOME/.local/bin/claude"
elif has_cmd claude;        then claude_bin="$(command -v claude)"
fi
if [[ -z "$claude_bin" ]]; then
    skip "Claude Code not installed — nothing to register."
else
    want="$(jq -cn --args '$ARGS.positional' -- "${PW_ARGS[@]}")"
    have="$(jq -c '.mcpServers.playwright.args // empty' "$HOME/.claude.json" 2>/dev/null || true)"
    if [[ "$have" == "$want" ]]; then
        skip "Claude Code: playwright already registered."
    elif [[ -n "$have" && "$BLE_FORCE" != true ]]; then
        skip "Claude Code: your playwright entry differs — left as it is (./setup.sh resets it)."
    elif [[ "$DRY_RUN" == true ]]; then
        printf '%s  would run:%s claude mcp add -s user playwright -- npx %s\n' "$C_DIM" "$C_OFF" "${PW_ARGS[*]}"
    else
        [[ -n "$have" ]] && "$claude_bin" mcp remove -s user playwright >/dev/null 2>&1 || true
        "$claude_bin" mcp add -s user playwright -- npx "${PW_ARGS[@]}" >/dev/null \
            && ok "Claude Code: playwright registered (user scope)." \
            || warn "Claude Code: could not register playwright."
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
        warn "  \"playwright\": $entry"
    else
        have="$(jq -c '.mcp.playwright // empty' "$oc_cfg" 2>/dev/null || true)"
        if [[ "$have" == "$entry" ]]; then
            skip "opencode: playwright already registered."
        elif [[ -n "$have" && "$BLE_FORCE" != true ]]; then
            skip "opencode: your playwright entry differs — left as it is (./setup.sh resets it)."
        elif [[ "$DRY_RUN" == true ]]; then
            printf '%s  would add:%s mcp.playwright → %s\n' "$C_DIM" "$C_OFF" "${oc_cfg/#$HOME/\~}"
        else
            new="$(jq --argjson e "$entry" '.mcp.playwright = $e' "$oc_cfg")"
            cp -a "$oc_cfg" "$oc_cfg.backup.$$"
            # `cat >` and not `mv`, to keep the inode.
            printf '%s\n' "$new" > "$oc_cfg"
            ok "opencode: playwright registered in ${oc_cfg/#$HOME/\~} (old copy: $(basename "$oc_cfg").backup.$$)."
        fi
    fi
fi

# Codex — a [mcp_servers.playwright] table in ~/.codex/config.toml.
codex_cfg="$HOME/.codex/config.toml"
if ! { has_cmd codex || [[ -d "$HOME/.codex" ]]; }; then
    skip "Codex not installed — nothing to register."
else
    toml_args="$(printf '"%s", ' "${PW_ARGS[@]}")"
    block="[mcp_servers.playwright]
command = \"npx\"
args = [${toml_args%, }]"
    # The table as it stands: its header up to the next header that isn't one of its own.
    have="$(awk '/^\[/{on = ($0 ~ /^\[mcp_servers\.playwright(\.|\])/)} on' "$codex_cfg" 2>/dev/null \
        | sed -e '/^[[:space:]]*$/d' || true)"
    if [[ "$have" == "$block" ]]; then
        skip "Codex: playwright already registered."
    elif [[ -n "$have" && "$BLE_FORCE" != true ]]; then
        skip "Codex: your playwright entry differs — left as it is (./setup.sh resets it)."
    elif [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s [mcp_servers.playwright] → %s\n' "$C_DIM" "$C_OFF" "${codex_cfg/#$HOME/\~}"
    else
        mkdir -p "$(dirname "$codex_cfg")"
        touch "$codex_cfg"
        rest="$(awk '/^\[/{on = ($0 ~ /^\[mcp_servers\.playwright(\.|\])/)} !on' "$codex_cfg")"
        [[ -n "$have" ]] && cp -a "$codex_cfg" "$codex_cfg.backup.$$"
        { [[ -n "$rest" ]] && printf '%s\n\n' "$rest"; printf '%s\n' "$block"; } > "$codex_cfg"
        ok "Codex: playwright registered in ${codex_cfg/#$HOME/\~}."
    fi
fi

ok "Playwright MCP ready — restart the agent, then ask it to open a page."
