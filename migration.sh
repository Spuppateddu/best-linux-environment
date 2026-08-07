#!/usr/bin/env bash
# One-off converter: old layout → ~/linux-configuration. Standalone, needs no
# lib/, safe to run twice. `./migration.sh --help` for the rest.

set -euo pipefail

usage() {
    cat <<'EOF'
One-off converter: old layout → ~/linux-configuration.

Gathers the five tool config repos into a single folder:

  ~/linux-configuration/
  ├── zsh/        ← ~/.zsh
  ├── vim/        ← ~/.vim
  ├── tmux/       ← ~/.tmuxrc
  ├── alacritty/  ← ~/.alacritty
  └── i3/         ← ~/.i3rc

They used to be cloned straight into $HOME as hidden folders. Each moves into
~/linux-configuration/<name>, and the old $HOME path stays behind as a symlink
pointing at it.

best-linux-environment itself is NOT moved: it stays at ~/best-linux-environment
and its @reboot cron is left alone. linux-configuration sits *beside* it rather
than inside it, deliberately — inside, it would have to be gitignored, and a
gitignored directory inside a git repo is precisely what `git clean -xfd`
removes: all five checkouts and any uncommitted work in them, silently.

The symlink is what makes this safe. The installers are relocatable — each
resolves its own location with `cd "$(dirname "$0")" && pwd` — but the configs
they install are not: ~/.i3rc/config names ~/.i3rc/ some twenty times (picom,
dunst, rofi, scripts/), ~/.zshrc is a single `source ~/.zsh/zshrc`, and vim
reaches its vimrc through a runtimepath containing ~/.vim alone. Keeping those
paths alive as symlinks means none of them has to change.

Git does not care: a normal clone stores no absolute path, so a moved repo
keeps its remote, its history and its uncommitted work.

Only needed on a machine that predates linux-configuration/. A fresh machine
needs nothing: setup.sh clones and symlinks the new layout itself, and
basic/10-tools.sh refuses to touch a tool still sitting at its old $HOME path,
so an unconverted box is reported rather than silently given a second copy.

Standalone on purpose — no dependency on the repo's lib/. Run it once, on each
old machine. Running it twice changes nothing.

Usage:
  ./migration.sh              # convert
  ./migration.sh --dry-run    # show the plan, touch nothing
  CONFIG_DIR=~/somewhere/else ./migration.sh

Close vim first if a coc/plugin session is live — the checkout moves underneath
the editor otherwise.
EOF
}

# Beside best-linux-environment, not inside it: inside it would be gitignored,
# and `git clean -xfd` deletes exactly that — every checkout, silently.
CONFIG_DIR="${CONFIG_DIR:-$HOME/linux-configuration}"
DRY_RUN=false

for a in "$@"; do
    case "$a" in
        --dry-run) DRY_RUN=true ;;
        -h|--help) usage; exit 0 ;;
        *) printf '✗ Unknown argument %s. Usage: %s [--dry-run]\n' "$a" "$0" >&2; exit 1 ;;
    esac
done

if [[ -t 1 ]]; then
    C_OFF=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
    C_OFF=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=
fi
step()  { printf '%s▸%s %s\n' "$C_BLUE"   "$C_OFF" "$*"; }
ok()    { printf '%s✓%s %s\n' "$C_GREEN"  "$C_OFF" "$*"; }
skip()  { printf '%s·%s %s%s%s\n' "$C_DIM" "$C_OFF" "$C_DIM" "$*" "$C_OFF"; }
warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_OFF" "$*"; }
run()   { if [[ "$DRY_RUN" == true ]]; then printf '%s  would run:%s %s\n' "$C_DIM" "$C_OFF" "$*"; else "$@"; fi; }

# name:old $HOME path. Hardcoded rather than parsed out of tools.conf so this
# stays a self-contained file you can scp anywhere.
TOOLS=(
    "zsh:$HOME/.zsh"
    "vim:$HOME/.vim"
    "tmux:$HOME/.tmuxrc"
    "alacritty:$HOME/.alacritty"
    "i3:$HOME/.i3rc"
)

printf '\n%s══ Convert to ~/linux-configuration ══%s\n' "$C_BOLD" "$C_OFF"
skip "Target: $CONFIG_DIR"
[[ "$DRY_RUN" == true ]] && skip "Dry run — nothing will be moved."
printf '\n'

moved=0 linked=0 settled=0 absent=0 problems=0

for entry in "${TOOLS[@]}"; do
    name="${entry%%:*}"
    link="${entry#*:}"
    short="${link/#$HOME/\~}"
    dir="$CONFIG_DIR/$name"

    if [[ -L "$link" ]]; then
        if [[ "$(readlink "$link")" == "$dir" ]]; then
            skip "$name — already converted."
            settled=$((settled + 1))
        elif [[ -d "$dir/.git" ]]; then
            step "$name — re-pointing $short at $CONFIG_DIR/$name"
            run ln -sfn "$dir" "$link"
            ok "$name re-pointed."
            linked=$((linked + 1))
        elif target="$(readlink -f "$link")" && [[ -d "$target/.git" ]]; then
            # Converted already, but into some other folder (an earlier version of
            # this script). Relocate it, rather than straddle two layouts.
            step "$name — relocating ${target/#$HOME/\~} → $CONFIG_DIR/$name"
            run mkdir -p "$CONFIG_DIR"
            run mv "$target" "$dir"
            run ln -sfn "$dir" "$link"
            ok "$name relocated, $short now points at it."
            moved=$((moved + 1))
        else
            warn "$name — $short is a symlink to $(readlink "$link") and $CONFIG_DIR/$name does not exist. Left alone."
            problems=$((problems + 1))
        fi

    elif [[ -d "$link/.git" ]]; then
        # The old layout. This is the move the script exists for.
        if [[ -e "$dir" ]]; then
            warn "$name — $short is a clone but linux-configuration/$name already exists. Left alone; merge them by hand."
            problems=$((problems + 1))
        else
            step "$name — moving $short → linux-configuration/$name"
            run mkdir -p "$CONFIG_DIR"
            run mv "$link" "$dir"
            run ln -sfn "$dir" "$link"
            ok "$name moved, $short now points at it."
            moved=$((moved + 1))
        fi

    elif [[ -e "$link" ]]; then
        warn "$name — $short exists but is not a git checkout. Left untouched."
        problems=$((problems + 1))

    elif [[ -d "$dir/.git" ]]; then
        # Already under linux-configuration/ but nothing links back to it.
        step "$name — linking $short → linux-configuration/$name"
        run ln -sfn "$dir" "$link"
        ok "$name linked."
        linked=$((linked + 1))
    else
        skip "$name — not installed on this machine."
        absent=$((absent + 1))
    fi
done

printf '\n'
if [[ $((moved + linked)) -eq 0 ]]; then
    ok "Nothing to do — $settled already converted, $absent not installed here."
else
    ok "Done — $moved moved, $linked linked, $settled already converted, $absent not installed here."
fi
if [[ $problems -gt 0 ]]; then
    warn "$problems tool(s) need a decision only you can make — see above."
    exit 1
fi
exit 0
