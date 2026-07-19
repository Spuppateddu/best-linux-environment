#!/usr/bin/env bash
# Replicate my personal Ubuntu environment. Idempotent — re-run anytime to pick
# up newly added packages/apps; already-installed things are skipped.
#
# Usage:
#   ./install.sh                 # interactive: basic, tool menu, advanced apps
#   ./install.sh basic           # only the essentials (base, tools, fonts, …)
#   ./install.sh advanced        # only the optional-apps menu
#   ./install.sh all             # basic + every tool + every advanced app
#   ./install.sh advanced steam okular   # basic-free, install named apps
#   ./install.sh update          # non-interactive: pull this repo + every
#                                #   installed tool repo, re-apply configs
#                                #   (what the @reboot cron runs)
#   ./install.sh cron            # (re)install the @reboot auto-update cron
#   ./install.sh --dry-run all   # preview everything, touch nothing
#
# Target: Ubuntu 26.04 LTS. Expected to live at ~/best-linux-environment.

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

# Detect (or honour BLE_PROFILE=desktop|server) once, up front, and export it so
# every sub-script sees the same answer. On a server, GUI modules skip themselves.
export BLE_PROFILE="${BLE_PROFILE:-auto}"
step "Host profile: Ubuntu $(lsb_release -rs 2>/dev/null || echo '?') — $(profile_label)$([[ "$BLE_PROFILE" != auto ]] && echo " (forced via BLE_PROFILE)")"
is_server && skip "Server profile — GUI apps (i3, browsers, fonts, advanced apps) will be skipped."

# How basic/10-tools.sh treats the tool repos: menu | all | update.
export BLE_TOOLS_MODE="${BLE_TOOLS_MODE:-menu}"

# ── module runners ───────────────────────────────────────────────────────────
run_basic() {
    title "Basic environment"
    local m
    for m in "$HERE"/basic/*.sh; do
        [[ -e "$m" ]] || continue
        if [[ "$BLE_TOOLS_MODE" == update ]]; then
            # Boot-cron path: one broken module must not stop the others.
            bash "$m" || warn "Module $(basename "$m") failed — continuing."
        else
            bash "$m"
        fi
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
    is_server && { skip "Server profile — skipping advanced GUI apps."; return 0; }
    local SELECTED
    select_advanced
    [[ ${#SELECTED[@]} -eq 0 ]] && { skip "No advanced apps selected."; return; }
    title "Installing ${#SELECTED[@]} app(s): ${SELECTED[*]}"
    local app
    for app in "${SELECTED[@]}"; do run_advanced_one "$app"; done
}

run_advanced_all() {
    is_server && { skip "Server profile — skipping advanced GUI apps."; return 0; }
    title "All advanced apps"
    local n
    while IFS= read -r n; do run_advanced_one "$n"; done < <(advanced_names)
}

# ── update mode (the @reboot cron path) ──────────────────────────────────────
# Pull this repo first; if it changed, re-exec the NEW install.sh once so the
# rest of the update runs the freshly pulled code.
self_update() {
    local before after
    before="$(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo unknown)"
    step "Updating best-linux-environment itself"
    run git -C "$HERE" pull --ff-only --quiet \
        || warn "Could not pull $HERE — continuing with the current version."
    after="$(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo unknown)"
    if [[ "$before" != "$after" && "${BLE_SELF_UPDATED:-}" != 1 ]]; then
        ok "Repo updated — re-running the new install.sh."
        BLE_SELF_UPDATED=1 exec bash "$HERE/install.sh" update
    fi
}

run_update() {
    title "Update ($(date '+%F %T'))"
    self_update
    export BLE_TOOLS_MODE=update
    run_basic
}

# ── @reboot cron ─────────────────────────────────────────────────────────────
BLE_STATE_DIR="$HOME/.cache/best-linux-environment"

cron_installed() { crontab -l 2>/dev/null | grep -qF "$HERE/install.sh update"; }

install_cron() {
    if ! has_cmd crontab; then
        warn "crontab not found — install cron first: sudo apt install cron"
        return 1
    fi
    if cron_installed; then
        skip "Boot-update cron already installed."
        return 0
    fi
    local entry="@reboot sleep 45 && /usr/bin/env bash $HERE/install.sh update >> $BLE_STATE_DIR/update.log 2>&1"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would add cron:%s %s\n' "$C_DIM" "$C_OFF" "$entry"
        return 0
    fi
    mkdir -p "$BLE_STATE_DIR"
    (crontab -l 2>/dev/null || true; printf '%s\n' "$entry") | crontab -
    ok "Boot-update cron installed (log: $BLE_STATE_DIR/update.log)."
}

# First-install question: create the auto-update cron? A "no" is remembered so
# it's asked only once — re-add any time with ./install.sh cron.
offer_cron() {
    cron_installed && return 0
    local declined="$BLE_STATE_DIR/cron-declined"
    [[ -f "$declined" ]] && return 0
    title "Auto-update at boot"
    printf 'Add a @reboot cron that runs "install.sh update" (git pull this repo +\nevery tool repo, re-apply configs) at every boot? [y/N] '
    local reply; read -r reply || reply=n
    if [[ "$reply" =~ ^[yY] ]]; then
        install_cron
    else
        run mkdir -p "$BLE_STATE_DIR"
        run touch "$declined"
        skip "No cron — update by hand: ./install.sh update   (add later: ./install.sh cron)"
    fi
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
        export BLE_TOOLS_MODE=all
        run_basic
        run_advanced_all
        ;;
    update)
        run_update
        ;;
    cron)
        install_cron
        ;;
    interactive)
        run_basic
        run_advanced_menu
        offer_cron
        ;;
    -h|--help|help)
        grep '^#' "$0" | grep -v '^#!' | sed 's/^# \?//'
        exit 0
        ;;
    *)
        fail "Unknown mode '$mode'. Try: basic | advanced | all | update | cron | --help"
        exit 1
        ;;
esac

echo
ok "Done."
[[ "$DRY_RUN" == true ]] && warn "This was a --dry-run: nothing was changed."
