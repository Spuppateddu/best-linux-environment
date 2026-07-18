#!/usr/bin/env bash
# Shared helpers for every installer in this repo. Source it, don't run it.
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
#
# Everything here is idempotent-friendly: helpers report and skip work that is
# already done. Honour DRY_RUN=true (exported by install.sh) to preview only.

set -euo pipefail

# Guard against double-sourcing when modules chain each other.
[[ -n "${_BLE_COMMON_LOADED:-}" ]] && return 0
_BLE_COMMON_LOADED=1

# Repo root = parent of this lib/ dir. Resolved once, exported for sub-scripts.
BLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BLE_ROOT

DRY_RUN="${DRY_RUN:-false}"

# ── Colors ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
    C_RED=$'\033[1;31m';  C_DIM=$'\033[2m';       C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
    C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_DIM=''; C_BOLD=''; C_OFF=''
fi

step()  { printf '%s▸%s %s\n' "$C_BLUE"  "$C_OFF" "$*"; }
ok()    { printf '%s✓%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
skip()  { printf '%s·%s %s%s%s\n' "$C_DIM" "$C_OFF" "$C_DIM" "$*" "$C_OFF"; }
warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_OFF" "$*"; }
fail()  { printf '%s✗%s %s\n' "$C_RED"   "$C_OFF" "$*" >&2; }
title() { printf '\n%s══ %s ══%s\n' "$C_BOLD" "$*" "$C_OFF"; }

# run CMD...  — execute, or just print under --dry-run.
run() {
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would run:%s %s\n' "$C_DIM" "$C_OFF" "$*"
    else
        "$@"
    fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# sudo works here only with a terminal (password prompt) or cached credentials;
# boot/cron runs must never hang waiting for a password.
can_sudo() { [[ -t 0 ]] || sudo -n true 2>/dev/null; }

require_apt() {
    if ! has_cmd apt; then
        fail "This repo targets Ubuntu (apt). Adapt for your distro."
        exit 1
    fi
}

# Ubuntu codename (noble, etc.) — resolved at runtime, never hardcoded, so the
# same scripts work across releases and on the 26.04 LTS target.
distro_codename() {
    if has_cmd lsb_release; then
        lsb_release -cs 2>/dev/null && return
    fi
    # shellcheck disable=SC1091
    [[ -r /etc/os-release ]] && . /etc/os-release && printf '%s\n' "${VERSION_CODENAME:-}"
}

# ── apt ─────────────────────────────────────────────────────────────────────
# apt_ensure pkg...  — install only the packages that are missing, in one call.
# Skips packages with no install candidate on this release (warns instead).
apt_ensure() {
    local pkg candidate missing=()
    for pkg in "$@"; do
        dpkg -s "$pkg" >/dev/null 2>&1 && continue
        candidate=$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2}')
        if [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
            missing+=("$pkg")
        else
            warn "Package '$pkg' has no install candidate on this release — skipping."
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        skip "apt: nothing to install (${*})."
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would install:%s %s\n' "$C_DIM" "$C_OFF" "${missing[*]}"
        return 0
    fi
    if ! can_sudo; then
        warn "sudo unavailable (non-interactive) — skipped apt install: ${missing[*]}"
        warn "Run ./install.sh from a terminal to pick these up."
        return 0
    fi
    step "apt: installing ${#missing[@]} package(s): ${missing[*]}"
    # A broken third-party PPA can make `apt update` exit non-zero; that
    # shouldn't abort the install against cached indexes.
    sudo apt-get update -qq || warn "apt update reported errors — continuing."
    sudo apt-get install -y "${missing[@]}"
    ok "apt: installed ${missing[*]}."
}

apt_installed() { dpkg -s "$1" >/dev/null 2>&1; }

# apt_repo_add NAME KEY_URL DEB_LINE
# Installs a dearmored keyring at /usr/share/keyrings/NAME.gpg and writes the
# source list. DEB_LINE must reference signed-by=/usr/share/keyrings/NAME.gpg.
apt_repo_add() {
    local name="$1" key_url="$2" deb_line="$3"
    local keyring="/usr/share/keyrings/$name.gpg"
    local list="/etc/apt/sources.list.d/$name.list"
    if [[ -f "$keyring" && -f "$list" ]]; then
        skip "apt repo '$name' already configured."
        return
    fi
    step "Adding apt repo '$name'"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would add key:%s %s → %s\n' "$C_DIM" "$C_OFF" "$key_url" "$keyring"
        printf '%s  would write:%s %s → %s\n' "$C_DIM" "$C_OFF" "$deb_line" "$list"
        return
    fi
    curl -fsSL "$key_url" | sudo gpg --dearmor --yes -o "$keyring"
    printf '%s\n' "$deb_line" | sudo tee "$list" >/dev/null
    ok "apt repo '$name' added."
}

# ── git ─────────────────────────────────────────────────────────────────────
# clone_or_pull URL DEST  — clone if absent, fast-forward pull if present.
clone_or_pull() {
    local url="$1" dest="$2"
    if [[ -d "$dest/.git" ]]; then
        step "Updating $(basename "$dest") ($dest)"
        run git -C "$dest" pull --ff-only --quiet || warn "Could not pull $dest — leaving as-is."
        ok "$(basename "$dest") up to date."
    elif [[ -e "$dest" ]]; then
        warn "$dest exists but is not a git checkout — leaving untouched."
    else
        step "Cloning $url → $dest"
        run git clone --quiet "$url" "$dest"
        ok "Cloned $(basename "$dest")."
    fi
}

# ── files ───────────────────────────────────────────────────────────────────
# link SRC DST  — symlink DST→SRC, backing up any real file already there.
link() {
    local src="$1" dst="$2"
    run mkdir -p "$(dirname "$dst")"
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        skip "$dst already linked."
        return
    fi
    if [[ -e "$dst" && ! -L "$dst" ]]; then
        local backup="$dst.backup.$$"
        warn "$dst exists — backing up to $backup"
        run mv "$dst" "$backup"
    fi
    run ln -sfn "$src" "$dst"
    ok "linked $dst"
}

# write_line_once LINE FILE  — ensure FILE contains exactly LINE (idempotent).
# Backs up a pre-existing non-matching file before overwriting.
ensure_source_line() {
    local line="$1" file="$2"
    if [[ -f "$file" ]] && grep -qxF "$line" "$file"; then
        skip "$file already sources the repo."
        return
    fi
    if [[ -s "$file" ]]; then
        local backup="$file.backup.$$"
        warn "$file exists — backing up to $backup"
        run cp "$file" "$backup"
    fi
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s %s → %s\n' "$C_DIM" "$C_OFF" "$line" "$file"
    else
        printf '%s\n' "$line" > "$file"
    fi
    ok "wired $file"
}
