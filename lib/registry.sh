#!/usr/bin/env bash
# Reads modules.conf and answers "is this here?" and "put this here". Source after
# lib/common.sh. Everything the entry scripts know about what exists comes from here.

[[ -n "${_BLE_REGISTRY_LOADED:-}" ]] && return 0
_BLE_REGISTRY_LOADED=1

# Parallel arrays, one entry per usable line of modules.conf, in file order.
M_TIER=(); M_ID=(); M_SCOPE=(); M_CHECK=(); M_ACT=(); M_LABEL=()

# registry_load  — parse modules.conf. A 'gui' scope is dropped outright on a
# server, so a headless box never lists, installs or misses them.
registry_load() {
    local conf="${BLE_MODULES_CONF:-$BLE_ROOT/modules.conf}"
    [[ -f "$conf" ]] || { fail "Missing $conf — this repo is incomplete."; exit 1; }

    local tier id scope check act label
    while IFS='|' read -r tier id scope check act label; do
        [[ -z "$tier" || "$tier" == \#* ]] && continue
        case "$tier" in
            necessary|core|secondary) ;;
            *) warn "modules.conf: unknown tier '$tier' on '$id' — line ignored."; continue ;;
        esac
        [[ "$scope" == gui ]] && is_server && continue
        M_TIER+=("$tier"); M_ID+=("$id"); M_SCOPE+=("$scope")
        M_CHECK+=("$check"); M_ACT+=("$act"); M_LABEL+=("$label")
    done < "$conf"

    [[ ${#M_ID[@]} -gt 0 ]] || { fail "modules.conf declares nothing usable."; exit 1; }
}

# mod_indices TIER  — the indices of every entry in TIER, in file (install) order.
mod_indices() {
    local want="$1" i
    for i in "${!M_TIER[@]}"; do
        [[ "${M_TIER[$i]}" == "$want" ]] && printf '%s\n' "$i"
    done
}

# mod_index_of ID  — print the index of one entry by id; non-zero if unknown.
mod_index_of() {
    local want="$1" i
    for i in "${!M_ID[@]}"; do
        [[ "${M_ID[$i]}" == "$want" ]] && { printf '%s' "$i"; return 0; }
    done
    return 1
}

# mod_actions IDX  — an entry's actions, one per line. Split on '+' and nothing
# else: splitting on spaces too would break `apt:unzip xz-utils` in half.
mod_actions() {
    local acts a
    IFS='+' read -ra acts <<< "${M_ACT[$1]}"
    for a in ${acts[@]+"${acts[@]}"}; do
        [[ -n "$a" ]] && printf '%s\n' "$a"
    done
}

# mod_first_script IDX  — an entry's first `run:` script, the one that answers
# --check for advanced/ modules.
mod_first_script() {
    local a
    while read -r a; do
        [[ "$a" == run:* ]] && { printf '%s' "$BLE_ROOT/${a#run:}"; return 0; }
    done < <(mod_actions "$1")
    return 1
}

# mod_installed IDX  — 0 when this is already on the machine. A `-` check answers
# "no", the safe way round: modules are idempotent, so a needless re-run is cheap.
mod_installed() {
    # Two statements, not one `local`: the builtin expands ALL its arguments
    # before assigning any, so `$i` there would still be the CALLER's `i`.
    local i="$1"
    local check="${M_CHECK[$i]}" arg script
    case "$check" in
        # PATH *or* ~/.local/bin, which the boot cron's minimal PATH lacks. A
        # binary living elsewhere (opencode) needs the `script` check instead.
        cmd:*)  has_cmd "${check#cmd:}" || have_local_bin "${check#cmd:}" ;;
        apt:*)  apt_installed "${check#apt:}" ;;
        link:*) arg="${check#link:}"; [[ -L "${arg/#\~/$HOME}" ]] ;;
        path:*) arg="${check#path:}"; [[ -e "${arg/#\~/$HOME}" ]] ;;
        script)
            script="$(mod_first_script "$i")" || return 1
            [[ -f "$script" ]] || return 1
            bash "$script" --check >/dev/null 2>&1
            ;;
        -|'') return 1 ;;
        *)  warn "modules.conf: unknown check '$check' on '${M_ID[$i]}' — treating as not installed."
            return 1
            ;;
    esac
}

# mod_apt_packages IDX  — the apt packages an entry names, one per line. Batches
# the whole necessary tier into a single apt-get call.
mod_apt_packages() {
    local a p
    while read -r a; do
        [[ "$a" == apt:* ]] || continue
        # Word-split here on purpose: one `apt:` action may name several
        # packages, and each is wanted on its own line.
        for p in ${a#apt:}; do printf '%s\n' "$p"; done
    done < <(mod_actions "$1")
}

# mod_run IDX [--no-apt]  — carry out an entry's actions in order; --no-apt skips
# `apt:` ones already installed up front. Non-zero on failure; the caller goes on.
mod_run() {
    local i="$1" skip_apt="${2:-}" a rc=0
    while read -r a; do
        case "$a" in
            apt:*)
                [[ "$skip_apt" == --no-apt ]] && continue
                # Word-split on purpose: `apt:build-essential pkg-config` is one
                # action naming two packages.
                apt_ensure ${a#apt:} || rc=1
                ;;
            run:*)
                local script="$BLE_ROOT/${a#run:}"
                if [[ ! -f "$script" ]]; then
                    fail "modules.conf: '${M_ID[$i]}' names a missing script — ${a#run:}"
                    rc=1
                    continue
                fi
                bash "$script" || rc=1
                ;;
            tool:*)
                bash "$BLE_ROOT/basic/10-tools.sh" "${a#tool:}" || rc=1
                ;;
            '') ;;
            *)  fail "modules.conf: unknown action '$a' on '${M_ID[$i]}'."; rc=1 ;;
        esac
    done < <(mod_actions "$i")
    return "$rc"
}
