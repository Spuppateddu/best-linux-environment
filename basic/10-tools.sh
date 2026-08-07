#!/usr/bin/env bash
# One tool config repo: clone into linux-configuration/, symlink it to the $HOME
# path it is known by, run the install.sh THE REPO ships. No args = refresh only.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

CONF="$BLE_ROOT/tools.conf"
# Beside this repo, not inside it: inside it would be gitignored, and
# `git clean -xfd` deletes exactly that — every checkout, silently.
CONFIG_DIR="${BLE_CONFIG_DIR:-$HOME/linux-configuration}"

# tools.conf into parallel arrays: DIRS is where the repo is, LINKS the $HOME path
# it answers to, BINS an executable to put on PATH, INSTALLERS --dry-run's oracle.
NAMES=(); URLS=(); DIRS=(); LINKS=(); SCOPES=(); BINS=(); INSTALLERS=()
while IFS='|' read -r name url dest scope bin installer; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    NAMES+=("$name"); URLS+=("$url"); SCOPES+=("${scope:-all}"); BINS+=("${bin:-}")
    INSTALLERS+=("${installer:-}")
    DIRS+=("$CONFIG_DIR/$name"); LINKS+=("${dest/#\~/$HOME}")
done < "$CONF"

index_of() {
    local want="$1" i
    for i in "${!NAMES[@]}"; do
        [[ "${NAMES[$i]}" == "$want" ]] && { printf '%s' "$i"; return 0; }
    done
    return 1
}

tool_cloned() { [[ -d "${DIRS[$1]}/.git" ]]; }

# A machine predating linux-configuration/ has the checkout itself at the old $HOME
# path. Cloning again would leave two copies, so it is reported and left alone.
unconverted() { [[ ! -L "${LINKS[$1]}" && -d "${LINKS[$1]}/.git" ]]; }

# The answers an installer would stop to ask for, gathered up front by ./setup.sh.
# zsh/bash get --no-login-shell on EVERY run, or both would fight over `chsh`.
tool_args() {
    case "$1" in
        vim)     [[ -n "${BLE_VIM_LANGUAGES:-}" ]]     && printf -- '--languages=%s' "$BLE_VIM_LANGUAGES" ;;
        firefox) [[ -n "${BLE_FIREFOX_EXTENSIONS:-}" ]] && printf -- '--extensions=%s' "$BLE_FIREFOX_EXTENSIONS" ;;
        zsh|bash) [[ "$1" == "$BLE_SHELL" ]] || printf -- '--no-login-shell' ;;
    esac
    # "Printed nothing" is a normal answer, but an unmatched `[[ -n … ]] &&` leaves
    # a non-zero status the caller's `$( )` would trip over under set -e.
    return 0
}

# The one installer allowed to keep the terminal: firefox's add-on catalogue only
# arrives with its clone, so on a first run it asks once. boot.sh never sets this.
tool_asks_for_itself() {
    case "$1" in
        firefox) [[ "${BLE_FIREFOX_ASK_LATER:-}" == true && -t 0 && -t 1 ]] ;;
        *)       false ;;
    esac
}

install_tool() {
    local i="$1"
    local name="${NAMES[$i]}" url="${URLS[$i]}" dir="${DIRS[$i]}" linkpath="${LINKS[$i]}"

    if [[ "${SCOPES[$i]}" == gui ]] && is_server; then
        skip "Tool '$name' is desktop-only — skipped (server profile)."
        return 0
    fi
    if unconverted "$i"; then
        warn "$name — still a clone at ${linkpath/#$HOME/\~}, from before linux-configuration/."
        warn "Move it into $CONFIG_DIR (leaving the old path as a symlink), then re-run."
        return 0
    fi

    title "Tool: $name"
    run mkdir -p "$CONFIG_DIR"
    clone_or_pull "$url" "$dir"
    link "$dir" "$linkpath"

    # Read off the clone whenever there is one, so a repo that grows an install.sh
    # needs no tools.conf edit. The declared field is only --dry-run's fallback.
    local have_installer=false
    if [[ -d "$dir" ]]; then
        [[ -f "$dir/install.sh" ]] && have_installer=true
    else
        [[ "${INSTALLERS[$i]}" == install.sh ]] && have_installer=true
    fi

    if [[ "$have_installer" == true ]]; then
        step "Running $name's own install.sh"
        local extra; extra="$(tool_args "$name")"
        # Entered through the symlink, so an installer resolving its own location
        # sees ~/.vim. stdin is /dev/null bar tool_asks_for_itself: nothing hangs.
        if [[ ! -f "$linkpath/install.sh" ]]; then
            # Dry run where the clone was only printed: no script to enter, so say
            # what a real run would do. Unreachable when the repo is present.
            printf '%s  would run:%s %s/install.sh %s\n' \
                "$C_DIM" "$C_OFF" "${linkpath/#$HOME/\~}" "$extra"
        elif [[ -n "$extra" ]]; then
            (cd "$linkpath" && bash ./install.sh "$extra" </dev/null)
        elif tool_asks_for_itself "$name"; then
            (cd "$linkpath" && bash ./install.sh)
        else
            (cd "$linkpath" && bash ./install.sh </dev/null)
        fi
    elif [[ -n "${BINS[$i]}" ]]; then
        # A repo that is just an executable (temps), linked into ~/.local/bin.
        local bin="${BINS[$i]}"
        # Tested in the clone, linked through the $HOME path: under --dry-run the
        # symlink was only printed, and both arms keep the preview honest.
        if [[ -f "$dir/$bin" ]] || [[ "$DRY_RUN" == true && ! -d "$dir" ]]; then
            run mkdir -p "$HOME/.local/bin"
            run chmod +x "$dir/$bin"
            link "$linkpath/$bin" "$HOME/.local/bin/$bin"
        else
            warn "$name ships no install.sh and no '$bin' executable — nothing wired up."
        fi
    else
        # Neither an installer nor an executable. Rare: a basic/ module then has
        # to own the package and the linking instead.
        skip "$name ships no install.sh — config-only repo, nothing else to run."
    fi
}

# ── dispatch ─────────────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    rc=0
    for want in "$@"; do
        if idx="$(index_of "$want")"; then
            install_tool "$idx" || rc=1
        else
            fail "Unknown tool '$want'. tools.conf has: ${NAMES[*]}"
            rc=1
        fi
    done
    exit "$rc"
fi

# No arguments: refresh what is here and add nothing. This is ./boot.sh's call —
# cloning a repo you never picked would be a decision, and a boot makes none.
title "Tool config repos — refreshing what is already cloned"
any=false
for i in "${!NAMES[@]}"; do
    tool_cloned "$i" || continue
    any=true
    install_tool "$i" || warn "Tool '${NAMES[$i]}' failed — continuing."
done
[[ "$any" == false ]] && skip "No tool repos cloned yet — run ./setup.sh to pick some."
exit 0
