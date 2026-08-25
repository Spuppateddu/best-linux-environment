#!/usr/bin/env bash
# Shared helpers for every installer. Source it, don't run it. Helpers skip work
# already done; honour DRY_RUN (preview only) and BLE_MODE (setup / boot).

set -euo pipefail

# Guard against double-sourcing when modules chain each other.
[[ -n "${_BLE_COMMON_LOADED:-}" ]] && return 0
_BLE_COMMON_LOADED=1

# Repo root = parent of this lib/ dir. Resolved once, exported for sub-scripts.
BLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BLE_ROOT

DRY_RUN="${DRY_RUN:-false}"

# Scratch state: the boot log, and the record of what you have ticked before.
BLE_STATE_DIR="${BLE_STATE_DIR:-$HOME/.cache/best-linux-environment}"

# ── run mode ────────────────────────────────────────────────────────────────
# setup re-asserts what the repo owns; boot never rewrites an existing seed.
BLE_MODE="${BLE_MODE:-setup}"
case "$BLE_MODE" in
    setup) BLE_FORCE=true;  BLE_UPGRADE=true ;;
    boot)  BLE_FORCE=false; BLE_UPGRADE=true ;;
    *)
        printf 'Unknown BLE_MODE "%s" — expected setup or boot.\n' "$BLE_MODE" >&2
        exit 1
        ;;
esac
export BLE_MODE BLE_FORCE BLE_UPGRADE

# True when this run may replace a config file the user is expected to edit.
force_config() { [[ "$BLE_FORCE" == true ]]; }
# True when this run should refresh binaries that apt does not manage for us.
want_upgrade() { [[ "$BLE_UPGRADE" == true ]]; }

# ── the shell ───────────────────────────────────────────────────────────────
# zsh or bash: exported BLE_SHELL wins, then the remembered answer, then zsh.
BLE_SHELL_FILE="$BLE_STATE_DIR/shell"
if [[ -z "${BLE_SHELL:-}" && -r "$BLE_SHELL_FILE" ]]; then
    read -r BLE_SHELL < "$BLE_SHELL_FILE" || BLE_SHELL=""
fi
case "${BLE_SHELL:-}" in
    zsh|bash) ;;
    "") BLE_SHELL=zsh ;;
    *)  printf 'Ignoring unknown shell "%s" in %s — using zsh.\n' \
            "$BLE_SHELL" "$BLE_SHELL_FILE" >&2
        BLE_SHELL=zsh
        ;;
esac
export BLE_SHELL BLE_SHELL_FILE

# remember_shell zsh|bash  — persist the choice for later runs and for ./boot.sh.
remember_shell() {
    local want="$1"
    case "$want" in
        zsh|bash) ;;
        *) fail "remember_shell: expected zsh or bash, got '$want'"; return 1 ;;
    esac
    [[ "$DRY_RUN" == true ]] && {
        printf '%s  would remember:%s login shell = %s\n' "$C_DIM" "$C_OFF" "$want"
        return 0
    }
    mkdir -p "$BLE_STATE_DIR"
    printf '%s\n' "$want" > "$BLE_SHELL_FILE"
}

# The tools.conf name of the shell config repo NOT in charge of the login shell,
# or nothing when there is no such repo to name. Read by basic/10-tools.sh.
other_shell() { [[ "$BLE_SHELL" == zsh ]] && printf bash || printf zsh; }

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

# warm_sudo  — cache the sudo password ONCE, here, where the terminal is; modules
# run with </dev/null and can only use `sudo -n`. Non-zero when root is impossible.
warm_sudo() {
    [[ $EUID -eq 0 ]] && return 0
    has_cmd sudo || return 1
    # Already cached — say nothing and cost nothing.
    sudo -n true 2>/dev/null && return 0
    # No terminal (the boot cron, a pipe): there is nobody to ask, and blocking on
    # a password nobody will type is the one thing a boot must never do.
    [[ -t 0 && -t 1 ]] || return 1
    if [[ "$DRY_RUN" == true ]]; then
        skip "Would ask for your sudo password once here (dry run — not asking)."
        return 0
    fi
    step "Your sudo password, once — so no later step has to stop and ask."
    sudo -v
}

# Nothing here asks questions: every choice is made once in ./setup.sh's checkbox
# lists, driven by modules.conf. See lib/ui.sh.

require_apt() {
    if ! has_cmd apt; then
        fail "This repo targets Ubuntu (apt). Adapt for your distro."
        exit 1
    fi
}

# ── profile: desktop vs server ───────────────────────────────────────────────
# GUI modules skip themselves on a server. Force with BLE_PROFILE=desktop|server.
is_desktop() {
    case "${BLE_PROFILE:-auto}" in
        desktop) return 0 ;;
        server)  return 1 ;;
    esac
    # The install-type metapackage is the one signal our own lightdm+i3 install
    # can't pollute, so it is checked before any runtime signal below.
    if apt_installed ubuntu-desktop || apt_installed ubuntu-desktop-minimal; then
        return 0
    fi
    if apt_installed ubuntu-server; then
        return 1
    fi
    # Neither metapackage (a bare minimal install): fall back to runtime signals —
    # a live session, then the systemd default target, then desktop/X packages.
    [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && return 0
    if has_cmd systemctl; then
        case "$(systemctl get-default 2>/dev/null)" in
            graphical.target)  return 0 ;;
            multi-user.target) return 1 ;;
        esac
    fi
    apt_installed xserver-xorg || has_cmd Xorg
}
is_server() { ! is_desktop; }

# One-word label for the detected profile (for banners/logs).
profile_label() { is_desktop && echo desktop || echo server; }

# GUI modules call this right after their title; on a headless server it prints a
# skip and exits 0 so the run moves on to the next module cleanly.
require_desktop() {
    if is_server; then
        skip "${1:-This GUI component} — skipped (server profile: no desktop)."
        exit 0
    fi
}

# ── apt ─────────────────────────────────────────────────────────────────────
# apt_refresh  — re-fetch the indexes so a freshly-added third-party repo shows up.
apt_refresh() {
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would run:%s sudo apt-get update -qq\n' "$C_DIM" "$C_OFF"
        return 0
    fi
    can_sudo || { warn "sudo unavailable — skipping apt index refresh."; return 0; }
    step "Refreshing apt package index"
    # A broken third-party PPA can make `apt update` exit non-zero; that shouldn't
    # abort work against the cached indexes.
    sudo apt-get update -qq || warn "apt update reported errors — continuing."
}

# apt_has_candidate PKG  — true when apt can install PKG on this release. Captured,
# not piped into `grep -q`: under pipefail that SIGPIPEs apt-cache and reads as false.
apt_has_candidate() {
    local candidate
    candidate="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}')"
    [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

# _apt_scan pkg...  — populate the caller's MISSING and NOCAND arrays (bash
# dynamic scope): installable-but-absent packages vs those with no candidate.
_apt_scan() {
    local pkg
    MISSING=(); NOCAND=()
    for pkg in "$@"; do
        dpkg -s "$pkg" >/dev/null 2>&1 && continue
        if apt_has_candidate "$pkg"; then
            MISSING+=("$pkg")
        else
            NOCAND+=("$pkg")
        fi
    done
}

# apt_ensure pkg...  — install only the missing packages, in one call. No candidate
# usually means a stale index, so refresh once and re-scan before giving up.
apt_ensure() {
    local MISSING=() NOCAND=() refreshed=false pkg
    _apt_scan "$@"
    if [[ ${#NOCAND[@]} -gt 0 && "$DRY_RUN" != true ]] && can_sudo; then
        apt_refresh; refreshed=true
        _apt_scan "$@"
    fi
    for pkg in "${NOCAND[@]}"; do
        warn "Package '$pkg' has no install candidate on this release — skipping."
    done

    if [[ ${#MISSING[@]} -eq 0 ]]; then
        # Say which of the two "nothing to do" cases this is: listing every argument
        # read as "all satisfied" even when some had no install candidate.
        if [[ ${#NOCAND[@]} -gt 0 ]]; then
            skip "apt: nothing installable left — ${#NOCAND[@]} package(s) above have no candidate."
        else
            skip "apt: nothing to install (${*})."
        fi
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would install:%s %s\n' "$C_DIM" "$C_OFF" "${MISSING[*]}"
        return 0
    fi
    if ! can_sudo; then
        warn "sudo unavailable (non-interactive) — skipped apt install: ${MISSING[*]}"
        warn "Run ./setup.sh from a terminal to pick these up."
        return 0
    fi
    step "apt: installing ${#MISSING[@]} package(s): ${MISSING[*]}"
    # If we didn't already refresh above, do it now so we don't install against a
    # stale index (404s on superseded versions).
    [[ "$refreshed" == true ]] || apt_refresh
    sudo apt-get install -y "${MISSING[@]}"
    ok "apt: installed ${MISSING[*]}."
}

apt_installed() { dpkg -s "$1" >/dev/null 2>&1; }

# apt_repo_add NAME KEY_URL DEB_LINE  — dearmored keyring at /usr/share/keyrings/
# NAME.gpg plus the source list. DEB_LINE must say signed-by= that same keyring.
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

# apt_app_module PKG LABEL [--desktop]  — the whole body of a module that just
# installs one Ubuntu package. The module still answers --check itself.
apt_app_module() {
    local pkg="$1" label="$2" scope="${3:-}"
    title "$label"
    [[ "$scope" == --desktop ]] && require_desktop "$label"
    if apt_installed "$pkg"; then
        skip "$label already installed."
    else
        apt_ensure "$pkg"
    fi
    ok "$label ready."
}

# ── prebuilt downloads ──────────────────────────────────────────────────────
# tmp_file [SUFFIX] / tmp_dir — a private temp path, not a plantable /tmp/x.$$.
tmp_file() {
    if [[ "$DRY_RUN" == true ]]; then
        printf '/tmp/ble-dry-run%s\n' "${1:-}"
    else
        mktemp --suffix="${1:-}"
    fi
}

tmp_dir() {
    if [[ "$DRY_RUN" == true ]]; then
        printf '/tmp/ble-dry-run.d\n'
    else
        mktemp -d
    fi
}

# arch_pick X86_VALUE ARM_VALUE  — print whichever matches this CPU, non-zero
# otherwise. Upstreams spell assets differently, so the caller passes both.
arch_pick() {
    case "$(uname -m)" in
        x86_64)        printf '%s\n' "$1" ;;
        aarch64|arm64) printf '%s\n' "$2" ;;
        *) return 1 ;;
    esac
}

# gh_latest_tag OWNER/REPO  — print the newest release tag (e.g. v0.44.1).
# Non-zero if GitHub is unreachable, rate-limited, or the repo has no release.
gh_latest_tag() {
    local tag
    tag="$(curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
        | awk -F'"' '/"tag_name"/ {print $4; exit}')"
    [[ -n "$tag" ]] || return 1
    printf '%s\n' "$tag"
}

# gh_newer_tag OWNER/REPO CURRENT  — newest tag only when it differs from CURRENT.
# Unreachable or empty CURRENT is non-zero too, so a boot never re-downloads.
gh_newer_tag() {
    local repo="$1" current="${2#v}" tag
    [[ -n "$current" ]] || return 1
    tag="$(gh_latest_tag "$repo")" || return 1
    [[ "${tag#v}" == "$current" ]] && return 1
    printf '%s\n' "$tag"
}

# have_local_bin CMD  — true when ~/.local/bin/CMD is ours to upgrade (apt's is
# apt's). A path test, not `command -v`: the boot cron's PATH lacks ~/.local/bin.
have_local_bin() { [[ -x "$HOME/.local/bin/$1" ]]; }

# have_opencode_bin  — same, for the one binary that lands elsewhere: its own
# installer uses ~/.opencode/bin. A path test, for the reason above.
have_opencode_bin() { [[ -x "$HOME/.opencode/bin/opencode" ]]; }

# install_tarball_bin URL BINARY  — extract one binary from a .tar.gz into
# ~/.local/bin. Non-zero (temp file cleaned) on failure, so `set -e` spares the caller.
install_tarball_bin() {
    local url="$1" bin="$2" tmp
    tmp="$(tmp_file .tgz)"
    run mkdir -p "$HOME/.local/bin"
    if run curl -fL --progress-bar -o "$tmp" "$url" \
       && run tar -xzf "$tmp" -C "$HOME/.local/bin" "$bin"; then
        run chmod +x "$HOME/.local/bin/$bin"
        run rm -f "$tmp"
        return 0
    fi
    run rm -f "$tmp"
    return 1
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
# config_write DEST [--seed|--if-missing] [--exec] — stdin in, $HOME out. Sets
# CONFIG_WRITTEN.
config_write() {
    local dst="$1"; shift
    local seed=false if_missing=false exec_bit=false arg
    CONFIG_WRITTEN=false
    for arg in "$@"; do
        case "$arg" in
            --seed) seed=true ;;
            --if-missing) if_missing=true ;;
            --exec) exec_bit=true ;;
            *) fail "config_write: unknown flag '$arg'"; return 1 ;;
        esac
    done

    local label="${dst/#$HOME/\~}" new
    # Both sides of the comparison below lose trailing newlines to $( ), so it
    # stays a fair one; the printf that writes the file puts exactly one back.
    new="$(cat)"

    # --if-missing: the file only has to EXIST. Not compared and not backed up,
    # so even ./setup.sh's reset leaves what is already there alone.
    if [[ -e "$dst" && "$if_missing" == true ]]; then
        skip "$label already there — left as it is."
        return 0
    fi

    if [[ -f "$dst" ]] && [[ "$new" == "$(cat "$dst" 2>/dev/null)" ]]; then
        skip "$label already up to date."
        if [[ "$exec_bit" == true && ! -x "$dst" && "$DRY_RUN" != true ]]; then
            chmod +x "$dst"
        fi
        return 0
    fi

    if [[ -e "$dst" && "$seed" == true && "$BLE_FORCE" != true ]]; then
        skip "$label is yours now — left as it is (./setup.sh rewrites it)."
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        if [[ -e "$dst" ]]; then
            printf '%s  would rewrite:%s %s (backing the old one up)\n' "$C_DIM" "$C_OFF" "$label"
        else
            printf '%s  would write:%s %s\n' "$C_DIM" "$C_OFF" "$label"
        fi
        # So a --dry-run also previews whatever the caller does after a write.
        CONFIG_WRITTEN=true
        return 0
    fi

    mkdir -p "$(dirname "$dst")"
    local verb=wrote
    if [[ -e "$dst" ]]; then
        cp -a "$dst" "$dst.backup.$$"
        verb="rewrote"
        warn "$label differed — old copy kept as $(basename "$dst").backup.$$"
    fi
    printf '%s\n' "$new" > "$dst"
    [[ "$exec_bit" == true ]] && chmod +x "$dst"
    CONFIG_WRITTEN=true
    ok "$verb $label"
}

# write_gen / drop_gen — the other half of config_write, for a file this repo
# owns WHOLE: no backup is kept, because nothing you wrote is ever in it and
# the module can rebuild it at any time. config_write is for files a person
# may reasonably have edited; these two are for generated ones. Both set
# GEN_CHANGED, which callers read to decide whether to reload anything.
# write_gen DEST  — stdin into a file this repo owns whole. No backup is kept:
# nothing you wrote is in it, and settings.local can rebuild it at any time.
write_gen() {
    local dst="$1" new label; label="${dst/#$HOME/\~}"
    new="$(cat)"
    GEN_CHANGED=false
    if [[ -f "$dst" && "$new" == "$(cat "$dst" 2>/dev/null)" ]]; then
        skip "$label already up to date."
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would write:%s %s\n' "$C_DIM" "$C_OFF" "$label"
    else
        mkdir -p "$(dirname "$dst")"
        printf '%s\n' "$new" > "$dst"
        ok "wrote $label"
    fi
    GEN_CHANGED=true
}

drop_gen() {
    local dst="$1" owner="$2" label="${1/#$HOME/\~}"
    GEN_CHANGED=false
    [[ -e "$dst" ]] || return 0
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would remove:%s %s\n' "$C_DIM" "$C_OFF" "$label"
    else
        rm -f "$dst"
        ok "removed $label — back to what $owner says."
    fi
    GEN_CHANGED=true
}

# ensure_line FILE PATTERN LINE  — append LINE unless grep -E PATTERN already
# matches FILE. The insert half of "create what is missing"; sets LINE_ADDED.
ensure_line() {
    local file="$1" pattern="$2" line="$3"
    local label="${file/#$HOME/\~}"
    LINE_ADDED=false

    if [[ -f "$file" ]] && grep -Eq -- "$pattern" "$file"; then
        skip "$label already has it."
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would append:%s %s → %s\n' "$C_DIM" "$C_OFF" "$line" "$label"
        LINE_ADDED=true
        return 0
    fi

    mkdir -p "$(dirname "$file")"
    # A file not ending in a newline would otherwise glue the two lines together.
    [[ -s "$file" && -n "$(tail -c 1 "$file")" ]] && printf '\n' >> "$file"
    printf '%s\n' "$line" >> "$file"
    LINE_ADDED=true
    ok "appended to $label: $line"
}

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

# xsessionrc_export NAME VALUE  — export it before X starts, where a shell rc is
# too late. Replaces any earlier line; sets XSESSIONRC_CHANGED when it wrote.
xsessionrc_export() {
    local name="$1" value="$2" xsr="$HOME/.xsessionrc"
    XSESSIONRC_CHANGED=false

    if [[ -f "$xsr" ]] && grep -qx "export $name=$value" "$xsr"; then
        skip "~/.xsessionrc already exports $name."
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  would set:%s export %s=%s → %s\n' "$C_DIM" "$C_OFF" "$name" "$value" "$xsr"
        return 0
    fi

    touch "$xsr"
    sed -i "/^export $name=/d" "$xsr"
    printf 'export %s=%s\n' "$name" "$value" >> "$xsr"
    XSESSIONRC_CHANGED=true
    ok "$name=$value exported in ~/.xsessionrc."
}
