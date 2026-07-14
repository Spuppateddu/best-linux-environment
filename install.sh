#!/usr/bin/env bash
# Replicate my personal Ubuntu environment. Idempotent — re-run anytime to pick
# up newly added packages/apps; already-installed things are skipped.
#
# Usage:
#   ./install.sh                 # interactive: basic, then pick advanced apps
#   ./install.sh basic           # only the essentials (shell, editor, tmux, i3)
#   ./install.sh advanced        # only the optional-apps menu
#   ./install.sh all             # basic + every advanced app, no prompts
#   ./install.sh advanced steam okular   # basic-free, install named apps
#   ./install.sh --dry-run all   # preview everything, touch nothing
#
# Target: Ubuntu 26.04 LTS.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

# --dry-run may appear anywhere; strip it and export for every sub-script.
ARGS=()
for a in "$@"; do
    case "$a" in
        --dry-run) DRY_RUN=true ;;
        *) ARGS+=("$a") ;;
    esac
done
export DRY_RUN
set -- "${ARGS[@]:-}"

require_apt

# ── module runners ───────────────────────────────────────────────────────────
run_basic() {
    title "Basic environment"
    local m
    for m in "$HERE"/basic/*.sh; do
        [[ -e "$m" ]] || continue
        bash "$m"
    done
}

# List advanced modules as bare names (steam, okular, ...).
advanced_names() {
    local f
    for f in "$HERE"/advanced/*.sh; do
        [[ -e "$f" ]] || continue
        basename "$f" .sh
    done
}

# True if the advanced app is already installed (module answers its own --check).
app_is_installed() {
    bash "$HERE/advanced/$1.sh" --check >/dev/null 2>&1
}

run_advanced_one() {
    local name="$1"
    local script="$HERE/advanced/$name.sh"
    if [[ ! -f "$script" ]]; then
        fail "Unknown app '$name'. Available: $(advanced_names | tr '\n' ' ')"
        return 1
    fi
    bash "$script"
}

# Interactive multi-select. Only lists apps that are NOT already installed.
# Populates the global SELECTED array.
select_advanced() {
    local n avail=() installed=()
    while IFS= read -r n; do
        if app_is_installed "$n"; then installed+=("$n"); else avail+=("$n"); fi
    done < <(advanced_names)
    SELECTED=()

    title "Advanced apps"
    [[ ${#installed[@]} -gt 0 ]] && skip "Already installed (hidden): ${installed[*]}"
    if [[ ${#avail[@]} -eq 0 ]]; then
        ok "Every advanced app is already installed."
        return
    fi

    local i
    for i in "${!avail[@]}"; do
        printf '  %s%2d%s  %s\n' "$C_BLUE" "$((i + 1))" "$C_OFF" "${avail[$i]}"
    done
    printf '\nPick numbers (e.g. "1 3 4"), %sall%s, or %sq%s to skip: ' \
        "$C_GREEN" "$C_OFF" "$C_DIM" "$C_OFF"

    local reply; read -r reply
    case "$reply" in
        q|Q|"") return ;;
        all|ALL|a) SELECTED=("${avail[@]}") ;;
        *)
            local tok
            for tok in $reply; do
                if [[ "$tok" =~ ^[0-9]+$ ]] && (( tok >= 1 && tok <= ${#avail[@]} )); then
                    SELECTED+=("${avail[$((tok - 1))]}")
                else
                    warn "Ignoring invalid choice: $tok"
                fi
            done
            ;;
    esac
}

run_advanced_menu() {
    local SELECTED
    select_advanced
    [[ ${#SELECTED[@]} -eq 0 ]] && { skip "No advanced apps selected."; return; }
    title "Installing ${#SELECTED[@]} app(s): ${SELECTED[*]}"
    local app
    for app in "${SELECTED[@]}"; do run_advanced_one "$app"; done
}

run_advanced_all() {
    title "All advanced apps"
    local n
    while IFS= read -r n; do run_advanced_one "$n"; done < <(advanced_names)
}

# ── dispatch ─────────────────────────────────────────────────────────────────
mode="${1:-interactive}"
shift || true

case "$mode" in
    basic)
        run_basic
        ;;
    advanced)
        if [[ $# -gt 0 ]]; then
            for app in "$@"; do run_advanced_one "$app"; done
        else
            run_advanced_menu
        fi
        ;;
    all)
        run_basic
        run_advanced_all
        ;;
    interactive)
        run_basic
        run_advanced_menu
        ;;
    -h|--help|help)
        grep '^#' "$0" | grep -v '^#!' | sed 's/^# \?//'
        exit 0
        ;;
    *)
        fail "Unknown mode '$mode'. Try: basic | advanced | all | --help"
        exit 1
        ;;
esac

echo
ok "Done."
[[ "$DRY_RUN" == true ]] && warn "This was a --dry-run: nothing was changed."
