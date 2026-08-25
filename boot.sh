#!/usr/bin/env bash
# What the @reboot cron runs: pull, re-apply, reload, refresh — and never decide
# anything. `./boot.sh --help` for the rest.

set -euo pipefail

usage() {
    cat <<'EOF'
What runs at every boot, from the @reboot cron ./setup.sh offers to install.
You are not expected to run it by hand, though you can — it is the fastest way
to pull every repo and re-apply every config after editing one.

It does five things and refuses to do a sixth:

  1. git pull this repo, and re-exec itself if that changed anything.
  2. git pull every config repo you have (zsh, vim, tmux, temps, alacritty,
     i3) and re-run the install.sh each one ships. That last part is the
     "source": it is what re-links ~/.zshrc, rewrites ~/.tmux.conf, reinstalls
     a plugin the repo has gained, and puts back a symlink something broke.
  3. Re-apply this machine's settings from settings.local and aliases.local
     (the agent $mod+c opens, your prompt colours, your shared aliases) and its
     font sizes from fonts.local, then reload i3, the bar and dunst if any of
     them moved.
  4. Reload what is running right now, so an edit you pushed from another
     machine is live without a logout: i3 reloads its config, every running
     tmux server re-sources its, the font cache is rebuilt, X resources are
     re-merged.
  5. Move the binaries apt doesn't manage to their latest release — lazygit,
     yazi/ya, fzf, opencode.

What it will not do is make a decision. It never asks a question (there is
nobody there to answer), never installs a config repo you didn't pick, and
never overwrites a config file you were meant to make your own. Adding
something new to this machine is ./setup.sh's job, always.

One honest limit on "reload": at boot there are no shells running yet, and
nothing can source a file into a shell that already exists anyway. A new zshrc
applies to the next shell you open. Steps 2, 3 and 4 are the parts that can be
made to take effect immediately, and they are.

Usage:
  ./boot.sh              pull, re-apply, reload, refresh
  ./boot.sh --dry-run    preview, change nothing

Anything needing sudo without a terminal to type a password into is skipped
with a warning — run ./setup.sh to pick those up.
EOF
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Nobody is watching, so config you own is left exactly as you left it, while
# binaries outside apt still move forward. See lib/common.sh.
export BLE_MODE=boot
BLE_ENTRY="$HERE/boot.sh"

DRY_RUN=false
for a in "$@"; do
    case "$a" in
        --dry-run) DRY_RUN=true ;;
        -h|--help|help) usage; exit 0 ;;
        *)
            printf '✗ Unknown argument '\''%s'\''. Usage: ./boot.sh [--dry-run]\n' "$a" >&2
            printf '✗ To install something new, run ./setup.sh instead.\n' >&2
            exit 1
            ;;
    esac
done
export DRY_RUN

# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=lib/runner.sh
source "$HERE/lib/runner.sh"
# shellcheck source=lib/registry.sh
source "$HERE/lib/registry.sh"

require_apt
export BLE_PROFILE="${BLE_PROFILE:-auto}"

# The cron line's `>>` creates the log file but NOT the directory holding it, and
# a cache cleaner removing it would send every boot's output nowhere.
[[ "$DRY_RUN" == true ]] || mkdir -p "$BLE_STATE_DIR"
trim_boot_log

title "Boot ($(date '+%F %T')) — $(profile_label)"

# ── 1. this repo ─────────────────────────────────────────────────────────────
self_update "$@"

# ── 2. the config repos ──────────────────────────────────────────────────────
# No arguments: 10-tools refreshes what is cloned. Cloning a new one is a decision.
bash "$HERE/basic/10-tools.sh" || FAILED+=("config repos")

# ── 3. this machine's settings and font sizes ────────────────────────────────
# After the pull, so settings.local and fonts.local survive what the config
# repos just re-applied.
bash "$HERE/basic/95-settings.sh" || FAILED+=("settings")
bash "$HERE/basic/99-font-sizes.sh" || FAILED+=("font sizes")

# ── 4. reload what is running ────────────────────────────────────────────────
# The catch-all for repos whose own installer didn't reload. All best-effort.
title "Reloading live configuration"

# i3 and X tools need to know which display to talk to. Under cron there is no
# DISPLAY, so take it from the running X session if there is one.
if [[ -z "${DISPLAY:-}" ]]; then
    DISPLAY="$(ps -u "$(id -u)" -o args= 2>/dev/null \
        | grep -oE '^/usr/lib/xorg/Xorg[[:space:]]+(:[0-9]+)' \
        | awk '{print $2}' | head -1 || true)"
    [[ -n "$DISPLAY" ]] && export DISPLAY
fi

if [[ -n "${DISPLAY:-}" ]] && has_cmd i3-msg; then
    run i3-msg -q reload >/dev/null 2>&1 && ok "i3 reloaded." \
        || skip "No i3 to reload."
else
    skip "No graphical session — nothing to reload in i3."
fi

# Every running tmux server, not just the default one.
if has_cmd tmux && [[ -f "$HOME/.tmux.conf" ]] && tmux list-sessions >/dev/null 2>&1; then
    run tmux source-file "$HOME/.tmux.conf" >/dev/null 2>&1 && ok "tmux config re-sourced." \
        || warn "tmux reload failed — check ~/.tmux.conf."
else
    skip "No running tmux server."
fi

if has_cmd fc-cache; then
    run fc-cache -f >/dev/null 2>&1 && ok "Font cache rebuilt." || warn "fc-cache failed."
fi

if [[ -n "${DISPLAY:-}" && -f "$HOME/.Xresources" ]] && has_cmd xrdb; then
    run xrdb -merge "$HOME/.Xresources" 2>/dev/null && ok "X resources merged." \
        || skip "Could not merge ~/.Xresources."
fi

# ── 5. binaries apt doesn't manage ───────────────────────────────────────────
# Each checks upstream's latest release and downloads only when there is one.
title "Refreshing hand-installed binaries"

registry_load
for id in lazygit yazi opencode; do
    if idx="$(mod_index_of "$id")"; then
        # Only if it is actually here: installing something you never picked is
        # the one decision this script doesn't get to make.
        mod_installed "$idx" || { skip "$id not installed — ./setup.sh installs it."; continue; }
        mod_run "$idx" --no-apt || FAILED+=("$id")
    fi
done

finish
