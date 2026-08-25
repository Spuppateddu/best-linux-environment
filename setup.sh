#!/usr/bin/env bash
# The one thing you run by hand, and a reset as much as an install. Target: Ubuntu
# 26.04 LTS at ~/best-linux-environment. `./setup.sh --help` for the rest.

set -euo pipefail

usage() {
    cat <<'EOF'
The one thing you run by hand. No arguments to remember, no mode to pick.

It goes in this order, and the order is the point:

  1. Mass install.  Everything in modules.conf's `necessary` tier, in a single
     apt-get call. Not asked about — the substrate (git, curl, a compiler) and
     the programs your config repos name (the i3 config binds keys to
     alacritty, firefox and flameshot; the zshrc calls yazi and lazygit). A
     missing one of those is a broken environment, not a preference.

  2. Every question, together, once.  Two checkbox lists — your config repos,
     then the extra applications — plus vim's per-language support as a third
     list rather than four yes/no prompts. Arrow keys to move, space to tick.
     Anything already on the machine is shown as such instead of asked about.

  3. Install what you ticked.  From here on nothing stops to ask: the answers
     are already in hand, including the ones the tool repos' own installers
     would otherwise have wanted (vim's languages are passed down as a flag).

  4. Say what happened.  What went in, what failed, and what you ticked that
     still isn't there.

Run it again any time. What is already here stays and moves forward, and config
this repo owns goes back to the repo's version (your copy is backed up first).

Usage:
  ./setup.sh                  the whole thing, as described above
  ./setup.sh --list           print the three tiers and exit, touching nothing
  ./setup.sh only ID [ID…]    install just these, no questions (ids from --list)
  ./setup.sh --dry-run        preview everything, change nothing

Its counterpart is ./boot.sh, which the @reboot cron runs: git pull everything,
re-apply the configs, ask nothing, install nothing new.

Target: Ubuntu 26.04 LTS. Expected to live at ~/best-linux-environment.
EOF
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# You asked for this run, so it may re-assert what the repo owns. See lib/common.sh.
export BLE_MODE=setup
BLE_ENTRY="$HERE/setup.sh"

DRY_RUN=false
LIST_ONLY=false
ONLY=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --list|list) LIST_ONLY=true ;;
        only) shift; ONLY=("$@"); break ;;
        -h|--help|help) usage; exit 0 ;;
        *)
            printf '✗ Unknown argument '\''%s'\''. Try: ./setup.sh [--list] [--dry-run] [only ID…]\n' "$1" >&2
            exit 1
            ;;
    esac
    shift
done
export DRY_RUN

# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=lib/runner.sh
source "$HERE/lib/runner.sh"
# shellcheck source=lib/ui.sh
source "$HERE/lib/ui.sh"
# shellcheck source=lib/registry.sh
source "$HERE/lib/registry.sh"

require_apt

# Detected (or forced with BLE_PROFILE) once and exported, so every sub-script
# agrees. On a server the gui entries drop out of modules.conf as it loads.
export BLE_PROFILE="${BLE_PROFILE:-auto}"

registry_load

# in_list NEEDLE HAY…  — plain membership, spelled out once rather than as a
# `[[ " ${arr[*]} " == *" $x "* ]]` that goes wrong the day a value has a space.
in_list() {
    local needle="$1" x
    shift
    for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
    return 1
}

# Everything you have ever ticked, one id per line, read back to pre-tick the
# secondary list so a second run offers the machine you already chose.
CHOSEN_FILE="$BLE_STATE_DIR/chosen"
was_chosen() { [[ -f "$CHOSEN_FILE" ]] && grep -Fxq "$1" "$CHOSEN_FILE"; }
remember() {
    [[ "$DRY_RUN" == true ]] && return 0
    mkdir -p "$BLE_STATE_DIR"
    was_chosen "$1" || printf '%s\n' "$1" >> "$CHOSEN_FILE"
}

# ── --list ───────────────────────────────────────────────────────────────────
if [[ "$LIST_ONLY" == true ]]; then
    for tier in necessary core secondary; do
        case "$tier" in
            necessary) title "NECESSARY — always installed, never asked" ;;
            core)      title "CORE — your config repos (checkbox list, all pre-ticked)" ;;
            secondary) title "SECONDARY — extra apps (checkbox list, none pre-ticked)" ;;
        esac
        while read -r i; do
            if mod_installed "$i"; then mark="${C_GREEN}✓${C_OFF}"; else mark="${C_DIM}·${C_OFF}"; fi
            printf ' %s %-14s %s\n' "$mark" "${M_ID[$i]}" "${M_LABEL[$i]}"
        done < <(mod_indices "$tier")
    done
    printf '\n%s✓ installed · not yet. Change a tier by moving its line in modules.conf.%s\n' \
        "$C_DIM" "$C_OFF"
    exit 0
fi

title "Setup — Ubuntu $(lsb_release -rs 2>/dev/null || echo '?'), $(profile_label) profile"
is_server && skip "Server profile — desktop-only entries are not listed and not installed."

# First, because this is the only script with a terminal to ask on; every later
# privileged step has no stdin. Failure is fine — see warm_sudo in lib/common.sh.
warm_sudo || skip "No sudo available — steps needing root will be skipped and named."

# ── only ID… ─────────────────────────────────────────────────────────────────
# The escape hatch: install one named thing, no questions and no mass install.
if [[ ${#ONLY[@]} -gt 0 ]]; then
    # Naming a shell config here IS the answer to the shell question: there are no
    # lists on this path, so otherwise the remembered answer would keep the shell.
    for want in "${ONLY[@]}"; do
        case "$want" in
            zsh-config)  BLE_SHELL=zsh ;;
            bash-config) BLE_SHELL=bash ;;
            *) continue ;;
        esac
        export BLE_SHELL
        remember_shell "$BLE_SHELL"
        step "Login shell → $BLE_SHELL"
        # Naming both is not an error: both get wired, and the last one named
        # takes the login shell.
    done
    for want in "${ONLY[@]}"; do
        if idx="$(mod_index_of "$want")"; then
            title "${M_LABEL[$idx]}"
            mod_run "$idx" || FAILED+=("$want")
            remember "$want"
        else
            fail "Unknown id '$want' — see ./setup.sh --list"
            FAILED+=("$want (unknown)")
        fi
    done
    finish
fi

self_update

# ── 1. mass install ──────────────────────────────────────────────────────────
# Every apt package the necessary tier names, in ONE call, before anything else.
title "1/4  Mass install — the necessary tier"

PKGS=()
while read -r i; do
    while read -r p; do [[ -n "$p" ]] && PKGS+=("$p"); done < <(mod_apt_packages "$i")
done < <(mod_indices necessary)

if [[ ${#PKGS[@]} -gt 0 ]]; then
    step "${#PKGS[@]} package(s) from modules.conf: ${PKGS[*]}"
    apt_ensure "${PKGS[@]}" || FAILED+=("apt (necessary)")
else
    skip "No apt packages in the necessary tier."
fi

# ── 2. every question, together ──────────────────────────────────────────────
# Nothing installs here; section 3 then runs start to finish without stopping.
title "2/4  Questions — all of them, now, so nothing interrupts the install"

# ── the shell, first ─────────────────────────────────────────────────────────
# One-of-two, not a checkbox: the core list then offers only the repo you picked.
SHELL_ROWS=(zsh bash)
declare -A SHELL_ID=([zsh]=zsh-config [bash]=bash-config)
# Kept short on purpose: these rows share one terminal line with a note, so a long
# label gets cut. The distinguishing word comes first in each.
declare -A SHELL_DESC=(
    [zsh]="zsh — Oh My Zsh: autosuggestions, syntax highlighting"
    [bash]="bash — no framework, same aliases and prompt"
)
# The current login shell is the honest default: on a re-run the answer that keeps
# the machine as it is should be the one a bare enter gives you.
CURRENT_LOGIN="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7 || true)"
[[ -z "$CURRENT_LOGIN" ]] && CURRENT_LOGIN="${SHELL:-}"
case "$CURRENT_LOGIN" in
    */bash) SHELL_DEFAULT=bash ;;
    */zsh)  SHELL_DEFAULT=zsh ;;
    # Neither (dash, fish, a fresh container): fall back to the remembered answer
    # lib/common.sh already resolved — zsh on a machine never asked.
    *)      SHELL_DEFAULT="$BLE_SHELL" ;;
esac

chk_reset
for s in "${SHELL_ROWS[@]}"; do
    note=""; ticked=0
    if [[ "$s" == "$SHELL_DEFAULT" ]]; then note="in use"; ticked=1; fi
    # The core entry's `link:` check is the usual "this repo is wired in" test,
    # so the note tells you which one you already have.
    if idx="$(mod_index_of "${SHELL_ID[$s]}")" && mod_installed "$idx"; then
        note="${note:+$note · }installed"
    fi
    chk_add "${SHELL_DESC[$s]}" "$ticked" "$note"
done
radiolist "Which shell does this machine log in with?" \
    "Both configs can sit on the machine; only this one gets 'chsh'. Change your mind by re-running ./setup.sh."
# radiolist leaves exactly one row ticked, so chk_picked prints exactly one index.
SHELL_PICK="$(chk_picked)"
BLE_SHELL="${SHELL_ROWS[$SHELL_PICK]}"
export BLE_SHELL
remember_shell "$BLE_SHELL"
step "Login shell → $BLE_SHELL (its config repo is in the core list below)"

CORE_IDX=(); while read -r i; do CORE_IDX+=("$i"); done < <(mod_indices core)
SEC_IDX=();  while read -r i; do SEC_IDX+=("$i");  done < <(mod_indices secondary)

# Drop the shell config you did not pick, rather than show it unticked: an unticked
# row invites a tick, and two ticked configs means two installers wanting `chsh`.
CORE_KEEP=()
for i in "${CORE_IDX[@]}"; do
    case "${M_ID[$i]}" in
        zsh-config|bash-config)
            [[ "${M_ID[$i]}" == "${SHELL_ID[$BLE_SHELL]}" ]] || continue
            ;;
    esac
    CORE_KEEP+=("$i")
done
CORE_IDX=(${CORE_KEEP[@]+"${CORE_KEEP[@]}"})

# Core: all pre-ticked. The list is there to let you say no to one repo, not to
# make you re-choose your whole environment.
chk_reset
for i in "${CORE_IDX[@]}"; do
    if mod_installed "$i"; then chk_add "${M_LABEL[$i]}" 1 "✓ installed"; else chk_add "${M_LABEL[$i]}" 1 ""; fi
done
checklist "Core — your config repos" "Cloned into ~/linux-configuration/ and symlinked into place."
# chk_picked, not `(( CHK_STATE[n] )) && …`: an arithmetic test on an unticked row
# returns non-zero and ends the run under `set -e`. See the note in lib/ui.sh.
CORE_PICK=()
while read -r n; do CORE_PICK+=("${CORE_IDX[$n]}"); done < <(chk_picked)

# Vim's languages — one list here instead of four prompts mid-run, passed down
# as --languages=… so vim's own installer never gets to ask.
VIM_LANGS=""
VIM_IDX="$(mod_index_of vim || true)"
if [[ -n "$VIM_IDX" ]] && in_list "$VIM_IDX" ${CORE_PICK[@]+"${CORE_PICK[@]}"}; then
    LANG_FILE="$HOME/.vim/config_files/languages.vim"
    # What is selected right now, so the list opens on the truth: --languages
    # REMOVES whatever it leaves out, so a misread costs you plugins.
    CURRENT=""
    [[ -f "$LANG_FILE" ]] && CURRENT="$(sed -n "s/.*let[[:space:]]\+g:vim_languages[[:space:]]*=[[:space:]]*\[\(.*\)\].*/\1/p" "$LANG_FILE" | tr -d "' " )"
    ALL_LANGS=(php javascript python c)
    declare -A LANG_DESC=(
        [php]="PHP — intelephense, Blade syntax, prettier, css, tailwind"
        [javascript]="JavaScript / TypeScript — tsserver, eslint, jsx, prettier, tailwind"
        [python]="Python — pyright"
        [c]="C — clangd"
    )
    chk_reset
    for l in "${ALL_LANGS[@]}"; do
        if [[ ",$CURRENT," == *",$l,"* ]]; then chk_add "${LANG_DESC[$l]}" 1 "in use"; else chk_add "${LANG_DESC[$l]}" 0 ""; fi
    done
    checklist "Vim — which language support to keep" "Unticking one REMOVES its plugins and LSP. All four at once, not four questions."
    picked=()
    while read -r n; do picked+=("${ALL_LANGS[$n]}"); done < <(chk_picked)
    if [[ ${#picked[@]} -eq 0 ]]; then
        VIM_LANGS=none
    else
        VIM_LANGS="$(IFS=,; printf '%s' "${picked[*]}")"
    fi
    export BLE_VIM_LANGUAGES="$VIM_LANGS"
fi

# Firefox's add-ons — vim's languages again: asked here, passed down as
# --extensions=… which is exactly what tells the repo's installer not to ask.
FF_EXT=""
FF_IDX="$(mod_index_of firefox-config || true)"
if [[ -n "$FF_IDX" ]] && in_list "$FF_IDX" ${CORE_PICK[@]+"${CORE_PICK[@]}"}; then
    FF_CONF="$HOME/.firefox/extensions.conf"
    # Read here so the list opens on the last choice; written by the repo's own
    # installer and never by this script — one owner for that file.
    FF_STATE="$HOME/.cache/firefox-config/extensions"
    if [[ ! -f "$FF_CONF" ]]; then
        # ~/.firefox is cloned in section 3, so on a first run there is no
        # catalogue yet. Passing no --extensions= defers the question, not loses it.
        skip "Firefox add-ons: the config repo isn't cloned yet, so the list can't be built here."
        skip "Its own installer asks you instead, once section 3 has cloned it. Later runs ask here."
        # Read by 10-tools.sh, which hands firefox's installer the terminal for
        # this one run. Nothing else ever sets it.
        export BLE_FIREFOX_ASK_LATER=true
    else
        FF_SLUG=()
        chk_reset
        while IFS='|' read -r id slug label def; do
            [[ -z "$id" || "$id" == \#* ]] && continue
            FF_SLUG+=("$slug")
            if [[ -f "$FF_STATE" ]]; then
                # -Fx: a slug must not be matched as a substring of another.
                if grep -Fxq "$slug" "$FF_STATE"; then chk_add "$label" 1 "chosen before"; else chk_add "$label" 0 ""; fi
            elif [[ "${def:-1}" == 1 ]]; then
                chk_add "$label" 1 ""
            else
                chk_add "$label" 0 ""
            fi
        done < "$FF_CONF"
        checklist "Firefox — which add-ons to install" \
            "Installed by Firefox's own policy and kept updated from AMO. Unticking one never uninstalls it — do that in about:addons."
        picked=()
        while read -r n; do picked+=("${FF_SLUG[$n]}"); done < <(chk_picked)
        if [[ ${#picked[@]} -eq 0 ]]; then
            # An empty answer is an answer — passing no flag at all would let the
            # installer fall back to defaults and re-add what you just unticked.
            FF_EXT=none
        else
            FF_EXT="$(IFS=,; printf '%s' "${picked[*]}")"
        fi
        export BLE_FIREFOX_EXTENSIONS="$FF_EXT"
    fi
fi

# Secondary: nothing pre-ticked but what is already here or was ticked before.
# Unticking never uninstalls, so those ticks are just an honest picture.
chk_reset
for i in "${SEC_IDX[@]}"; do
    if mod_installed "$i"; then
        chk_add "${M_LABEL[$i]}" 1 "✓ installed"
    elif was_chosen "${M_ID[$i]}"; then
        chk_add "${M_LABEL[$i]}" 1 "chosen before"
    else
        chk_add "${M_LABEL[$i]}" 0 ""
    fi
done
checklist "Secondary — extra applications" "Nothing else depends on these; leaving them all unticked still gives you a complete environment."
SEC_PICK=()
while read -r n; do SEC_PICK+=("${SEC_IDX[$n]}"); done < <(chk_picked)

# The boot cron, asked the same way as everything else and only while it is
# still a question.
WANT_CRON=0
if cron_installed && ! cron_stale; then
    skip "Boot cron already installed — ./boot.sh runs at every boot."
else
    chk_reset
    chk_add "Run ./boot.sh at every boot — git pull this repo and every config repo, re-apply the configs, refresh the binaries. Asks nothing, installs nothing new." 1 ""
    checklist "Automation"
    WANT_CRON=${CHK_STATE[0]}
fi

# ── 3. install, without stopping ─────────────────────────────────────────────
title "3/4  Installing — no more questions from here"

step "Necessary: $(mod_indices necessary | wc -l) entries"
while read -r i; do
    # --no-apt: their packages went in above. What is left is the work around
    # them — linking a config, downloading a release, setting the display manager.
    mod_run "$i" --no-apt || FAILED+=("${M_ID[$i]}")
done < <(mod_indices necessary)

if [[ ${#CORE_PICK[@]} -gt 0 ]]; then
    step "Core: ${#CORE_PICK[@]} repo(s)"
    [[ -n "$VIM_LANGS" ]] && step "vim language support → $VIM_LANGS"
    [[ -n "$FF_EXT" ]] && step "firefox add-ons → $FF_EXT"
    for i in "${CORE_PICK[@]}"; do
        mod_run "$i" || FAILED+=("${M_ID[$i]}")
        remember "${M_ID[$i]}"
    done
else
    skip "No core repos ticked."
fi

if [[ ${#SEC_PICK[@]} -gt 0 ]]; then
    step "Secondary: ${#SEC_PICK[@]} app(s)"
    for i in "${SEC_PICK[@]}"; do
        mod_run "$i" || FAILED+=("${M_ID[$i]}")
        remember "${M_ID[$i]}"
    done
else
    skip "No secondary apps ticked."
fi

# Last, and not modules.conf entries: these two write INTO the config repos the
# tiers above clone, so they only have somewhere to write once those are on disk.
bash "$BLE_ROOT/basic/95-settings.sh" || FAILED+=("settings")
bash "$BLE_ROOT/basic/99-font-sizes.sh" || FAILED+=("font sizes")

if (( WANT_CRON )); then
    title "Boot cron"
    install_cron || FAILED+=("cron")
elif ! cron_installed; then
    skip "No boot cron — update by hand with ./boot.sh, or re-run ./setup.sh to add it."
fi

# ── 4. what actually happened ────────────────────────────────────────────────
# Re-check what can be checked cheaply; a `-` check is skipped, not guessed at.
title "4/4  Result"

MISSING=()
for i in "${!M_ID[@]}"; do
    [[ "${M_CHECK[$i]}" == '-' || -z "${M_CHECK[$i]}" ]] && continue
    case "${M_TIER[$i]}" in
        necessary) ;;   # always attempted, so always worth verifying
        core)      in_list "$i" ${CORE_PICK[@]+"${CORE_PICK[@]}"} || continue ;;
        secondary) in_list "$i" ${SEC_PICK[@]+"${SEC_PICK[@]}"}   || continue ;;
    esac
    mod_installed "$i" || MISSING+=("${M_ID[$i]}")
done

if [[ "$DRY_RUN" == true ]]; then
    skip "Dry run — nothing was installed, so nothing is verified."
elif [[ ${#MISSING[@]} -gt 0 ]]; then
    warn "Asked for but still not installed: ${MISSING[*]}"
    warn "Scroll up for the reason (no sudo, no install candidate, a failed download)."
else
    ok "Everything asked for is installed."
fi

finish
