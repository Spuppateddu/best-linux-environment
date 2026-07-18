#!/usr/bin/env bash
# Tool config repos (zsh, vim, tmux, alacritty, i3 — listed in tools.conf):
# clone/update each into its hidden folder in $HOME and run the install.sh THE
# REPO ITSELF ships. This repo deliberately knows nothing about what a tool
# needs — only where it lives.
#
# Already-cloned tools are always pulled + re-installed (idempotent update);
# missing ones are offered in a menu. Modes via $BLE_TOOLS_MODE (set by
# install.sh):
#   menu    (default) update the cloned tools, then offer the missing ones
#   all     update + install every tool, no questions
#   update  only update already-cloned tools (the boot-cron path)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MODE="${BLE_TOOLS_MODE:-menu}"
CONF="$BLE_ROOT/tools.conf"

title "Tool config repos"

# Parse tools.conf into parallel arrays (order preserved).
NAMES=(); URLS=(); DESTS=()
while IFS='|' read -r name url dest; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    NAMES+=("$name"); URLS+=("$url"); DESTS+=("${dest/#\~/$HOME}")
done < "$CONF"

tool_cloned() { [[ -d "${DESTS[$1]}/.git" ]]; }

# Clone/update one tool, then hand over to the script its repo ships.
install_tool() {
    local name="${NAMES[$1]}" url="${URLS[$1]}" dest="${DESTS[$1]}"
    title "Tool: $name"
    clone_or_pull "$url" "$dest"
    if [[ -f "$dest/install.sh" ]]; then
        step "Running $name's own install.sh"
        (cd "$dest" && bash ./install.sh)
    else
        warn "$name ships no install.sh — repo updated, nothing else run."
    fi
}

# ── Pass 1: every tool already on disk gets pulled + its installer re-run ────
any_cloned=false
for i in "${!NAMES[@]}"; do
    if tool_cloned "$i"; then
        any_cloned=true
        install_tool "$i"
    fi
done
[[ "$any_cloned" == false ]] && skip "No tool repos cloned yet."

[[ "$MODE" == update ]] && exit 0

# ── Pass 2: install the missing ones (all, or menu selection) ────────────────
missing=()
for i in "${!NAMES[@]}"; do
    tool_cloned "$i" || missing+=("$i")
done
if [[ ${#missing[@]} -eq 0 ]]; then
    ok "All tools installed."
    exit 0
fi

if [[ "$MODE" == all ]]; then
    for i in "${missing[@]}"; do install_tool "$i"; done
    exit 0
fi

printf '\nNot installed yet:\n'
for j in "${!missing[@]}"; do
    printf '  %s%2d%s  %s\n' "$C_BLUE" "$((j + 1))" "$C_OFF" "${NAMES[${missing[$j]}]}"
done
printf '\nPick numbers (e.g. "1 3"), %sall%s, or %sq%s for none: ' \
    "$C_GREEN" "$C_OFF" "$C_DIM" "$C_OFF"

read -r reply || reply=q
selected=()
case "$reply" in
    q|Q|"") ;;
    all|ALL|a) selected=("${missing[@]}") ;;
    *)
        for tok in $reply; do
            if [[ "$tok" =~ ^[0-9]+$ ]] && (( tok >= 1 && tok <= ${#missing[@]} )); then
                selected+=("${missing[$((tok - 1))]}")
            else
                warn "Ignoring invalid choice: $tok"
            fi
        done
        ;;
esac

if [[ ${#selected[@]} -eq 0 ]]; then
    skip "No tools selected."
    exit 0
fi
for i in "${selected[@]}"; do install_tool "$i"; done
